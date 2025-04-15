module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const governanceManager = await get("GovernanceManager");
  if (!governanceManager) {
    throw new Error("GovernanceManager not deployed");
  }

  const claimManager = await deploy("ClaimManager", {
    from: deployer,
    args: [
      governanceManager.address 
    ],
    log: true,
    waitConfirmations: 5,
  });

  console.log("ClaimManager address: ", claimManager.address);

  await execute(
    "GovernanceManager",
    { from: deployer, log: true },
    "setClaimManager",
    claimManager.address
  );
  console.log("set claim manager to governance manager");
};

module.exports.tags = ["ClaimManager", "Deploy1"];
module.exports.dependencies = ["Manager"]; 