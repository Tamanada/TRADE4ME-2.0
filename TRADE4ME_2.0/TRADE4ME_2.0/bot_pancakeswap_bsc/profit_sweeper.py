# profit_sweeper.py — TRADE4ME 2.0
# Automatic profit transfer to cold wallet after each profitable trade.
#
# Logic:
#   After each trade, check the bot wallet balance for each watched token.
#   If balance > KEEP_CAPITAL + SWEEP_THRESHOLD  →  transfer excess to COLD_WALLET.
#   The bot always keeps KEEP_CAPITAL_BNB worth of working capital.

import logging
from typing import Optional

from web3 import Web3

from config import (
    PRIVATE_KEY, WALLET_ADDRESS,
    COLD_WALLET_ADDRESS, AUTO_SWEEP,
    SWEEP_THRESHOLD_BNB, KEEP_CAPITAL_BNB,
    GAS_PRICE_GWEI, WBNB,
)
from abis import ERC20_ABI

logger = logging.getLogger("profit_sweeper")

BSC_CHAIN_ID  = 56
GAS_TRANSFER  = 65_000   # ERC-20 transfer gas


class ProfitSweeper:
    """
    Monitors bot wallet balances and sweeps profits to COLD_WALLET_ADDRESS
    whenever the balance exceeds KEEP_CAPITAL_BNB + SWEEP_THRESHOLD_BNB.

    Example with default config (KEEP=0.5 BNB, THRESHOLD=0.2 BNB):
        Bot balance = 0.9 BNB
        Keep        = 0.5 BNB
        Sweep amount= 0.4 BNB  → sent to cold wallet
        Remaining   = 0.5 BNB  → stays on bot wallet for next trades
    """

    def __init__(self, w3: Web3):
        self.w3     = w3
        self.wallet = Web3.to_checksum_address(WALLET_ADDRESS)

        if not COLD_WALLET_ADDRESS:
            raise ValueError("COLD_WALLET_ADDRESS missing in .env")

        self.cold_wallet = Web3.to_checksum_address(COLD_WALLET_ADDRESS)
        self._sweep_count = 0
        self._total_swept_wei: dict = {}   # token_address -> total wei swept

        logger.info(
            f"ProfitSweeper ready | "
            f"cold wallet: {self.cold_wallet} | "
            f"keep: {KEEP_CAPITAL_BNB} BNB | "
            f"threshold: {SWEEP_THRESHOLD_BNB} BNB | "
            f"auto: {AUTO_SWEEP}"
        )

    # ── Public API ────────────────────────────────────────────────────────────

    def check_and_sweep(self, token_address: str) -> Optional[str]:
        """
        Check balance of token_address and sweep if above threshold.
        Returns tx hash if a sweep was executed, None otherwise.
        Call this after every profitable trade.
        """
        if not AUTO_SWEEP:
            return None

        token_addr = Web3.to_checksum_address(token_address)
        balance_wei = self._get_token_balance(token_addr)
        if balance_wei is None:
            return None

        keep_wei      = Web3.to_wei(KEEP_CAPITAL_BNB,   "ether")
        threshold_wei = Web3.to_wei(SWEEP_THRESHOLD_BNB, "ether")
        trigger_wei   = keep_wei + threshold_wei

        if balance_wei <= trigger_wei:
            logger.debug(
                f"[sweeper] {token_address[:10]} balance "
                f"{balance_wei/1e18:.4f} BNB ≤ trigger {trigger_wei/1e18:.4f} — no sweep"
            )
            return None

        sweep_amount_wei = balance_wei - keep_wei

        logger.info(
            f"[sweeper] SWEEP TRIGGERED | "
            f"balance={balance_wei/1e18:.4f} | "
            f"sweep={sweep_amount_wei/1e18:.4f} | "
            f"keep={keep_wei/1e18:.4f}"
        )

        return self._transfer_token(token_addr, sweep_amount_wei)

    def sweep_all_tokens(self, token_addresses: list) -> dict:
        """
        Sweep all provided token addresses in one call.
        Returns {token_address: tx_hash_or_None}.
        """
        results = {}
        for addr in token_addresses:
            results[addr] = self.check_and_sweep(addr)
        return results

    def get_sweep_stats(self) -> dict:
        """Returns cumulative sweep statistics."""
        return {
            "sweep_count":    self._sweep_count,
            "total_swept":    {
                addr: amount / 1e18
                for addr, amount in self._total_swept_wei.items()
            },
        }

    # ── Internal ──────────────────────────────────────────────────────────────

    def _get_token_balance(self, token_address: str) -> Optional[int]:
        try:
            token = self.w3.eth.contract(
                address=Web3.to_checksum_address(token_address),
                abi=ERC20_ABI,
            )
            return token.functions.balanceOf(self.wallet).call()
        except Exception as e:
            logger.error(f"[sweeper] balanceOf failed for {token_address[:10]}: {e}")
            return None

    def _transfer_token(self, token_address: str, amount_wei: int) -> Optional[str]:
        """Signs and sends an ERC-20 transfer to cold wallet."""
        try:
            token = self.w3.eth.contract(
                address=Web3.to_checksum_address(token_address),
                abi=ERC20_ABI,
            )
            nonce = self.w3.eth.get_transaction_count(self.wallet)
            tx = token.functions.transfer(
                self.cold_wallet, amount_wei
            ).build_transaction({
                "from":     self.wallet,
                "nonce":    nonce,
                "gas":      GAS_TRANSFER,
                "gasPrice": Web3.to_wei(GAS_PRICE_GWEI, "gwei"),
                "chainId":  BSC_CHAIN_ID,
            })

            signed  = self.w3.eth.account.sign_transaction(tx, PRIVATE_KEY)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)

            if receipt.status == 1:
                self._sweep_count += 1
                self._total_swept_wei[token_address] = (
                    self._total_swept_wei.get(token_address, 0) + amount_wei
                )
                logger.info(
                    f"[sweeper] Sweep #{self._sweep_count} OK | "
                    f"{amount_wei/1e18:.4f} tokens → {self.cold_wallet} | "
                    f"tx: {tx_hash.hex()}"
                )
                return tx_hash.hex()
            else:
                logger.error(f"[sweeper] Transfer REVERTED | tx: {tx_hash.hex()}")
                return None

        except Exception as e:
            logger.error(f"[sweeper] Transfer failed: {e}")
            return None
