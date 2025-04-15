const { TASK_SOURCIFY } = require("hardhat-deploy");
const { network } = require("hardhat");

module.exports = async (hre) => {
  if (network.name === "ronin" || network.name === "saigon") {
    await hre.run(TASK_SOURCIFY, {
      endpoint: "https://sourcify.roninchain.com/server/",
    });
  }
};

module.exports.tags = ["VerifyContracts", "Deploy1"];
module.exports.runAtTheEnd = true;