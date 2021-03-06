import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import { removeConsoleLog } from "hardhat-preprocessor";
import "@openzeppelin/hardhat-upgrades";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "hardhat-abi-exporter";
import "solidity-coverage";

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
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    testnet: {
      url: process.env.MORALIS_BSC_TESTNET_URL || "",
      chainId: 97,
      gasPrice: 20000000000,
      accounts:
        process.env.DEPLOYER001_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER001_PRIVATE_KEY]
          : [],
    },
    mainnet: {
      url: process.env.MORALIS_BSC_MAINNET_URL || "",
      chainId: 56,
      gasPrice: 20000000000,
      accounts:
        process.env.DEPLOYER001_PRIVATE_KEY !== undefined
          ? [process.env.DEPLOYER001_PRIVATE_KEY]
          : [],
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  abiExporter: {
    path: "./data/abi",
    clear: true,
    flat: true,
    only: [],
    spacing: 2,
  },
  preprocess: {
    eachLine: removeConsoleLog(
      (hre: any) =>
        hre.network.name !== "hardhat" && hre.network.name !== "localhost"
    ),
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
  },
  etherscan: {
    apiKey: process.env.BSCSCAN_API_KEY,
  },
};

export default config;
