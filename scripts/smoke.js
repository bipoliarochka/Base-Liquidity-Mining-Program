require("dotenv").config(); 
const fs = require("fs");
const path = require("path");

async function main() {
  const depPath = path.join(__dirname, "..", "deployments.json");
  const deployments = JSON.parse(fs.readFileSync(depPath, "utf8"));

  const lmAddr = deployments.contracts.LiquidityMining;
  const lpAddr = deployments.contracts.LPToken;
  const rwAddr = deployments.contracts.RewardToken;

  const [owner, user] = await ethers.getSigners();
  const lm = await ethers.getContractAt("LiquidityMining", lmAddr);
  const lp = await ethers.getContractAt("RewardCalculator", lpAddr);
  const rw = await ethers.getContractAt("RewardCalculator", rwAddr);

  console.log("LM:", lmAddr);

  const amt = ethers.utils.parseUnits("10", 18);
  await (await lp.mint(user.address, amt)).wait();
  await (await rw.mint(lmAddr, ethers.utils.parseUnits("1000", 18))).wait();

  await (await lp.connect(user).approve(lmAddr, amt)).wait();
  await (await lm.connect(user).deposit(amt)).wait();
  console.log("Deposited");

  if (hre.network.name === "hardhat") {
    await ethers.provider.send("evm_increaseTime", [5]);
    await ethers.provider.send("evm_mine", []);
  }

  await (await lm.connect(user).claim()).wait();
  console.log("Claimed");

  await (await lm.connect(user).emergencyWithdraw()).wait();
  console.log("EmergencyWithdraw OK");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

