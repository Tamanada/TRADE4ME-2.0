# demo.py -- TRADE4ME 2.0 Demo Mode
# No wallet, no private key required.
# Parallel RPC calls for fast scanning on public nodes.
#
# Run: python demo.py

import sys
import os
os.environ.setdefault("PYTHONIOENCODING", "utf-8")
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import time
import requests as _req
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
from web3 import Web3

# -- Config -------------------------------------------------------------------

RPC_NODES = [
    "https://bsc-dataseed1.binance.org/",
    "https://bsc-dataseed2.binance.org/",
    "https://bsc-dataseed3.binance.org/",
    "https://bsc-dataseed4.binance.org/",
]

SCAN_INTERVAL  = 15    # seconds between scans
MAX_WORKERS    = 12    # parallel RPC threads
CAPITAL_BNB    = 0.5
BNB_PRICE_USD  = 300.0
MIN_PROFIT_USD = 0.5

# Top 6 most liquid pairs for demo (full bot scans 21)
DEMO_PAIRS = [
    ("WBNB/BUSD",  "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"),
    ("WBNB/USDT",  "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c", "0x55d398326f99059fF775485246999027B3197955"),
    ("ETH/WBNB",   "0x2170Ed0880ac9A755fd29B2688956BD959F933F8",  "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"),
    ("BTCB/WBNB",  "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c",  "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"),
    ("CAKE/WBNB",  "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82", "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"),
    ("BSW/WBNB",   "0x965F527D9159dCe6288a2219DB51fc6Eef120dD1",  "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"),
]

DEXES = {
    "PancakeSwap": {"factory": "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73", "fee_num": 9975},
    "BiSwap":      {"factory": "0x858E3312ed3A876947EA49d572A7C42DE08af7EE", "fee_num": 9990},
    "BabySwap":    {"factory": "0x86407bEa2078ea5f5EB5A52B2caA963bC1F889Da", "fee_num": 9980},
    "MDEX":        {"factory": "0x3CD1C46068dAEa5Ebb0d3f55F6915B10648062B8", "fee_num": 9970},
}

FACTORY_ABI = [{"constant":True,"inputs":[{"name":"tokenA","type":"address"},{"name":"tokenB","type":"address"}],"name":"getPair","outputs":[{"name":"pair","type":"address"}],"type":"function"}]
PAIR_ABI    = [{"constant":True,"inputs":[],"name":"getReserves","outputs":[{"name":"_reserve0","type":"uint112"},{"name":"_reserve1","type":"uint112"},{"name":"_blockTimestampLast","type":"uint32"}],"type":"function"},{"constant":True,"inputs":[],"name":"token0","outputs":[{"name":"","type":"address"}],"type":"function"}]

# -- Colours ------------------------------------------------------------------
RESET="\033[0m"; GREEN="\033[92m"; YELLOW="\033[93m"
CYAN="\033[96m"; BOLD="\033[1m"; DIM="\033[2m"
def G(s): return f"{GREEN}{s}{RESET}"
def Y(s): return f"{YELLOW}{s}{RESET}"
def C(s): return f"{CYAN}{s}{RESET}"
def B(s): return f"{BOLD}{s}{RESET}"
def D(s): return f"{DIM}{s}{RESET}"
def sep(c="-",n=72): print(D(c*n))

# -- Scanner ------------------------------------------------------------------

_pair_cache = {}   # (factory, tokA, tokB) -> pair_address

def fetch_pair_data(w3, dex_name, factory_addr, fee_num, pair_name, tok_a, tok_b):
    """Fetches price + reserves for one (DEX, pair) combo. Runs in thread."""
    key = (factory_addr.lower(), tok_a.lower(), tok_b.lower())

    # Get pair address (cached after first call)
    if key not in _pair_cache:
        try:
            f = w3.eth.contract(address=Web3.to_checksum_address(factory_addr), abi=FACTORY_ABI)
            addr = f.functions.getPair(
                Web3.to_checksum_address(tok_a), Web3.to_checksum_address(tok_b)
            ).call()
            _pair_cache[key] = None if addr == "0x0000000000000000000000000000000000000000" else addr
        except:
            _pair_cache[key] = None

    pair_addr = _pair_cache[key]
    if not pair_addr:
        return None

    # Get reserves
    try:
        pair  = w3.eth.contract(address=Web3.to_checksum_address(pair_addr), abi=PAIR_ABI)
        r0, r1, _ = pair.functions.getReserves().call()
        t0    = pair.functions.token0().call()
        r_in, r_out = (r0, r1) if t0.lower() == tok_a.lower() else (r1, r0)
        if r_in == 0 or r_out < 10**16:
            return None
        price = (r_out / r_in) * (fee_num / 10000)
        return {"dex": dex_name, "pair": pair_name, "price": price,
                "r_in": r_in, "r_out": r_out, "fee_num": fee_num}
    except:
        return None

def get_amount_out(amount_in, r_in, r_out, fee_num):
    a = amount_in * fee_num
    return (a * r_out) // (r_in * 10000 + a)

# -- Main demo ----------------------------------------------------------------

def run_demo():
    print()
    print(B(C("  ================================================")))
    print(B(C("       TRADE4ME 2.0  --  Cross-DEX Arb Bot"      )))
    print(B(C("  ================================================")))
    print(B(f"           {G('[ DEMO MODE  --  READ ONLY ]')}"))
    print()

    # Connect — use direct HTTP ping to avoid slow is_connected()
    w3 = None
    for rpc in RPC_NODES:
        print(f"  Trying {rpc[:45]}... ", end="", flush=True)
        try:
            resp = _req.post(rpc,
                json={"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1},
                timeout=5)
            block = int(resp.json()["result"], 16)
            print(G("OK") + f"  block #{block:,}", flush=True)
            w3 = Web3(Web3.HTTPProvider(rpc, request_kwargs={"timeout": 10}))
            break
        except Exception as e:
            print(Y(f"skip ({str(e)[:30]})"), flush=True)

    if not w3:
        print(f"\n  Cannot connect to BSC. Check your internet.\n")
        sys.exit(1)

    print(f"\n  DEXes   : {C(' | '.join(DEXES.keys()))}")
    print(f"  Pairs   : {C(str(len(DEMO_PAIRS)))} (demo)  --  full bot scans 21")
    print(f"  Threads : {C(str(MAX_WORKERS))} parallel RPC calls")
    print(f"  Capital : {C(str(CAPITAL_BNB) + ' BNB')} (simulated -- no real funds)")
    sep()

    dex_names = list(DEXES.keys())
    scan_n    = 0

    while True:
        scan_n += 1
        ts = datetime.now().strftime("%H:%M:%S")
        print(f"\n{B(f'  Scan #{scan_n}')}  {D(ts)}")
        print(D("  Fetching prices in parallel..."))
        sep(".")

        t0 = time.time()

        # Build all tasks
        tasks = [
            (dex_name, dcfg["factory"], dcfg["fee_num"], pair_name, tok_a, tok_b)
            for dex_name, dcfg in DEXES.items()
            for pair_name, tok_a, tok_b in DEMO_PAIRS
        ]

        # Execute all in parallel
        results = {}   # pair_name -> {dex_name -> data}
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
            futures = {
                pool.submit(fetch_pair_data, w3, *task): task
                for task in tasks
            }
            for fut in as_completed(futures):
                data = fut.result()
                if data:
                    p = data["pair"]
                    d = data["dex"]
                    if p not in results:
                        results[p] = {}
                    results[p][d] = data

        elapsed = (time.time() - t0) * 1000

        # -- Price table
        col = 13
        hdr = f"  {'Pair':<13}" + "".join(f"{n[:col]:<{col}}" for n in dex_names) + "  Spread"
        print(B(hdr))
        sep(".")

        opportunities = []

        for pair_name, tok_a, tok_b in DEMO_PAIRS:
            dex_data = results.get(pair_name, {})
            if len(dex_data) < 2:
                continue

            prices = {d: v["price"] for d, v in dex_data.items()}
            lo_dex = min(prices, key=prices.get)
            hi_dex = max(prices, key=prices.get)
            lo_p   = prices[lo_dex]
            hi_p   = prices[hi_dex]
            spread = (hi_p - lo_p) / lo_p * 100 if lo_p > 0 else 0

            row = f"  {pair_name:<13}"
            for dn in dex_names:
                if dn in prices:
                    cell = f"{prices[dn]:.5f}"
                    if dn == lo_dex:
                        cell = G(cell + " ^")
                    elif dn == hi_dex:
                        cell = Y(cell + " v")
                    row += f"{cell:<{col+9}}"
                else:
                    row += f"{'n/a':<{col}}"

            s = f"{spread:.3f}%"
            if   spread >= 0.5:  s = B(G(s)) + "  *** HOT"
            elif spread >= 0.25: s = Y(s)    + "  (watch)"
            else:                s = D(s)
            print(row + "  " + s)

            # Profitability check
            if lo_dex in dex_data and hi_dex in dex_data:
                bd = dex_data[lo_dex]
                sd = dex_data[hi_dex]
                amount_in = int(CAPITAL_BNB * 1e18)
                amount_b  = get_amount_out(amount_in, bd["r_in"], bd["r_out"], bd["fee_num"])
                amount_a  = get_amount_out(amount_b,  sd["r_out"], sd["r_in"], sd["fee_num"])
                profit_wei = amount_a - amount_in
                gas_usd    = (400_000 * 5e9) / 1e18 * BNB_PRICE_USD
                profit_usd = (profit_wei / 1e18) * BNB_PRICE_USD - gas_usd
                if profit_usd > MIN_PROFIT_USD:
                    opportunities.append((pair_name, lo_dex, hi_dex, spread, profit_usd))

        sep(".")
        if opportunities:
            opportunities.sort(key=lambda x: x[4], reverse=True)
            print(B(G(f"  {len(opportunities)} OPPORTUNITY(IES) DETECTED:")))
            for pn, db, ds, sprd, pnl in opportunities[:3]:
                print(f"  >> {C(pn):<14}  BUY {G(db):<14}  SELL {Y(ds):<14}  spread {sprd:.3f}%  profit {B(G(f'${pnl:.3f}'))}")
            print(D("     (no transaction sent -- demo mode)"))
        else:
            print(D(f"  No profitable opportunity above ${MIN_PROFIT_USD} this scan"))

        print(D(f"\n  Done in {elapsed:.0f}ms | next in {SCAN_INTERVAL}s | Ctrl+C to stop"))
        sep()
        time.sleep(SCAN_INTERVAL)


if __name__ == "__main__":
    try:
        run_demo()
    except KeyboardInterrupt:
        print(f"\n\n  {Y('Demo stopped.')} No transactions were sent.\n")
