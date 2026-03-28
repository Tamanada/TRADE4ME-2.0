// scripts/deploy.js — Déploie ArbBot.sol sur BSC

const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("═══════════════════════════════════════════");
  console.log("  Déploiement ArbBot — BSC");
  console.log("═══════════════════════════════════════════");
  console.log(`  Deployer  : ${deployer.address}`);

  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`  Balance   : ${ethers.formatEther(balance)} BNB`);

  // Déploie le contrat
  console.log("\n  Déploiement en cours...");
  const ArbBot = await ethers.getContractFactory("ArbBot");
  const arbBot = await ArbBot.deploy();
  await arbBot.waitForDeployment();

  const address = await arbBot.getAddress();
  console.log(`\n  ✓ ArbBot déployé à : ${address}`);
  console.log(`\n  Sauvegarde l'adresse dans ton .env :`);
  console.log(`  ARB_CONTRACT_ADDRESS=${address}`);
  console.log("\n═══════════════════════════════════════════");
  console.log("  Vérification BSCScan (optionnel) :");
  console.log(`  npx hardhat verify --network bsc ${address}`);
  console.log("═══════════════════════════════════════════");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
