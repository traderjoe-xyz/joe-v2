// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "./TestHelper.sol";

contract LiquidityBinQuoterTest is TestHelper {
    IJoeFactory private factoryV1;
    ERC20MockDecimals private testWavax;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 19_358_000);

        usdc = new ERC20MockDecimals(6);
        usdt = new ERC20MockDecimals(6);
        testWavax = new ERC20MockDecimals(18);

        factoryV1 = IJoeFactory(JOE_V1_FACTORY_ADDRESS);
        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        factory.addQuoteAsset(testWavax);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        router = new LBRouter(factory, IJoeFactory(JOE_V1_FACTORY_ADDRESS), IWAVAX(WAVAX_AVALANCHE_ADDRESS));
        quoter = new LBQuoter(address(router), JOE_V1_FACTORY_ADDRESS, address(factory));

        // Minting and giving approval
        testWavax.mint(DEV, 1_000_000e18);
        testWavax.approve(address(routerV1), type(uint256).max);
        usdc.mint(DEV, 1_000_000e6);
        usdc.approve(address(routerV1), type(uint256).max);
        usdt.mint(DEV, 1_000_000e6);
        usdt.approve(address(routerV1), type(uint256).max);

        // Create pairs
        factoryV1.createPair(address(usdc), address(testWavax));
        factoryV1.createPair(address(usdt), address(usdc));

        createLBPairDefaultFeesFromStartId(usdc, testWavax, convertIdAvaxToUSD(DEFAULT_BIN_STEP));
        createLBPairDefaultFees(usdt, usdc);

        // Add Liquidity
        routerV1.addLiquidity(address(usdc), address(testWavax), 20_000e6, 1_000e18, 0, 0, DEV, block.timestamp);
        routerV1.addLiquidity(address(usdt), address(usdc), 1_000e6, 1_000e6, 0, 0, DEV, block.timestamp);
        addLiquidityFromRouter(usdt, usdc, 10_000e6, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        addLiquidityFromRouter(usdc, testWavax, 100e18, convertIdAvaxToUSD(DEFAULT_BIN_STEP), 9, 2, DEFAULT_BIN_STEP);
    }

    function testConstructor() public {
        assertEq(address(quoter.routerV2()), address(router));
        assertEq(address(quoter.factoryV1()), JOE_V1_FACTORY_ADDRESS);
        assertEq(address(quoter.factoryV2()), address(factory));
    }

    function testGetSwapOut() public {
        address[] memory route;
        route = new address[](3);
        route[0] = address(testWavax);
        route[1] = address(usdc);
        route[2] = address(usdt);

        LBQuoter.Quote memory quote = quoter.findBestPathAmountIn(route, 1e18);

        assertApproxEqAbs(quote.amounts[2], 20e6, 2e6, "Price of 1 AVAX should be approx 20 USDT");
    }

    function testGetSwapIn() public {
        address[] memory route;
        route = new address[](3);
        route[0] = address(testWavax);
        route[1] = address(usdc);
        route[2] = address(usdt);

        LBQuoter.Quote memory quote = quoter.findBestPathAmountOut(route, 20e6);

        assertApproxEqAbs(quote.amounts[0], 1e18, 0.1e18, "Price of 1 AVAX should be approx 20 USDT");
    }

    function testInvalidLength() public {
        address[] memory route;
        route = new address[](1);
        vm.expectRevert(LBQuoter_InvalidLength.selector);
        quoter.findBestPathAmountIn(route, 1e18);
        vm.expectRevert(LBQuoter_InvalidLength.selector);
        quoter.findBestPathAmountOut(route, 20e6);
    }

    function convertIdAvaxToUSD(uint16 _binStep) internal pure returns (uint24 id) {
        id = getIdFromPrice(20e48, _binStep);
    }

    function getIdFromPrice(uint256 _price, uint16 _binStep) internal pure returns (uint24 id) {
        id = BinHelper.getIdFromPrice(_price, _binStep);
    }
}
