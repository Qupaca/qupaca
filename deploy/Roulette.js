const { deployConfig_testnet, deployConfig_mainnet } = require("../configs/config");

module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployConfig = network.name === "saigon" ? deployConfig_testnet : deployConfig_mainnet;
  const { GAME_ID, MIN_BUY_IN_GAS, BUY_IN_GAS_PER_GUESS, gasRecipient } = deployConfig.roulette;

  const governanceManager = await get("GovernanceManager");
  const history = await get("HistoryManager");
  
  if (!governanceManager || !history) {
    throw new Error("dependent contracts not deployed");
  }

  const roulette = await deploy("Roulette", {
    from: deployer,
    args: [
      GAME_ID,
      history.address,
      MIN_BUY_IN_GAS,
      BUY_IN_GAS_PER_GUESS,
      governanceManager.address,
      gasRecipient
    ],
    log: true,
    waitConfirmations: 5,
  });

  console.log("Roulette address: ", roulette.address);

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setIsGame",
    roulette.address,
    true
  );
  console.log("set roulette as game contract");
};

module.exports.tags = ["Roulette", "Deploy1"];
module.exports.dependencies = ["Manager", "History"];