# contract_executor.py — TRADE4ME 2.0 — Pilote ArbBot.sol (4 modes)
#
# Remplace tx_builder.py : un seul appel = une seule tx atomique.
# Modes disponibles :
#   1. execute_arb()            — same-DEX, capital propre
#   2. flash_swap_arb()         — same-DEX, flash swap PancakeSwap
#   3. execute_cross_dex_arb()  — cross-DEX, capital propre  ← NOUVEAU
#   4. flash_cross_dex_arb()    — cross-DEX, flash swap       ← NOUVEAU

import os
import logging
from typing import Optional

from web3 import Web3
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger("contract_executor")

# ── Config ────────────────────────────────────────────────────────────────────

PRIVATE_KEY          = os.getenv("PRIVATE_KEY")
WALLET_ADDRESS       = os.getenv("WALLET_ADDRESS")
BSC_RPC_URL          = os.getenv("BSC_RPC_URL", "https://bsc-dataseed1.binance.org/")
ARB_CONTRACT_ADDRESS = os.getenv("ARB_CONTRACT_ADDRESS")   # set after deployment
GAS_PRICE_GWEI       = 5
DRY_RUN              = os.getenv("DRY_RUN", "true").lower() == "true"
BSC_CHAIN_ID         = 56

# ── ABI — all functions used by the Python bot ────────────────────────────────

ARB_BOT_ABI = [
    # ── Mode 1 : executeArb ──────────────────────────────────────────────────
    {
        "inputs": [
            {"name": "tokenA",    "type": "address"},
            {"name": "tokenB",    "type": "address"},
            {"name": "amountIn",  "type": "uint256"},
            {"name": "minProfit", "type": "uint256"},
        ],
        "name": "executeArb",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    # ── Mode 2 : flashSwapArb ────────────────────────────────────────────────
    {
        "inputs": [
            {"name": "tokenA",    "type": "address"},
            {"name": "tokenB",    "type": "address"},
            {"name": "amountIn",  "type": "uint256"},
            {"name": "minProfit", "type": "uint256"},
        ],
        "name": "flashSwapArb",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    # ── Mode 3 : executeCrossDexArb ─────────────────────────────────────────
    {
        "inputs": [
            {"name": "tokenA",     "type": "address"},
            {"name": "tokenB",     "type": "address"},
            {"name": "amountIn",   "type": "uint256"},
            {"name": "minProfit",  "type": "uint256"},
            {"name": "routerBuy",  "type": "address"},
            {"name": "routerSell", "type": "address"},
        ],
        "name": "executeCrossDexArb",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    # ── Mode 4 : flashCrossDexArb ────────────────────────────────────────────
    {
        "inputs": [
            {"name": "tokenA",     "type": "address"},
            {"name": "tokenB",     "type": "address"},
            {"name": "amountIn",   "type": "uint256"},
            {"name": "minProfit",  "type": "uint256"},
            {"name": "routerSell", "type": "address"},
        ],
        "name": "flashCrossDexArb",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    # ── Simulation cross-DEX (view — no gas) ─────────────────────────────────
    {
        "inputs": [
            {"name": "tokenA",     "type": "address"},
            {"name": "tokenB",     "type": "address"},
            {"name": "amountIn",   "type": "uint256"},
            {"name": "routerBuy",  "type": "address"},
            {"name": "routerSell", "type": "address"},
        ],
        "name": "simulateCrossDexArb",
        "outputs": [
            {"name": "amountBReceived", "type": "uint256"},
            {"name": "amountAReturned", "type": "uint256"},
            {"name": "profitOrLoss",    "type": "int256"},
        ],
        "stateMutability": "view",
        "type": "function",
    },
    # ── Simulation same-DEX (backward compat) ────────────────────────────────
    {
        "inputs": [
            {"name": "tokenA",   "type": "address"},
            {"name": "tokenB",   "type": "address"},
            {"name": "amountIn", "type": "uint256"},
        ],
        "name": "simulateArb",
        "outputs": [
            {"name": "amountBReceived", "type": "uint256"},
            {"name": "amountAReturned", "type": "uint256"},
            {"name": "profitOrLoss",    "type": "int256"},
        ],
        "stateMutability": "view",
        "type": "function",
    },
    # ── Utility ──────────────────────────────────────────────────────────────
    {
        "inputs": [
            {"name": "token",  "type": "address"},
            {"name": "amount", "type": "uint256"},
        ],
        "name": "withdraw",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
    {
        "inputs": [{"name": "_paused", "type": "bool"}],
        "name": "setPaused",
        "outputs": [],
        "stateMutability": "nonpayable",
        "type": "function",
    },
]

ERC20_APPROVE_ABI = [
    {
        "constant": False,
        "inputs": [
            {"name": "_spender", "type": "address"},
            {"name": "_value",   "type": "uint256"},
        ],
        "name": "approve",
        "outputs": [{"name": "", "type": "bool"}],
        "type": "function",
    },
]


class ContractExecutor:
    """
    Drives ArbBot.sol — each call = one atomic transaction.
    Supports all 4 arb modes + on-chain simulation.
    """

    def __init__(self, w3: Web3):
        self.w3     = w3
        self.wallet = Web3.to_checksum_address(WALLET_ADDRESS)

        if not ARB_CONTRACT_ADDRESS:
            raise ValueError("ARB_CONTRACT_ADDRESS missing in .env — deploy the contract first.")

        self.contract = w3.eth.contract(
            address=Web3.to_checksum_address(ARB_CONTRACT_ADDRESS),
            abi=ARB_BOT_ABI,
        )
        logger.info(f"ContractExecutor ready | contract: {ARB_CONTRACT_ADDRESS}")

    # ── Simulations (free — view calls) ──────────────────────────────────────

    def simulate_same_dex(self, token_a: str, token_b: str, amount_in_wei: int) -> dict:
        """Calls simulateArb() — no gas consumed."""
        b, a_back, pnl = self.contract.functions.simulateArb(
            Web3.to_checksum_address(token_a),
            Web3.to_checksum_address(token_b),
            amount_in_wei,
        ).call()
        return {"amount_b": b, "amount_a_back": a_back, "profit_or_loss": pnl, "profitable": pnl > 0}

    def simulate_cross_dex(
        self, token_a: str, token_b: str, amount_in_wei: int,
        router_buy: str, router_sell: str
    ) -> dict:
        """Calls simulateCrossDexArb() — no gas consumed."""
        b, a_back, pnl = self.contract.functions.simulateCrossDexArb(
            Web3.to_checksum_address(token_a),
            Web3.to_checksum_address(token_b),
            amount_in_wei,
            Web3.to_checksum_address(router_buy),
            Web3.to_checksum_address(router_sell),
        ).call()
        return {"amount_b": b, "amount_a_back": a_back, "profit_or_loss": pnl, "profitable": pnl > 0}

    # ── Mode 1 : executeArb ───────────────────────────────────────────────────

    def execute_arb(
        self, token_a: str, token_b: str,
        amount_in_wei: int, min_profit_wei: int = 0,
    ) -> Optional[str]:
        """Same-DEX round-trip on PancakeSwap with own capital."""
        logger.info(f"[Mode1] executeArb | {token_a[:8]}→{token_b[:8]} | {amount_in_wei/1e18:.4f}")

        if DRY_RUN:
            sim = self.simulate_same_dex(token_a, token_b, amount_in_wei)
            logger.info(f"[DRY_RUN] profit={sim['profit_or_loss']/1e18:.6f} | ok={sim['profitable']}")
            return "0xDRY_RUN"

        self._approve(token_a, amount_in_wei)
        tx = self.contract.functions.executeArb(
            Web3.to_checksum_address(token_a),
            Web3.to_checksum_address(token_b),
            amount_in_wei, min_profit_wei,
        ).build_transaction(self._tx_params(400_000))
        return self._sign_and_send(tx, "executeArb")

    # ── Mode 2 : flashSwapArb ─────────────────────────────────────────────────

    def flash_swap_arb(
        self, token_a: str, token_b: str,
        amount_in_wei: int, min_profit_wei: int = 0,
    ) -> Optional[str]:
        """Same-DEX flash swap — zero capital required."""
        logger.info(f"[Mode2] flashSwapArb | {token_a[:8]}→{token_b[:8]} | borrow={amount_in_wei/1e18:.4f}")

        if DRY_RUN:
            sim = self.simulate_same_dex(token_a, token_b, amount_in_wei)
            flash_fee = int(amount_in_wei * 25 / 10000)
            net = sim["profit_or_loss"] - flash_fee
            logger.info(f"[DRY_RUN] gross={sim['profit_or_loss']/1e18:.6f} fee={flash_fee/1e18:.6f} net={net/1e18:.6f}")
            return "0xDRY_RUN_FLASH"

        tx = self.contract.functions.flashSwapArb(
            Web3.to_checksum_address(token_a),
            Web3.to_checksum_address(token_b),
            amount_in_wei, min_profit_wei,
        ).build_transaction(self._tx_params(500_000))
        return self._sign_and_send(tx, "flashSwapArb")

    # ── Mode 3 : executeCrossDexArb ───────────────────────────────────────────

    def execute_cross_dex_arb(
        self, token_a: str, token_b: str,
        amount_in_wei: int, min_profit_wei: int,
        router_buy: str, router_sell: str,
    ) -> Optional[str]:
        """
        Cross-DEX atomic arb with own capital.
        Swap 1: tokenA -> tokenB on router_buy
        Swap 2: tokenB -> tokenA on router_sell
        Full revert if profit < min_profit_wei.
        """
        logger.info(
            f"[Mode3] executeCrossDexArb | {token_a[:8]}→{token_b[:8]} | "
            f"buy={router_buy[:10]} sell={router_sell[:10]} | {amount_in_wei/1e18:.4f}"
        )

        if DRY_RUN:
            sim = self.simulate_cross_dex(token_a, token_b, amount_in_wei, router_buy, router_sell)
            logger.info(
                f"[DRY_RUN] cross-DEX profit={sim['profit_or_loss']/1e18:.6f} | ok={sim['profitable']}"
            )
            return "0xDRY_RUN_CROSS"

        self._approve(token_a, amount_in_wei)
        tx = self.contract.functions.executeCrossDexArb(
            Web3.to_checksum_address(token_a),
            Web3.to_checksum_address(token_b),
            amount_in_wei, min_profit_wei,
            Web3.to_checksum_address(router_buy),
            Web3.to_checksum_address(router_sell),
        ).build_transaction(self._tx_params(500_000))
        return self._sign_and_send(tx, "executeCrossDexArb")

    # ── Mode 4 : flashCrossDexArb ─────────────────────────────────────────────

    def flash_cross_dex_arb(
        self, token_a: str, token_b: str,
        amount_in_wei: int, min_profit_wei: int,
        router_sell: str,
    ) -> Optional[str]:
        """
        Cross-DEX flash swap — zero capital.
        Borrows amountIn from PancakeSwap, sells tokenB on router_sell,
        repays flash loan + 0.25%, keeps spread.
        """
        logger.info(
            f"[Mode4] flashCrossDexArb | {token_a[:8]}→{token_b[:8]} | "
            f"sell={router_sell[:10]} | borrow={amount_in_wei/1e18:.4f}"
        )

        if DRY_RUN:
            from config import DEXES
            pancake_router = DEXES["pancakeswap"]["router"]
            sim = self.simulate_cross_dex(token_a, token_b, amount_in_wei, pancake_router, router_sell)
            flash_fee = int(amount_in_wei * 25 / 10000)
            net = sim["profit_or_loss"] - flash_fee
            logger.info(
                f"[DRY_RUN] flash cross-DEX gross={sim['profit_or_loss']/1e18:.6f} "
                f"fee={flash_fee/1e18:.6f} net={net/1e18:.6f} ok={net>0}"
            )
            return "0xDRY_RUN_FLASH_CROSS"

        tx = self.contract.functions.flashCrossDexArb(
            Web3.to_checksum_address(token_a),
            Web3.to_checksum_address(token_b),
            amount_in_wei, min_profit_wei,
            Web3.to_checksum_address(router_sell),
        ).build_transaction(self._tx_params(600_000))
        return self._sign_and_send(tx, "flashCrossDexArb")

    # ── Utility ───────────────────────────────────────────────────────────────

    def withdraw(self, token: str, amount_wei: int = 0) -> Optional[str]:
        """Withdraws tokens from the contract to owner wallet."""
        tx = self.contract.functions.withdraw(
            Web3.to_checksum_address(token), amount_wei
        ).build_transaction(self._tx_params(80_000))
        return self._sign_and_send(tx, "withdraw")

    def set_paused(self, paused: bool) -> Optional[str]:
        """Emergency pause/unpause."""
        tx = self.contract.functions.setPaused(paused).build_transaction(self._tx_params(50_000))
        return self._sign_and_send(tx, f"setPaused({paused})")

    # ── Internal helpers ──────────────────────────────────────────────────────

    def _tx_params(self, gas: int) -> dict:
        return {
            "from":     self.wallet,
            "nonce":    self.w3.eth.get_transaction_count(self.wallet),
            "gas":      gas,
            "gasPrice": Web3.to_wei(GAS_PRICE_GWEI, "gwei"),
            "chainId":  BSC_CHAIN_ID,
        }

    def _approve(self, token_address: str, amount_wei: int):
        """Approves the ArbBot contract to spend token_address."""
        token = self.w3.eth.contract(
            address=Web3.to_checksum_address(token_address),
            abi=ERC20_APPROVE_ABI,
        )
        tx = token.functions.approve(
            Web3.to_checksum_address(ARB_CONTRACT_ADDRESS), 2**256 - 1,
        ).build_transaction(self._tx_params(60_000))
        self._sign_and_send(tx, f"approve({token_address[:10]})")

    def _sign_and_send(self, tx: dict, label: str) -> Optional[str]:
        try:
            signed  = self.w3.eth.account.sign_transaction(tx, PRIVATE_KEY)
            tx_hash = self.w3.eth.send_raw_transaction(signed.raw_transaction)
            receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=60)
            if receipt.status == 1:
                logger.info(f"{label} OK | gas={receipt.gasUsed} | tx={tx_hash.hex()}")
                return tx_hash.hex()
            else:
                logger.error(f"{label} REVERT | tx={tx_hash.hex()}")
                return None
        except Exception as e:
            logger.error(f"{label} error: {e}")
            return None
