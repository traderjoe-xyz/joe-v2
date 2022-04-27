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
      30,
      ethers.utils.parseUnits("1", 42) // 1e12 / 1e6 * 1e36
    );
  });

  it("Should return the right number of decimals", async function () {
    for (let i = 0; i < 78; i++) {
      expect(
        await this.lbe.getDecimals(ethers.utils.parseUnits("1", i))
      ).to.be.equal(i);
    }
  });

  it("Should return the right bin step", async function () {
    for (let i = 4; i < 78; i++) {
      expect(
        await this.lbe.getBinStep(ethers.utils.parseUnits("1", i))
      ).to.be.equal(ethers.utils.parseUnits("1", i - 4));
    }
  });

  it("Should return the right bin price range", async function () {
    await expect(this.lbe.getBinId("192")).to.be.revertedWith(
      "LBE: Id too low"
    );

    await expect(
      this.lbe.getBinId(
        "5192296858534827628530496329220096000000000000000000000000000000000000"
      )
    ).to.be.revertedWith("LBE: Id too high");

    expect(
      await this.lbe.getBinId(ethers.utils.parseUnits("9.23422312", 40))
    ).to.be.equal(ethers.utils.parseUnits("9.2342", 40));

    expect(
      await this.lbe.getBinId(ethers.utils.parseEther("1"))
    ).to.be.equal(ethers.utils.parseEther("1"));

    expect(
      await this.lbe.getBinId(ethers.utils.parseUnits("1", 4))
    ).to.be.equal(10000);
  });

  it("Should add liquidity accordingly", async function () {
    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("100", 6)
    );
    await this.token12D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("100.01", 12)
    );

    // [100, 0], [0, 100]
    await this.lbe.addLiquidity(
      [ethers.utils.parseUnits("1", 42), ethers.utils.parseUnits("1.0001", 42)],
      [ethers.utils.parseUnits("100", 6), 0],
      [0, ethers.utils.parseUnits("100.01", 12)]
    );

    const reserveBin1 = await this.lbe.getBin(ethers.utils.parseUnits("1", 42));
    expect(reserveBin1.l).to.be.equal(ethers.utils.parseUnits("100", 12));
    expect(reserveBin1.reserve0).to.be.equal(ethers.utils.parseUnits("100", 6));
    expect(reserveBin1.reserve1).to.be.equal(0);

    const reserveBin1_0001 = await this.lbe.getBin(
      ethers.utils.parseUnits("1.0001", 42)
    );
    expect(reserveBin1_0001.l).to.be.equal(
      ethers.utils.parseUnits("100.01", 12)
    );
    expect(reserveBin1_0001.reserve0).to.be.equal(0);
    expect(reserveBin1_0001.reserve1).to.be.equal(
      ethers.utils.parseUnits("100.01", 12)
    );
  });

  it("Should swap in only 1 bin 1.003.. token1 for 1 token0 at price 1 (0.3% fee)", async function () {
    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("100", 6)
    );

    // [100, 0]
    await this.lbe.addLiquidity(
      [ethers.utils.parseUnits("1", 42)],
      [ethers.utils.parseUnits("100", 6)],
      [0]
    );

    await this.token12D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("1.003009027081", 12)
    );
    await this.lbe.connect(this.alice).swap(ethers.utils.parseUnits("1", 6), 0);
    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(
      ethers.utils.parseUnits("1", 6)
    );
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(0);

    const reserve = await this.lbe.getBin(ethers.utils.parseUnits("1", 42));

    expect(reserve.l).to.be.equal(
      ethers.utils.parseUnits("100.003009027081", 12)
    );
    expect(reserve.reserve0).to.be.equal(ethers.utils.parseUnits("99", 6));
    expect(reserve.reserve1).to.be.equal(
      ethers.utils.parseUnits("1.003009027081", 12)
    );
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
      [ethers.utils.parseUnits("1", 42), ethers.utils.parseUnits("1.0001", 42)],
      [ethers.utils.parseUnits("100", 6), 0],
      [0, ethers.utils.parseUnits("100", 12)]
    );

    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("1.002908", 6)
    );
    await this.lbe
      .connect(this.alice)
      .swap(0, ethers.utils.parseUnits("1", 12));

    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(0);
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(
      ethers.utils.parseUnits("1", 12)
    );

    const reserve = await this.lbe.getBin(ethers.utils.parseUnits("1.0001", 42));

    expect(reserve.l).to.be.equal(
      ethers.utils.parseUnits("100.0030082908", 12)
    );
    expect(reserve.reserve0).to.be.equal(
      ethers.utils.parseUnits("1.002908", 6)
    );
    expect(reserve.reserve1).to.be.equal(ethers.utils.parseUnits("99", 12));
  });

  it("Should add liquidity and swap, in multiple bins, token1 for 100 token0 at market price (0.3% fee)", async function () {
    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("100", 6)
    );

    const nb = 10;
    let i = -1;
    let prices = Array(nb)
      .fill()
      .map(() => {
        i++;
        return ethers.utils
          .parseUnits("1", 42)
          .sub(ethers.utils.parseUnits(i.toString(), 37));
      });
    let getBin0 = Array(nb).fill(ethers.utils.parseUnits("10", 6));
    let getBin1 = Array(nb).fill(0);
    // price 1: [10, 0]
    // price 0.9999: [10, 0]
    // ...
    // price 0.9991: [10, 0]
    await this.lbe.addLiquidity(prices, getBin0, getBin1);

    await this.token12D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("110", 12)
    );
    await this.lbe
      .connect(this.alice)
      .swap(ethers.utils.parseUnits("100", 6), 0);
    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(
      ethers.utils.parseUnits("100", 6)
    );
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(0);

    const global = await this.lbe.global();
    expect(global.reserve0).to.be.equal(0);
    expect(global.reserve1).to.be.above(ethers.utils.parseUnits("100", 12));
  });

  it("Should add liquidity and swap, in multiple bins, token0 for 100 token1 at market price (0.3% fee)", async function () {
    await this.token12D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("100", 12)
    );

    const nb = 10;
    let i = -1;
    let prices = Array(nb)
      .fill()
      .map(() => {
        i++;
        return ethers.utils
          .parseUnits("1", 42)
          .add(ethers.utils.parseUnits(i.toString(), 38));
      });
    let getBin0 = Array(nb).fill(0);
    let getBin1 = Array(nb).fill(ethers.utils.parseUnits("10", 12));
    // price 1: 0, 10]
    // price 1.0001: [0, 10]
    // ...
    // price 1.0099: [0, 10]
    await this.lbe.addLiquidity(prices, getBin0, getBin1);

    await this.token6D.mint(
      this.lbe.address,
      ethers.utils.parseUnits("110", 6)
    );
    await this.lbe
      .connect(this.alice)
      .swap(0, ethers.utils.parseUnits("100", 12));
    expect(await this.token6D.balanceOf(this.alice.address)).to.be.equal(0);
    expect(await this.token12D.balanceOf(this.alice.address)).to.be.equal(
      ethers.utils.parseUnits("100", 12)
    );

    const global = await this.lbe.global();
    expect(global.reserve0).to.be.above(ethers.utils.parseUnits("100", 6));
    expect(global.reserve1).to.be.equal(0);
  });

  // TODO add liquidity when fill factor is not 0

  after(async function () {
    await network.provider.request({
      method: "hardhat_reset",
      params: [],
    });
  });
});
