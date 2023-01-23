// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "test/helpers/TestHelper.sol";

contract LiquidityBinRouterTest is TestHelper {
    LBPair internal pair0;
    LBPair internal pair1;
    LBPair internal pair2;
    LBPair internal pair3;
    LBPair internal taxTokenPair1;
    LBPair internal taxTokenPair;

    function setUp() public override {
        usdc = new ERC20Mock(6);
        link = new ERC20Mock(10);
        wbtc = new ERC20Mock(12);
        weth = new ERC20Mock(18);
        wbtc = new ERC20Mock(24);

        taxToken = new ERC20TransferTaxMock();

        wavax = new WAVAX();

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        router = new LBRouter(factory, IJoeFactory(address(0)), IWAVAX(address(wavax)));

        pair = createLBPairDefaultFees(usdc, weth);
        addLiquidityFromRouter(usdc, weth, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);

        pair0 = createLBPairDefaultFees(usdc, link);
        addLiquidityFromRouter(usdc, link, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair1 = createLBPairDefaultFees(link, wbtc);
        addLiquidityFromRouter(link, wbtc, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair2 = createLBPairDefaultFees(wbtc, weth);
        addLiquidityFromRouter(wbtc, weth, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair3 = createLBPairDefaultFees(weth, wbtc);
        addLiquidityFromRouter(weth, wbtc, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        taxTokenPair1 = createLBPairDefaultFees(usdc, taxToken);
        addLiquidityFromRouter(usdc, ERC20Mock(address(taxToken)), 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);

        taxTokenPair = createLBPairDefaultFees(taxToken, wavax);
        addLiquidityFromRouter(
            ERC20Mock(address(taxToken)), ERC20Mock(address(wavax)), 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP
        );

        pairWavax = createLBPairDefaultFees(usdc, wavax);
        addLiquidityFromRouter(usdc, ERC20Mock(address(wavax)), 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
    }

    function testSwapExactTokensForTokensSinglePair() public {
        uint256 amountIn = 1e18;

        usdc.mint(DEV, amountIn);

        usdc.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = usdc;
        tokenList[1] = weth;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        (uint256 amountOut,) = router.getSwapOut(pair, amountIn, true);
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactTokensForTokens(amountIn, amountOut + 1, pairVersions, tokenList, DEV, block.timestamp);

        router.swapExactTokensForTokens(amountIn, amountOut, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(weth.balanceOf(DEV), amountOut, 10);
    }

    function testSwapExactTokensForAvaxSinglePair() public {
        uint256 amountIn = 1e18;

        usdc.mint(ALICE, amountIn);

        vm.startPrank(ALICE);
        usdc.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = usdc;
        tokenList[1] = wavax;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        (uint256 amountOut,) = router.getSwapOut(pair, amountIn, true);

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
        tokenList[1] = usdc;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        (uint256 amountOut,) = router.getSwapOut(pairWavax, amountIn, false);

        vm.deal(DEV, amountIn);
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactAVAXForTokens{value: amountIn}(amountOut + 1, pairVersions, tokenList, DEV, block.timestamp);

        router.swapExactAVAXForTokens{value: amountIn}(amountOut, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(usdc.balanceOf(DEV), amountOut, 13);
    }

    function testSwapTokensForExactTokensSinglePair() public {
        uint256 amountOut = 1e18;

        (uint256 amountIn,) = router.getSwapIn(pair, amountOut, true);
        usdc.mint(DEV, amountIn);

        usdc.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = usdc;
        tokenList[1] = weth;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;
        vm.expectRevert(abi.encodeWithSelector(LBRouter__MaxAmountInExceeded.selector, amountIn - 1, amountIn));
        router.swapTokensForExactTokens(amountOut, amountIn - 1, pairVersions, tokenList, DEV, block.timestamp);

        router.swapTokensForExactTokens(amountOut, amountIn, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(weth.balanceOf(DEV), amountOut, 10);
    }

    function testSwapTokensForExactAVAXSinglePair() public {
        uint256 amountOut = 1e18;

        (uint256 amountIn,) = router.getSwapIn(pairWavax, amountOut, true);
        usdc.mint(ALICE, amountIn);

        vm.startPrank(ALICE);
        usdc.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = usdc;
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

        (uint256 amountIn,) = router.getSwapIn(pairWavax, amountOut, false);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = wavax;
        tokenList[1] = usdc;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        vm.deal(DEV, amountIn);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__MaxAmountInExceeded.selector, amountIn - 1, amountIn));
        router.swapAVAXForExactTokens{value: amountIn - 1}(amountOut, pairVersions, tokenList, ALICE, block.timestamp);
        router.swapAVAXForExactTokens{value: amountIn}(amountOut, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(usdc.balanceOf(DEV), amountOut, 13);
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

        (uint256 amountOut,) = router.getSwapOut(taxTokenPair, amountIn, true);
        amountOut = amountOut / 2;
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut + 1, pairVersions, tokenList, DEV, block.timestamp
        );
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 0, pairVersions, tokenList, DEV, block.timestamp
        );

        // 50% tax to take into account
        assertApproxEqAbs(wavax.balanceOf(DEV), amountOut, 10);

        // Swap back in the other direction
        amountIn = wavax.balanceOf(DEV);
        wavax.approve(address(router), amountIn);
        tokenList[0] = wavax;
        tokenList[1] = taxToken;

        (amountOut,) = router.getSwapOut(taxTokenPair, amountIn, true);
        amountOut = amountOut / 2;
        uint256 balanceBefore = taxToken.balanceOf(DEV);
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut + 1, pairVersions, tokenList, DEV, block.timestamp
        );

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, amountOut, pairVersions, tokenList, DEV, block.timestamp
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

        (uint256 amountOut,) = router.getSwapOut(taxTokenPair, amountIn, true);
        amountOut = amountOut / 2;
        uint256 devBalanceBefore = ALICE.balance;
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, amountOut + 1, pairVersions, tokenList, ALICE, block.timestamp
        );
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, amountOut, pairVersions, tokenList, ALICE, block.timestamp
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

        (uint256 amountOut,) = router.getSwapOut(taxTokenPair, amountIn, true);
        amountOut = amountOut / 2;
        vm.deal(DEV, amountIn);
        vm.expectRevert(abi.encodeWithSelector(LBRouter__InsufficientAmountOut.selector, amountOut + 1, amountOut));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOut + 1, pairVersions, tokenList, DEV, block.timestamp
        );
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOut, pairVersions, tokenList, DEV, block.timestamp
        );

        assertApproxEqAbs(taxToken.balanceOf(DEV), amountOut, 10);
    }

    function testSwapExactTokensForTokensMultiplePairs() public {
        uint256 amountIn = 1e18;

        usdc.mint(DEV, amountIn);

        usdc.approve(address(router), amountIn);

        (IERC20[] memory tokenList, uint256[] memory pairVersions) = _buildComplexSwapRoute();

        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(wbtc.balanceOf(DEV), 0);
    }

    function testSwapTokensForExactTokensMultiplePairs() public {
        uint256 amountOut = 1e18;

        usdc.mint(DEV, 100e18);

        usdc.approve(address(router), 100e18);

        (IERC20[] memory tokenList, uint256[] memory pairVersions) = _buildComplexSwapRoute();
        vm.expectRevert(
            abi.encodeWithSelector(LBRouter__MaxAmountInExceeded.selector, 100500938281494149, 1005015664148120440)
        );
        router.swapTokensForExactTokens(amountOut, 100500938281494149, pairVersions, tokenList, DEV, block.timestamp);
        router.swapTokensForExactTokens(amountOut, 100e18, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(wbtc.balanceOf(DEV), amountOut);
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
        createLBPairDefaultFeesFromStartIdAndBinStep(usdc, weth, ID_ONE, 75);
        addLiquidityFromRouter(usdc, weth, 100e18, ID_ONE, 9, 2, 75);

        uint256 amountIn = 1e18;

        usdc.mint(DEV, amountIn);
        usdc.approve(address(router), amountIn);

        IERC20[] memory tokenList;
        uint256[] memory pairVersions;
        tokenList = new IERC20[](2);
        tokenList[0] = usdc;
        tokenList[1] = weth;
        pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(weth.balanceOf(DEV), 0);

        weth.approve(address(router), weth.balanceOf(DEV));

        tokenList[0] = weth;
        tokenList[1] = usdc;
        pairVersions = new uint256[](1);
        pairVersions[0] = 75;

        router.swapExactTokensForTokens(weth.balanceOf(DEV), 0, pairVersions, tokenList, DEV, block.timestamp);
        assertGt(usdc.balanceOf(DEV), 0);
    }

    function _buildComplexSwapRoute() private view returns (IERC20[] memory tokenList, uint256[] memory pairVersions) {
        tokenList = new IERC20[](5);
        tokenList[0] = usdc;
        tokenList[1] = link;
        tokenList[2] = wbtc;
        tokenList[3] = weth;
        tokenList[4] = wbtc;

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
        usdc.mint(ALICE, amountIn);
        usdc.mint(BOB, amountIn);

        IERC20[] memory tokenList = new IERC20[](3);
        tokenList[0] = usdc;
        tokenList[1] = taxToken;
        tokenList[2] = wavax;
        uint256[] memory pairVersions = new uint256[](2);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = DEFAULT_BIN_STEP;

        vm.startPrank(ALICE);
        usdc.approve(address(router), amountIn);
        taxToken.approve(address(router), amountIn);
        uint256 aliceBalanceBefore = ALICE.balance;
        uint256 amountOutNotSupporting =
            router.swapExactTokensForAVAX(amountIn, 0, pairVersions, tokenList, ALICE, block.timestamp);
        vm.stopPrank();

        vm.startPrank(BOB);
        usdc.approve(address(router), amountIn);
        taxToken.approve(address(router), amountIn);
        uint256 bobBalanceBefore = BOB.balance;
        uint256 amountOutSupporting = router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, 0, pairVersions, tokenList, BOB, block.timestamp
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
        tokenList[0] = usdc;
        tokenList[1] = weth;
        tokenList[2] = wavax;

        pairVersions = new uint256[](2);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = DEFAULT_BIN_STEP + 1;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapExactTokensForTokens(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapExactTokensForAVAX(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapTokensForExactTokens(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapTokensForExactAVAX(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp
        );

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp
        );

        tokenListAvaxIn = new IERC20[](3);
        tokenListAvaxIn[0] = wavax;
        tokenListAvaxIn[1] = usdc;
        tokenListAvaxIn[2] = weth;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, usdc, weth, pairVersions[1]));
        router.swapExactAVAXForTokens{value: amountIn2}(0, pairVersions, tokenListAvaxIn, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, usdc, weth, pairVersions[1]));
        router.swapAVAXForExactTokens{value: amountIn2}(0, pairVersions, tokenListAvaxIn, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, usdc, weth, pairVersions[1]));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn2}(
            0, pairVersions, tokenListAvaxIn, DEV, block.timestamp
        );
    }

    receive() external payable {}
}
