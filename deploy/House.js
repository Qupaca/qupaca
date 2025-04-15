module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const governanceManager = await get("GovernanceManager");
  if (!governanceManager) {
    throw new Error("GovernanceManager not deployed");
  }

  const house = await deploy("House", {
    from: deployer,
    args: [
      governanceManager.address 
    ],
    log: true,
    waitConfirmations: 5,
  });

  console.log("House address: ", house.address);

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setHouse",
    house.address
  );
  console.log("set house to governance manager");
};

module.exports.tags = ["House", "Deploy1"];
module.exports.dependencies = ["Manager"];