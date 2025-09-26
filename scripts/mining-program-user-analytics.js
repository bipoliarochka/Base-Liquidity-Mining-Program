// base-liquidity-mining/scripts/user-analytics.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function analyzeMiningProgramUserBehavior() {
  console.log("Analyzing user behavior for Base Liquidity Mining Program...");
  
  const miningAddress = "0x...";
  const mining = await ethers.getContractAt("LiquidityMining", miningAddress);
  
  // Анализ пользовательского поведения
  const userAnalytics = {
    timestamp: new Date().toISOString(),
    miningAddress: miningAddress,
    userDemographics: {},
    engagementMetrics: {},
    miningPatterns: {},
    userSegments: {},
    recommendations: []
  };
  
  try {
    // Демография пользователей
    const userDemographics = await mining.getUserDemographics();
    userAnalytics.userDemographics = {
      totalUsers: userDemographics.totalUsers.toString(),
      activeUsers: userDemographics.activeUsers.toString(),
      newUsers: userDemographics.newUsers.toString(),
      returningUsers: userDemographics.returningUsers.toString(),
      userDistribution: userDemographics.userDistribution
    };
    
    // Метрики вовлеченности
    const engagementMetrics = await mining.getEngagementMetrics();
    userAnalytics.engagementMetrics = {
      avgSessionTime: engagementMetrics.avgSessionTime.toString(),
      dailyActiveUsers: engagementMetrics.dailyActiveUsers.toString(),
      weeklyActiveUsers: engagementMetrics.weeklyActiveUsers.toString(),
      monthlyActiveUsers: engagementMetrics.monthlyActiveUsers.toString(),
      userRetention: engagementMetrics.userRetention.toString(),
      engagementScore: engagementMetrics.engagementScore.toString()
    };
    
    // Паттерны майнинга
    const miningPatterns = await mining.getMiningPatterns();
    userAnalytics.miningPatterns = {
      avgMiningAmount: miningPatterns.avgMiningAmount.toString(),
      miningFrequency: miningPatterns.miningFrequency.toString(),
      popularPools: miningPatterns.popularPools,
      peakMiningHours: miningPatterns.peakMiningHours,
      averageMiningPeriod: miningPatterns.averageMiningPeriod.toString(),
      rewardDistributionRate: miningPatterns.rewardDistributionRate.toString()
    };
    
    // Сегментация пользователей
    const userSegments = await mining.getUserSegments();
    userAnalytics.userSegments = {
      casualMiners: userSegments.casualMiners.toString(),
      activeMiners: userSegments.activeMiners.toString(),
      frequentMiners: userSegments.frequentMiners.toString(),
      occasionalMiners: userSegments.occasionalMiners.toString(),
      highValueMiners: userSegments.highValueMiners.toString(),
      segmentDistribution: userSegments.segmentDistribution
    };
    
    // Анализ поведения
    if (parseFloat(userAnalytics.engagementMetrics.userRetention) < 65) {
      userAnalytics.recommendations.push("Low user retention - implement retention strategies");
    }
    
    if (parseFloat(userAnalytics.miningPatterns.rewardDistributionRate) < 90) {
      userAnalytics.recommendations.push("Low reward distribution rate - improve mining incentives");
    }
    
    if (parseFloat(userAnalytics.userSegments.highValueMiners) < 100) {
      userAnalytics.recommendations.push("Low high-value miners - focus on premium user acquisition");
    }
    
    if (userAnalytics.userSegments.casualMiners > userAnalytics.userSegments.activeMiners) {
      userAnalytics.recommendations.push("More casual miners than active miners - consider miner engagement");
    }
    
    // Сохранение отчета
    const analyticsFileName = `mining-user-analytics-${Date.now()}.json`;
    fs.writeFileSync(`./analytics/${analyticsFileName}`, JSON.stringify(userAnalytics, null, 2));
    console.log(`User analytics report created: ${analyticsFileName}`);
    
    console.log("Mining program user analytics completed successfully!");
    console.log("Recommendations:", userAnalytics.recommendations);
    
  } catch (error) {
    console.error("User analytics error:", error);
    throw error;
  }
}

analyzeMiningProgramUserBehavior()
  .catch(error => {
    console.error("User analytics failed:", error);
    process.exit(1);
  });
