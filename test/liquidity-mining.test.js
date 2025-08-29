// base-liquidity-mining/test/liquidity-mining.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Base Liquidity Mining Program", function () {
  let mining;
  let rewardToken;
  let stakingToken;
  let owner;
  let addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();
    
    // Деплой токенов
    const RewardToken = await ethers.getContractFactory("ERC20Token");
    rewardToken = await RewardToken.deploy("Reward Token", "REWARD");
    await rewardToken.deployed();
    
    const StakingToken = await ethers.getContractFactory("ERC20Token");
    stakingToken = await StakingToken.deploy("Staking Token", "STAKE");
    await stakingToken.deployed();
    
    // Деплой Liquidity Mining
    const LiquidityMining = await ethers.getContractFactory("LiquidityMining");
    mining = await LiquidityMining.deploy(
      rewardToken.address,
      ethers.utils.parseEther("1000000"), // 1 million reward tokens
      1000 // 10% fee percentage
    );
    await mining.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await mining.owner()).to.equal(owner.address);
    });

    it("Should initialize with correct parameters", async function () {
      expect(await mining.rewardToken()).to.equal(rewardToken.address);
      expect(await mining.totalRewardTokens()).to.equal(ethers.utils.parseEther("1000000"));
    });
  });

  describe("Pool Creation", function () {
    it("Should create a pool", async function () {
      await expect(mining.createPool(
        stakingToken.address,
        1000,
        ethers.utils.parseEther("100"),
        Math.floor(Date.now() / 1000),
        Math.floor(Date.now() / 1000) + 3600
      )).to.emit(mining, "PoolCreated");
    });
  });

  describe("Staking Operations", function () {
    beforeEach(async function () {
      await mining.createPool(
        stakingToken.address,
        1000,
        ethers.utils.parseEther("100"),
        Math.floor(Date.now() / 1000),
        Math.floor(Date.now() / 1000) + 3600
      );
    });

    it("Should stake tokens", async function () {
      await stakingToken.mint(addr1.address, ethers.utils.parseEther("1000"));
      await stakingToken.connect(addr1).approve(mining.address, ethers.utils.parseEther("1000"));
      
      await expect(mining.connect(addr1).stake(stakingToken.address, ethers.utils.parseEther("100")))
        .to.emit(mining, "Staked");
    });
  });
});
