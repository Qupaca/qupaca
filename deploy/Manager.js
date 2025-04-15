const { deployConfig_testnet, deployConfig_mainnet } = require("../configs/config");

module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployConfig = network.name === "saigon" ? deployConfig_testnet : deployConfig_mainnet;
  const {owner, feeSetter} = deployConfig.manager;

  if (!owner || !feeSetter) {
    throw new Error("owner or feeSetter not set");
  }

  const governanceManager = await deploy("GovernanceManager", {
    from: deployer,
    args: [
      owner, 
      feeSetter
    ],
    log: true,
    waitConfirmations: 5,
  });

  console.log("GovernanceManager address: ", governanceManager.address);
};

module.exports.tags = ["Manager", "Deploy1"];
module.exports.dependencies = ["VerifyContracts"];