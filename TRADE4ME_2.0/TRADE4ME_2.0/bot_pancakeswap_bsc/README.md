# Bot d'arbitrage BSC / PancakeSwap — Python

Bot d'arbitrage automatique sur Binance Smart Chain,
ciblant les pools PancakeSwap V2.

## Structure du projet

```
pancakeswap_arb_bot/
├── config.py          # Tokens, paires, paramètres
├── abis.py            # ABI partiels (Factory, Router, Pair, ERC-20)
├── price_scanner.py   # Lecture des prix via getReserves()
├── profit_calc.py     # Détection et calcul des opportunités
├── tx_builder.py      # Construction et envoi des transactions
├── bot_engine.py      # Boucle principale (point d'entrée)
├── .env.example       # Template variables d'environnement
├── requirements.txt   # Dépendances Python
└── README.md
```

## Installation

```bash
# 1. Crée un environnement virtuel
python -m venv venv
source venv/bin/activate          # Linux/Mac
# ou : venv\Scripts\activate      # Windows

# 2. Installe les dépendances
pip install -r requirements.txt

# 3. Configure le wallet
cp .env.example .env
# Édite .env avec ta clé privée et ton adresse wallet DÉDIÉS
nano .env
```

## Lancement

```bash
# Mode simulation (DRY_RUN=True dans config.py) — aucun fond dépensé
python bot_engine.py

# Mode réel — UNIQUEMENT après avoir testé en simulation
# Passe DRY_RUN = False dans config.py
python bot_engine.py
```

## Checklist sécurité avant de passer en mode réel

- [ ] Testé en DRY_RUN pendant au moins 24h
- [ ] Wallet dédié bot (jamais le wallet principal)
- [ ] Fichier .env dans .gitignore
- [ ] Capital limité (commence avec 0.1–0.5 BNB)
- [ ] Tous les tokens approuvés (approve_token() appelé une fois)
- [ ] RPC node privé configuré (pas le RPC public en prod)

## Limites de cette implémentation

- Les deux swaps sont séquentiels (pas atomiques) — risque entre les deux tx
- Pas de protection MEV / Flashbots (BSC n'a pas Flashbots mais il existe des solutions équivalentes)
- Stratégie simple aller-retour (A→B→A) — pas triangulaire
- Prix BNB/USD codé en dur (à remplacer par un oracle Chainlink)

## Amélioration recommandée : Smart contract atomique

Pour éliminer le risque entre swap1 et swap2, déploie un smart contract Solidity
qui effectue les deux swaps dans la même transaction. Si swap2 échoue, 
toute la transaction est annulée et tu ne perds que le gas.

## Disclaimer

Ce code est fourni à titre éducatif. L'arbitrage on-chain comporte des risques
financiers réels. Ne jamais investir plus que ce que tu es prêt à perdre.
