module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const governanceManager = await get("GovernanceManager");
  const wrappedAssetManager = await get("WrappedAssetManager");
  const houseManager = await get("HouseManager");
  const tokenHouseImpl = await get("TokenHouse");
  const projectTokensManager = await get("ProjectTokensManager");

  if (!governanceManager || !wrappedAssetManager || !houseManager || !tokenHouseImpl || !projectTokensManager) {
    throw new Error("Dependencies not deployed");
  }

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setProjectTokens",
    projectTokensManager.address
  );
  console.log("ProjectTokensManager set in GovernanceManager");

  await execute(
    "WrappedAssetManager",
    { from: deployer, log: true },
    "setHouseManager",
    houseManager.address
  );
  console.log("HouseManager set in WrappedAssetManager");

  await execute(
    "TokenHouse",
    { from: deployer, log: true },
    "enableCloning"
  );
  console.log("TokenHouse isImplementation set");
};

module.exports.tags = ["SetProjectManagerConfig", "Deploy1"];
module.exports.dependencies = ["ProjectTokenManager"]; 