// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "../helpers/TestHelper.sol";

/**
 * Market deployed:
 * - USDT/USDC, V1 with low liquidity, V2 with high liquidity
 * - WNATIVE/USDC, V1 with high liquidity, V2 with low liquidity
 * - WETH/USDC, V1 with low liquidity, V2.2 with high liquidity
 * - BNB/USDC, V2 with high liquidity, V2.2 with low liquidity
 *
 * Every market with low liquidity has a slighly higher price.
 * It should be picked with small amounts but not with large amounts.
 * All tokens are considered 18 decimals for simplification purposes.
 */
contract LiquidityBinQuoterTest is TestHelper {
    using Utils for ILBRouter.LiquidityParameters;

    uint256 private defaultBaseFee = DEFAULT_BIN_STEP * uint256(DEFAULT_BASE_FACTOR) * 1e10;

    address wethe = 0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB;

    function setUp() public override {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 46012280);
        super.setUp();

        uint256 lowLiquidityAmount = 1e18;
        uint256 highLiquidityAmount = 1e24;

        // Get tokens to add liquidity
        deal(address(usdc), address(this), 10 * highLiquidityAmount);
        deal(address(usdt), address(this), 10 * highLiquidityAmount);
        deal(address(wnative), address(this), 10 * highLiquidityAmount);
        deal(address(weth), address(this), 10 * highLiquidityAmount);
        deal(address(bnb), address(this), 10 * highLiquidityAmount);

        // Add liquidity to V1
        routerV1.addLiquidity(
            address(usdt),
            address(usdc),
            lowLiquidityAmount / 2, // 1 USDT = 2 USDC
            lowLiquidityAmount,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        routerV1.addLiquidity(
            address(wnative),
            address(usdc),
            highLiquidityAmount, // 1 NATIVE = 1 USDC
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
        legacyFactoryV2.createLBPair(wnative, usdc, ID_ONE + 50, DEFAULT_BIN_STEP); // 1 NATIVE > 1 USDC
        legacyFactoryV2.createLBPair(bnb, usdc, ID_ONE, DEFAULT_BIN_STEP); // 1 BNB = 1 USDC
        vm.stopPrank();

        factory.createLBPair(weth, usdc, ID_ONE, DEFAULT_BIN_STEP); // 1 WETH = 1 USDC
        factory.createLBPair(bnb, usdc, ID_ONE + 50, DEFAULT_BIN_STEP); // 1 BNB > 1 USDC

        // Add liquidity to V2
        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdt, usdc, highLiquidityAmount, ID_ONE, 7, 0);
        legacyRouterV2.addLiquidity(liquidityParameters.toLegacy());

        liquidityParameters = getLiquidityParameters(wnative, usdc, lowLiquidityAmount, ID_ONE + 50, 7, 0);
        legacyRouterV2.addLiquidity(liquidityParameters.toLegacy());

        liquidityParameters = getLiquidityParameters(weth, usdc, highLiquidityAmount, ID_ONE, 7, 0);
        router.addLiquidity(liquidityParameters);

        liquidityParameters = getLiquidityParameters(bnb, usdc, highLiquidityAmount, ID_ONE, 7, 0);
        legacyRouterV2.addLiquidity(liquidityParameters.toLegacy());

        liquidityParameters = getLiquidityParameters(bnb, usdc, lowLiquidityAmount, ID_ONE + 50, 7, 0);
        router.addLiquidity(liquidityParameters);
    }

    function test_Constructor() public view {
        assertEq(address(quoter.getRouterV2_2()), address(router), "test_Constructor::1");
        assertEq(address(quoter.getRouterV2_1()), address(AvalancheAddresses.JOE_V2_1_ROUTER), "test_Constructor::2");
        assertEq(address(quoter.getFactoryV1()), AvalancheAddresses.JOE_V1_FACTORY, "test_Constructor::3");
        assertEq(address(quoter.getLegacyFactoryV2()), AvalancheAddresses.JOE_V2_FACTORY, "test_Constructor::4");
        assertEq(address(quoter.getFactoryV2_2()), address(factory), "test_Constructor::5");
        assertEq(address(quoter.getFactoryV2_1()), AvalancheAddresses.JOE_V2_1_FACTORY, "test_Constructor::6");
        assertEq(address(quoter.getLegacyRouterV2()), address(legacyRouterV2), "test_Constructor::7");
    }

    function test_InvalidLength() public {
        address[] memory route;
        route = new address[](1);
        vm.expectRevert(LBQuoter.LBQuoter_InvalidLength.selector);
        quoter.findBestPathFromAmountIn(route, 1e18);
        vm.expectRevert(LBQuoter.LBQuoter_InvalidLength.selector);
        quoter.findBestPathFromAmountOut(route, 20e6);
    }

    function test_Scenario1() public view {
        // USDT/USDC, V1 with low liquidity, V2 with high liquidity
        address[] memory route = new address[](2);
        route[0] = address(usdt);
        route[1] = address(usdc);

        // Small amountIn
        uint128 amountIn = 1e16;
        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(quote.amounts[0], amountIn, "test_Scenario1::1");
        assertApproxEqRel(quote.amounts[1], amountIn * 2, 5e16, "test_Scenario1::2");
        assertEq(quote.binSteps[0], 0, "test_Scenario1::3");
        assertEq(uint256(quote.versions[0]), 0, "test_Scenario1::4");

        // Large amountIn
        amountIn = 100e18;
        quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(quote.amounts[0], amountIn, "test_Scenario1::5");
        assertApproxEqRel(quote.amounts[1], amountIn, 5e16, "test_Scenario1::6");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "test_Scenario1::7");
        assertEq(uint256(quote.versions[0]), 1, "test_Scenario1::8");

        // Small amountOut
        uint128 amountOut = 1e16;
        quote = quoter.findBestPathFromAmountOut(route, amountOut);

        assertApproxEqRel(quote.amounts[0], amountOut / 2, 5e16, "test_Scenario1::9");
        assertEq(quote.amounts[1], amountOut, "test_Scenario1::10");
        assertEq(quote.binSteps[0], 0, "test_Scenario1::11");
        assertEq(uint256(quote.versions[0]), 0, "test_Scenario1::12");

        // Large amountOut
        amountOut = 100e18;
        quote = quoter.findBestPathFromAmountOut(route, amountOut);

        assertApproxEqRel(quote.amounts[0], amountOut, 5e16, "test_Scenario1::13");
        assertEq(quote.amounts[1], amountOut, "test_Scenario1::14");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "test_Scenario1::15");
        assertEq(uint256(quote.versions[0]), 1, "test_Scenario1::16");
    }

    function test_Scenario2() public view {
        // WNATIVE/USDC, V1 with high liquidity, V2 with low liquidity
        address[] memory route = new address[](2);
        route[0] = address(wnative);
        route[1] = address(usdc);

        // Small amountIn
        uint128 amountIn = 1e16;
        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(quote.amounts[0], amountIn, "test_Scenario2::1");
        assertGt(quote.amounts[1], amountIn, "test_Scenario2::2");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "test_Scenario2::3");
        assertEq(uint256(quote.versions[0]), 1, "test_Scenario2::4");

        // Large amountIn
        amountIn = 100e18;
        quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(quote.amounts[0], amountIn, "test_Scenario2::5");
        assertApproxEqRel(quote.amounts[1], amountIn, 5e16, "test_Scenario2::6");
        assertEq(quote.binSteps[0], 0, "test_Scenario2::7");
        assertEq(uint256(quote.versions[0]), 0, "test_Scenario2::8");

        // Small amountOut
        uint128 amountOut = 1e16;
        quote = quoter.findBestPathFromAmountOut(route, amountOut);

        assertLt(quote.amounts[0], amountOut, "test_Scenario2::9");
        assertEq(quote.amounts[1], amountOut, "test_Scenario2::10");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "test_Scenario2::11");
        assertEq(uint256(quote.versions[0]), 1, "test_Scenario2::12");

        // Large amountOut
        amountOut = 100e18;
        quote = quoter.findBestPathFromAmountOut(route, amountOut);

        assertApproxEqRel(quote.amounts[0], amountOut, 5e16, "test_Scenario2::13");
        assertEq(quote.amounts[1], amountOut, "test_Scenario2::14");
        assertEq(quote.binSteps[0], 0, "test_Scenario2::15");
        assertEq(uint256(quote.versions[0]), 0, "test_Scenario2::16");
    }

    function test_Scenario3() public view {
        // WETH/USDC, V1 with low liquidity, V2.2 with high liquidity
        address[] memory route = new address[](2);
        route[0] = address(weth);
        route[1] = address(usdc);

        // Small amountIn
        uint128 amountIn = 1e16;
        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(quote.amounts[0], amountIn, "test_Scenario3::1");
        assertApproxEqRel(quote.amounts[1], amountIn * 2, 5e16, "test_Scenario3::2");
        assertEq(quote.binSteps[0], 0, "test_Scenario3::3");
        assertEq(uint256(quote.versions[0]), 0, "test_Scenario3::4");

        // Large amountIn
        amountIn = 100e18;
        quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(quote.amounts[0], amountIn, "test_Scenario3::5");
        assertApproxEqRel(quote.amounts[1], amountIn, 5e16, "test_Scenario3::6");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "test_Scenario3::7");
        assertEq(uint256(quote.versions[0]), 3, "test_Scenario3::8");

        // Small amountOut
        uint128 amountOut = 1e16;
        quote = quoter.findBestPathFromAmountOut(route, amountOut);

        assertApproxEqRel(quote.amounts[0], amountOut / 2, 5e16, "test_Scenario3::9");
        assertEq(quote.amounts[1], amountOut, "test_Scenario3::10");
        assertEq(quote.binSteps[0], 0, "test_Scenario3::11");
        assertEq(uint256(quote.versions[0]), 0, "test_Scenario3::12");

        // Large amountOut
        amountOut = 100e18;
        quote = quoter.findBestPathFromAmountOut(route, amountOut);

        assertApproxEqRel(quote.amounts[0], amountOut, 5e16, "test_Scenario3::13");
        assertEq(quote.amounts[1], amountOut, "test_Scenario3::14");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "test_Scenario3::15");
        assertEq(uint256(quote.versions[0]), 3, "test_Scenario3::16");
    }

    function test_Scenario4() public view {
        // BNB/USDC, V2 with high liquidity, V2.2 with low liquidity
        address[] memory route = new address[](2);
        route[0] = address(bnb);
        route[1] = address(usdc);

        // Small amountIn
        uint128 amountIn = 1e16;
        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(quote.amounts[0], amountIn, "test_Scenario4::1");
        assertGt(quote.amounts[1], amountIn, "test_Scenario4::2");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "test_Scenario4::3");
        assertEq(uint256(quote.versions[0]), 3, "test_Scenario4::4");

        // Large amountIn
        amountIn = 100e18;
        quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(quote.amounts[0], amountIn, "test_Scenario4::5");
        assertApproxEqRel(quote.amounts[1], amountIn, 5e16, "test_Scenario4::6");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "test_Scenario4::7");
        assertEq(uint256(quote.versions[0]), 1, "test_Scenario4::8");

        // Small amountOut
        uint128 amountOut = 1e16;
        quote = quoter.findBestPathFromAmountOut(route, amountOut);

        assertLt(quote.amounts[0], amountOut, "test_Scenario4::9");
        assertEq(quote.amounts[1], amountOut, "test_Scenario4::10");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "test_Scenario4::11");
        assertEq(uint256(quote.versions[0]), 3, "test_Scenario4::12");

        // Large amountOut
        amountOut = 100e18;
        quote = quoter.findBestPathFromAmountOut(route, amountOut);

        assertApproxEqRel(quote.amounts[0], amountOut, 5e16, "test_Scenario4::13");
        assertEq(quote.amounts[1], amountOut, "test_Scenario4::14");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "test_Scenario4::15");
        assertEq(uint256(quote.versions[0]), 1, "test_Scenario4::16");
    }

    function test_Scenario5() public view {
        // WETH/WAVAX, V2.1 with high liquidity
        address[] memory route = new address[](2);
        route[0] = address(wnative);
        route[1] = address(wethe);

        uint256 price = 103.5e18; // 103.5 avax for 1 weth

        // Large amountIn
        uint128 amountIn = 100e18;
        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(quote.amounts[0], amountIn, "test_Scenario5::1");
        assertApproxEqRel(quote.amounts[1], amountIn * 1e18 / price, 5e16, "test_Scenario5::2");
        assertEq(quote.binSteps[0], 10, "test_Scenario5::3");
        assertEq(uint256(quote.versions[0]), 2, "test_Scenario5::4");

        // Large amountOut
        uint128 amountOut = 100e18;
        quote = quoter.findBestPathFromAmountOut(route, amountOut);

        assertApproxEqRel(quote.amounts[0], price * amountOut / 1e18, 5e16, "test_Scenario5::5");
        assertEq(quote.amounts[1], amountOut, "test_Scenario5::6");
        assertEq(quote.binSteps[0], 10, "test_Scenario5::7");
        assertEq(uint256(quote.versions[0]), 2, "test_Scenario5::8");
    }
}
