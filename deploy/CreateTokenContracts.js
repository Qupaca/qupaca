const { ethers } = require("hardhat");

module.exports = async ({ getNamedAccounts, deployments, network }) => {
    const { get, execute } = deployments;
    const { deployer } = await getNamedAccounts();

    let erc20Token = "0x1e8b254b82912A8C9B6Eef118933d43630e2B4aD";

    if (!erc20Token) {
        throw new Error("ERC20 token address is empty");
    }

    const projectTokensManager = await get("ProjectTokensManager");
    if (!projectTokensManager) {
        throw new Error("ProjectTokensManager not deployed");
    }

    console.log("start create token contracts   ...");
    console.log("ERC20 Token:", erc20Token);
    console.log("ProjectTokensManager:", projectTokensManager.address);

    try {
        // create token contracts
        await execute(
            "ProjectTokensManager",
            { from: deployer, log: true },
            "createTokenContracts",
            erc20Token
        );
        console.log("✓ token contracts created successfully");

        const wrapper = await ethers.getContractAt(
            "ProjectTokensManager",
            projectTokensManager.address
        ).then(contract => contract.getWrapper(erc20Token));

        const tokenHouse = await ethers.getContractAt(
            "ProjectTokensManager",
            projectTokensManager.address
        ).then(contract => contract.getHouse(erc20Token));

        const mappingResult = {
            partnerToken: erc20Token,
            wrapper: wrapper,
            tokenHouse: tokenHouse,
            network: network.name
        };
        
        console.log(mappingResult);

    } catch (error) {
        console.error("token contracts creation failed:", error);
        throw error;
    }
};

module.exports.tags = ["CreateTokenContracts"];
module.exports.dependencies = ["ProjectTokenManager"];