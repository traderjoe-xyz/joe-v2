// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "test/helpers/TestHelper.sol";

/**
 * This file only test single hop swaps using V2.1 pairs
 * Test scenarios:
 * 1. swapExactTokensForTokens
 * 2. swapExactTokensForNATIVE
 * 3. swapExactNATIVEForTokens
 * 4. swapTokensForExactTokens
 * 5. swapTokensForExactNATIVE
 * 6. swapNATIVEForExactTokens
 * 7. swapExactTokensForTokensSupportingFeeOnTransferTokens
 * 8. swapExactTokensForNATIVESupportingFeeOnTransferTokens
 * 9. swapExactNATIVEForTokensSupportingFeeOnTransferTokens
 */
contract LiquidityBinRouterSwapTest is TestHelper {
    function setUp() public override {
        super.setUp();

        factory.setPresetOpenState(DEFAULT_BIN_STEP, true);

        // Create necessary pairs
        router.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(wnative, usdc, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(taxToken, wnative, ID_ONE, DEFAULT_BIN_STEP);

        uint256 startingBalance = type(uint112).max;
        deal(address(usdc), address(this), startingBalance);
        deal(address(usdt), address(this), startingBalance);
        deal(address(taxToken), address(this), startingBalance);

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdt, usdc, 100e18, ID_ONE, 15, 0);
        router.addLiquidity(liquidityParameters);

        liquidityParameters = getLiquidityParameters(wnative, usdc, 100e18, ID_ONE, 15, 0);
        router.addLiquidityNATIVE{value: liquidityParameters.amountX}(liquidityParameters);

        liquidityParameters = getLiquidityParameters(taxToken, wnative, 200e18, ID_ONE, 15, 0);
        router.addLiquidityNATIVE{value: liquidityParameters.amountY}(liquidityParameters);
    }

    function test_GetIdFromPrice() public view {
        ILBPair pair = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).LBPair;

        router.getIdFromPrice(pair, 924521306405372907020063908180274956666);

        router.getPriceFromId(pair, 1_000 + ID_ONE);
    }

    function test_SwapExactTokensForTokens() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, true);

        ILBRouter.Path memory path = _buildPath(usdt, usdc);

        uint256 balanceBefore = usdc.balanceOf(address(this));

        (uint256 amountOut) =
            router.swapExactTokensForTokens(amountIn, amountOutExpected, path, address(this), block.timestamp + 1);

        assertEq(amountOut, amountOutExpected, "test_SwapExactTokensForTokens::1");
        assertEq(usdc.balanceOf(address(this)), balanceBefore + amountOut, "test_SwapExactTokensForTokens::2");

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

        // Revert if the pair doesn't exist
        path.tokenPath = new IERC20[](2);
        path.tokenPath[0] = usdt;
        path.tokenPath[1] = taxToken;
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__PairNotCreated.selector, usdt, taxToken, DEFAULT_BIN_STEP)
        );
        router.swapExactTokensForTokens(amountIn, amountOutExpected, path, address(this), block.timestamp + 1);
    }

    function test_SwapExactTokensForNATIVE() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(wnative, usdc, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, false);

        ILBRouter.Path memory path = _buildPath(usdc, wnative);

        uint256 balanceBefore = address(this).balance;

        (uint256 amountOut) = router.swapExactTokensForNATIVE(
            amountIn, amountOutExpected, path, payable(address(this)), block.timestamp + 1
        );

        assertEq(amountOut, amountOutExpected, "test_SwapExactTokensForNATIVE::1");
        assertEq(address(this).balance, balanceBefore + amountOut, "test_SwapExactTokensForNATIVE::2");

        // Reverts if amountOut is less than amountOutMin
        (, amountOutExpected,) = router.getSwapOut(pair, amountIn, false);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__InsufficientAmountOut.selector, amountOutExpected + 1, amountOutExpected
            )
        );
        router.swapExactTokensForNATIVE(
            amountIn, amountOutExpected + 1, path, payable(address(this)), block.timestamp + 1
        );

        // Revert if token out isn't WNATIVE
        path.tokenPath[1] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapExactTokensForNATIVE(
            amountIn, amountOutExpected + 1, path, payable(address(this)), block.timestamp + 1
        );

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapExactTokensForNATIVE(amountIn, amountOutExpected, path, payable(address(this)), block.timestamp - 1);

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapExactTokensForNATIVE(amountIn, amountOutExpected, path, payable(address(this)), block.timestamp + 1);
    }

    function test_SwapExactNATIVEForTokens() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(wnative, usdc, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, true);

        ILBRouter.Path memory path = _buildPath(wnative, usdc);

        uint256 balanceBefore = usdc.balanceOf(address(this));

        (uint256 amountOut) = router.swapExactNATIVEForTokens{value: amountIn}(
            amountOutExpected, path, address(this), block.timestamp + 1
        );

        assertEq(amountOut, amountOutExpected, "test_SwapExactNATIVEForTokens::1");
        assertEq(usdc.balanceOf(address(this)), balanceBefore + amountOut, "test_SwapExactNATIVEForTokens::2");

        (, amountOutExpected,) = router.getSwapOut(pair, amountIn, true);

        // Reverts if amountOut is less than amountOutMin
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__InsufficientAmountOut.selector, amountOutExpected + 1, amountOutExpected
            )
        );
        router.swapExactNATIVEForTokens{value: amountIn}(
            amountOutExpected + 1, path, address(this), block.timestamp + 1
        );

        // Revert if token in isn't WNATIVE
        path.tokenPath[0] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapExactNATIVEForTokens{value: amountIn}(amountOutExpected, path, address(this), block.timestamp + 1);

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapExactNATIVEForTokens{value: amountIn}(amountOutExpected, path, address(this), block.timestamp - 1);

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapExactNATIVEForTokens{value: amountIn}(amountOutExpected, path, address(this), block.timestamp + 1);
    }

    function test_SwapTokensForExactTokens() public {
        uint128 amountOut = 20e18;

        ILBPair pair = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).LBPair;
        (uint128 amountInExpected,,) = router.getSwapIn(pair, amountOut, true);

        ILBRouter.Path memory path = _buildPath(usdt, usdc);

        uint256 balanceBefore = usdt.balanceOf(address(this));

        (uint256[] memory amountsIn) =
            router.swapTokensForExactTokens(amountOut, amountInExpected, path, address(this), block.timestamp + 1);

        assertEq(amountsIn[0], amountInExpected, "test_SwapTokensForExactTokens::1");
        assertEq(usdt.balanceOf(address(this)), balanceBefore - amountsIn[0], "test_SwapTokensForExactTokens::2");

        (amountInExpected,,) = router.getSwapIn(pair, amountOut, true);

        // Revert if amountIn is too high
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__MaxAmountInExceeded.selector, amountInExpected - 1, amountInExpected
            )
        );
        router.swapTokensForExactTokens(amountOut, amountInExpected - 1, path, address(this), block.timestamp + 1);

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

    function test_SwapTokensForExactNATIVE() public {
        uint128 amountOut = 20e18;

        ILBPair pair = factory.getLBPairInformation(wnative, usdc, DEFAULT_BIN_STEP).LBPair;
        (uint128 amountInExpected,,) = router.getSwapIn(pair, amountOut, false);

        ILBRouter.Path memory path = _buildPath(usdc, wnative);

        uint256 balanceBefore = usdc.balanceOf(address(this));

        (uint256[] memory amountsIn) = router.swapTokensForExactNATIVE(
            amountOut, amountInExpected, path, payable(address(this)), block.timestamp + 1
        );

        assertEq(amountsIn[0], amountInExpected, "test_SwapTokensForExactNATIVE::1");
        assertEq(usdc.balanceOf(address(this)), balanceBefore - amountsIn[0], "test_SwapTokensForExactNATIVE::2");

        (amountInExpected,,) = router.getSwapIn(pair, amountOut, false);

        // Revert if amountIn is too high
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__MaxAmountInExceeded.selector, amountInExpected - 1, amountInExpected
            )
        );
        router.swapTokensForExactTokens(amountOut, amountInExpected - 1, path, address(this), block.timestamp + 1);

        // Revert if token out isn't WNATIVE
        path.tokenPath[1] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapTokensForExactNATIVE(amountOut, amountInExpected, path, payable(address(this)), block.timestamp + 1);

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

    function test_SwapNATIVEForExactTokens() public {
        uint128 amountOut = 20e18;

        ILBPair pair = factory.getLBPairInformation(wnative, usdc, DEFAULT_BIN_STEP).LBPair;
        (uint128 amountInExpected,,) = router.getSwapIn(pair, amountOut, true);

        ILBRouter.Path memory path = _buildPath(wnative, usdc);

        uint256 balanceBefore = address(this).balance;

        // Sending too much NATIVE to test the refund
        (uint256[] memory amountsIn) = router.swapNATIVEForExactTokens{value: amountInExpected + 100}(
            amountOut, path, address(this), block.timestamp + 1
        );

        assertEq(amountsIn[0], amountInExpected, "test_SwapNATIVEForExactTokens::1");
        assertEq(address(this).balance, balanceBefore - amountsIn[0], "test_SwapNATIVEForExactTokens::2");

        (amountInExpected,,) = router.getSwapIn(pair, amountOut, true);

        // Revert if not enough NATIVE has been sent
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__MaxAmountInExceeded.selector, amountInExpected / 2, amountInExpected
            )
        );
        router.swapNATIVEForExactTokens{value: amountInExpected / 2}(
            amountOut, path, address(this), block.timestamp + 1
        );

        // Revert if token in isn't WNATIVE
        path.tokenPath[0] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapNATIVEForExactTokens{value: amountInExpected}(amountOut, path, address(this), block.timestamp + 1);

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapNATIVEForExactTokens{value: amountInExpected}(amountOut, path, address(this), block.timestamp - 1);

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapNATIVEForExactTokens{value: amountInExpected}(amountOut, path, address(this), block.timestamp + 1);
    }

    function test_SwapExactTokensForNATIVESupportingFeeOnTransferTokens() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(taxToken, wnative, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, true);

        ILBRouter.Path memory path = _buildPath(taxToken, wnative);

        // Reverts if amountOut is less than amountOutMin
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__InsufficientAmountOut.selector, amountOutExpected, amountOutExpected / 2
            )
        );
        router.swapExactTokensForNATIVESupportingFeeOnTransferTokens(
            amountIn, amountOutExpected, path, payable(address(this)), block.timestamp + 1
        );

        uint256 balanceBefore = address(this).balance;

        (uint256 amountOut) = router.swapExactTokensForNATIVESupportingFeeOnTransferTokens(
            amountIn, amountOutExpected / 2, path, payable(address(this)), block.timestamp + 1
        );

        assertEq(amountOut, amountOutExpected / 2, "test_SwapExactTokensForNATIVESupportingFeeOnTransferTokens::1");
        assertEq(
            address(this).balance,
            balanceBefore + amountOut,
            "test_SwapExactTokensForNATIVESupportingFeeOnTransferTokens::2"
        );

        // Revert if token out isn't WNATIVE
        path.tokenPath[1] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapExactTokensForNATIVESupportingFeeOnTransferTokens(
            amountIn, amountOutExpected + 1, path, payable(address(this)), block.timestamp + 1
        );

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapExactTokensForNATIVESupportingFeeOnTransferTokens(
            amountIn, amountOutExpected, path, payable(address(this)), block.timestamp - 1
        );

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapExactTokensForNATIVESupportingFeeOnTransferTokens(
            amountIn, amountOutExpected, path, payable(address(this)), block.timestamp + 1
        );
    }

    function test_SwapExactNATIVEForTokensSupportingFeeOnTransferTokens() public {
        uint128 amountIn = 20e18;

        ILBPair pair = factory.getLBPairInformation(taxToken, wnative, DEFAULT_BIN_STEP).LBPair;
        (, uint128 amountOutExpected,) = router.getSwapOut(pair, amountIn, false);

        ILBRouter.Path memory path = _buildPath(wnative, taxToken);

        // Reverts if amountOut is less than amountOutMin
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__InsufficientAmountOut.selector, amountOutExpected, amountOutExpected / 2 + 1
            )
        );
        router.swapExactNATIVEForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutExpected, path, address(this), block.timestamp + 1
        );

        uint256 balanceBefore = taxToken.balanceOf(address(this));

        (uint256 amountOut) = router.swapExactNATIVEForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutExpected / 2, path, address(this), block.timestamp + 1
        );

        assertEq(amountOut, amountOutExpected / 2 + 1, "test_SwapExactNATIVEForTokensSupportingFeeOnTransferTokens::1");
        assertEq(
            taxToken.balanceOf(address(this)),
            balanceBefore + amountOut,
            "test_SwapExactNATIVEForTokensSupportingFeeOnTransferTokens::2"
        );

        // Revert if token in isn't WNATIVE
        path.tokenPath[0] = usdt;
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__InvalidTokenPath.selector, address(usdt)));
        router.swapExactNATIVEForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutExpected, path, address(this), block.timestamp + 1
        );

        // Revert is dealine passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.swapExactNATIVEForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutExpected, path, address(this), block.timestamp - 1
        );

        // Revert if the path arrays are not valid
        path.tokenPath = new IERC20[](0);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.swapExactNATIVEForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            amountOutExpected, path, address(this), block.timestamp + 1
        );
    }

    function _buildPath(IERC20 tokenIn, IERC20 tokenOut) private pure returns (ILBRouter.Path memory path) {
        path.pairBinSteps = new uint256[](1);
        path.pairBinSteps[0] = DEFAULT_BIN_STEP;

        path.versions = new ILBRouter.Version[](1);
        path.versions[0] = ILBRouter.Version.V2_2;

        path.tokenPath = new IERC20[](2);
        path.tokenPath[0] = tokenIn;
        path.tokenPath[1] = tokenOut;
    }

    receive() external payable {}
}
