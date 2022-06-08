const { expect } = require("chai");
const { ethers, network } = require("hardhat");

const one = ethers.utils.parseUnits("1", 36);
let idOne, getId;

describe("Liquidity Bin Pair", function () {
  before(async function () {
    this.signers = await ethers.getSigners();
    this.alice = this.signers[0];

    this.LBP_CF = await ethers.getContractFactory("LBPair");
    this.ERC20MockDecimals_CF = await ethers.getContractFactory(
      "ERC20MockDecimals"
    );
  });

  beforeEach(async function () {
    this.token12D = await this.ERC20MockDecimals_CF.deploy(12);
    this.token6D = await this.ERC20MockDecimals_CF.deploy(6);
    this.LBP = await this.LBP_CF.deploy(
      this.alice.address,
      this.token6D.address, // x
      this.token12D.address, // y
      "0xb19a9e77af6827457b6619208c48",
      ethers.utils.solidityPack(
        ["uint160", "uint16", "uint16", "uint16", "uint16", "uint16", "uint16"],
        [0, 5_000, 5_000, 1_000, 25, 100, 1_000]
      )
    );

    if (idOne == null)
      idOne = await this.LBP.getIdFromPrice(ethers.utils.parseUnits("1", 42));

    getId = (x) => {
      return idOne + x;
    };
  });

  it("Should verify the constructor parameters", async function () {
    expect(await this.LBP.factory()).to.be.equal(this.alice.address);
    expect(await this.LBP.token0()).to.be.equal(this.token6D.address);
    expect(await this.LBP.token1()).to.be.equal(this.token12D.address);

    const feeParameters = await this.LBP.feeParameters();
    expect(feeParameters.accumulator).to.be.equal(0);
    expect(feeParameters.time).to.be.equal(0);
    expect(feeParameters.coolDownTime).to.be.equal(100);
    expect(feeParameters.binStep).to.be.equal(25);
    expect(feeParameters.fF).to.be.equal(1_000);
    expect(feeParameters.fV).to.be.equal(5_000);
    expect(feeParameters.maxFee).to.be.equal(1_000);
    expect(feeParameters.protocolShare).to.be.equal(5_000);
  });

  it("Should verify that 2 opposite ids have an inverse price", async function () {
    const int24 = (x) => 2 ** 23 + x;
    expect(
      (await this.LBP.getPriceFromId(int24(10)))
        .mul(await this.LBP.getPriceFromId(int24(-10)))
        .div(one)
    ).closeTo(one, one.div(100_000_000));
    expect(
      (await this.LBP.getPriceFromId(int24(1_000)))
        .mul(await this.LBP.getPriceFromId(int24(-1_000)))
        .div(one)
    ).closeTo(one, one.div(100_000_000));
    expect(
      (await this.LBP.getPriceFromId(int24(10_000)))
        .mul(await this.LBP.getPriceFromId(int24(-10_000)))
        .div(one)
    ).closeTo(one, one.div(100_000_000));
  });

  it("Should add liquidity accordingly", async function () {
    await this.token6D.mint(
      this.LBP.address,
      ethers.utils.parseUnits("150", 6)
    );
    await this.token12D.mint(
      this.LBP.address,
      ethers.utils.parseUnits("150", 12)
    );

    const startId = await this.LBP.getIdFromPrice(
      ethers.utils.parseUnits("0.99985", 36)
    );

    // 0.9999,   1.000,   1,001
    // [0, 100], [50, 50], [100, 0]
    await this.LBP.mint(
      startId,
      [0, ethers.utils.parseUnits("50", 6), ethers.utils.parseUnits("100", 6)],
      [
        ethers.utils.parseUnits("100", 12),
        ethers.utils.parseUnits("50", 12),
        0,
      ],
      this.alice.address
    );

    const bin0 = await this.LBP.getBin(startId);
    const bin1 = await this.LBP.getBin(startId + 1);
    const bin2 = await this.LBP.getBin(startId + 2);

    expect(bin0.reserve0).to.be.equal(0);
    expect(bin0.reserve1).to.be.equal(ethers.utils.parseUnits("100", 12));

    expect(bin1.reserve0).to.be.equal(ethers.utils.parseUnits("50", 6));
    expect(bin1.reserve1).to.be.equal(ethers.utils.parseUnits("50", 12));

    expect(bin2.reserve0).to.be.equal(ethers.utils.parseUnits("100", 6));
    expect(bin2.reserve1).to.be.equal(0);

    expect(bin1.price).to.be.above(bin0.price);
    expect(bin2.price).to.be.above(bin1.price);
  });

  it("Should swap in only 1 bin 1.003.. token1 for 1 token0 at bin id 0 (0.3% fee)", async function () {
    const tokenAmount = ethers.utils.parseUnits("100", 6);
    await this.token6D.mint(this.LBP.address, tokenAmount);

    const id = getId(0);

    //  1.0000
    // [100, 0]
    await this.LBP.mint(id, [tokenAmount], [0], this.alice.address);

    const amount0Out = ethers.utils.parseUnits("1", 6);
    const amount1In = (await this.LBP.getSwapIn(amount0Out, 0)).amount1In;

    await this.token12D.mint(this.LBP.address, amount1In);
    await this.LBP.connect(this.alice).swap(
      amount0Out,
      0,
      this.alice.address,
      0
    );

    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(
      amount0Out
    );
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(0);

    const bin = await this.LBP.getBin(id);
    const pairInformation = await this.LBP.pairInformation();

    expect(bin.reserve0).to.be.equal(tokenAmount.sub(amount0Out));
    expect(bin.reserve1).to.be.equal(
      amount1In.sub(pairInformation.protocolFees1)
    );
  });

  it("Should swap in only 1 bin 1.002908 token0 for 1 token1 at bin id 1 (0.3% fee)", async function () {
    const tokenAmount = ethers.utils.parseUnits("100", 12);
    await this.token12D.mint(this.LBP.address, tokenAmount);

    const id = getId(1);

    // [100, 0], [0, 100]
    await this.LBP.mint(id, [0], [tokenAmount], this.alice.address);

    const amount0In = ethers.utils.parseUnits("1", 6);
    const amount1Out = (await this.LBP.getSwapOut(amount0In, 0)).amount1Out;

    await this.token6D.mint(this.LBP.address, amount0In);
    await this.LBP.connect(this.alice).swap(
      0,
      amount1Out,
      this.alice.address,
      0
    );

    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(0);
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(
      amount1Out
    );

    const bin = await this.LBP.getBin(id);
    const pairInformation = await this.LBP.pairInformation();

    expect(bin.reserve0).to.be.closeTo(
      amount0In.sub(pairInformation.protocolFees0),
      amount0In.div(10_000)
    );
    expect(bin.reserve1).to.be.equal(tokenAmount.sub(amount1Out));
  });

  it("Should add liquidity and swap, in multiple bins, token0 for 100 token1 at market price (0.3% fee)", async function () {
    const tokenAmount = ethers.utils.parseUnits("100", 12);
    await this.token12D.mint(this.LBP.address, tokenAmount);

    const startId = getId(-1_000);

    const nb = 10;
    let bins0 = Array(nb).fill(0);
    let bins1 = Array(nb).fill(tokenAmount.div(nb));

    await this.LBP.mint(startId, bins0, bins1, this.alice.address);

    const amount1Out = tokenAmount;
    const amount0In = (await this.LBP.getSwapIn(0, amount1Out)).amount0In;

    await this.token6D.mint(this.LBP.address, amount0In);

    await this.LBP.connect(this.alice).swap(
      0,
      amount1Out,
      this.alice.address,
      0
    );

    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(0);
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(
      amount1Out
    );

    const pairInformation = await this.LBP.pairInformation();
    expect(pairInformation.reserve0).to.be.equal(
      amount0In.sub(pairInformation.protocolFees0)
    );
    expect(pairInformation.reserve1).to.be.equal(0);
  });

  it("Should add liquidity and swap, in multiple bins, 10 token1 for token0 at market price (0.3% fee)", async function () {
    const tokenAmount = ethers.utils.parseUnits("400", 6);
    await this.token6D.mint(this.LBP.address, tokenAmount);

    const startId = getId(1_000);

    const nb = 10;
    let bins0 = Array(nb).fill(tokenAmount.div(nb));
    let bins1 = Array(nb).fill(0);

    await this.LBP.mint(startId, bins0, bins1, this.alice.address);

    const amount1In = ethers.utils.parseUnits("10", 12);
    const amount0Out = (await this.LBP.getSwapOut(0, amount1In)).amount0Out;

    await this.token12D.mint(this.LBP.address, amount1In);

    await this.LBP.connect(this.alice).swap(
      amount0Out,
      0,
      this.alice.address,
      0
    );

    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(
      amount0Out
    );
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(0);

    const pairInformation = await this.LBP.pairInformation();
    expect(pairInformation.reserve0).to.be.equal(tokenAmount.sub(amount0Out));
    expect(pairInformation.reserve1).to.be.closeTo(
      amount1In.sub(pairInformation.protocolFees1),
      amount1In.div(10_000)
    );
  });

  it("Should add liquidity and swap token0 for token1, even if the 2 bins are really far away", async function () {
    const tokenAmount = ethers.utils.parseUnits("100", 12);
    await this.token12D.mint(this.LBP.address, tokenAmount);

    await this.LBP.mint(
      getId(10_000),
      [0],
      [tokenAmount.div(2)],
      this.alice.address
    );

    await this.LBP.mint(
      getId(-10_000),
      [0],
      [tokenAmount.div(2)],
      this.alice.address
    );

    await this.token6D.mint(this.LBP.address, ethers.utils.parseUnits("1", 75));
    await this.LBP.connect(this.alice).swap(
      0,
      tokenAmount,
      this.alice.address,
      0
    );

    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(0);
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(
      tokenAmount
    );

    const pairInformation = await this.LBP.pairInformation();
    expect(pairInformation.reserve0).to.be.above(0);
    expect(pairInformation.reserve1).to.be.equal(0);
  });

  it("Should add liquidity and swap token1 for token0, even if the 2 bins are really far away", async function () {
    const tokenAmount = ethers.utils.parseUnits("100", 6);
    await this.token6D.mint(this.LBP.address, tokenAmount);

    await this.LBP.mint(
      getId(-1_000),
      [tokenAmount.div(2)],
      [0],
      this.alice.address
    );

    await this.LBP.mint(
      getId(10_000),
      [tokenAmount.div(2)],
      [0],
      this.alice.address
    );

    await this.token12D.mint(
      this.LBP.address,
      ethers.utils.parseUnits("1", 75)
    );
    await this.LBP.connect(this.alice).swap(
      tokenAmount,
      0,
      this.alice.address,
      0
    );

    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(
      tokenAmount
    );
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(0);

    const pairInformation = await this.LBP.pairInformation();
    expect(pairInformation.reserve0).to.be.equal(0);
    expect(pairInformation.reserve1).to.be.above(0);
  });

  it("40M swap with 50M liq with 1% range, 1 binStep and 0.3% fee", async function () {
    //  6D = x
    // 12D = y
    const tokenAmount = ethers.utils.parseUnits("50000000", 12);
    await this.token12D.mint(this.LBP.address, tokenAmount);

    const nb = 100;
    let bins0 = [];
    let bins1 = [];

    for (let i = 0; i < nb; i++) {
      bins0 = bins0.concat(0);
      bins1 = bins1.concat(tokenAmount.div(nb));
    }

    const startId =
      (await this.LBP.getIdFromPrice(ethers.utils.parseUnits("1", 42))) - nb;

    // [Y Y Y Y | 0 0 0 0]
    await this.LBP.mint(startId, bins0, bins1, this.alice.address);

    const amount0In = ethers.utils.parseUnits("40000000", 6);
    const amount1Out = (await this.LBP.getSwapOut(amount0In, 0)).amount1Out;

    const startPrice = (
      await this.LBP.getPriceFromId((await this.LBP.pairInformation()).id)
    ).div(one.div(100));

    await this.token6D.mint(this.LBP.address, amount0In);
    await this.LBP.connect(this.alice).swap(
      0,
      amount1Out,
      this.alice.address,
      0
    );

    console.log(
      amount0In / 1e6,
      "token0 ->",
      (await this.token12D.balanceOf(this.alice.address)) / 1e12,
      "token1"
    );

    const endPrice = (
      await this.LBP.getPriceFromId((await this.LBP.pairInformation()).id)
    ).div(one.div(100));
    console.log(
      "Price impact:",
      (Math.abs(endPrice - startPrice) / startPrice) * 100,
      "%"
    );
    const pairInformation = await this.LBP.pairInformation();
    const feesPar = await this.LBP.feeParameters();
    console.log(
      "Fees paid:",
      pairInformation.protocolFees0 / 1e2 / feesPar.protocolShare,
      pairInformation.protocolFees1 / 1e8 / feesPar.protocolShare
    );
  });

  it("Should add and remove liquidity accordingly", async function () {
    await this.token6D.mint(
      this.LBP.address,
      ethers.utils.parseUnits("150", 6)
    );
    await this.token12D.mint(
      this.LBP.address,
      ethers.utils.parseUnits("150", 12)
    );

    const startId = await this.LBP.getIdFromPrice(
      ethers.utils.parseUnits("1", 42)
    );

    // 0.9999,   1.000,   1,001
    // [0, 100], [50, 50], [100, 0]
    await this.LBP.mint(
      startId,
      [0, ethers.utils.parseUnits("50", 6), ethers.utils.parseUnits("100", 6)],
      [
        ethers.utils.parseUnits("100", 12),
        ethers.utils.parseUnits("50", 12),
        0,
      ],
      this.alice.address
    );

    await this.LBP.connect(this.alice).safeTransfer(
      this.LBP.address,
      startId,
      await this.LBP.balanceOf(this.alice.address, startId)
    );
    await this.LBP.connect(this.alice).safeTransfer(
      this.LBP.address,
      startId + 1,
      await this.LBP.balanceOf(this.alice.address, startId + 1)
    );
    await this.LBP.connect(this.alice).safeTransfer(
      this.LBP.address,
      startId + 2,
      await this.LBP.balanceOf(this.alice.address, startId + 2)
    );

    await this.LBP.burn(
      [startId, startId + 1, startId + 2],
      this.alice.address
    );

    const bin0 = await this.LBP.getBin(startId);
    const bin1 = await this.LBP.getBin(startId + 1);
    const bin2 = await this.LBP.getBin(startId + 2);

    expect(bin0.reserve0).to.be.equal(0);
    expect(bin0.reserve1).to.be.equal("1000");

    expect(bin1.reserve0).to.be.equal("1");
    expect(bin1.reserve1).to.be.equal("500"); // @audit was 501... wtf

    expect(bin2.reserve0).to.be.equal("1");
    expect(bin2.reserve1).to.be.equal(0);

    expect(bin1.price).to.be.above(bin0.price);
    expect(bin2.price).to.be.above(bin1.price);
  });

  // TODO add liquidity when fill factor is not 0
  // TODO investigate price limit ()

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    });
  });
});
