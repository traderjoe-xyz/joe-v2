// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinRouterTest is TestHelper {
    LBPair internal pair0;
    LBPair internal pair1;
    LBPair internal pair2;
    LBPair internal pair3;

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token10D = new ERC20MockDecimals(10);
        token12D = new ERC20MockDecimals(12);
        token18D = new ERC20MockDecimals(18);
        token24D = new ERC20MockDecimals(24);

        if (block.number < 1000) {
            wavax = new WAVAX();
        } else {
            wavax = WAVAX(WAVAX_AVALANCHE_ADDRESS);
            usdc = ERC20MockDecimals(USDC_AVALANCHE_ADDRESS);
        }

        factory = new LBFactory(DEV);
        new LBFactoryHelper(factory);

        router = new LBRouter(factory, IJoeFactory(JOE_V1_FACTORY_ADDRESS), IWAVAX(address(wavax)));

        pair = createLBPairDefaultFees(token6D, token18D);
        addLiquidityFromRouter(100e18, ID_ONE, 9, 2, 0);

        pair0 = createLBPairDefaultFees(token6D, token10D);
        addLiquidityFromRouterForPair(token6D, token10D, 100e18, ID_ONE, 9, 2, 0);
        pair1 = createLBPairDefaultFees(token10D, token12D);
        addLiquidityFromRouterForPair(token10D, token12D, 100e18, ID_ONE, 9, 2, 0);
        pair2 = createLBPairDefaultFees(token12D, token18D);
        addLiquidityFromRouterForPair(token12D, token18D, 100e18, ID_ONE, 9, 2, 0);
        pair3 = createLBPairDefaultFees(token18D, token24D);
        addLiquidityFromRouterForPair(token18D, token24D, 100e18, ID_ONE, 9, 2, 0);

        pairWavax = createLBPairDefaultFees(token6D, wavax);
        (
            int256[] memory _deltaIds,
            uint256[] memory _distributionToken,
            uint256[] memory _distributionAVAX,
            uint256 amountTokenIn
        ) = spreadLiquidityForRouter(100e18, ID_ONE, 9, 2);

        token6D.mint(DEV, amountTokenIn);

        vm.deal(DEV, 100 ether);
        vm.startPrank(DEV);
        token6D.approve(address(router), amountTokenIn);

        router.addLiquidityAVAX{value: 100e18}(
            token6D,
            amountTokenIn,
            0,
            ID_ONE,
            0,
            _deltaIds,
            _distributionToken,
            _distributionAVAX,
            DEV,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testSwapExactTokensForTokensSinglePair() public {
        uint256 amountIn = 1e18;

        token6D.mint(DEV, amountIn);

        vm.startPrank(DEV);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = 2;

        uint256 amountOut = router.getSwapOut(pair, amountIn, true);

        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);
        vm.stopPrank();

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
        pairVersions[0] = 2;

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
        pairVersions[0] = 2;

        uint256 amountOut = router.getSwapOut(pairWavax, amountIn, false);

        vm.deal(DEV, amountIn);
        router.swapExactAVAXForTokens{value: amountIn}(0, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(token6D.balanceOf(DEV), amountOut, 10);
    }

    function testswapTokensForExactTokensSinglePair() public {
        uint256 amountOut = 1e18;

        uint256 amountIn = router.getSwapIn(pair, amountOut, true);
        token6D.mint(DEV, amountIn);

        vm.startPrank(DEV);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        uint256[] memory pairVersions = new uint256[](1);
        pairVersions[0] = 2;

        router.swapTokensForExactTokens(amountOut, amountIn, pairVersions, tokenList, DEV, block.timestamp);
        vm.stopPrank();

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
        pairVersions[0] = 2;

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
        pairVersions[0] = 2;

        vm.deal(DEV, amountIn);
        router.swapAVAXForExactTokens{value: amountIn}(amountOut, pairVersions, tokenList, DEV, block.timestamp);

        assertApproxEqAbs(token6D.balanceOf(DEV), amountOut, 10);
    }

    function testSwapExactTokensForTokensMultiplePairs() public {
        uint256 amountIn = 1e18;

        token6D.mint(DEV, amountIn);
        vm.prank(DEV);
        token6D.approve(address(router), amountIn);

        (IERC20[] memory tokenList, uint256[] memory pairVersions) = _buildComplexSwapRoute();

        vm.prank(DEV);
        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(token24D.balanceOf(DEV), 0);
    }

    function testSwapTokensForExactTokensMultiplePairs() public {
        uint256 amountOut = 1e18;

        token6D.mint(DEV, 100e18);
        vm.prank(DEV);
        token6D.approve(address(router), 100e18);

        (IERC20[] memory tokenList, uint256[] memory pairVersions) = _buildComplexSwapRoute();

        vm.prank(DEV);
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
        vm.prank(DEV);
        token6D.approve(address(router), amountIn);

        (IERC20[] memory tokenList, uint256[] memory pairVersions) = _buildComplexSwapRoute();
        tokenList = new IERC20[](3);
        tokenList[0] = token6D;
        tokenList[1] = wavax;
        tokenList[2] = usdc;

        pairVersions = new uint256[](2);
        pairVersions[0] = 2;
        pairVersions[1] = 1;

        vm.prank(DEV);
        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(usdc.balanceOf(DEV), 0);
    }

    function testSwapTokensForExactTokensMultiplePairsWithV1() public {
        if (block.number < 1000) {
            console.log("fork mainnet for V1 testing support");
            return;
        }

        uint256 amountOut = 1e6;

        token6D.mint(DEV, 100e18);
        vm.prank(DEV);
        token6D.approve(address(router), 100e18);

        (IERC20[] memory tokenList, uint256[] memory pairVersions) = _buildComplexSwapRoute();
        tokenList = new IERC20[](3);
        tokenList[0] = token6D;
        tokenList[1] = wavax;
        tokenList[2] = usdc;

        pairVersions = new uint256[](2);
        pairVersions[0] = 2;
        pairVersions[1] = 1;

        vm.prank(DEV);
        router.swapTokensForExactTokens(amountOut, 100e18, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(usdc.balanceOf(DEV), amountOut);
    }

    function _buildComplexSwapRoute() private view returns (IERC20[] memory tokenList, uint256[] memory pairVersions) {
        tokenList = new IERC20[](5);
        tokenList[0] = token6D;
        tokenList[1] = token10D;
        tokenList[2] = token12D;
        tokenList[3] = token18D;
        tokenList[4] = token24D;

        pairVersions = new uint256[](4);
        pairVersions[0] = 2;
        pairVersions[1] = 2;
        pairVersions[2] = 2;
        pairVersions[3] = 2;
    }

    receive() external payable {}
}
