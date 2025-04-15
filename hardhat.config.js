require("@nomicfoundation/hardhat-toolbox");
require("hardhat-deploy");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    ronin: {
      url: "https://ronin.lgns.net/rpc",
      chainId: 2020,
      accounts: [],
      gasPrice: 21000000000,
      timeout: 120000,
      retries: 5,
      httpHeaders: {
        "User-Agent": "Hardhat"
      }
    },
    saigon: {
      url: "https://saigon-testnet.roninchain.com/rpc",
      chainId: 2021,
      accounts: [],
      gasPrice: 21000000000,
      timeout: 120000,
      retries: 5,
      httpHeaders: {
        "User-Agent": "Hardhat"
      }
    }
  },
  sourcify: {
    enabled: true
  },
  namedAccounts: {
    deployer: {
      default: 0, // use the first account as deployer
    }
  },
  paths: {
    deployments: 'deployments',
    deploy: 'deploy',
  }
};
