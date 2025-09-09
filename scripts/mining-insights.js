// base-liquidity-mining/scripts/insights.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function generateMiningInsights() {
  console.log("Generating insights for Base Liquidity Mining Program...");
  
  const miningAddress = "0x...";
  const mining = await ethers.getContractAt("LiquidityMining", miningAddress);
  
  // Получение инсайтов
  const insights = {
    timestamp: new Date().toISOString(),
    miningAddress: miningAddress,
    programPerformance: {},
    userEngagement: {},
    rewardDistribution: {},
    growthMetrics: {},
    improvementRecommendations: []
  };
  
  // Производительность программы
  const programPerformance = await mining.getProgramPerformance();
  insights.programPerformance = {
    totalRewards: programPerformance.totalRewards.toString(),
    totalMiners: programPerformance.totalMiners.toString(),
    totalStaked: programPerformance.totalStaked.toString(),
    avgAPR: programPerformance.avgAPR.toString()
  };
  
  // Участие пользователей
  const userEngagement = await mining.getUserEngagement();
  insights.userEngagement = {
    activeMiners: userEngagement.activeMiners.toString(),
    newMiners: userEngagement.newMiners.toString(),
    retentionRate: userEngagement.retentionRate.toString(),
    avgStake: userEngagement.avgStake.toString()
  };
  
  // Распределение наград
  const rewardDistribution = await mining.getRewardDistribution();
  insights.rewardDistribution = {
    totalRewardsDistributed: rewardDistribution.totalRewardsDistributed.toString(),
    avgRewardPerMiner: rewardDistribution.avgRewardPerMiner.toString(),
    rewardConcentration: rewardDistribution.rewardConcentration.toString()
  };
  
  // Метрики роста
  const growthMetrics = await mining.getGrowthMetrics();
  insights.growthMetrics = {
    userGrowth: growthMetrics.userGrowth.toString(),
    volumeGrowth: growthMetrics.volumeGrowth.toString(),
    rewardGrowth: growthMetrics.rewardGrowth.toString(),
    engagementGrowth: growthMetrics.engagementGrowth.toString()
  };
  
  // Рекомендации по улучшению
  if (parseFloat(insights.userEngagement.retentionRate) < 70) {
    insights.improvementRecommendations.push("Improve user retention strategies");
  }
  
  if (parseFloat(insights.programPerformance.avgAPR) < 500) { // 5%
    insights.improvementRecommendations.push("Increase APR to attract more participants");
  }
  
  // Сохранение инсайтов
  const fileName = `mining-insights-${Date.now()}.json`;
  fs.writeFileSync(`./insights/${fileName}`, JSON.stringify(insights, null, 2));
  
  console.log("Mining insights generated successfully!");
  console.log("File saved:", fileName);
}

generateMiningInsights()
  .catch(error => {
    console.error("Insights error:", error);
    process.exit(1);
  });
