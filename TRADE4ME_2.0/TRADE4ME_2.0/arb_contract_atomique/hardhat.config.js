// hardhat.config.js — Configuration Hardhat pour déploiement BSC
require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,      // Optimise pour l'exécution répétée (bot = beaucoup d'appels)
      },
    },
  },

  networks: {
    // ── BSC Testnet (tests avec vrais DEX, argent factice) ──────────────────
    bscTestnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      accounts: [process.env.PRIVATE_KEY],
      gasPrice: 10_000_000_000,   // 10 gwei
    },

    // ── BSC Mainnet (production) ─────────────────────────────────────────────
    bsc: {
      url: process.env.BSC_RPC_URL || "https://bsc-dataseed1.binance.org/",
      chainId: 56,
      accounts: [process.env.PRIVATE_KEY],
      gasPrice: 5_000_000_000,    // 5 gwei
    },
  },

  // Vérification du contrat sur BSCScan (optionnel mais recommandé)
  etherscan: {
    apiKey: {
      bsc:        process.env.BSCSCAN_API_KEY || "",
      bscTestnet: process.env.BSCSCAN_API_KEY || "",
    },
  },
};
