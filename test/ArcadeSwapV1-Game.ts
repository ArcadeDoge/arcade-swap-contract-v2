import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";

const BIG_ONE = ethers.BigNumber.from(10).pow(18);

describe("ArcadeSwapV1-Game", function () {
  // eslint-disable-next-line no-unused-vars
  let owner: SignerWithAddress,
    alpha: SignerWithAddress,
    // eslint-disable-next-line no-unused-vars
    beta: SignerWithAddress,
    // eslint-disable-next-line no-unused-vars
    addrs: any;

  let arcadeSwap: Contract,
    bep20Price: Contract,
    arcToken: Contract,
    gcToken: Contract;

  beforeEach(async () => {
    [owner, alpha, beta, ...addrs] = await ethers.getSigners();

    const MockBep20Price: ContractFactory = await ethers.getContractFactory(
      "MockBEP20Price"
    );
    bep20Price = await MockBep20Price.deploy();

    const ArcToken: ContractFactory = await ethers.getContractFactory(
      "MockArcade"
    );
    arcToken = await ArcToken.deploy(100000000);
    await arcToken.deployed();

    const ArcadeSwapV1: ContractFactory = await ethers.getContractFactory(
      "ArcadeSwapV1"
    );
    arcadeSwap = await ArcadeSwapV1.deploy(
      bep20Price.address,
      arcToken.address
    );
    await arcadeSwap.deployed();
  });

  it("Should revert set Gc per USD if not initialized game", async () => {
    const gameId = 1;
    const gcPerUSD = 200;
    await expect(
      arcadeSwap.setGameGcPerUSD(gameId, gcPerUSD)
    ).to.be.revertedWith("not initialized game");
  });

  it("Should create game currency token if new game", async () => {
    const initGameId = 1;
    const initGcPerUSD = 200;
    await arcadeSwap.setNewGame(
      initGameId,
      initGcPerUSD,
      "StarShards",
      "SS",
      ethers.BigNumber.from(100000000).mul(ethers.BigNumber.from(10).pow(18))
    );

    const { id, gcPerUSD, gcToken, gcName, gcSymbol, isActive } =
      await arcadeSwap.gameInfo(initGameId);
    expect(gcPerUSD).to.equal(gcPerUSD);
    const gcContract: Contract = await ethers.getContractAt(
      "GameCurrency",
      gcToken
    );
    expect(await gcContract.name()).to.equal("StarShards");
    expect(await gcContract.symbol()).to.equal("SS");
    expect(gcName).to.equal("StarShards");
    expect(gcSymbol).to.equal("SS");
  });
});
