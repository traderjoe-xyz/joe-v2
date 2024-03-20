// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./helpers/TestHelper.sol";
import "../src/libraries/ImmutableClone.sol";

contract LBPairFeesTest is TestHelper {
    using PackedUint128Math for uint128;

    uint256 constant amountX = 1e18;
    uint256 constant amountY = 1e18;

    function setUp() public override {
        super.setUp();

        pairWnative = createLBPair(wnative, usdc);

        addLiquidity(DEV, DEV, pairWnative, ID_ONE, amountX, amountY, 10, 10);
        require(wnative.balanceOf(DEV) == 0 && usdc.balanceOf(DEV) == 0, "setUp::1");
    }

    function testFuzz_SwapInX(uint128 amountOut) external {
        vm.assume(amountOut > 0 && amountOut <= 1e18);

        (uint128 amountIn, uint128 amountOutLeft,) = pairWnative.getSwapIn(amountOut, true);
        assertEq(amountOutLeft, 0, "testFuzz_SwapInX::1");

        deal(address(wnative), ALICE, amountIn);

        vm.prank(ALICE);
        wnative.transfer(address(pairWnative), amountIn);
        pairWnative.swap(true, ALICE);

        assertEq(wnative.balanceOf(ALICE), 0, "testFuzz_SwapInX::2");
        assertEq(usdc.balanceOf(ALICE), amountOut, "testFuzz_SwapInX::3");

        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX,) = pairWnative.getProtocolFees();

        uint256 balanceX = wnative.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountIn - protocolFeeX, "testFuzz_SwapInX::4");
        assertEq(balanceY, amountY - amountOut, "testFuzz_SwapInX::5");
    }

    function testFuzz_SwapInY(uint128 amountOut) external {
        vm.assume(amountOut > 0 && amountOut <= 1e18);

        (uint128 amountIn, uint128 amountOutLeft,) = pairWnative.getSwapIn(amountOut, false);
        assertEq(amountOutLeft, 0, "testFuzz_SwapInY::1");

        deal(address(usdc), ALICE, amountIn);

        vm.prank(ALICE);
        usdc.transfer(address(pairWnative), amountIn);
        pairWnative.swap(false, ALICE);

        assertEq(usdc.balanceOf(ALICE), 0, "testFuzz_SwapInY::2");
        assertEq(wnative.balanceOf(ALICE), amountOut, "testFuzz_SwapInY::3");

        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);

        (, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        uint256 balanceX = wnative.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX - amountOut, "testFuzz_SwapInY::4");
        assertEq(balanceY, amountY + amountIn - protocolFeeY, "testFuzz_SwapInY::5");
    }

    function testFuzz_SwapOutX(uint128 amountIn) external {
        (uint128 amountInLeft, uint128 amountOut,) = pairWnative.getSwapOut(amountIn, true);
        vm.assume(amountOut > 0 && amountInLeft == 0);

        deal(address(wnative), ALICE, amountIn);

        vm.prank(ALICE);
        wnative.transfer(address(pairWnative), amountIn);
        pairWnative.swap(true, ALICE);

        assertEq(wnative.balanceOf(ALICE), 0, "testFuzz_SwapOutX::1");
        assertEq(usdc.balanceOf(ALICE), amountOut, "testFuzz_SwapOutX::2");

        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX,) = pairWnative.getProtocolFees();

        uint256 balanceX = wnative.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountIn - protocolFeeX, "testFuzz_SwapOutX::3");
        assertEq(balanceY, amountY - amountOut, "testFuzz_SwapOutX::4");
    }

    function testFuzz_SwapOutY(uint128 amountIn) external {
        (uint128 amountInLeft, uint128 amountOut,) = pairWnative.getSwapOut(amountIn, false);
        vm.assume(amountOut > 0 && amountInLeft == 0);

        deal(address(usdc), ALICE, amountIn);

        vm.prank(ALICE);
        usdc.transfer(address(pairWnative), amountIn);
        pairWnative.swap(false, ALICE);

        assertEq(usdc.balanceOf(ALICE), 0, "testFuzz_SwapOutY::1");
        assertEq(wnative.balanceOf(ALICE), amountOut, "testFuzz_SwapOutY::2");

        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);

        (, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        uint256 balanceX = wnative.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX - amountOut, "testFuzz_SwapOutY::3");
        assertEq(balanceY, amountY + amountIn - protocolFeeY, "testFuzz_SwapOutY::4");
    }

    function testFuzz_SwapInXAndY(uint128 amountXOut, uint128 amountYOut) external {
        vm.assume(amountXOut > 0 && amountXOut <= 1e18 && amountYOut > 0 && amountYOut <= 1e18);

        (uint128 amountXIn, uint128 amountYOutLeft,) = pairWnative.getSwapIn(amountYOut, true);
        assertEq(amountYOutLeft, 0, "testFuzz_SwapInXAndY::1");

        deal(address(wnative), BOB, 1e36);
        deal(address(usdc), BOB, 1e36);

        vm.prank(BOB);
        wnative.transfer(address(pairWnative), amountXIn);
        pairWnative.swap(true, ALICE);

        assertEq(usdc.balanceOf(ALICE), amountYOut, "testFuzz_SwapInXAndY::2");

        (uint128 amountYIn, uint128 amountXOutLeft,) = pairWnative.getSwapIn(amountXOut, false);
        assertEq(amountXOutLeft, 0, "testFuzz_SwapInXAndY::3");

        vm.prank(BOB);
        usdc.transfer(address(pairWnative), amountYIn);
        pairWnative.swap(false, ALICE);

        uint256 realAmountXOut = wnative.balanceOf(ALICE);
        assertGe(realAmountXOut, amountXOut, "testFuzz_SwapInXAndY::4");

        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        assertEq(wnative.balanceOf(address(pairWnative)), protocolFeeX, "testFuzz_SwapInXAndY::5");
        assertEq(usdc.balanceOf(address(pairWnative)), protocolFeeY, "testFuzz_SwapInXAndY::6");

        uint256 balanceX = wnative.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountXIn - realAmountXOut - protocolFeeX, "testFuzz_SwapInXAndY::7");
        assertEq(balanceY, amountY + amountYIn - amountYOut - protocolFeeY, "testFuzz_SwapInXAndY::8");
    }

    function testFuzz_SwapInYandX(uint128 amountYOut, uint128 amountXOut) external {
        vm.assume(amountXOut > 0 && amountXOut <= 1e18 && amountYOut > 0 && amountYOut <= 1e18);

        (uint128 amountYIn, uint128 amountXOutLeft,) = pairWnative.getSwapIn(amountXOut, false);
        assertEq(amountXOutLeft, 0, "testFuzz_SwapInYandX::1");

        deal(address(wnative), BOB, 1e36);
        deal(address(usdc), BOB, 1e36);

        vm.prank(BOB);
        usdc.transfer(address(pairWnative), amountYIn);
        pairWnative.swap(false, ALICE);

        assertEq(wnative.balanceOf(ALICE), amountXOut, "testFuzz_SwapInYandX::2");

        (uint128 amountXIn, uint128 amountYOutLeft,) = pairWnative.getSwapIn(amountYOut, true);
        assertEq(amountYOutLeft, 0, "testFuzz_SwapInYandX::3");

        vm.prank(BOB);
        wnative.transfer(address(pairWnative), amountXIn);
        pairWnative.swap(true, ALICE);

        uint256 realAmountYOut = usdc.balanceOf(ALICE);
        assertGe(realAmountYOut, amountYOut, "testFuzz_SwapInYandX::4");

        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        assertEq(wnative.balanceOf(address(pairWnative)), protocolFeeX, "testFuzz_SwapInYandX::5");
        assertEq(usdc.balanceOf(address(pairWnative)), protocolFeeY, "testFuzz_SwapInYandX::6");

        uint256 balanceX = wnative.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountXIn - amountXOut - protocolFeeX, "testFuzz_SwapInYandX::7");
        assertEq(balanceY, amountY + amountYIn - realAmountYOut - protocolFeeY, "testFuzz_SwapInYandX::8");
    }

    function testFuzz_SwapOutXAndY(uint128 amountXIn, uint128 amountYIn) external {
        (uint128 amountXInLeft, uint128 amountYOut,) = pairWnative.getSwapOut(amountXIn, true);
        vm.assume(amountXInLeft == 0 && amountYOut > 0);

        deal(address(wnative), BOB, 1e36);
        deal(address(usdc), BOB, 1e36);

        vm.prank(BOB);
        wnative.transfer(address(pairWnative), amountXIn);
        pairWnative.swap(true, ALICE);

        assertEq(usdc.balanceOf(ALICE), amountYOut, "testFuzz_SwapOutXAndY::1");

        (uint128 amountYInLeft, uint128 amountXOut,) = pairWnative.getSwapOut(amountYIn, false);
        vm.assume(amountYInLeft == 0 && amountXOut > 0);

        vm.prank(BOB);
        usdc.transfer(address(pairWnative), amountYIn);
        pairWnative.swap(false, ALICE);

        uint256 realAmountXOut = wnative.balanceOf(ALICE);
        assertGe(realAmountXOut, amountXOut, "testFuzz_SwapOutXAndY::2");

        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        assertEq(wnative.balanceOf(address(pairWnative)), protocolFeeX, "testFuzz_SwapOutXAndY::3");
        assertEq(usdc.balanceOf(address(pairWnative)), protocolFeeY, "testFuzz_SwapOutXAndY::4");

        uint256 balanceX = wnative.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountXIn - realAmountXOut - protocolFeeX, "testFuzz_SwapOutXAndY::5");
        assertEq(balanceY, amountY + amountYIn - amountYOut - protocolFeeY, "testFuzz_SwapOutXAndY::6");
    }

    function testFuzz_SwapOutYAndX(uint128 amountXIn, uint128 amountYIn) external {
        (uint128 amountYInLeft, uint128 amountXOut,) = pairWnative.getSwapOut(amountYIn, false);
        vm.assume(amountYInLeft == 0 && amountXOut > 0);

        deal(address(wnative), BOB, 1e36);
        deal(address(usdc), BOB, 1e36);

        vm.prank(BOB);
        usdc.transfer(address(pairWnative), amountYIn);
        pairWnative.swap(false, ALICE);

        assertEq(wnative.balanceOf(ALICE), amountXOut, "testFuzz_SwapOutYAndX::1");

        (uint128 amountXInLeft, uint128 amountYOut,) = pairWnative.getSwapOut(amountXIn, true);
        vm.assume(amountXInLeft == 0 && amountYOut > 0);

        vm.prank(BOB);
        wnative.transfer(address(pairWnative), amountXIn);
        pairWnative.swap(true, ALICE);

        uint256 realAmountYOut = usdc.balanceOf(ALICE);
        assertGe(realAmountYOut, amountYOut, "testFuzz_SwapOutYAndX::2");

        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        assertEq(wnative.balanceOf(address(pairWnative)), protocolFeeX, "testFuzz_SwapOutYAndX::3");
        assertEq(usdc.balanceOf(address(pairWnative)), protocolFeeY, "testFuzz_SwapOutYAndX::4");

        uint256 balanceX = wnative.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountXIn - amountXOut - protocolFeeX, "testFuzz_SwapOutYAndX::5");
        assertEq(balanceY, amountY + amountYIn - realAmountYOut - protocolFeeY, "testFuzz_SwapOutYAndX::6");
    }

    function test_FeesX2LP() external {
        addLiquidity(ALICE, ALICE, pairWnative, ID_ONE, amountX, amountY, 10, 10);

        uint128 amountXIn = 1e18;
        (, uint128 amountYOut,) = pairWnative.getSwapOut(amountXIn, true);

        deal(address(wnative), BOB, amountXIn);

        vm.prank(BOB);
        wnative.transfer(address(pairWnative), amountXIn);
        pairWnative.swap(true, BOB);

        removeLiquidity(ALICE, ALICE, pairWnative, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        assertApproxEqAbs(
            wnative.balanceOf(address(ALICE)), amountX + (amountXIn - protocolFeeX) / 2, 2, "test_FeesX2LP::1"
        );
        assertApproxEqAbs(
            usdc.balanceOf(address(ALICE)), amountY - (amountYOut + protocolFeeY) / 2, 2, "test_FeesX2LP::2"
        );

        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);

        assertApproxEqAbs(
            wnative.balanceOf(address(DEV)), amountX + (amountXIn - protocolFeeX) / 2, 2, "test_FeesX2LP::3"
        );
        assertApproxEqAbs(
            usdc.balanceOf(address(DEV)), amountY - (amountYOut + protocolFeeY) / 2, 2, "test_FeesX2LP::4"
        );
    }

    function test_FeesY2LP() external {
        addLiquidity(ALICE, ALICE, pairWnative, ID_ONE, amountX, amountY, 10, 10);

        uint128 amountYIn = 1e18;
        (, uint128 amountXOut,) = pairWnative.getSwapOut(amountYIn, false);

        deal(address(usdc), BOB, amountYIn);

        vm.prank(BOB);
        usdc.transfer(address(pairWnative), amountYIn);
        pairWnative.swap(false, BOB);

        removeLiquidity(ALICE, ALICE, pairWnative, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        assertApproxEqAbs(
            wnative.balanceOf(address(ALICE)), amountX - (amountXOut + protocolFeeX) / 2, 2, "test_FeesY2LP::1"
        );
        assertApproxEqAbs(
            usdc.balanceOf(address(ALICE)), amountY + (amountYIn - protocolFeeY) / 2, 2, "test_FeesY2LP::2"
        );

        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);

        assertApproxEqAbs(
            wnative.balanceOf(address(DEV)), amountX - (amountXOut + protocolFeeX) / 2, 2, "test_FeesY2LP::3"
        );
        assertApproxEqAbs(usdc.balanceOf(address(DEV)), amountY + (amountYIn - protocolFeeY) / 2, 2, "test_FeesY2LP::4");
    }

    function test_Fees2LPFlashloan() external {
        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 10, 10);
        addLiquidity(DEV, DEV, pairWnative, ID_ONE, amountX, amountY, 1, 1);

        FlashBorrower borrower = new FlashBorrower(pairWnative);

        deal(address(wnative), address(borrower), 2e18);
        deal(address(usdc), address(borrower), 2e18);

        (uint128 feeX1, uint128 feeY1) = (1e18 + 1, 1e18);

        vm.prank(address(borrower));
        pairWnative.flashLoan(borrower, bytes32(uint256(1)), abi.encode(feeX1, feeY1, Constants.CALLBACK_SUCCESS, 0));

        (uint128 protocolFeeX1, uint128 protocolFeeY1) = pairWnative.getProtocolFees();
        (feeX1, feeY1) = (feeX1 - protocolFeeX1, feeY1 - protocolFeeY1);

        addLiquidity(ALICE, ALICE, pairWnative, ID_ONE, amountX, amountY, 1, 1);

        (uint128 feeX2, uint128 feeY2) = (1e18 + 1, 1e18);

        vm.prank(address(borrower));
        pairWnative.flashLoan(borrower, bytes32(uint256(1)), abi.encode(feeX2, feeY2, Constants.CALLBACK_SUCCESS, 0));

        {
            (uint128 protocolFeeX2, uint128 protocolFeeY2) = pairWnative.getProtocolFees();
            (feeX2, feeY2) = (feeX2 - (protocolFeeX2 - protocolFeeX1), feeY2 - (protocolFeeY2 - protocolFeeY1));
        }

        (uint256 shareAlice, uint256 shareDev) =
            (pairWnative.balanceOf(address(ALICE), ID_ONE), pairWnative.balanceOf(address(DEV), ID_ONE));

        removeLiquidity(ALICE, ALICE, pairWnative, ID_ONE, 1e18, 1, 1);
        removeLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 1, 1);

        assertApproxEqAbs(
            wnative.balanceOf(address(ALICE)),
            amountX + feeX2 * shareAlice / (shareAlice + shareDev),
            1,
            "test_Fees2LPFlashloan::1"
        );
        assertApproxEqAbs(
            usdc.balanceOf(address(ALICE)),
            amountY + feeY2 * shareAlice / (shareAlice + shareDev),
            1,
            "test_Fees2LPFlashloan::2"
        );

        assertApproxEqAbs(
            wnative.balanceOf(address(DEV)),
            amountX + feeX1 + feeX2 * shareDev / (shareAlice + shareDev),
            1,
            "test_Fees2LPFlashloan::3"
        );
        assertApproxEqAbs(
            usdc.balanceOf(address(DEV)),
            amountY + feeY1 + feeY2 * shareDev / (shareAlice + shareDev),
            1,
            "test_Fees2LPFlashloan::4"
        );
    }

    function test_CollectProtocolFeesXTokens() external {
        FlashBorrower borrower = new FlashBorrower(pairWnative);

        deal(address(wnative), address(borrower), 1e36);
        deal(address(usdc), address(borrower), 1e36);

        vm.prank(address(borrower));
        pairWnative.flashLoan(borrower, uint128(1).encode(0), abi.encode(1e18 + 1, 0, Constants.CALLBACK_SUCCESS, 0));

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        address feeRecipient = factory.getFeeRecipient();

        vm.prank(feeRecipient);
        pairWnative.collectProtocolFees();

        assertEq(wnative.balanceOf(feeRecipient), protocolFeeX - 1, "test_CollectProtocolFeesXTokens::1");
        assertEq(usdc.balanceOf(feeRecipient), 0, "test_CollectProtocolFeesXTokens::2");

        (protocolFeeX, protocolFeeY) = pairWnative.getProtocolFees();

        assertEq(protocolFeeX, 1, "test_CollectProtocolFeesXTokens::3");
        assertEq(protocolFeeY, 0, "test_CollectProtocolFeesXTokens::4");
    }

    function test_CollectProtocolFeesYTokens() external {
        FlashBorrower borrower = new FlashBorrower(pairWnative);

        deal(address(wnative), address(borrower), 1e36);
        deal(address(usdc), address(borrower), 1e36);

        vm.prank(address(borrower));
        pairWnative.flashLoan(borrower, uint128(0).encode(1), abi.encode(0, 1e18 + 1, Constants.CALLBACK_SUCCESS, 0));

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        address feeRecipient = factory.getFeeRecipient();

        vm.prank(feeRecipient);
        pairWnative.collectProtocolFees();

        assertEq(wnative.balanceOf(feeRecipient), 0, "test_CollectProtocolFeesYTokens::1");
        assertEq(usdc.balanceOf(feeRecipient), protocolFeeY - 1, "test_CollectProtocolFeesYTokens::2");

        (protocolFeeX, protocolFeeY) = pairWnative.getProtocolFees();

        assertEq(protocolFeeX, 0, "test_CollectProtocolFeesYTokens::3");
        assertEq(protocolFeeY, 1, "test_CollectProtocolFeesYTokens::4");
    }

    function test_CollectProtocolFeesBothTokens() external {
        FlashBorrower borrower = new FlashBorrower(pairWnative);

        deal(address(wnative), address(borrower), 1e36);
        deal(address(usdc), address(borrower), 1e36);

        vm.prank(address(borrower));
        pairWnative.flashLoan(
            borrower, uint128(1).encode(1), abi.encode(1e18 + 1, 1e18 + 1, Constants.CALLBACK_SUCCESS, 0)
        );

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWnative.getProtocolFees();

        address feeRecipient = factory.getFeeRecipient();

        vm.prank(feeRecipient);
        pairWnative.collectProtocolFees();

        assertEq(wnative.balanceOf(feeRecipient), protocolFeeX - 1, "test_CollectProtocolFeesBothTokens::1");
        assertEq(usdc.balanceOf(feeRecipient), protocolFeeY - 1, "test_CollectProtocolFeesBothTokens::2");

        (protocolFeeX, protocolFeeY) = pairWnative.getProtocolFees();

        assertEq(protocolFeeX, 1, "test_CollectProtocolFeesBothTokens::3");
        assertEq(protocolFeeY, 1, "test_CollectProtocolFeesBothTokens::4");
    }

    function test_CollectProtocolFeesAfterSwap() external {
        deal(address(wnative), address(BOB), 1e18);

        vm.prank(BOB);
        wnative.transfer(address(pairWnative), 1e18);
        pairWnative.swap(true, BOB);
        pairWnative.getBinStep();

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWnative.getProtocolFees();
        uint128 previousProtocolFeeX = protocolFeeX;

        assertGt(protocolFeeX, 0, "test_CollectProtocolFeesAfterSwap::1");
        assertEq(protocolFeeY, 0, "test_CollectProtocolFeesAfterSwap::2");

        (uint128 reserveX, uint128 reserveY) = pairWnative.getReserves();

        address feeRecipient = factory.getFeeRecipient();

        vm.prank(feeRecipient);
        pairWnative.collectProtocolFees();

        (uint128 reserveXAfter, uint128 reserveYAfter) = pairWnative.getReserves();

        assertEq(reserveXAfter, reserveX, "test_CollectProtocolFeesAfterSwap::3");
        assertEq(reserveYAfter, reserveY, "test_CollectProtocolFeesAfterSwap::4");

        assertEq(wnative.balanceOf(feeRecipient), protocolFeeX - 1, "test_CollectProtocolFeesAfterSwap::5");
        assertEq(usdc.balanceOf(feeRecipient), 0, "test_CollectProtocolFeesAfterSwap::6");

        (protocolFeeX, protocolFeeY) = pairWnative.getProtocolFees();

        assertEq(protocolFeeX, 1, "test_CollectProtocolFeesAfterSwap::7");
        assertEq(protocolFeeY, 0, "test_CollectProtocolFeesAfterSwap::8");

        deal(address(usdc), address(BOB), 1e18);

        vm.prank(BOB);
        usdc.transfer(address(pairWnative), 1e18);
        pairWnative.swap(false, BOB);

        (protocolFeeX, protocolFeeY) = pairWnative.getProtocolFees();
        uint128 previousProtocolFeeY = protocolFeeY;

        assertEq(protocolFeeX, 1, "test_CollectProtocolFeesAfterSwap::9");
        assertGt(protocolFeeY, 0, "test_CollectProtocolFeesAfterSwap::10");

        (reserveX, reserveY) = pairWnative.getReserves();

        vm.prank(feeRecipient);
        pairWnative.collectProtocolFees();

        (reserveXAfter, reserveYAfter) = pairWnative.getReserves();

        assertEq(reserveXAfter, reserveX, "test_CollectProtocolFeesAfterSwap::11");
        assertEq(reserveYAfter, reserveY, "test_CollectProtocolFeesAfterSwap::12");

        assertEq(wnative.balanceOf(feeRecipient), previousProtocolFeeX - 1, "test_CollectProtocolFeesAfterSwap::13");
        assertEq(usdc.balanceOf(feeRecipient), protocolFeeY - 1, "test_CollectProtocolFeesAfterSwap::14");

        (protocolFeeX, protocolFeeY) = pairWnative.getProtocolFees();

        assertEq(protocolFeeX, 1, "test_CollectProtocolFeesAfterSwap::15");
        assertEq(protocolFeeY, 1, "test_CollectProtocolFeesAfterSwap::16");

        vm.prank(feeRecipient);
        pairWnative.collectProtocolFees();

        assertEq(wnative.balanceOf(feeRecipient), previousProtocolFeeX - 1, "test_CollectProtocolFeesAfterSwap::17");
        assertEq(usdc.balanceOf(feeRecipient), previousProtocolFeeY - 1, "test_CollectProtocolFeesAfterSwap::18");
    }

    function test_revert_TotalFeeExceeded(
        uint16 binStep,
        uint16 baseFactor,
        uint24 variableFeeControl,
        uint24 maxVolatilityAccumulator
    ) external {
        vm.assume(maxVolatilityAccumulator <= Encoded.MASK_UINT20);

        uint256 baseFee = uint256(baseFactor) * binStep * 1e10;
        uint256 varFee = ((uint256(binStep) * maxVolatilityAccumulator) ** 2 * variableFeeControl + 99) / 100;

        vm.assume(baseFee + varFee > 1e17);

        bytes memory data = abi.encodePacked(wnative, usdc, binStep);

        pairWnative = LBPair(ImmutableClone.cloneDeterministic(address(pairImplementation), data, keccak256(data)));

        vm.prank(address(factory));
        pairWnative.initialize(1, 1, 1, 1, 1, 1, 1, 1);

        vm.expectRevert(ILBPair.LBPair__MaxTotalFeeExceeded.selector);
        vm.prank(address(factory));
        pairWnative.setStaticFeeParameters(baseFactor, 1, 1, 1, variableFeeControl, 1, maxVolatilityAccumulator);
    }
}
