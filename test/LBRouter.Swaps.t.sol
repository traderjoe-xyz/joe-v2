// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinRouterTest is TestHelper {
    LBPair internal pair0;
    LBPair internal pair1;
    LBPair internal pair2;
    LBPair internal pair3;
    LBPair internal taxTokenPair;

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token10D = new ERC20MockDecimals(10);
        token12D = new ERC20MockDecimals(12);
        token18D = new ERC20MockDecimals(18);
        token24D = new ERC20MockDecimals(24);

        taxToken = new ERC20WithTransferTax();

        if (block.number < 1000) {
            wavax = new WAVAX();
        } else {
            wavax = WAVAX(WAVAX_AVALANCHE_ADDRESS);
            usdc = ERC20MockDecimals(USDC_AVALANCHE_ADDRESS);
        }

        factory = new LBFactory(DEV);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
        new LBFactoryHelper(factory);

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

    function testSwapExactTokensForTokensSinglePair() public {
        uint256 amountIn = 1e18;

        token6D.mint(DEV, amountIn);

        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        uint256 amountOut = router.getSwapOut(pair, amountIn, true);

        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(token18D.balanceOf(DEV), amountOut, 10);
    }

    function testswapExactTokensForAvaxSinglePair() public {
        uint256 amountIn = 1e18;

        token6D.mint(ALICE, amountIn);

        vm.startPrank(ALICE);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = wavax;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        uint256 amountOut = router.getSwapOut(pair, amountIn, true);

        uint256 devBalanceBefore = ALICE.balance;
        router.swapExactTokensForAVAX(amountIn, 0, pairVersions, tokenList, ALICE, block.timestamp);
        vm.stopPrank();

        assertEq(ALICE.balance - devBalanceBefore, amountOut);
    }

    function testswapExactAVAXForTokensSinglePair() public {
        uint256 amountIn = 1e18;

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = wavax;
        tokenList[1] = token6D;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        uint256 amountOut = router.getSwapOut(pairWavax, amountIn, false);

        vm.deal(DEV, amountIn);
        router.swapExactAVAXForTokens{value: amountIn}(0, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(token6D.balanceOf(DEV), amountOut, 10);
    }

    function testswapTokensForExactTokensSinglePair() public {
        uint256 amountOut = 1e18;

        uint256 amountIn = router.getSwapIn(pair, amountOut, true);
        token6D.mint(DEV, amountIn);

        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        router.swapTokensForExactTokens(amountOut, amountIn, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(token18D.balanceOf(DEV), amountOut, 10);
    }

    function testSwapTokensForExactAVAXSinglePair() public {
        uint256 amountOut = 1e18;

        uint256 amountIn = router.getSwapIn(pairWavax, amountOut, true);
        token6D.mint(ALICE, amountIn);

        vm.startPrank(ALICE);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = wavax;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        uint256 devBalanceBefore = ALICE.balance;
        router.swapTokensForExactAVAX(amountOut, amountIn, pairVersions, tokenList, ALICE, block.timestamp);
        vm.stopPrank();

        assertEq(ALICE.balance - devBalanceBefore, amountOut);
    }

    function testSwapAVAXForExactTokensSinglePair() public {
        uint256 amountOut = 1e18;

        uint256 amountIn = router.getSwapIn(pairWavax, amountOut, false);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = wavax;
        tokenList[1] = token6D;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        vm.deal(DEV, amountIn);
        router.swapAVAXForExactTokens{value: amountIn}(amountOut, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(token6D.balanceOf(DEV), amountOut, 10);
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

        uint256 amountOut = router.getSwapOut(taxTokenPair, amountIn, true);

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        // 50% tax to take into account
        assertApproxEqAbs(wavax.balanceOf(DEV), amountOut / 2, 10);

        // Swap back in the other direction
        amountIn = wavax.balanceOf(DEV);
        wavax.approve(address(router), amountIn);
        tokenList[0] = wavax;
        tokenList[1] = taxToken;

        amountOut = router.getSwapOut(taxTokenPair, amountIn, true);

        uint256 balanceBefore = taxToken.balanceOf(DEV);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        assertApproxEqAbs(taxToken.balanceOf(DEV) - balanceBefore, amountOut / 2, 10);
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

        uint256 amountOut = router.getSwapOut(taxTokenPair, amountIn, true);

        uint256 devBalanceBefore = ALICE.balance;
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn,
            0,
            pairVersions,
            tokenList,
            ALICE,
            block.timestamp
        );
        vm.stopPrank();

        assertGe(ALICE.balance - devBalanceBefore, amountOut / 2);
    }

    function testSwapExactAVAXForTokensSupportingFeeOnTransferTokens() public {
        uint256 amountIn = 1e18;

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = wavax;
        tokenList[1] = taxToken;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = DEFAULT_BIN_STEP;

        uint256 amountOut = router.getSwapOut(taxTokenPair, amountIn, true);

        vm.deal(DEV, amountIn);
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            0,
            pairVersions,
            tokenList,
            DEV,
            block.timestamp
        );

        assertApproxEqAbs(taxToken.balanceOf(DEV), amountOut / 2, 10);
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

        router.swapTokensForExactTokens(amountOut, 100e18, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(token24D.balanceOf(DEV), amountOut);
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
        pairVersions[1] = 1;

        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(usdc.balanceOf(DEV), 0);

        tokenList[0] = usdc;
        tokenList[1] = wavax;
        tokenList[2] = token6D;

        pairVersions[0] = 1;
        pairVersions[1] = 2;

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
        pairVersions[1] = 1;

        router.swapTokensForExactTokens(amountOut, 100e18, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(usdc.balanceOf(DEV), amountOut);

        tokenList[0] = usdc;
        tokenList[1] = wavax;
        tokenList[2] = token6D;

        pairVersions[0] = 1;
        pairVersions[1] = 2;

        uint256 balanceBefore = token6D.balanceOf(DEV);

        usdc.approve(address(router), usdc.balanceOf(DEV));
        router.swapTokensForExactTokens(amountOut, usdc.balanceOf(DEV), pairVersions, tokenList, DEV, block.timestamp);

        assertEq(token6D.balanceOf(DEV) - balanceBefore, amountOut);

        vm.stopPrank();
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

    receive() external payable {}
}
