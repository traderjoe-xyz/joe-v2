// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract LiquidityBinRouterTest is TestHelper {
    LBPair internal pair0;
    LBPair internal pair1;
    LBPair internal pair2;
    LBPair internal pair3;
    LBPair internal taxTokenPair1;
    LBPair internal taxTokenPair;

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token10D = new ERC20MockDecimals(10);
        token12D = new ERC20MockDecimals(12);
        token18D = new ERC20MockDecimals(18);
        token24D = new ERC20MockDecimals(24);

        taxToken = new ERC20WithTransferTax();

        wavax = new WAVAX();

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        router = new LBRouter(factory, IJoeFactory(JOE_V1_FACTORY_ADDRESS), IWAVAX(address(wavax)));

        pair = createLBPairDefaultFees(token6D, token18D);
        addLiquidityFromRouter(token6D, token18D, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);

        pair0 = createLBPairDefaultFees(token6D, token10D);
        addLiquidityFromRouter(token6D, token10D, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair1 = createLBPairDefaultFees(token10D, token12D);
        addLiquidityFromRouter(token10D, token12D, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair2 = createLBPairDefaultFees(token12D, token18D);
        addLiquidityFromRouter(token12D, token18D, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair3 = createLBPairDefaultFees(token18D, token24D);
        addLiquidityFromRouter(token18D, token24D, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        taxTokenPair1 = createLBPairDefaultFees(token6D, taxToken);
        addLiquidityFromRouter(token6D, ERC20MockDecimals(address(taxToken)), 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);

        taxTokenPair = createLBPairDefaultFees(taxToken, wavax);
        addLiquidityFromRouter(
            ERC20MockDecimals(address(taxToken)),
            ERC20MockDecimals(address(wavax)),
            100e18,
            ID_ONE,
            9,
            2,
            DEFAULT_BIN_STEP
        );

        pairWavax = createLBPairDefaultFees(token6D, wavax);
        addLiquidityFromRouter(token6D, ERC20MockDecimals(address(wavax)), 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
    }

    function testSwapExactTokensForTokensSinglePair() public {
        uint256 amountIn = 1e18;

        token6D.mint(DEV, amountIn);

        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        (uint256 amountOut, ) = router.getSwapOut(pair, amountIn, true);
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactTokensForTokens(amountIn, amountOut + 1, pairVersions, tokenList, DEV, block.timestamp);

        router.swapExactTokensForTokens(amountIn, amountOut, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(token18D.balanceOf(DEV), amountOut, 10);
    }

    function testSwapExactTokensForAvaxSinglePair() public {
        uint256 amountIn = 1e18;

        token6D.mint(ALICE, amountIn);

        vm.startPrank(ALICE);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = wavax;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        (uint256 amountOut, ) = router.getSwapOut(pair, amountIn, true);

        uint256 devBalanceBefore = ALICE.balance;
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactTokensForAVAX(amountIn, amountOut + 1, pairVersions, tokenList, ALICE, block.timestamp);

        router.swapExactTokensForAVAX(amountIn, amountOut, pairVersions, tokenList, ALICE, block.timestamp);
        vm.stopPrank();

        assertEq(ALICE.balance - devBalanceBefore, amountOut);
    }

    function testSwapExactAVAXForTokensSinglePair() public {
        uint256 amountIn = 1e18;

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = wavax;
        tokenList[1] = token6D;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        (uint256 amountOut, ) = router.getSwapOut(pairWavax, amountIn, false);

        vm.deal(DEV, amountIn);
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactAVAXForTokens{value: amountIn}(amountOut + 1, pairVersions, tokenList, DEV, block.timestamp);

        router.swapExactAVAXForTokens{value: amountIn}(amountOut, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(token6D.balanceOf(DEV), amountOut, 13);
    }

    function testSwapTokensForExactTokensSinglePair() public {
        uint256 amountOut = 1e18;

        (uint256 amountIn, ) = router.getSwapIn(pair, amountOut, true);
        token6D.mint(DEV, amountIn);

        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;
        vm.expectRevert(abi.encodeWithSelector(LBRouter__MaxAmountInExceeded.selector, amountIn - 1, amountIn));
        router.swapTokensForExactTokens(amountOut, amountIn - 1, pairVersions, tokenList, DEV, block.timestamp);

        router.swapTokensForExactTokens(amountOut, amountIn, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(token18D.balanceOf(DEV), amountOut, 10);
    }

    function testSwapTokensForExactAVAXSinglePair() public {
        uint256 amountOut = 1e18;

        (uint256 amountIn, ) = router.getSwapIn(pairWavax, amountOut, true);
        token6D.mint(ALICE, amountIn);

        vm.startPrank(ALICE);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = wavax;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        uint256 devBalanceBefore = ALICE.balance;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__MaxAmountInExceeded.selector, amountIn - 1, amountIn));
        router.swapTokensForExactAVAX(amountOut, amountIn - 1, pairVersions, tokenList, ALICE, block.timestamp);

        router.swapTokensForExactAVAX(amountOut, amountIn, pairVersions, tokenList, ALICE, block.timestamp);
        vm.stopPrank();

        assertEq(ALICE.balance - devBalanceBefore, amountOut);
    }

    function testSwapAVAXForExactTokensSinglePair() public {
        uint256 amountOut = 1e18;

        (uint256 amountIn, ) = router.getSwapIn(pairWavax, amountOut, false);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = wavax;
        tokenList[1] = token6D;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        vm.deal(DEV, amountIn);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__MaxAmountInExceeded.selector, amountIn - 1, amountIn));
        router.swapAVAXForExactTokens{value: amountIn - 1}(amountOut, pairVersions, tokenList, ALICE, block.timestamp);
        router.swapAVAXForExactTokens{value: amountIn}(amountOut, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(token6D.balanceOf(DEV), amountOut, 13);
    }

    function testSwapExactTokensForTokensSupportingFeeOnTransferTokens() public {
        uint256 amountIn = 1e18;

        taxToken.mint(DEV, amountIn);

        taxToken.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = taxToken;
        tokenList[1] = wavax;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        (uint256 amountOut, ) = router.getSwapOut(taxTokenPair, amountIn, true);
        amountOut = amountOut / 2;
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOut + 1,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        // 50% tax to take into account
        assertApproxEqAbs(wavax.balanceOf(DEV), amountOut, 10);

        // Swap back in the other direction
        amountIn = wavax.balanceOf(DEV);
        wavax.approve(address(router), amountIn);
        tokenList[0] = wavax;
        tokenList[1] = taxToken;

        (amountOut, ) = router.getSwapOut(taxTokenPair, amountIn, true);
        amountOut = amountOut / 2;
        uint256 balanceBefore = taxToken.balanceOf(DEV);
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOut + 1,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            amountOut,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        assertApproxEqAbs(taxToken.balanceOf(DEV) - balanceBefore, amountOut, 10);
    }

    function testSwapExactTokensForAVAXSupportingFeeOnTransferTokens() public {
        uint256 amountIn = 1e18;

        taxToken.mint(ALICE, amountIn);

        vm.startPrank(ALICE);
        taxToken.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = taxToken;
        tokenList[1] = wavax;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        (uint256 amountOut, ) = router.getSwapOut(taxTokenPair, amountIn, true);
        amountOut = amountOut / 2;
        uint256 devBalanceBefore = ALICE.balance;
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn,
            amountOut + 1,
            pairVersions,
            tokenList,
            ALICE,
            block.timestamp
        );
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn,
            amountOut,
            pairVersions,
            tokenList,
            ALICE,
            block.timestamp
        );
        vm.stopPrank();

        assertGe(ALICE.balance - devBalanceBefore, amountOut);
    }

    function testSwapExactAVAXForTokensSupportingFeeOnTransferTokens() public {
        uint256 amountIn = 1e18;

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = wavax;
        tokenList[1] = taxToken;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        (uint256 amountOut, ) = router.getSwapOut(taxTokenPair, amountIn, true);
        amountOut = amountOut / 2;
        vm.deal(DEV, amountIn);
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOut + 1,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOut,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        assertApproxEqAbs(taxToken.balanceOf(DEV), amountOut, 10);
    }

    function testSwapExactTokensForTokensMultiplePairs() public {
        uint256 amountIn = 1e18;

        token6D.mint(DEV, amountIn);

        token6D.approve(address(router), amountIn);

        (IERC20[] memory tokenList, uint256[] memory pairVersions) = _buildComplexSwapRoute();

        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(token24D.balanceOf(DEV), 0);
    }

    function testSwapTokensForExactTokensMultiplePairs() public {
        uint256 amountOut = 1e18;

        token6D.mint(DEV, 100e18);

        token6D.approve(address(router), 100e18);

        (IERC20[] memory tokenList, uint256[] memory pairVersions) = _buildComplexSwapRoute();
        vm.expectRevert(
            abi.encodeWithSelector(LBRouter__MaxAmountInExceeded.selector, 100500938281494149, 1005015664148120440)
        );
        router.swapTokensForExactTokens(amountOut, 100500938281494149, pairVersions, tokenList, DEV, block.timestamp);
        router.swapTokensForExactTokens(amountOut, 100e18, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(token24D.balanceOf(DEV), amountOut);
    }

    function testSwapWithDifferentBinSteps() public {
        factory.setPreset(
            75,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            5,
            10,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED,
            DEFAULT_SAMPLE_LIFETIME
        );
        createLBPairDefaultFeesFromStartIdAndBinStep(token6D, token18D, ID_ONE, 75);
        addLiquidityFromRouter(token6D, token18D, 100e18, ID_ONE, 9, 2, 75);

        uint256 amountIn = 1e18;

        token6D.mint(DEV, amountIn);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList;
        uint256[] memory pairVersions;
        tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(token18D.balanceOf(DEV), 0);

        token18D.approve(address(router), token18D.balanceOf(DEV));

        tokenList[0] = token18D;
        tokenList[1] = token6D;
        pairVersions = new uint256[](1);
        pairVersions[0] = 75;

        router.swapExactTokensForTokens(token18D.balanceOf(DEV), 0, pairVersions, tokenList, DEV, block.timestamp);
        assertGt(token6D.balanceOf(DEV), 0);
    }

    function _buildComplexSwapRoute() private view returns (IERC20[] memory tokenList, uint256[] memory pairVersions) {
        tokenList = new IERC20[](5);
        tokenList[0] = token6D;
        tokenList[1] = token10D;
        tokenList[2] = token12D;
        tokenList[3] = token18D;
        tokenList[4] = token24D;

        pairVersions = new uint256[](4);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = DEFAULT_BIN_STEP;
        pairVersions[2] = DEFAULT_BIN_STEP;
        pairVersions[3] = DEFAULT_BIN_STEP;
    }

    function testTaxTokenEqualOnlyV2Swap() public {
        uint256 amountIn = 1e18;

        taxToken.mint(ALICE, amountIn);
        taxToken.mint(BOB, amountIn);
        token6D.mint(ALICE, amountIn);
        token6D.mint(BOB, amountIn);

        IERC20[] memory tokenList = new IERC20[](3);
        tokenList[0] = token6D;
        tokenList[1] = taxToken;
        tokenList[2] = wavax;
        uint256[] memory pairVersions = new uint256[](2);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = DEFAULT_BIN_STEP;

        vm.startPrank(ALICE);
        token6D.approve(address(router), amountIn);
        taxToken.approve(address(router), amountIn);
        uint256 aliceBalanceBefore = ALICE.balance;
        uint256 amountOutNotSupporting = router.swapExactTokensForAVAX(
            amountIn,
            0,
            pairVersions,
            tokenList,
            ALICE,
            block.timestamp
        );
        vm.stopPrank();

        vm.startPrank(BOB);
        token6D.approve(address(router), amountIn);
        taxToken.approve(address(router), amountIn);
        uint256 bobBalanceBefore = BOB.balance;
        uint256 amountOutSupporting = router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn,
            0,
            pairVersions,
            tokenList,
            BOB,
            block.timestamp
        );
        vm.stopPrank();

        assertEq(ALICE.balance, BOB.balance);
        assertEq(amountOutNotSupporting, amountOutSupporting);
    }

    function testSwappingOnNotExistingV2PairReverts() public {
        IERC20[] memory tokenListAvaxIn;
        IERC20[] memory tokenList;
        uint256[] memory pairVersions;

        uint256 amountIn2 = 1e18;
        vm.deal(DEV, amountIn2);

        tokenList = new IERC20[](3);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        tokenList[2] = wavax;

        pairVersions = new uint256[](2);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = DEFAULT_BIN_STEP + 1;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapExactTokensForTokens(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapExactTokensForAVAX(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapTokensForExactTokens(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapTokensForExactAVAX(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn2,
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn2,
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        tokenListAvaxIn = new IERC20[](3);
        tokenListAvaxIn[0] = wavax;
        tokenListAvaxIn[1] = token6D;
        tokenListAvaxIn[2] = token18D;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token6D, token18D, pairVersions[1]));
        router.swapExactAVAXForTokens{value: amountIn2}(0, pairVersions, tokenListAvaxIn, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token6D, token18D, pairVersions[1]));
        router.swapAVAXForExactTokens{value: amountIn2}(0, pairVersions, tokenListAvaxIn, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token6D, token18D, pairVersions[1]));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn2}(
            0,
            pairVersions,
            tokenListAvaxIn,
            DEV,
            block.timestamp
        );
    }

    receive() external payable {}
}

contract LiquidityBinRouterForkTest is TestHelper {
    LBPair internal pair0;
    LBPair internal pair1;
    LBPair internal pair2;
    LBPair internal pair3;
    LBPair internal taxTokenPair;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 19_358_000);
        token6D = new ERC20MockDecimals(6);
        token10D = new ERC20MockDecimals(10);
        token12D = new ERC20MockDecimals(12);
        token18D = new ERC20MockDecimals(18);
        token24D = new ERC20MockDecimals(24);

        taxToken = new ERC20WithTransferTax();

        wavax = WAVAX(WAVAX_AVALANCHE_ADDRESS);
        usdc = ERC20MockDecimals(USDC_AVALANCHE_ADDRESS);

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        router = new LBRouter(factory, IJoeFactory(JOE_V1_FACTORY_ADDRESS), IWAVAX(address(wavax)));

        pair = createLBPairDefaultFees(token6D, token18D);
        addLiquidityFromRouter(token6D, token18D, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);

        pair0 = createLBPairDefaultFees(token6D, token10D);
        addLiquidityFromRouter(token6D, token10D, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair1 = createLBPairDefaultFees(token10D, token12D);
        addLiquidityFromRouter(token10D, token12D, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair2 = createLBPairDefaultFees(token12D, token18D);
        addLiquidityFromRouter(token12D, token18D, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair3 = createLBPairDefaultFees(token18D, token24D);
        addLiquidityFromRouter(token18D, token24D, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);

        taxTokenPair = createLBPairDefaultFees(taxToken, wavax);
        addLiquidityFromRouter(
            ERC20MockDecimals(address(taxToken)),
            ERC20MockDecimals(address(wavax)),
            100e18,
            ID_ONE,
            9,
            2,
            DEFAULT_BIN_STEP
        );

        pairWavax = createLBPairDefaultFees(token6D, wavax);
        addLiquidityFromRouter(token6D, ERC20MockDecimals(address(wavax)), 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
    }

    function testSwapExactTokensForTokensMultiplePairsWithV1() public {
        if (block.number < 1000) {
            console.log("fork mainnet for V1 testing support");
            return;
        }

        uint256 amountIn = 1e18;

        token6D.mint(DEV, amountIn);

        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList;
        uint256[] memory pairVersions;

        tokenList = new IERC20[](3);
        tokenList[0] = token6D;
        tokenList[1] = wavax;
        tokenList[2] = usdc;

        pairVersions = new uint256[](2);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = 0;

        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(usdc.balanceOf(DEV), 0);

        tokenList[0] = usdc;
        tokenList[1] = wavax;
        tokenList[2] = token6D;

        pairVersions[0] = 0;
        pairVersions[1] = DEFAULT_BIN_STEP;

        uint256 balanceBefore = token6D.balanceOf(DEV);

        usdc.approve(address(router), usdc.balanceOf(DEV));
        router.swapExactTokensForTokens(usdc.balanceOf(DEV), 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(token6D.balanceOf(DEV) - balanceBefore, 0);
    }

    function testSwapTokensForExactTokensMultiplePairsWithV1() public {
        if (block.number < 1000) {
            console.log("fork mainnet for V1 testing support");
            return;
        }

        uint256 amountOut = 1e6;

        token6D.mint(DEV, 100e18);

        token6D.approve(address(router), 100e18);

        IERC20[] memory tokenList;
        uint256[] memory pairVersions;

        tokenList = new IERC20[](3);
        tokenList[0] = token6D;
        tokenList[1] = wavax;
        tokenList[2] = usdc;

        pairVersions = new uint256[](2);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = 0;

        router.swapTokensForExactTokens(amountOut, 100e18, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(usdc.balanceOf(DEV), amountOut);

        tokenList[0] = usdc;
        tokenList[1] = wavax;
        tokenList[2] = token6D;

        pairVersions[0] = 0;
        pairVersions[1] = DEFAULT_BIN_STEP;

        uint256 balanceBefore = token6D.balanceOf(DEV);

        usdc.approve(address(router), usdc.balanceOf(DEV));
        router.swapTokensForExactTokens(amountOut, usdc.balanceOf(DEV), pairVersions, tokenList, DEV, block.timestamp);

        assertEq(token6D.balanceOf(DEV) - balanceBefore, amountOut);

        vm.stopPrank();
    }

    function testTaxTokenSwappedOnV1Pairs() public {
        if (block.number < 1000) {
            console.log("fork mainnet for V1 testing support");
            return;
        }
        uint256 amountIn = 100e18;

        IJoeFactory factoryv1 = IJoeFactory(JOE_V1_FACTORY_ADDRESS);
        //create taxToken-AVAX pair in DEXv1
        address taxPairv11 = factoryv1.createPair(address(taxToken), address(wavax));
        taxToken.mint(taxPairv11, amountIn);
        vm.deal(DEV, amountIn);
        wavax.deposit{value: amountIn}();
        wavax.transfer(taxPairv11, amountIn);
        IJoePair(taxPairv11).mint(DEV);

        //create taxToken-token6D pair in DEXv1
        address taxPairv12 = factoryv1.createPair(address(taxToken), address(token6D));
        taxToken.mint(taxPairv12, amountIn);
        token6D.mint(taxPairv12, amountIn);
        IJoePair(taxPairv12).mint(DEV);

        token6D.mint(DEV, amountIn);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList;
        uint256[] memory pairVersions;

        tokenList = new IERC20[](3);
        tokenList[0] = token6D;
        tokenList[1] = taxToken;
        tokenList[2] = wavax;

        pairVersions = new uint256[](2);
        pairVersions[0] = 0;
        pairVersions[1] = 0;
        uint256 amountIn2 = 1e18;

        vm.expectRevert("Joe: K");
        router.swapExactTokensForTokens(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn2,
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );
        vm.deal(DEV, amountIn2);
        vm.expectRevert("Joe: K");
        router.swapExactTokensForAVAX(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn2,
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        tokenList[0] = wavax;
        tokenList[1] = taxToken;
        tokenList[2] = token6D;

        vm.deal(DEV, amountIn2);
        vm.expectRevert("Joe: K");
        router.swapExactAVAXForTokens{value: amountIn2}(0, pairVersions, tokenList, DEV, block.timestamp);
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn2}(
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );
    }

    function testSwappingOnNotExistingV1PairReverts() public {
        IERC20[] memory tokenListAvaxIn;
        IERC20[] memory tokenList;
        uint256[] memory pairVersions;

        uint256 amountIn2 = 1e18;
        vm.deal(DEV, amountIn2);

        tokenList = new IERC20[](3);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        tokenList[2] = wavax;

        pairVersions = new uint256[](2);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = 0;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapExactTokensForTokens(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapExactTokensForAVAX(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapTokensForExactTokens(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapTokensForExactAVAX(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn2,
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token18D, wavax, pairVersions[1]));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn2,
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        tokenListAvaxIn = new IERC20[](3);
        tokenListAvaxIn[0] = wavax;
        tokenListAvaxIn[1] = token6D;
        tokenListAvaxIn[2] = token18D;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token6D, token18D, pairVersions[1]));
        router.swapExactAVAXForTokens{value: amountIn2}(0, pairVersions, tokenListAvaxIn, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token6D, token18D, pairVersions[1]));
        router.swapAVAXForExactTokens{value: amountIn2}(0, pairVersions, tokenListAvaxIn, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, token6D, token18D, pairVersions[1]));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn2}(
            0,
            pairVersions,
            tokenListAvaxIn,
            DEV,
            block.timestamp
        );
    }

    receive() external payable {}
}
