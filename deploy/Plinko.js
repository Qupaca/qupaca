const { deployConfig_testnet, deployConfig_mainnet } = require("../configs/config");

module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployConfig = network.name === "saigon" ? deployConfig_testnet : deployConfig_mainnet;
  const { 
    GAME_ID, 
    MIN_BUY_IN_GAS, 
    EXTRA_GAS_PER_BALL, 
    GAME_MODE,
    BUCKET_WEIGHTS,
    PAYOUTS,
    BOOST_ODDS,
    PAYOUT_REDUCTIONS,
    gasRecipient,
    betAmountLimitAddress,
    betAmountLimitAmount
  } = deployConfig.plinko;

  const governanceManager = await get("GovernanceManager");
  const history = await get("HistoryManager");
  
  if (!governanceManager || !history) {
    throw new Error("dependent contracts not deployed");
  }

  if (!gasRecipient) {
    throw new Error("gasRecipient not set");
  }

  const plinko = await deploy("Plinko", {
    from: deployer,
    args: [
      GAME_ID,
      history.address,
      MIN_BUY_IN_GAS,
      EXTRA_GAS_PER_BALL,
      governanceManager.address,
      gasRecipient
    ],
    log: true,
    waitConfirmations: 5,
  });

  console.log("Plinko address: ", plinko.address);

  await execute(
    "Plinko",
    { from: deployer, log: true },
    "setGameMode",
    GAME_MODE,
    BUCKET_WEIGHTS,
    PAYOUTS,
    BOOST_ODDS,
    PAYOUT_REDUCTIONS
  );
  console.log("set plinko game mode");

  await execute(
    "Plinko",
    { from: deployer, log: true },
    "setBetAmountLimits",
    betAmountLimitAddress,
    betAmountLimitAmount
  );
  console.log("set plinko bet amount limits");

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setIsGame",
    plinko.address,
    true
  );
  console.log("set plinko as game contract");
};

module.exports.tags = ["Plinko", "Deploy1"];
module.exports.dependencies = ["Manager", "History"];