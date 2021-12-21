import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "ethers";

const BIG_ONE = ethers.BigNumber.from(10).pow(18);

describe("ArcadeSwapV1", function () {
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

  const buyGc = async (
    user: SignerWithAddress,
    tokenPrice: BigNumber,
    buyArcAmount: BigNumber,
    expectedWeightedAverage: BigNumber,
    expectedArcAmount: BigNumber,
    expectedGcAmount: BigNumber
  ) => {
    const initArcBalance = await arcToken.balanceOf(user.address);
    const initGcBalance = await gcToken.balanceOf(user.address);

    const { arcAmount: initArcAmount, gcAmount: initGcAmount } =
      await arcadeSwap.userInfo(user.address);

    await bep20Price.setTokenPrice(arcToken.address, tokenPrice);
    await arcToken.connect(user).approve(arcadeSwap.address, buyArcAmount);
    await arcadeSwap.connect(alpha).buyGc(buyArcAmount);

    const { weightedAverage, arcAmount, gcAmount } = await arcadeSwap.userInfo(
      user.address
    );

    expect(expectedArcAmount).to.equal(buyArcAmount);

    expect(weightedAverage).to.equal(expectedWeightedAverage);
    expect(arcAmount.sub(initArcAmount)).to.equal(expectedArcAmount);
    expect(gcAmount.sub(initGcAmount)).to.equal(expectedGcAmount);

    const balanceOfArc = await arcToken.balanceOf(user.address);
    expect(initArcBalance.sub(balanceOfArc)).to.equal(buyArcAmount);
    const balanceOfGc = await gcToken.balanceOf(user.address);
    expect(balanceOfGc.sub(initGcBalance)).to.equal(expectedGcAmount);
  };

  const sellGc = async (
    user: SignerWithAddress,
    tokenPrice: BigNumber,
    sellGcAmount: BigNumber,
    expectedWeightedAverage: BigNumber,
    expectedGcAmount: BigNumber,
    expectedArcAmount: BigNumber
  ) => {
    const initArcBalance = await arcToken.balanceOf(user.address);
    const initGcBalance = await gcToken.balanceOf(user.address);

    const { arcAmount: initArcAmount, gcAmount: initGcAmount } =
      await arcadeSwap.userInfo(user.address);

    await bep20Price.setTokenPrice(arcToken.address, tokenPrice);
    await arcadeSwap.connect(alpha).sellGc(sellGcAmount);

    const { weightedAverage, arcAmount, gcAmount } = await arcadeSwap.userInfo(
      user.address
    );

    expect(expectedGcAmount).to.equal(sellGcAmount);

    expect(weightedAverage).to.equal(expectedWeightedAverage);
    expect(initGcAmount.sub(gcAmount)).to.equal(expectedGcAmount);
    expect(initArcAmount.sub(arcAmount)).to.equal(expectedArcAmount);

    const balanceOfArc = await arcToken.balanceOf(user.address);
    expect(balanceOfArc.sub(initArcBalance)).to.equal(expectedArcAmount);
    const balanceOfGc = await gcToken.balanceOf(user.address);
    expect(initGcBalance.sub(balanceOfGc)).to.equal(sellGcAmount);
  };

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

    const GcToken: ContractFactory = await ethers.getContractFactory(
      "GameCurrency"
    );
    gcToken = await GcToken.deploy("StarShards", "SS");
    await gcToken.deployed();

    const gcPerArc = 200;

    const ArcadeSwapV1: ContractFactory = await ethers.getContractFactory(
      "ArcadeSwapV1"
    );
    arcadeSwap = await ArcadeSwapV1.deploy(
      bep20Price.address,
      arcToken.address,
      gcToken.address,
      gcPerArc
    );
    await arcadeSwap.deployed();

    await gcToken.transferOwnership(arcadeSwap.address);
  });

  it("Should revert if sell without buy", async () => {
    await expect(arcadeSwap.connect(alpha).sellGc("20000")).to.be.revertedWith(
      "not enough game currency"
    );
  });

  it("Should mint if buy Gc", async () => {
    await arcToken.transfer(alpha.address, "100000");

    await buyGc(
      alpha,
      BIG_ONE.div(100), // $0.01
      BigNumber.from("100000"),
      BIG_ONE.div(100),
      BigNumber.from("100000"),
      BigNumber.from("200000")
    );
  });

  it("Should burn if sell Gc", async () => {
    await arcToken.transfer(alpha.address, "100000");

    await buyGc(
      alpha,
      BIG_ONE.div(100), // $0.01
      BigNumber.from("100000"),
      BIG_ONE.div(100),
      BigNumber.from("100000"),
      BigNumber.from("200000")
    );

    await sellGc(
      alpha,
      BIG_ONE.div(100), // $0.01
      BigNumber.from("200000"),
      BIG_ONE.div(100),
      BigNumber.from("200000"),
      BigNumber.from("100000")
    );
  });

  it("Should mint/burn even if different arc price", async () => {
    await arcToken.transfer(arcadeSwap.address, BigNumber.from("1000000"));

    await arcToken.transfer(alpha.address, "100000");
    await buyGc(
      alpha,
      BIG_ONE.div(100),
      BigNumber.from("100000"),
      BIG_ONE.div(100),
      BigNumber.from("100000"),
      BigNumber.from("200000")
    );
    await sellGc(
      alpha,
      BIG_ONE.div(100),
      BigNumber.from("200000"),
      BIG_ONE.div(100),
      BigNumber.from("200000"),
      BigNumber.from("100000")
    );
    await arcToken.transfer(alpha.address, "100000");
    await buyGc(
      alpha,
      BIG_ONE.mul(4).div(100),
      BigNumber.from("100000"),
      BIG_ONE.mul(4).div(100),
      BigNumber.from("100000"),
      BigNumber.from("800000")
    );
    await arcToken.transfer(alpha.address, "3000");
    await buyGc(
      alpha,
      BIG_ONE.mul(4).div(100),
      BigNumber.from("3000"),
      BIG_ONE.mul(4).div(100),
      BigNumber.from("3000"),
      BigNumber.from("24000")
    );
    await sellGc(
      alpha,
      BIG_ONE.mul(4).div(100),
      BigNumber.from("824000"),
      BIG_ONE.mul(4).div(100),
      BigNumber.from("824000"),
      BigNumber.from("103000")
    );
    await arcToken.transfer(alpha.address, "20000");
    await buyGc(
      alpha,
      BIG_ONE.mul(5).div(100),
      BigNumber.from("20000"),
      BIG_ONE.mul(5).div(100),
      BigNumber.from("20000"),
      BigNumber.from("200000")
    );
  });
});
