# ArbBot.sol — Contrat d'arbitrage atomique BSC / PancakeSwap

Smart contract Solidity déployable sur BSC qui exécute les deux swaps
dans **une seule transaction atomique**. Si le profit est insuffisant → revert
complet → tu ne perds que le gas.

## Structure

```
trade4me_arb_contract/
├── contracts/
│   └── ArbBot.sol          # Le contrat principal (2 modes)
├── scripts/
│   └── deploy.js           # Script de déploiement Hardhat
├── test/
│   └── ArbBot.test.js      # Tests unitaires
├── contract_executor.py    # Remplace tx_builder.py dans le bot Python
├── hardhat.config.js       # Config réseau BSC
└── README.md
```

## Les deux modes du contrat

### Mode 1 — executeArb() : capital propre
Tu envoies tes tokens au contrat, il fait les deux swaps atomiquement,
te renvoie capital + profit. Si profit < minProfit → revert.

### Mode 2 — flashSwapArb() : zéro capital
PancakeSwap prête les tokens GRATUITEMENT pour la durée d'une transaction.
Le contrat fait les swaps, rembourse l'emprunt + 0.25%, garde le reste.
Tu n'as besoin que de BNB pour le gas.

## Installation & déploiement

```bash
# 1. Installe Hardhat
npm init -y
npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox
npm install dotenv

# 2. Configure .env
echo "PRIVATE_KEY=0x..." >> .env
echo "BSC_RPC_URL=https://bsc-dataseed1.binance.org/" >> .env

# 3. Compile
npx hardhat compile

# 4. Tests (optionnel, nécessite fork BSC)
npx hardhat test

# 5. Déploie sur BSC Testnet d'abord !
npx hardhat run scripts/deploy.js --network bscTestnet

# 6. Déploie sur BSC Mainnet quand tout est OK
npx hardhat run scripts/deploy.js --network bsc

# 7. Copie l'adresse du contrat dans .env du bot Python
echo "ARB_CONTRACT_ADDRESS=0x..." >> ../pancakeswap_arb_bot/.env
```

## Intégration dans le bot Python

Dans `bot_engine.py`, remplace `TxBuilder` par `ContractExecutor` :

```python
# Avant (deux txs séquentielles)
from tx_builder import TxBuilder
tx_builder = TxBuilder(w3)
tx_builder.execute_arb(opp)

# Après (une seule tx atomique)
from contract_executor import ContractExecutor
executor = ContractExecutor(w3)

# Avec capital propre
executor.execute_arb(token_a, token_b, amount_in_wei, min_profit_wei)

# Ou en flash swap (zéro capital)
executor.flash_swap_arb(token_a, token_b, amount_in_wei, min_profit_wei)
```

## Checklist sécurité avant mainnet

- [ ] Testé sur BSC Testnet avec les vraies adresses PancakeSwap
- [ ] simulateArb() retourne des résultats cohérents
- [ ] Tests Hardhat passent tous
- [ ] Contrat vérifié sur BSCScan (code source public = confiance)
- [ ] withdraw() testé — tu peux récupérer les fonds
- [ ] setPaused() testé — coupe d'urgence fonctionnel
- [ ] Montant de test initial : 0.05–0.1 BNB maximum

## Audit recommandé avant gros capital

Pour des montants > 1 000 $, il est conseillé de faire auditer le contrat
par un service comme Code4rena, Sherlock, ou un auditeur indépendant.
Les bugs dans un smart contract = perte définitive des fonds.
