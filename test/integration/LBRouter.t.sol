// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "../helpers/TestHelper.sol";

/**
 * Pairs created:
 * USDT/USDC V1
 * NATIVE/USDC V2
 * WETH/NATIVE V2.1
 * TaxToken/NATIVE V2.1
 */
contract LiquidityBinRouterForkTest is TestHelper {
    using Utils for ILBRouter.LiquidityParameters;

    function setUp() public override {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 46012280);
        super.setUp();

        uint256 liquidityAmount = 1e24;

        // Get tokens to add liquidity
        deal(address(usdc), address(this), 10 * liquidityAmount);
        deal(address(usdt), address(this), 10 * liquidityAmount);
        deal(address(weth), address(this), 10 * liquidityAmount);
        deal(address(taxToken), address(this), 10 * liquidityAmount);

        // Add liquidity to V1
        routerV1.addLiquidity(
            address(usdt),
            address(usdc),
            liquidityAmount, // 1 USDT = 1 USDC
            liquidityAmount,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        vm.startPrank(AvalancheAddresses.V2_FACTORY_OWNER);
        legacyFactoryV2.addQuoteAsset(usdc);
        legacyFactoryV2.createLBPair(wnative, usdc, ID_ONE, DEFAULT_BIN_STEP); // 1 NATIVE = 1 USDC
        vm.stopPrank();

        factory.createLBPair(weth, wnative, ID_ONE, DEFAULT_BIN_STEP); // 1 WETH = 1 NATIVE
        factory.createLBPair(taxToken, wnative, ID_ONE, DEFAULT_BIN_STEP); // 1 TaxToken = 1 NATIVE

        // Add liquidity to V2
        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(wnative, usdc, liquidityAmount, ID_ONE, 7, 0);
        legacyRouterV2.addLiquidityAVAX{value: liquidityParameters.amountX}(liquidityParameters.toLegacy());

        liquidityParameters = getLiquidityParameters(weth, wnative, liquidityAmount, ID_ONE, 7, 0);
        router.addLiquidityNATIVE{value: liquidityParameters.amountY}(liquidityParameters);

        liquidityParameters = getLiquidityParameters(taxToken, wnative, liquidityAmount, ID_ONE, 7, 0);
        router.addLiquidityNATIVE{value: liquidityParameters.amountY}(liquidityParameters);
    }

    function test_SwapExactTokensForTokens() public {
        uint256 amountIn = 1e18;

        ILBRouter.Path memory path = _buildPath(usdt, weth);
        LBQuoter.Quote memory quote =
            quoter.findBestPathFromAmountIn(_convertToAddresses(path.tokenPath), uint128(amountIn));

        uint256 amountOut = router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);

        assertEq(amountOut, quote.amounts[3], "test_SwapExactTokensForTokens::1");

        // Reverse path
        path = _buildPath(weth, usdt);
        quote = quoter.findBestPathFromAmountIn(_convertToAddresses(path.tokenPath), uint128(amountIn));

        amountOut = router.swapExactTokensForTokens(amountIn, 0, path, address(this), block.timestamp + 1);

        assertEq(amountOut, quote.amounts[3], "test_SwapExactTokensForTokens::2");
    }

    function test_SwapTokensForExactTokens() public {
        uint256 amountOut = 1e18;

        ILBRouter.Path memory path = _buildPath(weth, usdt);
        LBQuoter.Quote memory quote =
            quoter.findBestPathFromAmountOut(_convertToAddresses(path.tokenPath), uint128(amountOut));

        uint256[] memory amountsIn =
            router.swapTokensForExactTokens(amountOut, quote.amounts[0], path, address(this), block.timestamp + 1);

        assertEq(amountsIn[0], quote.amounts[0], "test_SwapTokensForExactTokens::1");

        // Reverse path
        path = _buildPath(usdt, weth);
        quote = quoter.findBestPathFromAmountOut(_convertToAddresses(path.tokenPath), uint128(amountOut));

        amountsIn =
            router.swapTokensForExactTokens(amountOut, quote.amounts[0], path, address(this), block.timestamp + 1);

        assertEq(amountsIn[0], quote.amounts[0], "test_SwapTokensForExactTokens::2");
    }

    function test_SwapExactTokensForTokensSupportingFeeOnTransferTokens() public {
        uint256 amountIn = 1e18;

        ILBRouter.Path memory path = _buildPath(taxToken, usdt);
        LBQuoter.Quote memory quote =
            quoter.findBestPathFromAmountIn(_convertToAddresses(path.tokenPath), uint128(amountIn));

        uint256 amountOut = router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 0, path, address(this), block.timestamp + 1
        );

        assertApproxEqRel(
            amountOut, quote.amounts[3] / 2, 1e12, "test_SwapExactTokensForTokensSupportingFeeOnTransferTokens::1"
        );

        // Reverse path
        path = _buildPath(usdt, taxToken);
        quote = quoter.findBestPathFromAmountIn(_convertToAddresses(path.tokenPath), uint128(amountIn));

        amountOut = router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 0, path, address(this), block.timestamp + 1
        );

        assertApproxEqRel(
            amountOut, quote.amounts[3] / 2, 1e12, "test_SwapExactTokensForTokensSupportingFeeOnTransferTokens::2"
        );
    }

    function _buildPath(IERC20 tokenIn, IERC20 tokenOut) private view returns (ILBRouter.Path memory path) {
        path.pairBinSteps = new uint256[](3);
        path.versions = new ILBRouter.Version[](3);
        path.tokenPath = new IERC20[](4);

        if (tokenIn == usdt) {
            path.tokenPath[0] = tokenIn;
            path.tokenPath[1] = usdc;
            path.tokenPath[2] = wnative;
            path.tokenPath[3] = tokenOut;

            path.pairBinSteps[0] = 0;
            path.pairBinSteps[1] = DEFAULT_BIN_STEP;
            path.pairBinSteps[2] = DEFAULT_BIN_STEP;

            path.versions[0] = ILBRouter.Version.V1;
            path.versions[1] = ILBRouter.Version.V2;
            path.versions[2] = ILBRouter.Version.V2_2;
        } else {
            path.tokenPath[0] = tokenIn;
            path.tokenPath[1] = wnative;
            path.tokenPath[2] = usdc;
            path.tokenPath[3] = tokenOut;

            path.pairBinSteps[0] = DEFAULT_BIN_STEP;
            path.pairBinSteps[1] = DEFAULT_BIN_STEP;
            path.pairBinSteps[2] = 0;

            path.versions[0] = ILBRouter.Version.V2_2;
            path.versions[1] = ILBRouter.Version.V2;
            path.versions[2] = ILBRouter.Version.V1;
        }
    }

    function _convertToAddresses(IERC20[] memory tokens) private pure returns (address[] memory addresses) {
        addresses = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            addresses[i] = address(tokens[i]);
        }
    }
}
