// base-liquidity-mining/scripts/rewards-analysis.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function analyzeMiningRewards() {
  console.log("Analyzing rewards for Base Liquidity Mining Program...");
  
  const miningAddress = "0x...";
  const mining = await ethers.getContractAt("LiquidityMining", miningAddress);
  
  // Получение информации о наградах
  const rewardsAnalysis = {
    timestamp: new Date().toISOString(),
    miningAddress: miningAddress,
    totalRewardsDistributed: "0",
    totalMiners: 0,
    averageRewardsPerUser: "0",
    rewardDistribution: [],
    poolDistribution: [],
    topMiners: []
  };
  
  // Получение общей статистики
  const totalRewards = await mining.getTotalRewardsDistributed();
  rewardsAnalysis.totalRewardsDistributed = totalRewards.toString();
  
  const totalMiners = await mining.getTotalMiners();
  rewardsAnalysis.totalMiners = totalMiners.toNumber();
  
  // Получение средних наград
  if (totalMiners.gt(0)) {
    const avgRewards = totalRewards.div(totalMiners);
    rewardsAnalysis.averageRewardsPerUser = avgRewards.toString();
  }
  
  // Получение распределения наград по пулам
  const pools = await mining.getAllPools();
  console.log("Mining pools:", pools.length);
  
  for (let i = 0; i < pools.length; i++) {
    const poolAddress = pools[i];
    const poolRewards = await mining.getPoolRewards(poolAddress);
    
    rewardsAnalysis.poolDistribution.push({
      poolAddress: poolAddress,
      rewards: poolRewards.toString()
    });
  }
  
  // Получение топ майнеров
  const topMiners = await mining.getTopMiners(10);
  console.log("Top miners:", topMiners.length);
  
  rewardsAnalysis.topMiners = topMiners.map(miner => ({
    minerAddress: miner.miner,
    totalRewards: miner.totalRewards.toString(),
    stakedAmount: miner.stakedAmount.toString()
  }));
  
  // Анализ эффективности
  const efficiencyAnalysis = {
    totalRewards: totalRewards.toString(),
    totalMiners: totalMiners.toString(),
    avgRewardsPerMiner: rewardsAnalysis.averageRewardsPerUser,
    rewardDistributionRatio: rewardsAnalysis.poolDistribution
  };
  
  // Сохранение отчета
  fs.writeFileSync(`./rewards/rewards-analysis-${Date.now()}.json`, JSON.stringify(efficiencyAnalysis, null, 2));
  
  console.log("Rewards analysis completed successfully!");
  console.log("Total rewards:", rewardsAnalysis.totalRewardsDistributed);
  console.log("Top miners:", rewardsAnalysis.topMiners.length);
}

analyzeMiningRewards()
  .catch(error => {
    console.error("Rewards analysis error:", error);
    process.exit(1);
  });
