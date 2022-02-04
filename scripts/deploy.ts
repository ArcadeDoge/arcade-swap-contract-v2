// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers, network, run } from "hardhat";
import { NomicLabsHardhatPluginError } from "hardhat/plugins";
import config from "../config";

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
    const arcadeSwap = await Swap.deploy(
      config[network.name].BEP20Price,
      config[network.name].ARC
    );
    await arcadeSwap.deployed();

    console.log("Deployed Swap Address: " + arcadeSwap.address);

    await gameCurrency.transferOwnership(arcadeSwap.address);
    console.log("Transferred ownership of GameCurrency to Swap Address");

    try {
      // Verify
      console.log("Verifying ArcadeSwapV1: ", arcadeSwap.address);
      await run("verify:verify", {
        address: arcadeSwap.address,
        ConstructorArgs: [
          config[network.name].BEP20Price,
          config[network.name].ARC,
        ],
      });
    } catch (error) {
      if (error instanceof NomicLabsHardhatPluginError) {
        console.log("Contract source code already verified");
      } else {
        console.error(error);
      }
    }

    const deployerLog = { Label: "Deploying Address", Info: deployer.address };
    const swapLog = {
      Label: "Deployed and Verified ArcadeSwapV1 Address",
      Info: arcadeSwap.address,
    };

    console.table([deployerLog, swapLog]);
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
