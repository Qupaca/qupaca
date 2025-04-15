const { deployConfig_testnet, deployConfig_mainnet } = require("../configs/config");

module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const deployConfig = network.name === "saigon" ? deployConfig_testnet : deployConfig_mainnet;
  const { GAME_ID, REEL1, REEL2, REEL3, MIN_BUY_IN_GAS, BUY_IN_GAS_PER_SPIN, BOOST_ODDS, PAYOUT_REDUCTIONS, id1s, id2s, id3s, payouts, gasRecipient, betAmountLimitAddress, betAmountLimitAmount } = deployConfig.slots;

  const governanceManager = await get("GovernanceManager");
  const history = await get("HistoryManager");
  
  if (!governanceManager || !history) {
    throw new Error("dependent contracts not deployed");
  }

  if (!gasRecipient) {
    throw new Error("gasRecipient not set");
  }

  const slots = await deploy("Slots", {
    from: deployer,
    args: [
      GAME_ID,
      history.address,
      governanceManager.address,
      REEL1,
      REEL2,
      REEL3,
      MIN_BUY_IN_GAS,
      BUY_IN_GAS_PER_SPIN,
      BOOST_ODDS,
      PAYOUT_REDUCTIONS,
      gasRecipient
    ],
    log: true,
    waitConfirmations: 5,
  });

  console.log("Slots deployed address: ", slots.address);

  await execute(
    "Slots",
    { from: deployer, log: true },
    "batchSetPayouts",
    id1s,
    id2s,
    id3s,
    payouts
  );
  console.log("set slots payouts");

  await execute(
    "Slots",
    { from: deployer, log: true },
    "setBetAmountLimits",
    betAmountLimitAddress,
    betAmountLimitAmount
  );
  console.log("set slots bet amount limits");

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setIsGame",
    slots.address,
    true
  );
  console.log("set slots is game");
};

module.exports.tags = ["Slots", "Deploy1"];
module.exports.dependencies = ["Manager", "History"]; 