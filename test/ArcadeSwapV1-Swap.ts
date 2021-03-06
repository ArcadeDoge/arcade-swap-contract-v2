import { expect } from "chai";
import { ethers, upgrades } from "hardhat";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Signature } from "ethers";
import { RequestType, RequestWithSignature } from "./helpers/Request";
import { createBuyRequest } from "./helpers/createRequest";

const BIG_ONE = ethers.BigNumber.from(10).pow(18);

describe("ArcadeSwapV1-Swap", function () {
  const gameId = 1;
  const gcPerUSD = 200;

  // eslint-disable-next-line no-unused-vars
  let owner: SignerWithAddress,
    alpha: SignerWithAddress,
    // eslint-disable-next-line no-unused-vars
    beta: SignerWithAddress,
    // eslint-disable-next-line no-unused-vars
    addrs: any;

  let arcadeSwap: Contract, bep20Price: Contract, arcToken: Contract;
  let gcToken: string;

  const buyGc = async (
    user: SignerWithAddress,
    tokenPrice: BigNumber,
    buyArcAmount: BigNumber,
    expectedWeightedAverage: BigNumber,
    expectedArcAmount: BigNumber,
    expectedGcAmount: BigNumber
  ) => {
    const gcTokenContract: Contract = await ethers.getContractAt(
      "GameCurrency",
      gcToken,
      user
    );

    const initArcBalance = await arcToken.balanceOf(user.address);
    const initGcBalance = await gcTokenContract.balanceOf(user.address);

    const { arcAmount: initArcAmount } = await arcadeSwap.userInfo(
      gameId,
      user.address
    );

    await bep20Price.setTokenPrice(arcToken.address, tokenPrice);
    await arcToken.connect(user).approve(arcadeSwap.address, buyArcAmount);

    const request: RequestType = {
      maker: owner.address,
      requester: user.address,
      gcToken: gcToken,
      gameId: gameId,
      amount: buyArcAmount.toString(),
      reserved1: 0,
      reserved2: 0,
    };
    const signature: Signature = await createBuyRequest(
      owner,
      user,
      request.gcToken,
      request.gameId,
      buyArcAmount,
      BigNumber.from(0),
      BigNumber.from(0),
      arcadeSwap.address
    );
    const requestWithSignature: RequestWithSignature = {
      // eslint-disable-next-line
      ...request,
      v: signature.v,
      r: signature.r,
      s: signature.s,
    };
    await arcadeSwap.connect(user).buyGc(requestWithSignature);

    const { weightedAverage, arcAmount } = await arcadeSwap.userInfo(
      gameId,
      user.address
    );

    expect(expectedArcAmount).to.equal(buyArcAmount);

    expect(weightedAverage).to.equal(expectedWeightedAverage);
    expect(arcAmount.sub(initArcAmount)).to.equal(expectedArcAmount);

    const balanceOfArc = await arcToken.balanceOf(user.address);
    expect(initArcBalance.sub(balanceOfArc)).to.equal(buyArcAmount);
    const balanceOfGc = await gcTokenContract.balanceOf(user.address);
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
    const gcTokenContract: Contract = await ethers.getContractAt(
      "GameCurrency",
      gcToken,
      user
    );

    const initArcBalance = await arcToken.balanceOf(user.address);
    const initGcBalance = await gcTokenContract.balanceOf(user.address);

    const { arcAmount: initArcAmount } = await arcadeSwap.userInfo(
      gameId,
      user.address
    );

    await bep20Price.setTokenPrice(arcToken.address, tokenPrice);

    const request: RequestType = {
      maker: owner.address,
      requester: user.address,
      gcToken: gcToken,
      gameId: gameId,
      amount: sellGcAmount.toString(),
      reserved1: 0,
      reserved2: 0,
    };
    const signature: Signature = await createBuyRequest(
      owner,
      user,
      request.gcToken,
      request.gameId,
      sellGcAmount,
      BigNumber.from(0),
      BigNumber.from(0),
      arcadeSwap.address
    );
    const requestWithSignature: RequestWithSignature = {
      // eslint-disable-next-line
      ...request,
      v: signature.v,
      r: signature.r,
      s: signature.s,
    };
    await arcadeSwap.connect(user).sellGc(requestWithSignature);

    const { weightedAverage, arcAmount } = await arcadeSwap.userInfo(
      gameId,
      user.address
    );

    expect(expectedGcAmount).to.equal(sellGcAmount);

    expect(weightedAverage).to.equal(expectedWeightedAverage);
    expect(initArcAmount.sub(arcAmount)).to.equal(expectedArcAmount);

    const balanceOfArc = await arcToken.balanceOf(user.address);
    expect(balanceOfArc.sub(initArcBalance)).to.equal(expectedArcAmount);
    const balanceOfGc = await gcTokenContract.balanceOf(user.address);
    expect(initGcBalance.sub(balanceOfGc)).to.equal(sellGcAmount);
  };

  const mintGc = async (
    user: SignerWithAddress,
    increaseGcAmount: BigNumber,
    expectedGcAmount: BigNumber
  ) => {
    const gcTokenContract: Contract = await ethers.getContractAt(
      "GameCurrency",
      gcToken,
      user
    );

    const initGcBalance = await gcTokenContract.balanceOf(user.address);

    const request: RequestType = {
      maker: owner.address,
      requester: user.address,
      gcToken: gcToken,
      gameId: gameId,
      amount: increaseGcAmount.toString(),
      reserved1: 0,
      reserved2: 0,
    };
    const signature: Signature = await createBuyRequest(
      owner,
      user,
      request.gcToken,
      request.gameId,
      increaseGcAmount,
      BigNumber.from(0),
      BigNumber.from(0),
      arcadeSwap.address
    );
    const requestWithSignature: RequestWithSignature = {
      // eslint-disable-next-line
      ...request,
      v: signature.v,
      r: signature.r,
      s: signature.s,
    };
    await arcadeSwap.connect(user).mintGc(requestWithSignature);

    expect(expectedGcAmount).to.equal(increaseGcAmount);

    const balanceOfGc = await gcTokenContract.balanceOf(user.address);
    expect(balanceOfGc.sub(initGcBalance)).to.equal(expectedGcAmount);
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
    arcToken = await ArcToken.deploy(
      ethers.BigNumber.from(100000000).mul(ethers.BigNumber.from(10).pow(18))
    );
    await arcToken.deployed();

    const ArcadeSwapV1: ContractFactory = await ethers.getContractFactory(
      "ArcadeSwapV1"
    );
    arcadeSwap = await upgrades.deployProxy(
      ArcadeSwapV1,
      [bep20Price.address, arcToken.address],
      {
        kind: "uups",
        initializer: "__ArcadeSwap_init",
      }
    );
    await arcadeSwap.deployed();

    await arcadeSwap.setBackendSigner(owner.address);

    await arcadeSwap.setNewGame(gameId, gcPerUSD, "StarShards", "SS");
    const gameInfo = await arcadeSwap.gameInfo(gameId);
    gcToken = gameInfo.gcToken;
  });

  it("Should revert if sell without buy", async () => {
    await expect(
      sellGc(
        alpha,
        BIG_ONE.div(100), // $0.01
        BigNumber.from("200000"),
        BIG_ONE.div(100),
        BigNumber.from("200000"),
        BigNumber.from("100000")
      )
    ).to.be.revertedWith("not enough game currency");
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
    await arcToken.transfer(alpha.address, "10000");
    await buyGc(
      alpha,
      BIG_ONE.mul(8).div(100),
      BigNumber.from("10000"),
      BIG_ONE.mul(6).div(100),
      BigNumber.from("10000"),
      BigNumber.from("160000")
    );
    await arcToken.transfer(alpha.address, "5000");
    await buyGc(
      alpha,
      BIG_ONE.mul(2).div(10),
      BigNumber.from("5000"),
      BIG_ONE.mul(8).div(100),
      BigNumber.from("5000"),
      BigNumber.from("200000")
    );
    await sellGc(
      alpha,
      BIG_ONE.div(10),
      BigNumber.from("300000"),
      BIG_ONE.mul(8).div(100),
      BigNumber.from("300000"),
      BigNumber.from("18750")
    );
    await sellGc(
      alpha,
      BIG_ONE.mul(11).div(100),
      BigNumber.from("40000"),
      BIG_ONE.mul(8).div(100),
      BigNumber.from("40000"),
      BigNumber.from("2500")
    );
  });

  it("Should revert if sell more amount than purchased mount", async () => {
    await arcToken.transfer(arcadeSwap.address, BigNumber.from("100000000"));

    await arcToken.transfer(alpha.address, "100000");
    await buyGc(
      alpha,
      BIG_ONE.div(100), // $0.01
      BigNumber.from("10000"),
      BIG_ONE.div(100),
      BigNumber.from("10000"),
      BigNumber.from("20000")
    );
    await expect(
      sellGc(
        alpha,
        BIG_ONE.div(100), // $0.01
        BigNumber.from("500000"),
        BIG_ONE.div(100),
        BigNumber.from("500000"),
        BigNumber.from("250000")
      )
    ).to.be.revertedWith("not enough game currency");
    // await buyGc(
    //   alpha,
    //   BIG_ONE.mul(2).div(100), // $0.02
    //   BigNumber.from("20000"),
    //   BIG_ONE.div(110), // 0.0090909
    //   BigNumber.from("20000"),
    //   BigNumber.from("80000")
    // );
  });

  it("Should sell more amount than purchased mount with mintting gc", async () => {
    await arcToken.transfer(arcadeSwap.address, BigNumber.from("100000000"));

    await arcToken.transfer(alpha.address, "100000");
    await buyGc(
      alpha,
      BIG_ONE.div(100), // $0.01
      BigNumber.from("10000"),
      BIG_ONE.div(100),
      BigNumber.from("10000"),
      BigNumber.from("20000")
    );
    await mintGc(alpha, BigNumber.from("480000"), BigNumber.from("480000"));
    await sellGc(
      alpha,
      BIG_ONE.div(100), // $0.01
      BigNumber.from("500000"),
      BIG_ONE.div(100),
      BigNumber.from("500000"),
      BigNumber.from("250000")
    );
    await buyGc(
      alpha,
      BIG_ONE.mul(2).div(100), // $0.02
      BigNumber.from("20000"),
      BIG_ONE.div(110), // 0.0090909
      BigNumber.from("20000"),
      BigNumber.from("80000")
    );
  });
});
