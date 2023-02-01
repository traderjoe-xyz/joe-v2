// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "../helpers/TestHelper.sol";

/*
* Market deployed:
* - USDT/USDC, V1 with low liquidity, V2 with high liquidity
* - WAVAX/USDC, V1 with high liquidity, V2 with low liquidity
* - WETH/USDC, V1 with low liquidity, V2.1.rev1 with low liquidity, V2.1.rev2 with high liquidity
* - BNB/USDC, V2 with high liquidity, V2.1 with low liquidity
* 
* Every market with low liquidity has a slighly higher price. 
* It should be picked with small amounts but not with large amounts.
* All tokens are considered 18 decimals for simplification purposes.
**/

contract LiquidityBinQuoterTest is TestHelper {
    uint256 private defaultBaseFee = DEFAULT_BIN_STEP * uint256(DEFAULT_BASE_FACTOR) * 1e10;

    using Utils for ILBRouter.LiquidityParameters;

    function setUp() public override {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 25_396_630);
        super.setUp();

        uint256 lowLiquidityAmount = 1e18;
        uint256 highLiquidityAmount = 1e24;

        // Get tokens to add liquidity
        deal(address(usdc), address(this), 10 * highLiquidityAmount);
        deal(address(usdt), address(this), 10 * highLiquidityAmount);
        deal(address(wavax), address(this), 10 * highLiquidityAmount);
        deal(address(weth), address(this), 10 * highLiquidityAmount);
        deal(address(bnb), address(this), 10 * highLiquidityAmount);

        // Add liquidity to V1
        routerV1.addLiquidity(
            address(usdt),
            address(usdc),
            lowLiquidityAmount / 2, // 1 USDT = 2 USDC
            lowLiquidityAmount,
            lowLiquidityAmount,
            lowLiquidityAmount,
            address(this),
            block.timestamp + 1
        );

        routerV1.addLiquidity(
            address(wavax),
            address(usdc),
            highLiquidityAmount, // 1 AVAX = 1 USDC
            highLiquidityAmount,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        routerV1.addLiquidity(
            address(weth),
            address(usdc),
            lowLiquidityAmount / 2, // 1 WETH = 2 USDC
            lowLiquidityAmount,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        vm.startPrank(AvalancheAddresses.V2_FACTORY_OWNER);
        legacyFactoryV2.addQuoteAsset(usdc);
        legacyFactoryV2.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP); // 1 USDT = 1 USDC
        legacyFactoryV2.createLBPair(wavax, usdc, ID_ONE - 50, DEFAULT_BIN_STEP); // 1 AVAX > 1 USDC
        legacyFactoryV2.createLBPair(bnb, usdc, ID_ONE, DEFAULT_BIN_STEP); // 1 BNB = 1 USDC
        vm.stopPrank();

        factory.createLBPair(weth, usdc, ID_ONE, DEFAULT_BIN_STEP); // 1 WETH = 1 USDC
        factory.createLBPair(bnb, usdc, ID_ONE - 50, DEFAULT_BIN_STEP); // 1 BNB > 1 USDC
        factory.setLBPairImplementation(address(new LBPair(factory)));
        factory.createLBPairRevision(weth, usdc, DEFAULT_BIN_STEP); // 1 WETH = 1 USDC

        // Add liquidity to V2
        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdt, usdc, highLiquidityAmount, ID_ONE, 7, 0);
        legacyRouterV2.addLiquidity(liquidityParameters.toLegacy());
    }

    function test_Constructor() public {
        assertEq(address(quoter.getRouterV2()), address(router));
        assertEq(address(quoter.getFactoryV1()), AvalancheAddresses.JOE_V1_FACTORY);
        assertEq(address(quoter.getLegacyFactoryV2()), AvalancheAddresses.JOE_V2_FACTORY);
        assertEq(address(quoter.getFactoryV2()), address(factory));
    }

    function test_InvalidLength() public {
        address[] memory route;
        route = new address[](1);
        vm.expectRevert(LBQuoter.LBQuoter_InvalidLength.selector);
        quoter.findBestPathFromAmountIn(route, 1e18);
        vm.expectRevert(LBQuoter.LBQuoter_InvalidLength.selector);
        quoter.findBestPathFromAmountOut(route, 20e6);
    }

    function test_Scenario1() public {
        // USDT/USDC, V1 with low liquidity, V2 with high liquidity
        address[] memory route = new address[](2);
        route[0] = address(usdt);
        route[1] = address(usdc);

        // Small amountIn
        uint128 amountIn = 1e16;
        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(quote.amounts[0], amountIn);
        assertApproxEqRel(quote.amounts[1], amountIn * 2, 5e16);
        assertEq(quote.binSteps[0], 0);
        assertEq(quote.revisions[0], 0);

        // Large amountIn
        amountIn = 100e18;
        quote = quoter.findBestPathFromAmountIn(route, amountIn);

        // assertEq(quote.amounts[0], amountIn);
        // assertApproxEqRel(quote.amounts[1], amountIn * 2, 5e16);
        // assertEq(quote.binSteps[0], DEFAULT_BIN_STEP);
        // assertEq(quote.revisions[0], 0);
    }
}
