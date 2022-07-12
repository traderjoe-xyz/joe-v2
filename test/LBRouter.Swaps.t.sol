// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinRouterTest is TestHelper {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);
        wavax = new WAVAX();

        factory = new LBFactory(DEV);
        new LBFactoryHelper(factory);

        router = new LBRouter(factory, IJoeFactory(JOE_V1_FACTORY_ADDRESS), IWAVAX(address(wavax)));

        pair = createLBPairDefaultFees(token6D, token18D);
        pairWavax = createLBPairDefaultFees(token6D, wavax);

        addLiquidityFromRouter(100e18, ID_ONE, 9, 2, 0);

        (
            int256[] memory _deltaIds,
            uint256[] memory _distributionToken,
            uint256[] memory _distributionAVAX,
            uint256 amountTokenIn
        ) = spreadLiquidityForRouter(100e18, ID_ONE, 9, 2);

        token6D.mint(DEV, amountTokenIn);
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
    }

    function testSwapExactTokensForTokensSinglePair() public {
        uint256 amountIn = 1e18;

        token6D.mint(DEV, amountIn);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        uint256[] memory pairVersions = new uint256[](2);
        pairVersions[0] = 2;
        pairVersions[1] = 2;

        uint256 amountOut = router.getSwapOut(pair, amountIn, true);

        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(token18D.balanceOf(DEV), amountOut);
    }

    function testswapExactTokensForAvaxSinglePair() public {
        uint256 amountIn = 1e18;

        token6D.mint(DEV, amountIn);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = wavax;
        uint256[] memory pairVersions = new uint256[](2);
        pairVersions[0] = 2;
        pairVersions[1] = 2;

        uint256 amountOut = router.getSwapOut(pair, amountIn, true);

        uint256 devBalanceBefore = address(DEV).balance;
        router.swapExactTokensForAVAX(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(DEV.balance - devBalanceBefore, amountOut);
    }

    function testswapExactAVAXForTokensSinglePair() public {
        uint256 amountIn = 1e18;

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = wavax;
        tokenList[1] = token6D;
        uint256[] memory pairVersions = new uint256[](2);
        pairVersions[0] = 2;
        pairVersions[1] = 2;

        uint256 amountOut = router.getSwapOut(pairWavax, amountIn, false);

        router.swapExactAVAXForTokens{value: amountIn}(0, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(token6D.balanceOf(DEV), amountOut);
    }

    function testswapTokensForExactTokensSinglePair() public {
        uint256 amountOut = 1e18;

        uint256 amountIn = router.getSwapIn(pair, amountOut, true);
        token6D.mint(DEV, amountIn);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = token18D;
        uint256[] memory pairVersions = new uint256[](2);
        pairVersions[0] = 2;
        pairVersions[1] = 2;
        router.swapTokensForExactTokens(amountOut, amountIn, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(token18D.balanceOf(DEV), amountOut);
    }

    function testSwapTokensForExactAVAXSinglePair() public {
        uint256 amountOut = 1e18;

        uint256 amountIn = router.getSwapIn(pairWavax, amountOut, true);
        token6D.mint(DEV, amountIn);
        token6D.approve(address(router), amountIn);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = token6D;
        tokenList[1] = wavax;
        uint256[] memory pairVersions = new uint256[](2);
        pairVersions[0] = 2;
        pairVersions[1] = 2;

        uint256 devBalanceBefore = address(DEV).balance;
        router.swapTokensForExactAVAX(amountOut, amountIn, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(DEV.balance - devBalanceBefore, amountOut);
    }

    function testSwapAVAXForExactTokensSinglePair() public {
        uint256 amountOut = 1e18;

        uint256 amountIn = router.getSwapIn(pairWavax, amountOut, false);

        IERC20[] memory tokenList = new IERC20[](2);
        tokenList[0] = wavax;
        tokenList[1] = token6D;
        uint256[] memory pairVersions = new uint256[](2);
        pairVersions[0] = 2;
        pairVersions[1] = 2;

        router.swapAVAXForExactTokens{value: amountIn}(amountOut, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(token6D.balanceOf(DEV), amountOut);
    }

    receive() external payable {}
}
