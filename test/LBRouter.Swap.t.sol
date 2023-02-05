// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "test/helpers/TestHelper.sol";

/**
 * This file only test single hop swaps using V2.1 pairs
 * Test scenarios:
 * 1. swapExactTokensForTokens
 * 1. swapExactTokensForAVAX
 * 2. swapExactAVAXForTokens
 * 3. swapTokensForExactTokens
 * 4. swapTokensForExactAVAX
 * 5. swapAVAXForExactTokens
 * 6. swapExactTokensForTokensSupportingFeeOnTransferTokens
 * 7. swapExactTokensForAVAXSupportingFeeOnTransferTokens
 * 8. swapExactAVAXForTokensSupportingFeeOnTransferTokens
 */
contract LiquidityBinRouterSwapTest is TestHelper {
    function setUp() public override {
        super.setUp();

        factory.setOpenPreset(DEFAULT_BIN_STEP, true);

        // Create necessary pairs
        router.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(wavax, usdc, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(taxToken, wavax, ID_ONE, DEFAULT_BIN_STEP);

        uint256 startingBalance = type(uint112).max;
        deal(address(usdc), address(this), startingBalance);
        deal(address(usdt), address(this), startingBalance);
        deal(address(taxToken), address(this), startingBalance);

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdt, usdc, 100e18, ID_ONE, 15, 0);
        router.addLiquidity(liquidityParameters);

        liquidityParameters = getLiquidityParameters(wavax, usdc, 100e18, ID_ONE, 15, 0);
        router.addLiquidityAVAX{value: liquidityParameters.amountX}(liquidityParameters);

        liquidityParameters = getLiquidityParameters(taxToken, wavax, 200e18, ID_ONE, 15, 0);
        router.addLiquidityAVAX{value: liquidityParameters.amountY}(liquidityParameters);
    }

    function test_SwapExactTokensForTokens() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, true);

        ILBRouter.Path memory path = _buildPath(usdt, usdc);

        uint256 balanceBefore = usdc.balanceOf(address(this));

        (uint256 amountOut) =
            router.swapExactTokensForTokens(amountIn, amountOutExpected, path, address(this), block.timestamp + 1);

        assertEq(amountOut, amountOutExpected, "amountOut");
        assertEq(usdc.balanceOf(address(this)), balanceBefore + amountOut, "balance");

        // Reverts if amountOut is less than amountOutMin
        (, amountOutExpected,) = router.getSwapOut(pair, amountIn, true);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__InsufficientAmountOut.selector, amountOutExpected + 1, amountOutExpected
            )
        );
        router.swapExactTokensForTokens(amountIn, amountOutExpected + 1, path, address(this), block.timestamp + 1);

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapExactTokensForTokens(amountIn, amountOutExpected, path, address(this), block.timestamp - 1);

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapExactTokensForTokens(amountIn, amountOutExpected, path, address(this), block.timestamp + 1);
    }

    function test_SwapExactTokensForAVAX() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(wavax, usdc, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, false);

        ILBRouter.Path memory path = _buildPath(usdc, wavax);

        uint256 balanceBefore = address(this).balance;

        (uint256 amountOut) = router.swapExactTokensForAVAX(
            amountIn, amountOutExpected, path, payable(address(this)), block.timestamp + 1
        );

        assertEq(amountOut, amountOutExpected, "amountOut");
        assertEq(address(this).balance, balanceBefore + amountOut, "balance");

        // Reverts if amountOut is less than amountOutMin
        (, amountOutExpected,) = router.getSwapOut(pair, amountIn, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__InsufficientAmountOut.selector, amountOutExpected + 1, amountOutExpected
            )
        );
        router.swapExactTokensForAVAX(
            amountIn, amountOutExpected + 1, path, payable(address(this)), block.timestamp + 1
        );

        // Revert if token out isn't WAVAX
        path.tokenPath[1] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapExactTokensForAVAX(
            amountIn, amountOutExpected + 1, path, payable(address(this)), block.timestamp + 1
        );

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapExactTokensForAVAX(amountIn, amountOutExpected, path, payable(address(this)), block.timestamp - 1);

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapExactTokensForAVAX(amountIn, amountOutExpected, path, payable(address(this)), block.timestamp + 1);
    }

    function test_SwapExactAVAXForTokens() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(wavax, usdc, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, true);

        ILBRouter.Path memory path = _buildPath(wavax, usdc);

        uint256 balanceBefore = usdc.balanceOf(address(this));

        (uint256 amountOut) =
            router.swapExactAVAXForTokens{value: amountIn}(amountOutExpected, path, address(this), block.timestamp + 1);

        assertEq(amountOut, amountOutExpected, "amountOut");
        assertEq(usdc.balanceOf(address(this)), balanceBefore + amountOut, "balance");

        (, amountOutExpected,) = router.getSwapOut(pair, amountIn, true);

        // Reverts if amountOut is less than amountOutMin
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__InsufficientAmountOut.selector, amountOutExpected + 1, amountOutExpected
            )
        );
        router.swapExactAVAXForTokens{value: amountIn}(amountOutExpected + 1, path, address(this), block.timestamp + 1);

        // Revert if token in isn't WAVAX
        path.tokenPath[0] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapExactAVAXForTokens{value: amountIn}(amountOutExpected, path, address(this), block.timestamp + 1);

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapExactAVAXForTokens{value: amountIn}(amountOutExpected, path, address(this), block.timestamp - 1);

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapExactAVAXForTokens{value: amountIn}(amountOutExpected, path, address(this), block.timestamp + 1);
    }

    function test_SwapTokensForExactTokens() public {
        uint128 amountOut = 20e18;

        ILBPair pair = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).LBPair;
        (uint128 amountInExpected,,) = router.getSwapIn(pair, amountOut, true);

        ILBRouter.Path memory path = _buildPath(usdt, usdc);

        uint256 balanceBefore = usdt.balanceOf(address(this));

        (uint256[] memory amountsIn) =
            router.swapTokensForExactTokens(amountOut, amountInExpected, path, address(this), block.timestamp + 1);

        assertEq(amountsIn[0], amountInExpected, "amountOut");
        assertEq(usdt.balanceOf(address(this)), balanceBefore - amountsIn[0], "balance");

        (amountInExpected,,) = router.getSwapIn(pair, amountOut, true);

        // Revert if amountIn is too high
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__MaxAmountInExceeded.selector, amountInExpected - 1, amountInExpected
            )
        );
        router.swapTokensForExactTokens(amountOut, amountInExpected - 1, path, address(this), block.timestamp + 1);

        // TODO - try to hit LBRouter__InsufficientAmountOut

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapTokensForExactTokens(amountOut, amountInExpected, path, address(this), block.timestamp - 1);

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapTokensForExactTokens(amountOut, amountInExpected, path, address(this), block.timestamp + 1);
    }

    function test_SwapTokensForExactAVAX() public {
        uint128 amountOut = 20e18;

        ILBPair pair = factory.getLBPairInformation(wavax, usdc, DEFAULT_BIN_STEP).LBPair;
        (uint128 amountInExpected,,) = router.getSwapIn(pair, amountOut, false);

        ILBRouter.Path memory path = _buildPath(usdc, wavax);

        uint256 balanceBefore = usdc.balanceOf(address(this));

        (uint256[] memory amountsIn) = router.swapTokensForExactAVAX(
            amountOut, amountInExpected, path, payable(address(this)), block.timestamp + 1
        );

        assertEq(amountsIn[0], amountInExpected, "amountOut");
        assertEq(usdc.balanceOf(address(this)), balanceBefore - amountsIn[0], "balance");

        (amountInExpected,,) = router.getSwapIn(pair, amountOut, false);

        // Revert if amountIn is too high
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__MaxAmountInExceeded.selector, amountInExpected - 1, amountInExpected
            )
        );
        router.swapTokensForExactTokens(amountOut, amountInExpected - 1, path, address(this), block.timestamp + 1);

        // TODO - try to hit LBRouter__InsufficientAmountOut

        // Revert if token out isn't WAVAX
        path.tokenPath[1] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapTokensForExactAVAX(amountOut, amountInExpected, path, payable(address(this)), block.timestamp + 1);

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapTokensForExactTokens(amountOut, amountInExpected, path, address(this), block.timestamp - 1);

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapTokensForExactTokens(amountOut, amountInExpected, path, address(this), block.timestamp + 1);
    }

    function test_SwapAVAXForExactTokens() public {
        uint128 amountOut = 20e18;

        ILBPair pair = factory.getLBPairInformation(wavax, usdc, DEFAULT_BIN_STEP).LBPair;
        (uint128 amountInExpected,,) = router.getSwapIn(pair, amountOut, true);

        ILBRouter.Path memory path = _buildPath(wavax, usdc);

        uint256 balanceBefore = address(this).balance;

        // Sending too much AVAX to test the refund
        (uint256[] memory amountsIn) = router.swapAVAXForExactTokens{value: amountInExpected + 100}(
            amountOut, path, address(this), block.timestamp + 1
        );

        assertEq(amountsIn[0], amountInExpected, "amountOut");
        assertEq(address(this).balance, balanceBefore - amountsIn[0], "balance");

        (amountInExpected,,) = router.getSwapIn(pair, amountOut, true);

        // Revert if not enough AVAX has been sent
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__MaxAmountInExceeded.selector, amountInExpected / 2, amountInExpected
            )
        );
        router.swapAVAXForExactTokens{value: amountInExpected / 2}(amountOut, path, address(this), block.timestamp + 1);

        // TODO - try to hit LBRouter__InsufficientAmountOut

        // Revert if token in isn't WAVAX
        path.tokenPath[0] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapAVAXForExactTokens{value: amountInExpected}(amountOut, path, address(this), block.timestamp + 1);

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapAVAXForExactTokens{value: amountInExpected}(amountOut, path, address(this), block.timestamp - 1);

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapAVAXForExactTokens{value: amountInExpected}(amountOut, path, address(this), block.timestamp + 1);
    }

    function test_swapExactTokensForAVAXSupportingFeeOnTransferTokens() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(taxToken, wavax, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, true);

        ILBRouter.Path memory path = _buildPath(taxToken, wavax);

        // Reverts if amountOut is less than amountOutMin
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__InsufficientAmountOut.selector, amountOutExpected, amountOutExpected / 2
            )
        );
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, amountOutExpected, path, payable(address(this)), block.timestamp + 1
        );

        uint256 balanceBefore = address(this).balance;

        // Token tax is 50%
        (uint256 amountOut) = router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, amountOutExpected / 2, path, payable(address(this)), block.timestamp + 1
        );

        assertEq(amountOut, amountOutExpected / 2, "amountOut");
        assertEq(address(this).balance, balanceBefore + amountOut, "balance");

        // Revert if token out isn't WAVAX
        path.tokenPath[1] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, amountOutExpected / 2, path, payable(address(this)), block.timestamp + 1
        );

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapExactTokensForAVAX(
            amountIn, amountOutExpected / 2, path, payable(address(this)), block.timestamp - 1
        );

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapExactTokensForAVAX(
            amountIn, amountOutExpected / 2, path, payable(address(this)), block.timestamp + 1
        );
    }

    function test_SwapExactTokensForAVAXSupportingFeeOnTransferTokens() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(taxToken, wavax, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, true);

        ILBRouter.Path memory path = _buildPath(taxToken, wavax);

        // Reverts if amountOut is less than amountOutMin
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__InsufficientAmountOut.selector, amountOutExpected, amountOutExpected / 2
            )
        );
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, amountOutExpected, path, payable(address(this)), block.timestamp + 1
        );

        uint256 balanceBefore = address(this).balance;

        (uint256 amountOut) = router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, amountOutExpected / 2, path, payable(address(this)), block.timestamp + 1
        );

        assertEq(amountOut, amountOutExpected / 2, "amountOut");
        assertEq(address(this).balance, balanceBefore + amountOut, "balance");

        // Revert if token out isn't WAVAX
        path.tokenPath[1] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, amountOutExpected + 1, path, payable(address(this)), block.timestamp + 1
        );

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, amountOutExpected, path, payable(address(this)), block.timestamp - 1
        );

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn, amountOutExpected, path, payable(address(this)), block.timestamp + 1
        );
    }

    function test_SwapExactAVAXForTokensSupportingFeeOnTransferTokens() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(taxToken, wavax, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, false);

        ILBRouter.Path memory path = _buildPath(wavax, taxToken);

        // Reverts if amountOut is less than amountOutMin
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__InsufficientAmountOut.selector, amountOutExpected, amountOutExpected / 2 + 1
            )
        );
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutExpected, path, address(this), block.timestamp + 1
        );

        uint256 balanceBefore = taxToken.balanceOf(address(this));

        (uint256 amountOut) = router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutExpected / 2, path, address(this), block.timestamp + 1
        );

        assertEq(amountOut, amountOutExpected / 2 + 1, "amountOut");
        assertEq(taxToken.balanceOf(address(this)), balanceBefore + amountOut, "balance");

        // Revert if token in isn't WAVAX
        path.tokenPath[0] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutExpected, path, address(this), block.timestamp + 1
        );

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutExpected, path, address(this), block.timestamp - 1
        );

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutExpected, path, address(this), block.timestamp + 1
        );
    }

    function _buildPath(IERC20 tokenIn, IERC20 tokenOut) private pure returns (ILBRouter.Path memory path) {
        path.pairBinSteps = new uint256[](1);
        path.pairBinSteps[0] = DEFAULT_BIN_STEP;

        path.versions = new ILBRouter.Version[](1);
        path.versions[0] = ILBRouter.Version.V2_1;

        path.tokenPath = new IERC20[](2);
        path.tokenPath[0] = tokenIn;
        path.tokenPath[1] = tokenOut;
    }

    receive() external payable {}
}
