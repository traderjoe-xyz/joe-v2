// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./helpers/TestHelper.sol";

contract LBPairSwapTest is TestHelper {
    using SafeCast for uint256;

    function setUp() public override {
        super.setUp();

        pairWavax = createLBPair(wavax, usdc);

        addLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 1e18, 50, 50);
    }

    function testFuzz_SwapInForY(uint128 amountOut) public {
        vm.assume(amountOut > 0 && amountOut < 1e18);

        (uint128 amountIn, uint128 amountOutLeft,) = pairWavax.getSwapIn(amountOut, true);

        assertEq(amountOutLeft, 0, "TestFuzz_SwapInForY::1");

        deal(address(wavax), ALICE, amountIn);

        vm.startPrank(ALICE);
        wavax.transfer(address(pairWavax), amountIn);
        pairWavax.swap(true, ALICE);
        vm.stopPrank();

        assertEq(wavax.balanceOf(ALICE), 0, "TestFuzz_SwapInForY::2");
        assertEq(usdc.balanceOf(ALICE), amountOut, "TestFuzz_SwapInForY::3");
    }

    function testFuzz_SwapInForX(uint128 amountOut) public {
        vm.assume(amountOut > 0 && amountOut < 1e18);

        (uint128 amountIn, uint128 amountOutLeft,) = pairWavax.getSwapIn(amountOut, false);

        assertEq(amountOutLeft, 0, "TestFuzz_SwapInForX::1");

        deal(address(usdc), ALICE, amountIn);

        vm.startPrank(ALICE);
        usdc.transfer(address(pairWavax), amountIn);
        pairWavax.swap(false, ALICE);
        vm.stopPrank();

        assertEq(usdc.balanceOf(ALICE), 0, "TestFuzz_SwapInForX::2");
        assertEq(wavax.balanceOf(ALICE), amountOut, "TestFuzz_SwapInForX::3");
    }

    function testFuzz_SwapOutForY(uint128 amountIn) public {
        vm.assume(amountIn > 0 && amountIn <= 1e18);

        (uint128 amountInLeft, uint128 amountOut,) = pairWavax.getSwapOut(amountIn, true);

        vm.assume(amountOut > 0);

        assertEq(amountInLeft, 0, "TestFuzz_SwapOutForY::1");

        deal(address(wavax), ALICE, amountIn);

        vm.startPrank(ALICE);
        wavax.transfer(address(pairWavax), amountIn);
        pairWavax.swap(true, ALICE);
        vm.stopPrank();

        assertEq(wavax.balanceOf(ALICE), 0, "TestFuzz_SwapOutForY::2");
        assertEq(usdc.balanceOf(ALICE), amountOut, "TestFuzz_SwapOutForY::3");
    }

    function testFuzz_SwapOutForX(uint128 amountIn) public {
        vm.assume(amountIn > 0 && amountIn <= 1e18);

        (uint128 amountInLeft, uint128 amountOut,) = pairWavax.getSwapOut(amountIn, false);

        vm.assume(amountOut > 0);

        assertEq(amountInLeft, 0, "TestFuzz_SwapOutForX::1");

        deal(address(usdc), ALICE, amountIn);

        vm.startPrank(ALICE);
        usdc.transfer(address(pairWavax), amountIn);
        pairWavax.swap(false, ALICE);
        vm.stopPrank();

        assertEq(usdc.balanceOf(ALICE), 0, "TestFuzz_SwapOutForX::2");
        assertEq(wavax.balanceOf(ALICE), amountOut, "TestFuzz_SwapOutForX::3");
    }

    function test_revert_SwapInsufficientAmountIn() external {
        vm.expectRevert(ILBPair.LBPair__InsufficientAmountIn.selector);
        pairWavax.swap(true, ALICE);

        vm.expectRevert(ILBPair.LBPair__InsufficientAmountIn.selector);
        pairWavax.swap(false, ALICE);
    }

    function test_revert_SwapInsufficientAmountOut() external {
        deal(address(wavax), ALICE, 1);
        deal(address(usdc), ALICE, 1);

        vm.prank(ALICE);
        wavax.transfer(address(pairWavax), 1);

        vm.expectRevert(ILBPair.LBPair__InsufficientAmountOut.selector);
        pairWavax.swap(true, ALICE);

        vm.prank(ALICE);
        usdc.transfer(address(pairWavax), 1);

        vm.expectRevert(ILBPair.LBPair__InsufficientAmountOut.selector);
        pairWavax.swap(false, ALICE);
    }

    function test_revert_SwapOutOfLiquidity() external {
        deal(address(wavax), ALICE, 2e18);
        deal(address(usdc), ALICE, 2e18);

        vm.prank(ALICE);
        wavax.transfer(address(pairWavax), 2e18);

        vm.expectRevert(ILBPair.LBPair__OutOfLiquidity.selector);
        pairWavax.swap(true, ALICE);

        vm.prank(ALICE);
        usdc.transfer(address(pairWavax), 2e18);

        vm.expectRevert(ILBPair.LBPair__OutOfLiquidity.selector);
        pairWavax.swap(false, ALICE);
    }
}
