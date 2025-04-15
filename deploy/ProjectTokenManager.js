module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const governanceManager = await get("GovernanceManager");
  if (!governanceManager) {
    throw new Error("GovernanceManager not deployed");
  }

  const wrappedAssetImpl = await deploy("WrappedAsset", {
    from: deployer,
    log: true,
    waitConfirmations: 5,
  });
  console.log("WrappedAsset implementation deployed to:", wrappedAssetImpl.address);

  const tokenHouseImpl = await deploy("TokenHouse", {
    from: deployer,
    args: [governanceManager.address],
    log: true,
    waitConfirmations: 5,
  });
  console.log("TokenHouse implementation deployed to:", tokenHouseImpl.address);

  const wrappedAssetManager = await deploy("WrappedAssetManager", {
    from: deployer,
    args: [wrappedAssetImpl.address, governanceManager.address],
    log: true,
    waitConfirmations: 5,
  });
  console.log("WrappedAssetManager deployed to:", wrappedAssetManager.address);

  const houseManager = await deploy("HouseManager", {
    from: deployer,
    args: [tokenHouseImpl.address, governanceManager.address],
    log: true,
    waitConfirmations: 5,
  });
  console.log("HouseManager deployed to:", houseManager.address);

  const projectTokensManager = await deploy("ProjectTokensManager", {
    from: deployer,
    args: [
      wrappedAssetManager.address,
      houseManager.address,
      governanceManager.address
    ],
    log: true,
    waitConfirmations: 5,
  });
  console.log("ProjectTokensManager deployed to:", projectTokensManager.address);
};

module.exports.tags = ["ProjectTokenManager", "Deploy1"];
module.exports.dependencies = ["Manager"];