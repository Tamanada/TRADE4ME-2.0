# config.py — Configuration centrale du bot TRADE4ME 2.0
import os
from dotenv import load_dotenv

load_dotenv()

# ── Wallet ───────────────────────────────────────────────────────────────────
PRIVATE_KEY    = os.getenv("PRIVATE_KEY")       # Never hardcode — always in .env
WALLET_ADDRESS = os.getenv("WALLET_ADDRESS")

# ── BSC Node ─────────────────────────────────────────────────────────────────
BSC_RPC_URL = os.getenv(
    "BSC_RPC_URL",
    "https://bsc-dataseed1.binance.org/"        # Public RPC (slow) — use QuickNode/Ankr in prod
)

# ── DEX Registry ─────────────────────────────────────────────────────────────
# Each entry: router, factory, fee (as decimal), fee_num/fee_den for integer math
# VERIFY addresses on-chain before using on mainnet.
DEXES = {
    "pancakeswap": {
        "name":     "PancakeSwap V2",
        "router":   "0x10ED43C718714eb63d5aA57B78B54704E256024E",
        "factory":  "0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73",
        "fee":      0.0025,   # 0.25%
        "fee_num":  9975,
        "fee_den":  10000,
    },
    "biswap": {
        "name":     "BiSwap",
        "router":   "0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8",
        "factory":  "0x858E3312ed3A876947EA49d572A7C42DE08af7EE",
        "fee":      0.001,    # 0.10%
        "fee_num":  9990,
        "fee_den":  10000,
    },
    "apeswap": {
        "name":     "ApeSwap",
        "router":   "0xcF0feBd3f17CEf5b47b0cD258aCf6780733b98B6",
        "factory":  "0x0841BD0B734E4F5853f0dD8d7Eb8496E4597B30B",
        "fee":      0.002,    # 0.20%
        "fee_num":  9980,
        "fee_den":  10000,
    },
    "mdex": {
        "name":     "MDEX",
        "router":   "0x7DAe51BD3E3376B8c7c4900E9107f12Be3AF1bA8",
        "factory":  "0x3CD1C46068dAEa5Ebb0d3f55F6915B10648062B8",
        "fee":      0.003,    # 0.30%
        "fee_num":  9970,
        "fee_den":  10000,
    },
}

# Legacy aliases kept for backward compatibility with existing imports
PANCAKE_FACTORY_V2 = DEXES["pancakeswap"]["factory"]
PANCAKE_ROUTER_V2  = DEXES["pancakeswap"]["router"]

# ── Tokens on BSC ────────────────────────────────────────────────────────────
# Binance-pegged tokens — verify addresses on bscscan.com before mainnet use

# Core / stablecoins
WBNB   = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c"
BUSD   = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
USDT   = "0x55d398326f99059fF775485246999027B3197955"
USDC   = "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d"

# Large-cap bridged
ETH    = "0x2170Ed0880ac9A755fd29B2688956BD959F933F8"   # Binance-pegged ETH
BTCB   = "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c"   # Binance-pegged BTC
XRP    = "0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE"   # Binance-pegged XRP
ADA    = "0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47"   # Binance-pegged ADA
DOT    = "0x7083609fCE4d1d8Dc0C979AAb8cf214346c6a2f4"   # Binance-pegged DOT
LINK   = "0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD"   # Binance-pegged LINK
LTC    = "0x4338665CBB7B2485A8855A139b75D5e34AB0DB94"   # Binance-pegged LTC
DOGE   = "0xbA2aE424d960c26247Dd6c32edC70B295c744C43"   # Binance-pegged DOGE
MATIC  = "0xCC42724C6683B7E57334c4E856f4c9965ED682bD"   # Binance-pegged MATIC
SOL    = "0x570A5D26f7765Ecb712C0924E4De545B89fD43dF"   # Binance-pegged SOL
ATOM   = "0x0Eb3a705fc54725037CC9e008bDede697f62F335"   # Binance-pegged ATOM

# BSC-native / DEX tokens (higher spread potential between DEXes)
CAKE   = "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82"   # PancakeSwap
XVS    = "0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63"   # Venus Protocol
BSW    = "0x965F527D9159dCe6288a2219DB51fc6Eef120dD1"   # BiSwap (native token)
BANANA = "0x603c7f932ED1fc6575303D8Fb018fDCBb0f39a95"   # ApeSwap (native token)
ALPACA = "0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F"   # Alpaca Finance

# Pairs to watch — format (token_A, token_B, human_name)
# 6 original + 15 new = 21 total
WATCHED_PAIRS = [
    # ── Original 6 ─────────────────────────────────────────
    (WBNB,   BUSD,   "WBNB/BUSD"),
    (WBNB,   USDT,   "WBNB/USDT"),
    (WBNB,   USDC,   "WBNB/USDC"),
    (BUSD,   USDT,   "BUSD/USDT"),
    (CAKE,   WBNB,   "CAKE/WBNB"),
    (ETH,    WBNB,   "ETH/WBNB"),

    # ── New 15 — large-cap bridged tokens ──────────────────
    (BTCB,   WBNB,   "BTCB/WBNB"),    # highest volume on BSC after BNB
    (BTCB,   BUSD,   "BTCB/BUSD"),    # frequent spread vs BTCB/WBNB route
    (ETH,    BUSD,   "ETH/BUSD"),     # second route for ETH arb
    (XRP,    WBNB,   "XRP/WBNB"),
    (ADA,    WBNB,   "ADA/WBNB"),
    (DOT,    WBNB,   "DOT/WBNB"),
    (LINK,   WBNB,   "LINK/WBNB"),
    (LTC,    WBNB,   "LTC/WBNB"),
    (DOGE,   WBNB,   "DOGE/WBNB"),
    (MATIC,  WBNB,   "MATIC/WBNB"),
    (SOL,    WBNB,   "SOL/WBNB"),
    (ATOM,   WBNB,   "ATOM/WBNB"),

    # ── BSC-native DEX tokens (best cross-DEX spread potential)
    (XVS,    WBNB,   "XVS/WBNB"),
    (BSW,    WBNB,   "BSW/WBNB"),     # BiSwap's own token — big spread on BiSwap vs others
    (BANANA, WBNB,   "BANANA/WBNB"),  # ApeSwap's own token — same logic
]

# ── Arbitrage parameters ──────────────────────────────────────────────────────
MIN_PROFIT_USD      = 0.5        # Minimum net profit in USD to execute a trade
SLIPPAGE_TOLERANCE  = 0.005      # 0.5% max accepted slippage
GAS_PRICE_GWEI      = 5          # BSC gas price (typically 3–7 gwei)
GAS_LIMIT_SWAP      = 400_000    # Estimated gas limit for a cross-DEX double swap
SCAN_INTERVAL_MS    = 300        # Price scan frequency in ms

# Minimum pool reserve to consider a pair (filters dead/dust pools).
# 10 tokens at 18 decimals ≈ ignores pools below ~$30 at BNB price.
# Raise to 100 * 10**18 for stricter filtering on low-cap tokens.
MIN_RESERVE_WEI     = 10 * 10**18

# Legacy: used by modules that still reference PANCAKE_FEE directly
PANCAKE_FEE = DEXES["pancakeswap"]["fee"]

# ── Profit sweeper — auto-transfer to cold wallet ────────────────────────────
AUTO_SWEEP           = os.getenv("AUTO_SWEEP", "false").lower() == "true"
COLD_WALLET_ADDRESS  = os.getenv("COLD_WALLET_ADDRESS", "")  # destination wallet
KEEP_CAPITAL_BNB     = float(os.getenv("KEEP_CAPITAL_BNB",  "0.5"))   # always keep this on bot wallet
SWEEP_THRESHOLD_BNB  = float(os.getenv("SWEEP_THRESHOLD_BNB", "0.2")) # sweep when profit exceeds this

# ── Simulation mode ──────────────────────────────────────────────────────────
DRY_RUN = True                  # Set False only after thorough testing
