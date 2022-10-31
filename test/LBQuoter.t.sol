// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract LiquidityBinQuoterTest is TestHelper {
    using Math512Bits for uint256;

    IJoeFactory private factoryV1;
    ERC20MockDecimals private testWavax;

    uint256 private defaultBaseFee = DEFAULT_BIN_STEP * uint256(DEFAULT_BASE_FACTOR) * 1e10;

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
        factoryV1.createPair(address(testWavax), address(usdc));
        factoryV1.createPair(address(usdt), address(usdc));
        createLBPairDefaultFees(usdt, usdc);
        createLBPairDefaultFeesFromStartId(testWavax, usdc, convertIdAvaxToUSD(DEFAULT_BIN_STEP));
    }

    function testConstructor() public {
        assertEq(address(quoter.routerV2()), address(router));
        assertEq(address(quoter.factoryV1()), JOE_V1_FACTORY_ADDRESS);
        assertEq(address(quoter.factoryV2()), address(factory));
    }

    function testGetSwapOutOnV2Pair() public {
        addLiquidityFromRouter(testWavax, usdc, 20_000e6, convertIdAvaxToUSD(DEFAULT_BIN_STEP), 9, 2, DEFAULT_BIN_STEP);

        address[] memory route;
        route = new address[](2);
        route[0] = address(testWavax);
        route[1] = address(usdc);

        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountIn(route, 1e18);

        assertApproxEqAbs(quote.amounts[1], 20e6, 2e6, "Price of 1 AVAX should be approx 20 USDC");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP);
        assertApproxEqAbs(quote.fees[0], defaultBaseFee, 1e14);
        // The tested swap stays in the current active bin, so the slippage is zero
        assertApproxEqAbs(quote.amounts[0], quote.virtualAmountsWithoutSlippage[0], 1);
    }

    function testGetSwapInOnV2Pair() public {
        addLiquidityFromRouter(testWavax, usdc, 20_000e6, convertIdAvaxToUSD(DEFAULT_BIN_STEP), 9, 2, DEFAULT_BIN_STEP);

        address[] memory route;
        route = new address[](2);
        route[0] = address(testWavax);
        route[1] = address(usdc);

        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountOut(route, 20e6);

        assertApproxEqAbs(quote.amounts[0], 1e18, 0.1e18, "Price of 1 AVAX should be approx 20 USDT");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP);
        assertApproxEqAbs(quote.fees[0], defaultBaseFee, 1e14);
        // The tested swap stays in the current active bin, so the slippage is zero
        assertApproxEqAbs(quote.amounts[0], quote.virtualAmountsWithoutSlippage[0], 1);
    }

    function testGetSwapOutOnV1Pair() public {
        uint256 amountIn = 1e18;
        routerV1.addLiquidity(address(testWavax), address(usdc), 1_000e18, 20_000e6, 0, 0, DEV, block.timestamp);

        address[] memory route;
        route = new address[](2);
        route[0] = address(testWavax);
        route[1] = address(usdc);

        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountIn(route, amountIn);

        assertApproxEqAbs(quote.amounts[1], 20e6, 2e6, "Price of 1 AVAX should be approx 20 USDC");
        assertEq(quote.binSteps[0], 0);
        assertEq(quote.fees[0], 0.003e18);

        uint256 quoteAmountOut = JoeLibrary.quote(amountIn, 1_000e18, 20_000e6);
        uint256 feePaid = (quoteAmountOut * quote.fees[0]) / 1e18;
        assertEq(quote.virtualAmountsWithoutSlippage[1], quoteAmountOut - feePaid);
    }

    function testGetSwapInOnV1Pair() public {
        uint256 amountOut = 20e6;
        routerV1.addLiquidity(address(testWavax), address(usdc), 1_000e18, 20_000e6, 0, 0, DEV, block.timestamp);

        address[] memory route;
        route = new address[](2);
        route[0] = address(testWavax);
        route[1] = address(usdc);

        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountOut(route, amountOut);

        assertApproxEqAbs(quote.amounts[0], 1e18, 0.1e18, "Price of 1 AVAX should be approx 20 USDT");
        assertEq(quote.binSteps[0], 0);
        assertEq(quote.fees[0], 0.003e18);

        // Fees are expressed in the In token
        // To get the theorical amountIn without slippage but with the fees, the calculation is amountIn = amountOut / price / (1 - fees)
        uint256 quoteAmountInWithFees = JoeLibrary.quote(
            (amountOut * 1e18) / (1e18 - quote.fees[0]),
            20_000e6,
            1_000e18
        );
        assertApproxEqAbs(quote.virtualAmountsWithoutSlippage[0], quoteAmountInWithFees, 1e12);
    }

    function testGetSwapOutOnComplexRoute() public {
        routerV1.addLiquidity(address(testWavax), address(usdc), 1_000e18, 20_000e6, 0, 0, DEV, block.timestamp);
        addLiquidityFromRouter(usdt, usdc, 10_000e6, ID_ONE, 9, 2, DEFAULT_BIN_STEP);

        address[] memory route;
        route = new address[](3);
        route[0] = address(testWavax);
        route[1] = address(usdc);
        route[2] = address(usdt);

        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountIn(route, 1e18);

        assertApproxEqAbs(quote.amounts[2], 20e6, 2e6, "Price of 1 AVAX should be approx 20 USDT");
        assertEq(quote.binSteps[0], 0);
        assertEq(quote.binSteps[1], DEFAULT_BIN_STEP);
        assertEq(quote.fees[0], 0.003e18);
        assertApproxEqAbs(quote.fees[1], defaultBaseFee, 1e14);
    }

    function testGetSwapInOnComplexRoute() public {
        routerV1.addLiquidity(address(testWavax), address(usdc), 1_000e18, 20_000e6, 0, 0, DEV, block.timestamp);
        addLiquidityFromRouter(usdt, usdc, 10_000e6, ID_ONE, 9, 2, DEFAULT_BIN_STEP);

        address[] memory route;
        route = new address[](3);
        route[0] = address(testWavax);
        route[1] = address(usdc);
        route[2] = address(usdt);

        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountOut(route, 20e6);

        assertApproxEqAbs(quote.amounts[0], 1e18, 0.1e18, "Price of 1 AVAX should be approx 20 USDT");

        assertEq(quote.binSteps[0], 0);
        assertEq(quote.binSteps[1], DEFAULT_BIN_STEP);
        assertEq(quote.fees[0], 0.003e18);
        assertApproxEqAbs(quote.fees[1], defaultBaseFee, 1e14);
    }

    function testGetSwapInWithMultipleChoices() public {
        // On V1, 1 AVAX = 19 USDC
        routerV1.addLiquidity(address(testWavax), address(usdc), 1_000e18, 19_000e6, 0, 0, DEV, block.timestamp);
        // On V2, 1 AVAX = 20 USDC
        addLiquidityFromRouter(testWavax, usdc, 20_000e6, convertIdAvaxToUSD(DEFAULT_BIN_STEP), 9, 2, DEFAULT_BIN_STEP);

        address[] memory route;
        route = new address[](2);
        route[0] = address(testWavax);
        route[1] = address(usdc);

        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountOut(route, 20e6);

        assertApproxEqAbs(quote.amounts[0], 1e18, 0.1e18, "Price of 1 AVAX should be approx 20 USDC");
        assertEq(quote.binSteps[0], DEFAULT_BIN_STEP, "LBPair should be picked as it has the best price");
    }

    function testGetSwapOutWithMultipleChoices() public {
        // On V1, 1 AVAX = 20 USDT
        routerV1.addLiquidity(address(testWavax), address(usdt), 1_000e18, 20_000e6, 0, 0, DEV, block.timestamp);
        // On V2, 1 AVAX = 19 USDT
        uint24 desiredId = getIdFromPrice(uint256(19e6).shiftDivRoundDown(128, 1e18));
        createLBPairDefaultFeesFromStartId(testWavax, usdt, desiredId);
        addLiquidityFromRouter(testWavax, usdt, 20_000e6, desiredId, 9, 2, DEFAULT_BIN_STEP);

        address[] memory route;
        route = new address[](2);
        route[0] = address(testWavax);
        route[1] = address(usdt);

        LBQuoter.Quote memory quote = quoter.findBestPathFromAmountIn(route, 1e18);

        assertApproxEqAbs(quote.amounts[1], 20e6, 2e6, "Price of 1 AVAX should be approx 20 USDT");
        assertEq(quote.binSteps[0], 0, "V1 pair should be picked as it has the best price");
    }

    function testInvalidLength() public {
        address[] memory route;
        route = new address[](1);
        vm.expectRevert(LBQuoter_InvalidLength.selector);
        quoter.findBestPathFromAmountIn(route, 1e18);
        vm.expectRevert(LBQuoter_InvalidLength.selector);
        quoter.findBestPathFromAmountOut(route, 20e6);
    }

    function convertIdAvaxToUSD(uint16 _binStep) internal pure returns (uint24 id) {
        uint256 price = uint256(20e6).shiftDivRoundDown(128, 1e18);
        id = getIdFromPrice(price, _binStep);
    }

    function getIdFromPrice(uint256 _price, uint16 _binStep) internal pure returns (uint24 id) {
        id = BinHelper.getIdFromPrice(_price, _binStep);
    }
}
