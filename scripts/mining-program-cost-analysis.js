// base-liquidity-mining/scripts/cost-analysis.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function analyzeMiningProgramCosts() {
  console.log("Analyzing costs for Base Liquidity Mining Program...");
  
  const miningAddress = "0x...";
  const mining = await ethers.getContractAt("LiquidityMining", miningAddress);
  
  // Анализ затрат
  const costReport = {
    timestamp: new Date().toISOString(),
    miningAddress: miningAddress,
    costBreakdown: {},
    efficiencyMetrics: {},
    costOptimization: {},
    revenueAnalysis: {},
    recommendations: []
  };
  
  try {

    const costBreakdown = await mining.getCostBreakdown();
    costReport.costBreakdown = {
      developmentCost: costBreakdown.developmentCost.toString(),
      maintenanceCost: costBreakdown.maintenanceCost.toString(),
      operationalCost: costBreakdown.operationalCost.toString(),
      securityCost: costBreakdown.securityCost.toString(),
      rewardDistributionCost: costBreakdown.rewardDistributionCost.toString(),
      totalCost: costBreakdown.totalCost.toString()
    };
    
    // Метрики эффективности
    const efficiencyMetrics = await mining.getEfficiencyMetrics();
    costReport.efficiencyMetrics = {
      costPerMiner: efficiencyMetrics.costPerMiner.toString(),
      costPerReward: efficiencyMetrics.costPerReward.toString(),
      roi: efficiencyMetrics.roi.toString(),
      costEffectiveness: efficiencyMetrics.costEffectiveness.toString(),
      efficiencyScore: efficiencyMetrics.efficiencyScore.toString()
    };
    
    // Оптимизация затрат
    const costOptimization = await mining.getCostOptimization();
    costReport.costOptimization = {
      optimizationOpportunities: costOptimization.optimizationOpportunities,
      potentialSavings: costOptimization.potentialSavings.toString(),
      implementationTime: costOptimization.implementationTime.toString(),
      riskLevel: costOptimization.riskLevel
    };
    
    // Анализ доходов
    const revenueAnalysis = await mining.getRevenueAnalysis();
    costReport.revenueAnalysis = {
      totalRevenue: revenueAnalysis.totalRevenue.toString(),
      miningFees: revenueAnalysis.miningFees.toString(),
      platformFees: revenueAnalysis.platformFees.toString(),
      netProfit: revenueAnalysis.netProfit.toString(),
      profitMargin: revenueAnalysis.profitMargin.toString()
    };
    
    // Анализ затрат
    if (parseFloat(costReport.costBreakdown.totalCost) > 2000000) {
      costReport.recommendations.push("Review and optimize operational costs");
    }
    
    if (parseFloat(costReport.efficiencyMetrics.costPerReward) > 200000000000000000) { // 0.2 ETH
      costReport.recommendations.push("Reduce reward distribution costs for better efficiency");
    }
    
    if (parseFloat(costReport.revenueAnalysis.profitMargin) < 15) { // 15%
      costReport.recommendations.push("Improve profit margins through cost optimization");
    }
    
    if (parseFloat(costReport.costOptimization.potentialSavings) > 80000) {
      costReport.recommendations.push("Implement cost optimization measures");
    }
    
    // Сохранение отчета
    const costFileName = `mining-cost-analysis-${Date.now()}.json`;
    fs.writeFileSync(`./cost/${costFileName}`, JSON.stringify(costReport, null, 2));
    console.log(`Cost analysis report created: ${costFileName}`);
    
    console.log("Mining program cost analysis completed successfully!");
    console.log("Recommendations:", costReport.recommendations);
    
  } catch (error) {
    console.error("Cost analysis error:", error);
    throw error;
  }
}

analyzeMiningProgramCosts()
  .catch(error => {
    console.error("Cost analysis failed:", error);
    process.exit(1);
  });
