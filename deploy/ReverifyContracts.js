const { TASK_SOURCIFY } = require("hardhat-deploy");
const { network, deployments } = require("hardhat");

module.exports = async (hre) => {
  if (network.name === "ronin" || network.name === "saigon") {
    console.log("start reverify all contracts...");

    const contracts = [
      "GovernanceManager",
      "WrappedAssetManager",
      "HouseManager",
      "TokenHouse",
      "ProjectTokensManager",
      "FeeReceiver",
      "HistoryManager",
      "Slots",
      "UserInfo",
      "TokenWagerViewer"
    ];

    for (const contractName of contracts) {
      try {
        const deployment = await deployments.get(contractName);
        if (deployment) {
          console.log(`reverify ${contractName}...`);
          await hre.run(TASK_SOURCIFY, {
            endpoint: "https://sourcify.roninchain.com/server/",
            contractName: contractName,
            address: deployment.address
          });
          console.log(`${contractName} reverify success`);
        }
      } catch (error) {
        console.error(`reverify ${contractName} failed:`, error.message);
      }
    }

    console.log("all contracts reverify success");
  }
};

module.exports.tags = ["ReverifyContracts"]; 