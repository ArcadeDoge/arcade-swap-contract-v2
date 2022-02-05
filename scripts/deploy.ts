// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers, network, run, upgrades } from "hardhat";
import { NomicLabsHardhatPluginError } from "hardhat/plugins";
import config from "../config";

const sleep = (m: number) => new Promise((r) => setTimeout(r, m));

async function main() {
  const signers = await ethers.getSigners();
  // Find deployer signer in signers.
  let deployer: SignerWithAddress | undefined;
  signers.forEach((a) => {
    if (a.address === process.env.ADDRESS) {
      deployer = a;
    }
  });
  if (!deployer) {
    throw new Error(`${process.env.ADDRESS} not found in signers!`);
  }

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Network:", network.name);

  if (network.name === "testnet" || network.name === "mainnet") {
    const GameCurrency = await ethers.getContractFactory("GameCurrency");
    const gameCurrency = await GameCurrency.deploy(
      config.GameCurrency.name,
      config.GameCurrency.symbol,
      ethers.BigNumber.from(100000000).mul(ethers.BigNumber.from(10).pow(18))
    );
    await gameCurrency.deployed();

    const Swap = await ethers.getContractFactory("ArcadeSwapV1");
    const arcadeSwapUpgrades = await upgrades.deployProxy(
      Swap,
      [config[network.name].BEP20Price, config[network.name].ARC],
      {
        kind: "uups",
        initializer: "__ArcadeSwap_init",
      }
    );
    await arcadeSwapUpgrades.deployed();

    console.log("Deployed Swap Address: " + arcadeSwapUpgrades.address);

    await sleep(1000);

    await gameCurrency.transferOwnership(arcadeSwapUpgrades.address);
    console.log("Transferred ownership of GameCurrency to Swap Address");

    await sleep(1000);

    try {
      // Verify
      console.log("Verifying GameCurrency: ", gameCurrency.address);
      await run("verify:verify", {
        address: gameCurrency.address,
        ConstructorArgs: [
          config.GameCurrency.name,
          config.GameCurrency.symbol,
          ethers.BigNumber.from(100000000).mul(
            ethers.BigNumber.from(10).pow(18)
          ),
        ],
      });
    } catch (error) {
      if (error instanceof NomicLabsHardhatPluginError) {
        console.log("Contract source code already verified");
      } else {
        console.error(error);
      }
    }

    await sleep(1000);

    try {
      // Verify
      const arcadeSwapImpl = await upgrades.erc1967.getImplementationAddress(
        arcadeSwapUpgrades.address
      );
      console.log("Verifying ArcadeSwapV1: ", arcadeSwapImpl);
      await run("verify:verify", {
        address: arcadeSwapImpl,
      });
    } catch (error) {
      if (error instanceof NomicLabsHardhatPluginError) {
        console.log("Contract source code already verified");
      } else {
        console.error(error);
      }
    }

    const deployerLog = { Label: "Deploying Address", Info: deployer.address };
    const gcLog = {
      Label: "Deployed and Verified GameCurrency Address",
      Info: gameCurrency.address,
    };
    const swapLog = {
      Label: "Deployed and Verified ArcadeSwapV1 Address",
      Info: arcadeSwapUpgrades.address,
    };

    console.table([deployerLog, gcLog, swapLog]);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
