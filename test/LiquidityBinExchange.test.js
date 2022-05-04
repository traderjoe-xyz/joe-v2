const { expect } = require("chai");
const { ethers, network } = require("hardhat");

describe.only("Liquidity Bin Exchange", function () {
  before(async function () {
    this.signers = await ethers.getSigners();
    this.alice = this.signers[0];

    this.LBE_CF = await ethers.getContractFactory("LiquidityBinExchange");
    this.ERC20MockDecimals_CF = await ethers.getContractFactory(
      "ERC20MockDecimals"
    );
  });

  beforeEach(async function () {
    this.token12D = await this.ERC20MockDecimals_CF.deploy(12);
    this.token6D = await this.ERC20MockDecimals_CF.deploy(6);
    this.lbe = await this.LBE_CF.deploy(
      this.token6D.address,
      this.token12D.address,
      30
    );
  });

  it("Should add liquidity accordingly", async function () {
    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("150", 6)
    );
    await this.token12D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("150", 12)
    );

    // 0.99999,   1.0000,   1,0001
    // [100, 0], [50, 50], [0, 100]
    await this.lbe.addLiquidity(
      ethers.utils.parseUnits("0.99999", 42),
      ethers.utils.parseUnits("1.0001", 42),
      [ethers.utils.parseUnits("100", 6), ethers.utils.parseUnits("50", 6), 0],
      [0, ethers.utils.parseUnits("50", 12), ethers.utils.parseUnits("100", 12)]
    );

    const reserveBin0 = await this.lbe.getBin(
      ethers.utils.parseUnits("0.99999", 42)
    );
    expect(reserveBin0.l).to.be.equal(ethers.utils.parseUnits("99.999", 12));
    expect(reserveBin0.reserve0).to.be.equal(ethers.utils.parseUnits("100", 6));
    expect(reserveBin0.reserve1).to.be.equal(0);

    const reserveBin1 = await this.lbe.getBin(ethers.utils.parseUnits("1", 42));
    expect(reserveBin1.l).to.be.equal(ethers.utils.parseUnits("100", 12));
    expect(reserveBin1.reserve0).to.be.equal(ethers.utils.parseUnits("50", 6));
    expect(reserveBin1.reserve1).to.be.equal(ethers.utils.parseUnits("50", 12));

    const reserveBin2 = await this.lbe.getBin(
      ethers.utils.parseUnits("1.0001", 42)
    );
    expect(reserveBin2.l).to.be.equal(ethers.utils.parseUnits("100", 12));
    expect(reserveBin2.reserve0).to.be.equal(0);
    expect(reserveBin2.reserve1).to.be.equal(
      ethers.utils.parseUnits("100", 12)
    );
  });

  it("Should swap in only 1 bin 1.003.. token1 for 1 token0 at price 1 (0.3% fee)", async function () {
    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("100", 6)
    );

    //  1.0000
    // [100, 0]
    await this.lbe.addLiquidity(
      ethers.utils.parseUnits("1", 42),
      ethers.utils.parseUnits("1", 42),
      [ethers.utils.parseUnits("100", 6)],
      [0]
    );

    const value = ethers.utils.parseUnits("1", 12).mul("1000").div("997");
    await this.token12D.mint(this.lbe.address, value + 1);
    await this.lbe
      .connect(this.alice)
      .swap(ethers.utils.parseUnits("1", 6), 0, this.alice.address, 0);
    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(
      ethers.utils.parseUnits("1", 6)
    );
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(0);

    const reserve = await this.lbe.getBin(ethers.utils.parseUnits("1", 42));

    expect(reserve.l).to.be.equal(ethers.utils.parseUnits("99", 12).add(value));
    expect(reserve.reserve0).to.be.equal(ethers.utils.parseUnits("99", 6));
    expect(reserve.reserve1).to.be.equal(value);
  });

  it("Should swap in only 1 bin 1.002908 token0 for 1 token1 at price 1.0001 (0.3% fee)", async function () {
    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("100", 6)
    );
    await this.token12D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("100", 12)
    );

    // [100, 0], [0, 100]
    await this.lbe.addLiquidity(
      ethers.utils.parseUnits("1", 42),
      ethers.utils.parseUnits("1.0001", 42),
      [ethers.utils.parseUnits("100", 6), 0],
      [0, ethers.utils.parseUnits("100", 12)]
    );

    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("1.002908", 6)
    );
    await this.lbe
      .connect(this.alice)
      .swap(0, ethers.utils.parseUnits("1", 12), this.alice.address, 0);

    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(0);
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(
      ethers.utils.parseUnits("1", 12)
    );

    const reserve = await this.lbe.getBin(
      ethers.utils.parseUnits("1.0001", 42)
    );

    expect(reserve.l).to.be.equal(
      ethers.utils.parseUnits("100.0030082908", 12)
    );
    expect(reserve.reserve0).to.be.equal(
      ethers.utils.parseUnits("1.002908", 6)
    );
    expect(reserve.reserve1).to.be.equal(ethers.utils.parseUnits("99", 12));
  });

  it("Should add liquidity and swap, in multiple bins, token1 for 100 token0 at market price (0.3% fee)", async function () {
    const tokenAmount = ethers.utils.parseUnits("100", 6);
    await this.token6D.mint(this.lbe.address, tokenAmount);

    const nb = 10;
    let bins0 = Array(nb).fill(tokenAmount.div(10));
    let bins1 = Array(nb).fill(0);
    // price 1: [10, 0]
    // price 0.9999: [10, 0]
    // ...
    // price 0.9991: [10, 0]
    await this.lbe.addLiquidity(
      ethers.utils.parseUnits("0.99991", 42),
      ethers.utils.parseUnits("1", 42),
      bins0,
      bins1
    );

    await this.token12D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("110", 12)
    );
    await this.lbe
      .connect(this.alice)
      .swap(ethers.utils.parseUnits("100", 6), 0, this.alice.address, 0);
    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(
      ethers.utils.parseUnits("100", 6)
    );
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(0);

    const global = await this.lbe.global();
    expect(global.reserve0).to.be.equal(0);
    expect(global.reserve1).to.be.above(ethers.utils.parseUnits("100", 12));
  });

  it("Should add liquidity and swap, in multiple bins, token0 for 100 token1 at market price (0.3% fee)", async function () {
    const tokenAmount = ethers.utils.parseUnits("100", 12);
    await this.token12D.mint(this.lbe.address, tokenAmount);

    const nb = 10;
    let bins0 = Array(nb).fill(0);
    let bins1 = Array(nb).fill(tokenAmount.div(nb));
    // price 1: 0, 10]
    // price 1.0001: [0, 10]
    // ...
    // price 1.0099: [0, 10]
    await this.lbe.addLiquidity(
      ethers.utils.parseUnits("1", 42),
      ethers.utils.parseUnits("1.0009", 42),
      bins0,
      bins1
    );

    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("110", 6)
    );
    await this.lbe
      .connect(this.alice)
      .swap(0, ethers.utils.parseUnits("100", 12), this.alice.address, 0);
    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(0);
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(
      ethers.utils.parseUnits("100", 12)
    );

    const global = await this.lbe.global();
    expect(global.reserve0).to.be.above(ethers.utils.parseUnits("100", 6));
    expect(global.reserve1).to.be.equal(0);
  });

  it("Should add liquidity and swap, even if the 2 bins are really far away", async function () {
    const tokenAmount = ethers.utils.parseUnits("100", 6);
    await this.token6D.mint(this.lbe.address, tokenAmount);

    await this.lbe.addLiquidity(
      ethers.utils.parseUnits("1", 42),
      ethers.utils.parseUnits("1", 42),
      [tokenAmount.div(2)],
      [0]
    );

    await this.lbe.addLiquidity(
      ethers.utils.parseUnits("1", 29),
      ethers.utils.parseUnits("1", 29),
      [tokenAmount.div(2)],
      [0]
    );

    await this.token12D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("51", 12)
    );
    await this.lbe
      .connect(this.alice)
      .swap(ethers.utils.parseUnits("100", 6), 0, this.alice.address, 0);
    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(
      ethers.utils.parseUnits("100", 6)
    );
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(0);

    const global = await this.lbe.global();
    expect(global.reserve0).to.be.equal(0);
    expect(global.reserve1).to.be.above(ethers.utils.parseUnits("50", 12));
  });

  it("Should add liquidity and swap, even if the 2 bins are really far away", async function () {
    const tokenAmount = ethers.utils.parseUnits("100", 12);
    await this.token12D.mint(this.lbe.address, tokenAmount);

    await this.lbe.addLiquidity(
      ethers.utils.parseUnits("1", 42),
      ethers.utils.parseUnits("1", 42),
      [0],
      [tokenAmount.div(2)]
    );

    await this.lbe.addLiquidity(
      ethers.utils.parseUnits("1", 49),
      ethers.utils.parseUnits("1", 49),
      [0],
      [tokenAmount.div(2)]
    );

    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("10000000000000000000", 6)
    );
    await this.lbe
      .connect(this.alice)
      .swap(0, ethers.utils.parseUnits("100", 12), this.alice.address, 0);
    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(0);
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(
      ethers.utils.parseUnits("100", 12)
    );

    const global = await this.lbe.global();
    expect(global.reserve0).to.be.above(ethers.utils.parseUnits("50", 6));
    expect(global.reserve1).to.be.equal(0);
  });

  // TODO add liquidity when fill factor is not 0
  // TODO remove liquidity
  // TODO investigate price limit ()
  // this crashed above test
  // await this.lbe.addLiquidity(
  //   ethers.utils.parseUnits("1", 48),
  //   ethers.utils.parseUnits("1", 48),
  //   [0],
  //   [tokenAmount.div(2)]
  // );

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    });
  });
});
