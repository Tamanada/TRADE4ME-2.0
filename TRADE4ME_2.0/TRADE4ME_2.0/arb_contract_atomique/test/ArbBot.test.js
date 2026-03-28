// test/ArbBot.test.js — Tests unitaires avec Hardhat + fork BSC mainnet

const { expect }  = require("chai");
const { ethers }  = require("hardhat");

// Adresses BSC mainnet
const WBNB  = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c";
const BUSD  = "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56";
const ROUTER = "0x10ED43C718714eb63d5aA57B78B54704E256024E";

// ABI minimal WBNB pour déposer du BNB → WBNB
const WBNB_ABI = [
  "function deposit() external payable",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address) external view returns (uint256)",
];

describe("ArbBot", function () {
  let arbBot, owner, wbnb;

  before(async function () {
    // Ce test nécessite un fork BSC : npx hardhat test --network hardhat
    // avec hardhat.config.js configuré pour forker BSC
    [owner] = await ethers.getSigners();

    const ArbBot = await ethers.getContractFactory("ArbBot");
    arbBot = await ArbBot.deploy();
    await arbBot.waitForDeployment();

    wbnb = new ethers.Contract(WBNB, WBNB_ABI, owner);
  });

  it("doit être déployé avec le bon owner", async function () {
    expect(await arbBot.owner()).to.equal(owner.address);
  });

  it("simulateArb() retourne des données cohérentes", async function () {
    const amountIn = ethers.parseEther("0.1"); // 0.1 WBNB

    const [amountB, amountABack, profitOrLoss] = await arbBot.simulateArb(
      WBNB, BUSD, amountIn
    );

    console.log(`    WBNB in      : ${ethers.formatEther(amountIn)}`);
    console.log(`    BUSD reçus   : ${ethers.formatUnits(amountB, 18)}`);
    console.log(`    WBNB retour  : ${ethers.formatEther(amountABack)}`);
    console.log(`    Profit/Perte : ${ethers.formatEther(profitOrLoss)} WBNB`);

    // L'aller-retour sur la même paire doit être légèrement négatif (double fee)
    expect(amountABack).to.be.lt(amountIn);
    expect(profitOrLoss).to.be.lt(0n);
  });

  it("doit pouvoir être mis en pause par le owner", async function () {
    await arbBot.setPaused(true);
    expect(await arbBot.paused()).to.be.true;

    await arbBot.setPaused(false);
    expect(await arbBot.paused()).to.be.false;
  });

  it("refuse les BNB non sollicités", async function () {
    await expect(
      owner.sendTransaction({
        to: await arbBot.getAddress(),
        value: ethers.parseEther("0.01"),
      })
    ).to.be.revertedWith("ArbBot: no BNB accepted");
  });

  it("refuse le withdraw si pas le owner", async function () {
    const [, attacker] = await ethers.getSigners();
    await expect(
      arbBot.connect(attacker).withdraw(WBNB, 0)
    ).to.be.revertedWith("ArbBot: not owner");
  });
});
