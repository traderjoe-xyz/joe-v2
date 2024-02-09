// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./helpers/TestHelper.sol";

contract LBPairSwapTest is TestHelper {
    using SafeCast for uint256;

    function setUp() public override {
        super.setUp();

        pairWnative = createLBPair(wnative, usdc);

        addLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 1e18, 50, 50);
    }

    function testFuzz_SwapInForY(uint128 amountOut) public {
        vm.assume(amountOut > 0 && amountOut < 1e18);

        (uint128 amountIn, uint128 amountOutLeft,) = pairWnative.getSwapIn(amountOut, true);

        assertEq(amountOutLeft, 0, "testFuzz_SwapInForY::1");

        deal(address(wnative), ALICE, amountIn);

        vm.startPrank(ALICE);
        wnative.transfer(address(pairWnative), amountIn);
        pairWnative.swap(true, ALICE);
        vm.stopPrank();

        assertEq(wnative.balanceOf(ALICE), 0, "testFuzz_SwapInForY::2");
        assertEq(usdc.balanceOf(ALICE), amountOut, "testFuzz_SwapInForY::3");
    }

    function testFuzz_SwapInForX(uint128 amountOut) public {
        vm.assume(amountOut > 0 && amountOut < 1e18);

        (uint128 amountIn, uint128 amountOutLeft,) = pairWnative.getSwapIn(amountOut, false);

        assertEq(amountOutLeft, 0, "testFuzz_SwapInForX::1");

        deal(address(usdc), ALICE, amountIn);

        vm.startPrank(ALICE);
        usdc.transfer(address(pairWnative), amountIn);
        pairWnative.swap(false, ALICE);
        vm.stopPrank();

        assertEq(usdc.balanceOf(ALICE), 0, "testFuzz_SwapInForX::2");
        assertEq(wnative.balanceOf(ALICE), amountOut, "testFuzz_SwapInForX::3");
    }

    function testFuzz_SwapOutForY(uint128 amountIn) public {
        vm.assume(amountIn > 0 && amountIn <= 1e18);

        (uint128 amountInLeft, uint128 amountOut,) = pairWnative.getSwapOut(amountIn, true);

        vm.assume(amountOut > 0);

        assertEq(amountInLeft, 0, "testFuzz_SwapOutForY::1");

        deal(address(wnative), ALICE, amountIn);

        vm.startPrank(ALICE);
        wnative.transfer(address(pairWnative), amountIn);
        pairWnative.swap(true, ALICE);
        vm.stopPrank();

        assertEq(wnative.balanceOf(ALICE), 0, "testFuzz_SwapOutForY::2");
        assertEq(usdc.balanceOf(ALICE), amountOut, "testFuzz_SwapOutForY::3");
    }

    function testFuzz_SwapOutForX(uint128 amountIn) public {
        vm.assume(amountIn > 0 && amountIn <= 1e18);

        (uint128 amountInLeft, uint128 amountOut,) = pairWnative.getSwapOut(amountIn, false);

        vm.assume(amountOut > 0);

        assertEq(amountInLeft, 0, "testFuzz_SwapOutForX::1");

        deal(address(usdc), ALICE, amountIn);

        vm.startPrank(ALICE);
        usdc.transfer(address(pairWnative), amountIn);
        pairWnative.swap(false, ALICE);
        vm.stopPrank();

        assertEq(usdc.balanceOf(ALICE), 0, "testFuzz_SwapOutForX::2");
        assertEq(wnative.balanceOf(ALICE), amountOut, "testFuzz_SwapOutForX::3");
    }

    function test_revert_SwapInsufficientAmountIn() external {
        vm.expectRevert(ILBPair.LBPair__InsufficientAmountIn.selector);
        pairWnative.swap(true, ALICE);

        vm.expectRevert(ILBPair.LBPair__InsufficientAmountIn.selector);
        pairWnative.swap(false, ALICE);
    }

    function test_revert_SwapInsufficientAmountOut() external {
        deal(address(wnative), ALICE, 1);
        deal(address(usdc), ALICE, 1);

        vm.prank(ALICE);
        wnative.transfer(address(pairWnative), 1);

        vm.expectRevert(ILBPair.LBPair__InsufficientAmountOut.selector);
        pairWnative.swap(true, ALICE);

        vm.prank(ALICE);
        usdc.transfer(address(pairWnative), 1);

        vm.expectRevert(ILBPair.LBPair__InsufficientAmountOut.selector);
        pairWnative.swap(false, ALICE);
    }

    function test_revert_SwapOutOfLiquidity() external {
        deal(address(wnative), ALICE, 2e18);
        deal(address(usdc), ALICE, 2e18);

        vm.prank(ALICE);
        wnative.transfer(address(pairWnative), 2e18);

        vm.expectRevert(ILBPair.LBPair__OutOfLiquidity.selector);
        pairWnative.swap(true, ALICE);

        vm.prank(ALICE);
        usdc.transfer(address(pairWnative), 2e18);

        vm.expectRevert(ILBPair.LBPair__OutOfLiquidity.selector);
        pairWnative.swap(false, ALICE);
    }
}
