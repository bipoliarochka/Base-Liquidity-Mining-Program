const fs = require("fs");
const path = require("path");
require("dotenv").config();

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  let lpToken = process.env.LP_TOKEN || "";
  let rewardToken = process.env.REWARD_TOKEN || "";

  // If not provided, deploy RewardCalculator as ERC20 helper if it exists in your repo
  if (!lpToken) {
    const T = await ethers.getContractFactory("RewardCalculator");
    const t = await T.deploy("LPToken", "LPT", 18);
    await t.deployed();
    lpToken = t.address;
    console.log("LPToken (RewardCalculator):", lpToken);
  }

  if (!rewardToken) {
    const T = await ethers.getContractFactory("RewardCalculator");
    const t = await T.deploy("RewardToken", "RWD", 18);
    await t.deployed();
    rewardToken = t.address;
    console.log("RewardToken (RewardCalculator):", rewardToken);
  }

  const rewardPerSecond = process.env.REWARD_PER_SECOND
    ? ethers.BigNumber.from(process.env.REWARD_PER_SECOND)
    : ethers.utils.parseUnits("1", 18);

  const LM = await ethers.getContractFactory("LiquidityMining");
  const lm = await LM.deploy(lpToken, rewardToken, rewardPerSecond);
  await lm.deployed();

  console.log("LiquidityMining:", lm.address);

  const out = {
    network: hre.network.name,
    chainId: (await ethers.provider.getNetwork()).chainId,
    deployer: deployer.address,
    contracts: {
      LPToken: lpToken,
      RewardToken: rewardToken,
      LiquidityMining: lm.address
    }
  };

  const outPath = path.join(__dirname, "..", "deployments.json");
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
  console.log("Saved:", outPath);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
