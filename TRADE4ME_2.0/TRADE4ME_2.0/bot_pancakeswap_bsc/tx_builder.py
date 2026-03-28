# tx_builder.py — Cross-DEX transaction builder for TRADE4ME 2.0

import time
import logging
from typing import Optional

from web3 import Web3
from web3.exceptions import ContractLogicError

from config import (
    PRIVATE_KEY, WALLET_ADDRESS,
    PANCAKE_ROUTER_V2, DEXES,
    GAS_PRICE_GWEI, GAS_LIMIT_SWAP,
    SLIPPAGE_TOLERANCE, DRY_RUN
)
from abis import ROUTER_ABI, ERC20_ABI
from profit_calc import ArbOpportunity, CrossDexOpportunity

logger = logging.getLogger("tx_builder")

BSC_CHAIN_ID = 56


class TxBuilder:
    """
    Builds, signs and sends arbitrage transactions on BSC.
    Supports both single-DEX (legacy) and cross-DEX execution.
    In DRY_RUN mode, simulates without sending anything.
    """

    def __init__(self, w3: Web3):
        self.w3     = w3
        self.wallet = Web3.to_checksum_address(WALLET_ADDRESS)
        # Cache of router contract instances keyed by address
        self._routers: dict = {}

    # ── Router contract factory ───────────────────────────────────────────────

    def _get_router(self, router_address: str):
        addr = Web3.to_checksum_address(router_address)
        if addr not in self._routers:
            self._routers[addr] = self.w3.eth.contract(address=addr, abi=ROUTER_ABI)
        return self._routers[addr]

    # ── ERC-20 approval ──────────────────────────────────────────────────────

    def approve_token(self, token_address: str, router_address: str) -> bool:
        """
        Approves `router_address` to spend `token_address` (max uint256).
        Call once per token/router pair — approval persists on-chain.
        """
        token    = self.w3.eth.contract(
            address=Web3.to_checksum_address(token_address), abi=ERC20_ABI
        )
        max_uint = 2 ** 256 - 1
        nonce    = self.w3.eth.get_transaction_count(self.wallet)
        tx = token.functions.approve(
            Web3.to_checksum_address(router_address), max_uint
        ).build_transaction({
            "from":     self.wallet,
            "nonce":    nonce,
            "gas":      60_000,
            "gasPrice": Web3.to_wei(GAS_PRICE_GWEI, "gwei"),
            "chainId":  BSC_CHAIN_ID,
        })

        if DRY_RUN:
            logger.info(f"[DRY_RUN] Approval simulated: {token_address[:10]}… on {router_address[:10]}…")
            return True

        signed  = self.w3.eth.account.sign_transaction(tx, PRIVATE_KEY)
        tx_hash = self.w3.eth.send_raw_transaction(signed.rawTransaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
        ok = receipt.status == 1
        logger.info(f"Approval {'OK' if ok else 'FAILED'} | tx: {tx_hash.hex()}")
        return ok

    # ── Balance check ─────────────────────────────────────────────────────────

    def check_balance(self, token_address: str, amount_needed_wei: int) -> bool:
        token   = self.w3.eth.contract(
            address=Web3.to_checksum_address(token_address), abi=ERC20_ABI
        )
        balance = token.functions.balanceOf(self.wallet).call()
        if balance < amount_needed_wei:
            logger.warning(
                f"Insufficient balance: {balance / 1e18:.4f} < {amount_needed_wei / 1e18:.4f}"
            )
            return False
        return True

    # ── Single swap tx builder ────────────────────────────────────────────────

    def _build_swap_tx(
        self,
        router_address: str,
        path: list,
        amount_in_wei: int,
        amount_out_min_wei: int,
        nonce: int,
    ) -> dict:
        router   = self._get_router(router_address)
        deadline = int(time.time()) + 180
        return router.functions.swapExactTokensForTokens(
            amount_in_wei,
            amount_out_min_wei,
            [Web3.to_checksum_address(t) for t in path],
            self.wallet,
            deadline,
        ).build_transaction({
            "from":     self.wallet,
            "nonce":    nonce,
            "gas":      GAS_LIMIT_SWAP,
            "gasPrice": Web3.to_wei(GAS_PRICE_GWEI, "gwei"),
            "chainId":  BSC_CHAIN_ID,
        })

    # ── Send helper ───────────────────────────────────────────────────────────

    def _send_tx(self, tx: dict, label: str) -> Optional[str]:
        signed  = self.w3.eth.account.sign_transaction(tx, PRIVATE_KEY)
        tx_hash = self.w3.eth.send_raw_transaction(signed.rawTransaction)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
        if receipt.status != 1:
            logger.error(f"{label} FAILED | tx: {tx_hash.hex()}")
            return None
        logger.info(f"{label} OK | tx: {tx_hash.hex()}")
        return tx_hash.hex()

    # ── Cross-DEX execution (primary strategy) ────────────────────────────────

    def execute_cross_dex_arb(self, opp: CrossDexOpportunity) -> Optional[str]:
        """
        Executes a cross-DEX arbitrage in two sequential swaps:
          Swap 1: tokenA → tokenB  on opp.router_buy
          Swap 2: tokenB → tokenA  on opp.router_sell

        WARNING: These are two separate transactions — not atomic.
        For full atomicity, deploy ArbBot.sol and use contract_executor.py instead.

        Returns the hash of the final transaction, or None on failure.
        """
        logger.info(f"Executing cross-DEX: {opp}")

        if DRY_RUN:
            logger.info(
                f"[DRY_RUN] Would buy {opp.amount_in_wei / 1e18:.4f} {opp.token_a[:8]} "
                f"on {opp.dex_buy}, sell {opp.amount_mid_wei / 1e18:.4f} {opp.token_b[:8]} "
                f"on {opp.dex_sell} → profit ${opp.profit_net_usd:.4f}"
            )
            return "0xDRY_RUN_CROSS_DEX"

        if not self.check_balance(opp.token_a, opp.amount_in_wei):
            return None

        min_b = int(opp.amount_mid_wei  * (1 - SLIPPAGE_TOLERANCE))
        min_a = int(opp.amount_out_wei  * (1 - SLIPPAGE_TOLERANCE))

        nonce = self.w3.eth.get_transaction_count(self.wallet)

        # ── Swap 1: tokenA → tokenB on dex_buy ───────────────────────────────
        try:
            tx1    = self._build_swap_tx(opp.router_buy, opp.path_forward, opp.amount_in_wei, min_b, nonce)
            hash1  = self._send_tx(tx1, f"Swap1 [{opp.dex_buy}] {opp.pair_name} A→B")
            if not hash1:
                return None
        except ContractLogicError as e:
            logger.error(f"Swap1 revert: {e}")
            return None

        # ── Swap 2: tokenB → tokenA on dex_sell ──────────────────────────────
        try:
            tx2   = self._build_swap_tx(opp.router_sell, opp.path_back, opp.amount_mid_wei, min_a, nonce + 1)
            hash2 = self._send_tx(tx2, f"Swap2 [{opp.dex_sell}] {opp.pair_name} B→A")
            if not hash2:
                logger.critical(
                    "Swap2 FAILED after Swap1 succeeded — funds stuck as tokenB! "
                    f"Recover {opp.amount_mid_wei / 1e18:.6f} of {opp.token_b}"
                )
                return None
            return hash2
        except ContractLogicError as e:
            logger.critical(f"Swap2 revert: {e} — Swap1 already executed, funds as tokenB!")
            return None

    # ── Legacy single-DEX execution (backward compat) ─────────────────────────

    def execute_arb(self, opp: ArbOpportunity) -> Optional[str]:
        """Legacy single-DEX round-trip on PancakeSwap V2."""
        logger.info(f"Executing single-DEX arb: {opp}")

        if DRY_RUN:
            logger.info("[DRY_RUN] Single-DEX simulation — no funds spent.")
            return "0xDRY_RUN_SIMULATION"

        if not self.check_balance(opp.token_a, opp.amount_in_wei):
            return None

        min_b  = int(opp.amount_mid_wei * (1 - SLIPPAGE_TOLERANCE))
        min_a  = int(opp.amount_out_wei * (1 - SLIPPAGE_TOLERANCE))
        nonce  = self.w3.eth.get_transaction_count(self.wallet)

        try:
            tx1   = self._build_swap_tx(PANCAKE_ROUTER_V2, opp.path_forward, opp.amount_in_wei, min_b, nonce)
            hash1 = self._send_tx(tx1, "Swap1 A→B")
            if not hash1:
                return None
        except ContractLogicError as e:
            logger.error(f"Swap1 revert: {e}")
            return None

        try:
            tx2   = self._build_swap_tx(PANCAKE_ROUTER_V2, opp.path_back, opp.amount_mid_wei, min_a, nonce + 1)
            hash2 = self._send_tx(tx2, "Swap2 B→A")
            return hash2
        except ContractLogicError as e:
            logger.error(f"Swap2 revert: {e} — Swap1 already executed!")
            return None
