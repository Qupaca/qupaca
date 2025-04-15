const { ethers } = require("hardhat");
const { deployConfig_testnet, deployConfig_mainnet } = require("../configs/config");

module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployConfig = network.name === "saigon" ? deployConfig_testnet : deployConfig_mainnet;
  const { defaultReceiver } = deployConfig.feeReceiver;

  const governanceManager = await get("GovernanceManager");
  if (!governanceManager) {
    throw new Error("GovernanceManager not deployed");
  }

  if(!defaultReceiver) {
    throw new Error("Default receiver not set");
  }

  const feeReceiver = await deploy("FeeReceiver", {
    from: deployer,
    args: [
      ethers.ZeroAddress,  // weth address (using zero address for native token)
      governanceManager.address  // manager address
    ],
    log: true,
    waitConfirmations: 5,
  });

  console.log("FeeReceiver address: ", feeReceiver.address);

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setFeeReceiver",
    feeReceiver.address
  );
  console.log("set fee receiver to governance manager");

  const feeReceiverContract = await ethers.getContractAt("FeeReceiver", feeReceiver.address);
  const currentAllocation = await feeReceiverContract.allocation(defaultReceiver);

  console.log("current allocation:", currentAllocation);
  console.log(currentAllocation == 0);
  
  if (currentAllocation == 0) {
    await execute(
      "FeeReceiver",
      { from: deployer, log: true },
      "addRecipient",
      defaultReceiver,
      100,
      true
    );
    console.log("add default recipient");
  } else {
    console.log("default recipient already exists with allocation:", currentAllocation);
  }
};

module.exports.tags = ["FeeReceiver", "Deploy1"];
module.exports.dependencies = ["Manager"]; 