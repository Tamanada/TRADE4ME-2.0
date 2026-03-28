# price_scanner.py — Multi-DEX price scanner for TRADE4ME 2.0

from web3 import Web3
from typing import Optional, Dict, Tuple
import logging

from config import DEXES, WATCHED_PAIRS, PANCAKE_FEE, MIN_RESERVE_WEI
from abis import PAIR_ABI, FACTORY_ABI

logger = logging.getLogger("price_scanner")


class DexScanner:
    """
    Reads PancakeSwap V2-compatible pool prices for ONE DEX.
    Compatible with PancakeSwap, BiSwap, ApeSwap, MDEX — all share the V2 interface.
    """

    def __init__(self, w3: Web3, dex_key: str):
        self.w3      = w3
        self.dex_key = dex_key
        cfg          = DEXES[dex_key]
        self.name    = cfg["name"]
        self.fee     = cfg["fee"]
        self.fee_num = cfg["fee_num"]
        self.fee_den = cfg["fee_den"]
        self.factory = w3.eth.contract(
            address=Web3.to_checksum_address(cfg["factory"]),
            abi=FACTORY_ABI,
        )
        self._pair_cache: Dict[Tuple[str, str], Optional[str]] = {}

    # ── Pair address ──────────────────────────────────────────────────────────

    def get_pair_address(self, token_a: str, token_b: str) -> Optional[str]:
        key = (token_a.lower(), token_b.lower())
        if key in self._pair_cache:
            return self._pair_cache[key]

        try:
            addr = self.factory.functions.getPair(
                Web3.to_checksum_address(token_a),
                Web3.to_checksum_address(token_b),
            ).call()
        except Exception as e:
            logger.warning(f"[{self.name}] getPair failed: {e}")
            self._pair_cache[key] = None
            return None

        if addr == "0x0000000000000000000000000000000000000000":
            logger.debug(f"[{self.name}] pair not found: {token_a[:8]}/{token_b[:8]}")
            self._pair_cache[key] = None
            return None

        self._pair_cache[key] = addr
        return addr

    # ── Reserves ─────────────────────────────────────────────────────────────

    def get_reserves(self, pair_address: str) -> Optional[Dict]:
        try:
            pair = self.w3.eth.contract(
                address=Web3.to_checksum_address(pair_address),
                abi=PAIR_ABI,
            )
            r0, r1, _ = pair.functions.getReserves().call()
            t0        = pair.functions.token0().call()
            t1        = pair.functions.token1().call()
            return {"reserve0": r0, "reserve1": r1, "token0": t0, "token1": t1}
        except Exception as e:
            logger.error(f"[{self.name}] getReserves failed on {pair_address}: {e}")
            return None

    # ── AMM math ─────────────────────────────────────────────────────────────

    def get_amount_out(self, amount_in_wei: int, reserve_in: int, reserve_out: int) -> int:
        """Exact V2 AMM formula using this DEX's fee."""
        amount_with_fee = amount_in_wei * self.fee_num
        numerator       = amount_with_fee * reserve_out
        denominator     = reserve_in * self.fee_den + amount_with_fee
        return numerator // denominator

    def calc_spot_price(
        self,
        reserve_in: int,
        reserve_out: int,
        decimals_in: int = 18,
        decimals_out: int = 18,
    ) -> float:
        """Spot price: how many token_out per 1 token_in (after fee)."""
        if reserve_in == 0:
            return 0.0
        r_in  = reserve_in  / (10 ** decimals_in)
        r_out = reserve_out / (10 ** decimals_out)
        return (r_out / r_in) * (1 - self.fee)

    # ── Full pair scan ────────────────────────────────────────────────────────

    def scan_pairs(self) -> Dict[str, Dict]:
        """
        Returns {pair_name: {price, reserve_in, reserve_out, pair_address, token_a, token_b, dex_key, fee_num, fee_den}}
        for all WATCHED_PAIRS that exist on this DEX.
        """
        results = {}
        for token_a, token_b, name in WATCHED_PAIRS:
            pair_addr = self.get_pair_address(token_a, token_b)
            if not pair_addr:
                continue

            reserves = self.get_reserves(pair_addr)
            if not reserves:
                continue

            if reserves["token0"].lower() == token_a.lower():
                r_in, r_out = reserves["reserve0"], reserves["reserve1"]
            else:
                r_in, r_out = reserves["reserve1"], reserves["reserve0"]

            # Skip dust/dead pools
            if r_in < MIN_RESERVE_WEI or r_out < MIN_RESERVE_WEI:
                logger.debug(f"[{self.name}] {name} skipped — reserve below MIN_RESERVE_WEI")
                continue

            price = self.calc_spot_price(r_in, r_out)
            results[name] = {
                "price":        price,
                "reserve_in":   r_in,
                "reserve_out":  r_out,
                "pair_address": pair_addr,
                "token_a":      token_a,
                "token_b":      token_b,
                "dex_key":      self.dex_key,
                "fee_num":      self.fee_num,
                "fee_den":      self.fee_den,
            }
            logger.debug(f"[{self.name}] {name} → {price:.6f}")

        return results


# ─────────────────────────────────────────────────────────────────────────────


class MultiDexScanner:
    """
    Aggregates price data from ALL configured DEXes.
    Returns: { dex_key: { pair_name: data_dict } }
    """

    def __init__(self, w3: Web3):
        self.scanners: Dict[str, DexScanner] = {
            key: DexScanner(w3, key) for key in DEXES
        }

    def scan_all(self) -> Dict[str, Dict[str, Dict]]:
        all_data: Dict[str, Dict[str, Dict]] = {}
        for dex_key, scanner in self.scanners.items():
            try:
                all_data[dex_key] = scanner.scan_pairs()
            except Exception as e:
                logger.error(f"Scan failed for {dex_key}: {e}")
                all_data[dex_key] = {}
        return all_data

    def get_dex_scanner(self, dex_key: str) -> DexScanner:
        return self.scanners[dex_key]


# ── Backward-compatible alias (used by legacy bot_engine / tx_builder) ────────

class PriceScanner(DexScanner):
    """Legacy shim — scans only PancakeSwap V2."""

    def __init__(self, w3: Web3):
        super().__init__(w3, "pancakeswap")

    def scan_all_pairs(self) -> Dict[str, Dict]:
        return self.scan_pairs()

    # Legacy signature kept
    def calc_price(self, reserve_in, reserve_out, decimals_in=18, decimals_out=18) -> float:
        return self.calc_spot_price(reserve_in, reserve_out, decimals_in, decimals_out)
