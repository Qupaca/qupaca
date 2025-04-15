const { deployConfig_testnet, deployConfig_mainnet } = require("../configs/config");

module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const governanceManager = await get("GovernanceManager");

  const deployConfig = network.name === "saigon" ? deployConfig_testnet : deployConfig_mainnet;
  const { PAUSE_MANAGER_ADDRESS, SUPRA_ROUTER_ADDRESS, SUPRA_CLIENT_ADDRESS } = deployConfig.manager;
  if (!governanceManager) {
    throw new Error("dependent contracts not deployed");
  }

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setPauseManager",
    PAUSE_MANAGER_ADDRESS
  );
  console.log("set pause manager to governance manager");

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setRNG",
    SUPRA_ROUTER_ADDRESS
  );
  console.log("set RNG to governance manager");

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setSupraClientAddress",
    SUPRA_CLIENT_ADDRESS
  );
  console.log("set RNG to governance manager");

};

module.exports.tags = ["SetManagerConfig", "Deploy1"];
module.exports.dependencies = ["Manager"];