# profit_calc.py — Cross-DEX arbitrage opportunity detection for TRADE4ME 2.0

from dataclasses import dataclass, field
from typing import Optional, List, Dict
from itertools import combinations
import logging

from web3 import Web3
from config import (
    GAS_PRICE_GWEI, GAS_LIMIT_SWAP, MIN_PROFIT_USD,
    SLIPPAGE_TOLERANCE, DEXES, WBNB
)
from price_scanner import MultiDexScanner, DexScanner

logger = logging.getLogger("profit_calc")

# Approximate BNB/USD — replace with Chainlink oracle in production
BNB_PRICE_USD = 300.0


@dataclass
class ArbOpportunity:
    """Single-DEX round-trip opportunity (A→B→A on the same DEX)."""
    pair_name:      str
    token_a:        str
    token_b:        str
    amount_in_wei:  int
    amount_mid_wei: int
    amount_out_wei: int
    profit_wei:     int
    gas_cost_wei:   int
    profit_net_usd: float
    pool_a_address: str
    pool_b_address: str
    path_forward:   List[str]
    path_back:      List[str]

    def __str__(self):
        return (
            f"[SAME-DEX ARB] {self.pair_name} | "
            f"In: {self.amount_in_wei / 1e18:.4f} BNB | "
            f"Net profit: ${self.profit_net_usd:.4f}"
        )


@dataclass
class CrossDexOpportunity:
    """
    Cross-DEX arbitrage: buy A→B on dex_buy, sell B→A on dex_sell.
    This is the primary strategy for TRADE4ME 2.0.
    """
    pair_name:       str
    token_a:         str
    token_b:         str
    amount_in_wei:   int        # Capital: tokenA in (wei)
    amount_mid_wei:  int        # tokenB received on dex_buy
    amount_out_wei:  int        # tokenA returned on dex_sell
    profit_wei:      int        # Gross profit in tokenA wei
    gas_cost_wei:    int        # Estimated gas in BNB wei
    profit_net_usd:  float      # Net profit in USD
    dex_buy:         str        # DEX key where we buy tokenB cheap
    dex_sell:        str        # DEX key where we sell tokenB for more tokenA
    router_buy:      str        # Router address for dex_buy
    router_sell:     str        # Router address for dex_sell
    pool_buy:        str        # Pool address on dex_buy
    pool_sell:       str        # Pool address on dex_sell
    path_forward:    List[str]  # [tokenA, tokenB]
    path_back:       List[str]  # [tokenB, tokenA]
    price_buy:       float      # Spot price on dex_buy
    price_sell:      float      # Spot price on dex_sell
    price_spread_pct: float     # (price_sell - price_buy) / price_buy * 100

    def __str__(self):
        return (
            f"[CROSS-DEX ARB] {self.pair_name} | "
            f"Buy on {self.dex_buy} @ {self.price_buy:.6f} | "
            f"Sell on {self.dex_sell} @ {self.price_sell:.6f} | "
            f"Spread: {self.price_spread_pct:.3f}% | "
            f"Net profit: ${self.profit_net_usd:.4f}"
        )


# ─────────────────────────────────────────────────────────────────────────────


class CrossDexCalculator:
    """
    Detects profitable cross-DEX arbitrage opportunities across all DEX pairs
    in DEXES config.

    Strategy:
        For every watched pair and every combination of two DEXes:
            1. Simulate: buy tokenB on dex_buy using amountIn of tokenA
            2. Simulate: sell that tokenB back to tokenA on dex_sell
            3. If amountOut > amountIn + gas + slippage → opportunity found
    """

    def __init__(self, w3: Web3, multi_scanner: MultiDexScanner):
        self.w3             = w3
        self.multi_scanner  = multi_scanner

    # ── Gas ──────────────────────────────────────────────────────────────────

    def _gas_cost_wei(self) -> int:
        return GAS_LIMIT_SWAP * Web3.to_wei(GAS_PRICE_GWEI, "gwei")

    def _gas_cost_usd(self) -> float:
        return (self._gas_cost_wei() / 1e18) * BNB_PRICE_USD

    # ── Main entry point ─────────────────────────────────────────────────────

    def find_opportunities(
        self,
        all_dex_data: Dict[str, Dict[str, Dict]],
        capital_bnb: float = 0.5,
    ) -> List[CrossDexOpportunity]:
        """
        all_dex_data : output of MultiDexScanner.scan_all()
        capital_bnb  : amount of tokenA to trade per opportunity
        Returns a list sorted by profit_net_usd descending.
        """
        opportunities: List[CrossDexOpportunity] = []
        amount_in_wei = Web3.to_wei(capital_bnb, "ether")
        gas_cost_wei  = self._gas_cost_wei()
        gas_cost_usd  = self._gas_cost_usd()

        # Build sorted list of DEX keys that have data
        active_dexes = [k for k, pairs in all_dex_data.items() if pairs]

        # Every ordered pair of DEXes (buy on A, sell on B) — both directions
        for dex_buy, dex_sell in combinations(active_dexes, 2):
            for direction in [(dex_buy, dex_sell), (dex_sell, dex_buy)]:
                db, ds = direction
                pairs_buy  = all_dex_data.get(db, {})
                pairs_sell = all_dex_data.get(ds, {})

                for pair_name, buy_data in pairs_buy.items():
                    if pair_name not in pairs_sell:
                        continue
                    sell_data = pairs_sell[pair_name]

                    try:
                        opp = self._evaluate(
                            pair_name, buy_data, sell_data,
                            db, ds, amount_in_wei,
                            gas_cost_wei, gas_cost_usd,
                        )
                        if opp:
                            opportunities.append(opp)
                    except Exception as e:
                        logger.error(f"[{db}→{ds}] {pair_name}: {e}")

        opportunities.sort(key=lambda o: o.profit_net_usd, reverse=True)
        return opportunities

    # ── Per-pair evaluation ───────────────────────────────────────────────────

    def _evaluate(
        self,
        pair_name:    str,
        buy_data:     Dict,
        sell_data:    Dict,
        dex_buy:      str,
        dex_sell:     str,
        amount_in_wei: int,
        gas_cost_wei:  int,
        gas_cost_usd:  float,
    ) -> Optional[CrossDexOpportunity]:

        r_in_buy   = buy_data["reserve_in"]
        r_out_buy  = buy_data["reserve_out"]
        r_in_sell  = sell_data["reserve_out"]   # reversed: tokenB is now "in"
        r_out_sell = sell_data["reserve_in"]    # tokenA is "out"

        if 0 in (r_in_buy, r_out_buy, r_in_sell, r_out_sell):
            return None

        scanner_buy  = self.multi_scanner.get_dex_scanner(dex_buy)
        scanner_sell = self.multi_scanner.get_dex_scanner(dex_sell)

        # Step 1: buy tokenB on dex_buy with amount_in_wei of tokenA
        amount_b_wei = scanner_buy.get_amount_out(amount_in_wei, r_in_buy, r_out_buy)
        if amount_b_wei <= 0:
            return None

        # Step 2: sell tokenB on dex_sell back to tokenA
        amount_a_out_wei = scanner_sell.get_amount_out(amount_b_wei, r_in_sell, r_out_sell)
        if amount_a_out_wei <= 0:
            return None

        # Gross profit
        profit_gross_wei = amount_a_out_wei - amount_in_wei
        if profit_gross_wei <= 0:
            return None

        # Apply slippage penalty
        slippage_penalty = int(amount_a_out_wei * SLIPPAGE_TOLERANCE)
        profit_net_wei   = profit_gross_wei - slippage_penalty - gas_cost_wei

        # Convert to USD (assumes tokenA ~ BNB; adjust for stablecoins)
        profit_net_usd = (profit_net_wei / 1e18) * BNB_PRICE_USD - gas_cost_usd

        if profit_net_usd < MIN_PROFIT_USD:
            logger.debug(
                f"[{dex_buy}→{dex_sell}] {pair_name} | "
                f"${profit_net_usd:.4f} below threshold ${MIN_PROFIT_USD}"
            )
            return None

        price_buy  = buy_data["price"]
        price_sell = sell_data["price"]
        spread_pct = ((price_sell - price_buy) / price_buy * 100) if price_buy > 0 else 0.0

        logger.info(
            f"CROSS-DEX OPPORTUNITY: {pair_name} | "
            f"{dex_buy} → {dex_sell} | "
            f"spread {spread_pct:.3f}% | "
            f"profit ${profit_net_usd:.4f}"
        )

        return CrossDexOpportunity(
            pair_name        = pair_name,
            token_a          = buy_data["token_a"],
            token_b          = buy_data["token_b"],
            amount_in_wei    = amount_in_wei,
            amount_mid_wei   = amount_b_wei,
            amount_out_wei   = amount_a_out_wei,
            profit_wei       = profit_gross_wei,
            gas_cost_wei     = gas_cost_wei,
            profit_net_usd   = profit_net_usd,
            dex_buy          = dex_buy,
            dex_sell         = dex_sell,
            router_buy       = DEXES[dex_buy]["router"],
            router_sell      = DEXES[dex_sell]["router"],
            pool_buy         = buy_data["pair_address"],
            pool_sell        = sell_data["pair_address"],
            path_forward     = [buy_data["token_a"],  buy_data["token_b"]],
            path_back        = [sell_data["token_b"], sell_data["token_a"]],
            price_buy        = price_buy,
            price_sell       = price_sell,
            price_spread_pct = spread_pct,
        )


# ── Legacy shim — keeps old bot_engine working without modification ───────────

class ProfitCalculator:
    """
    Legacy single-DEX calculator, kept for backward compatibility.
    New code should use CrossDexCalculator.
    """

    def __init__(self, w3: Web3, scanner):
        self.w3      = w3
        self.scanner = scanner

    def estimate_gas_cost_wei(self) -> int:
        return GAS_LIMIT_SWAP * Web3.to_wei(GAS_PRICE_GWEI, "gwei")

    def estimate_gas_cost_usd(self) -> float:
        return (self.estimate_gas_cost_wei() / 1e18) * BNB_PRICE_USD

    def find_opportunities(self, pair_data: Dict, capital_bnb: float = 0.5) -> List[ArbOpportunity]:
        opportunities = []
        amount_in_wei = Web3.to_wei(capital_bnb, "ether")
        gas_cost_wei  = self.estimate_gas_cost_wei()
        gas_cost_usd  = self.estimate_gas_cost_usd()

        for name, data in pair_data.items():
            try:
                opp = self._check_pair(name, data, amount_in_wei, gas_cost_wei, gas_cost_usd)
                if opp:
                    opportunities.append(opp)
            except Exception as e:
                logger.error(f"Error checking {name}: {e}")

        opportunities.sort(key=lambda o: o.profit_net_usd, reverse=True)
        return opportunities

    def _check_pair(self, name, data, amount_in_wei, gas_cost_wei, gas_cost_usd):
        r_in  = data["reserve_in"]
        r_out = data["reserve_out"]
        if r_in == 0 or r_out == 0:
            return None

        amount_b_wei     = self.scanner.get_amount_out(amount_in_wei, r_in, r_out)
        new_r_in         = r_in  + amount_in_wei
        new_r_out        = r_out - amount_b_wei
        if new_r_out <= 0:
            return None

        amount_a_out_wei = self.scanner.get_amount_out(amount_b_wei, new_r_out, new_r_in)
        profit_gross_wei = amount_a_out_wei - amount_in_wei
        slippage_penalty = int(amount_a_out_wei * SLIPPAGE_TOLERANCE)
        profit_net_wei   = profit_gross_wei - slippage_penalty - gas_cost_wei
        profit_net_usd   = (profit_net_wei / 1e18) * BNB_PRICE_USD - gas_cost_usd

        if profit_net_usd < MIN_PROFIT_USD:
            return None

        return ArbOpportunity(
            pair_name      = name,
            token_a        = data["token_a"],
            token_b        = data["token_b"],
            amount_in_wei  = amount_in_wei,
            amount_mid_wei = amount_b_wei,
            amount_out_wei = amount_a_out_wei,
            profit_wei     = profit_gross_wei,
            gas_cost_wei   = gas_cost_wei,
            profit_net_usd = profit_net_usd,
            pool_a_address = data["pair_address"],
            pool_b_address = data["pair_address"],
            path_forward   = [data["token_a"], data["token_b"]],
            path_back      = [data["token_b"], data["token_a"]],
        )
