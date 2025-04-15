module.exports = async ({ getNamedAccounts, deployments, network }) => {
  const { deploy, get, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const governanceManager = await get("GovernanceManager");
  if (!governanceManager) {
    throw new Error("GovernanceManager not deployed");
  }

  const history = await deploy("HistoryManager", {
    from: deployer,
    args: [
      governanceManager.address  // manager address
    ],
    log: true,
    waitConfirmations: 5,
  });

  console.log("HistoryManager address: ", history.address);
};

module.exports.tags = ["History", "Deploy1"];
module.exports.dependencies = ["Manager"];