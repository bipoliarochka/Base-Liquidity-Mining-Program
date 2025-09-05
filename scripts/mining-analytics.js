// base-liquidity-mining/scripts/analytics.js
const { ethers } = require("hardhat");

async function analyzeMiningProgram() {
  console.log("Analyzing Base Liquidity Mining Program...");
  
  const miningAddress = "0x...";
  const mining = await ethers.getContractAt("LiquidityMining", miningAddress);
  
  // Получение статистики майнинга
  const miningStats = await mining.getMiningStats();
  console.log("Mining Stats:", {
    totalRewards: miningStats.totalRewards.toString(),
    totalStaked: miningStats.totalStaked.toString(),
    totalMiners: miningStats.totalMiners.toString(),
    totalPools: miningStats.totalPools.toString(),
    avgAPR: miningStats.avgAPR.toString()
  });
  
  // Получение информации о пулах
  const poolStats = await mining.getPoolStats();
  console.log("Pool Stats:", {
    totalPools: poolStats.totalPools.toString(),
    activePools: poolStats.activePools.toString(),
    totalRewardsDistributed: poolStats.totalRewardsDistributed.toString()
  });
  
  // Получение информации о пользователях
  const userStats = await mining.getUserStats();
  console.log("User Stats:", {
    totalUsers: userStats.totalUsers.toString(),
    activeUsers: userStats.activeUsers.toString(),
    avgStaked: userStats.avgStaked.toString()
  });
  
  // Получение информации о наградах
  const rewardStats = await mining.getRewardStats();
  console.log("Reward Stats:", {
    totalRewardsClaimed: rewardStats.totalRewardsClaimed.toString(),
    avgRewardPerUser: rewardStats.avgRewardPerUser.toString()
  });
  
  // Генерация аналитического отчета
  const fs = require("fs");
  const analysis = {
    timestamp: new Date().toISOString(),
    miningAddress: miningAddress,
    analysis: {
      miningStats: miningStats,
      poolStats: poolStats,
      userStats: userStats,
      rewardStats: rewardStats
    }
  };
  
  fs.writeFileSync("./reports/mining-analysis.json", JSON.stringify(analysis, null, 2));
  
  console.log("Mining analysis completed successfully!");
}

analyzeMiningProgram()
  .catch(error => {
    console.error("Analysis error:", error);
    process.exit(1);
  });
