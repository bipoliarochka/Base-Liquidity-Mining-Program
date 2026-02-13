
const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying Base Liquidity Mining Program...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());


  const RewardToken = await ethers.getContractFactory("ERC20Token");
  const rewardToken = await RewardToken.deploy("Reward Token", "REWARD");
  await rewardToken.deployed();
  
  const StakingToken = await ethers.getContractFactory("ERC20Token");
  const stakingToken = await StakingToken.deploy("Staking Token", "STAKE");
  await stakingToken.deployed();

  // Деплой Liquidity Mining контракта
  const LiquidityMining = await ethers.getContractFactory("LiquidityMining");
  const mining = await LiquidityMining.deploy(
    rewardToken.address,
    ethers.utils.parseEther("1000000"), // 1 million reward tokens
    1000 // 10% fee percentage
  );

  await mining.deployed();

  console.log("Base Liquidity Mining Program deployed to:", mining.address);
  console.log("Reward Token deployed to:", rewardToken.address);
  console.log("Staking Token deployed to:", stakingToken.address);
  
  // Сохраняем адреса
  const fs = require("fs");
  const data = {
    mining: mining.address,
    rewardToken: rewardToken.address,
    stakingToken: stakingToken.address,
    owner: deployer.address
  };
  
  fs.writeFileSync("./config/deployment.json", JSON.stringify(data, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
