import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "hardhat-contract-sizer";
import "solidity-coverage";
import "@nomiclabs/hardhat-solhint";
import "@nomiclabs/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
import "hardhat-deploy";

dotenv.config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
    },
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  namedAccounts: {
    deployer: 0,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

module.exports = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 8,
      },
    },
  },
  contractSizer: {
    runOnCompile: true,
    only: ["Dublr", "OmniToken"],
  },
  networks: {
    hardhat: {
      // So that eth sent/received can be calculated without subtracting out gas used in tests
      initialBaseFeePerGas: 0,
    },
    maticmum: {
      url: process.env.ALCHEMY_MUMBAI_URL,
      account: process.env.TESTNET_WALLET_PRIVATE_KEY,
    },
    matic: {
      url: process.env.ALCHEMY_POLYGON_URL,
      account: process.env.MAINNET_WALLET_PRIVATE_KEY,
    },
  },
};

export default config;
