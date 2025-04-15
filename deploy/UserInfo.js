const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const governanceManager = await get("GovernanceManager");
  if (!governanceManager) {
    throw new Error("GovernanceManager not deployed");
  }

  const tokenWagerViewer = await deploy("TokenWagerViewer", {
    from: deployer,
    args: [],
    log: true,
    waitConfirmations: 5,
  });

  console.log("TokenWagerViewer address: ", tokenWagerViewer.address);

  const userInfoTracker = await deploy("UserInfo", {
    from: deployer,
    args: [
      "RON Wagered",           // name
      "RONw",                  // symbol
      tokenWagerViewer.address,  // wagerViewer
      ethers.ZeroAddress,      // weth address (using zero address for native token)
      governanceManager.address
    ],
    log: true,
    waitConfirmations: 5,
  });

  console.log("UserInfoTracker address: ", userInfoTracker.address);

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setUserInfoTracker",
    userInfoTracker.address
  );
  console.log("set user info tracker to governance manager");
};

module.exports.tags = ["UserInfo", "Deploy1"];
module.exports.dependencies = ["Manager"]; 