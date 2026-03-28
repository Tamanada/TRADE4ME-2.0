# TRADE4ME 2.0

Bot d'arbitrage automatique BSC / PancakeSwap avec smart contract atomique.

## Structure du projet

```
TRADE4ME_2.0/
│
├── bot_pancakeswap_bsc/          # Bot Python — scanner + exécuteur
│   ├── bot_engine.py             # Point d'entrée — boucle principale
│   ├── price_scanner.py          # Lecture prix via getReserves()
│   ├── profit_calc.py            # Détection et calcul des opportunités
│   ├── tx_builder.py             # Transactions séquentielles (v1)
│   ├── config.py                 # Tokens, paires, paramètres
│   ├── abis.py                   # ABI PancakeSwap
│   ├── requirements.txt          # Dépendances Python
│   ├── .env.example              # Template variables d'environnement
│   └── README.md
│
└── arb_contract_atomique/        # Smart contract Solidity — atomique
    ├── contracts/
    │   └── ArbBot.sol            # Contrat principal (executeArb + flashSwapArb)
    ├── scripts/
    │   └── deploy.js             # Déploiement Hardhat
    ├── test/
    │   └── ArbBot.test.js        # Tests unitaires
    ├── contract_executor.py      # Remplace tx_builder.py (intégration contrat)
    ├── hardhat.config.js         # Config BSC Testnet + Mainnet
    └── README.md
```

## Démarrage rapide

### 1 — Bot Python (mode simulation)
```bash
cd bot_pancakeswap_bsc
pip install -r requirements.txt
cp .env.example .env   # puis édite avec ta clé privée
python bot_engine.py   # DRY_RUN=True par défaut
```

### 2 — Déployer le contrat atomique
```bash
cd arb_contract_atomique
npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
npx hardhat compile
npx hardhat run scripts/deploy.js --network bscTestnet  # Testnet d'abord !
npx hardhat run scripts/deploy.js --network bsc          # Mainnet ensuite
```

### 3 — Passer au contrat atomique
Dans `.env` du bot Python, ajoute :
```
ARB_CONTRACT_ADDRESS=0x...   # adresse après déploiement
```
Puis remplace `TxBuilder` par `ContractExecutor` dans `bot_engine.py`.

## Règles de sécurité

- Jamais de clé privée dans le code — toujours dans `.env`
- `.env` dans `.gitignore` — jamais sur GitHub
- Tester 24h en DRY_RUN avant de mettre du vrai argent
- Commencer avec 0.05–0.1 BNB maximum
- Déployer sur BSC Testnet avant le mainnet
