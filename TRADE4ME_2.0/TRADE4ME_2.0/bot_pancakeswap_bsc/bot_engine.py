# bot_engine.py — TRADE4ME 2.0 main loop (cross-DEX arbitrage)

import time
import logging
import signal
import sys
from datetime import datetime

from web3 import Web3

from config import BSC_RPC_URL, SCAN_INTERVAL_MS, DRY_RUN, DEXES, AUTO_SWEEP, WBNB
from price_scanner import MultiDexScanner
from profit_calc import CrossDexCalculator, CrossDexOpportunity
from tx_builder import TxBuilder
from profit_sweeper import ProfitSweeper

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(name)-18s | %(levelname)-7s | %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(f"bot_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"),
    ],
)
logger = logging.getLogger("bot_engine")


class ArbBot:
    """
    TRADE4ME 2.0 — Cross-DEX arbitrage bot.

    Cycle:
      1. Scan prices on ALL DEXes (PancakeSwap, BiSwap, ApeSwap, MDEX)
      2. Find the best cross-DEX opportunity (buy cheap, sell expensive)
      3. Execute if net profit > MIN_PROFIT_USD
      4. Log the result
    """

    def __init__(self):
        logger.info("=== TRADE4ME 2.0 — Cross-DEX Arbitrage Bot Starting ===")
        if DRY_RUN:
            logger.warning("DRY_RUN mode — no real transactions will be sent")

        dex_names = ", ".join(cfg["name"] for cfg in DEXES.values())
        logger.info(f"DEXes enabled: {dex_names}")

        # BSC connection
        self.w3 = Web3(Web3.HTTPProvider(BSC_RPC_URL))
        if not self.w3.is_connected():
            raise ConnectionError(f"Cannot connect to BSC at {BSC_RPC_URL}")
        logger.info(f"Connected to BSC | block: {self.w3.eth.block_number}")

        # Modules
        self.scanner    = MultiDexScanner(self.w3)
        self.calc       = CrossDexCalculator(self.w3, self.scanner)
        self.tx_builder = TxBuilder(self.w3)
        self.sweeper    = ProfitSweeper(self.w3) if AUTO_SWEEP else None

        if AUTO_SWEEP:
            logger.info("Auto-sweep ENABLED — profits will be sent to cold wallet automatically")
        else:
            logger.info("Auto-sweep DISABLED — set AUTO_SWEEP=true in .env to enable")

        # Stats
        self.scans_count  = 0
        self.trades_count = 0
        self.total_profit = 0.0
        self.running      = True

        signal.signal(signal.SIGINT,  self._shutdown)
        signal.signal(signal.SIGTERM, self._shutdown)

    # ── Main loop ─────────────────────────────────────────────────────────────

    def run(self, capital_bnb: float = 0.5):
        logger.info(f"Capital per trade : {capital_bnb} BNB")
        logger.info(f"Scan interval     : {SCAN_INTERVAL_MS} ms")
        logger.info("Starting loop...")

        while self.running:
            start = time.time()
            try:
                self._cycle(capital_bnb)
            except Exception as e:
                logger.error(f"Cycle error: {e}", exc_info=True)

            elapsed  = (time.time() - start) * 1000
            sleep_ms = max(0, SCAN_INTERVAL_MS - elapsed)
            time.sleep(sleep_ms / 1000)

    def _cycle(self, capital_bnb: float):
        self.scans_count += 1

        # 1. Scan all DEXes
        all_dex_data = self.scanner.scan_all()

        active = {k: v for k, v in all_dex_data.items() if v}
        if len(active) < 2:
            logger.warning(f"Only {len(active)} DEX(es) with data — need >= 2 for cross-DEX arb")
            return

        # 2. Find best cross-DEX opportunity
        opportunities = self.calc.find_opportunities(all_dex_data, capital_bnb)

        if not opportunities:
            if self.scans_count % 10 == 0:
                self._log_price_summary(all_dex_data)
            return

        best: CrossDexOpportunity = opportunities[0]
        logger.info(f"Best opportunity: {best}")

        # 3. Execute
        tx_hash = self.tx_builder.execute_cross_dex_arb(best)
        if tx_hash:
            self.trades_count += 1
            self.total_profit += best.profit_net_usd
            logger.info(
                f"Trade #{self.trades_count} executed | "
                f"{best.dex_buy} -> {best.dex_sell} | "
                f"Profit: ${best.profit_net_usd:.4f} | "
                f"Cumulative: ${self.total_profit:.4f} | "
                f"tx: {tx_hash}"
            )
            # Auto-sweep profits to cold wallet if threshold reached
            if self.sweeper:
                sweep_tx = self.sweeper.check_and_sweep(best.token_a)
                if sweep_tx:
                    stats = self.sweeper.get_sweep_stats()
                    logger.info(
                        f"[sweeper] Sweep #{stats['sweep_count']} completed | "
                        f"tx: {sweep_tx}"
                    )
        else:
            logger.warning("Execution failed — opportunity missed")

    # ── Price summary ─────────────────────────────────────────────────────────

    def _log_price_summary(self, all_dex_data: dict):
        """Logs the price of each pair across all DEXes for spread monitoring."""
        logger.info(f"=== Price snapshot (scan #{self.scans_count}) ===")
        all_pairs = set()
        for pairs in all_dex_data.values():
            all_pairs.update(pairs.keys())

        for pair in sorted(all_pairs):
            prices = {
                dex: float(data[pair]["price"])
                for dex, data in all_dex_data.items()
                if pair in data
            }
            if len(prices) >= 2:
                lo, hi = min(prices.values()), max(prices.values())
                spread = (hi - lo) / lo * 100 if lo > 0 else 0
                row = " | ".join(f"{d}: {p:.6f}" for d, p in prices.items())
                logger.info(f"  {pair:<14} {row}  spread: {spread:.4f}%")

    # ── Graceful shutdown ─────────────────────────────────────────────────────

    def _shutdown(self, *args):
        logger.info("=== Shutting down ===")
        logger.info(f"Total scans  : {self.scans_count}")
        logger.info(f"Total trades : {self.trades_count}")
        logger.info(f"Total profit : ${self.total_profit:.4f}")
        if self.sweeper:
            stats = self.sweeper.get_sweep_stats()
            logger.info(f"Total sweeps : {stats['sweep_count']}")
            for addr, amount in stats["total_swept"].items():
                logger.info(f"  {addr[:10]}… → {amount:.4f} swept to cold wallet")
        self.running = False
        sys.exit(0)


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    bot = ArbBot()
    bot.run(capital_bnb=0.5)   # Adjust to your available capital
