// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./helpers/TestHelper.sol";
import "../src/libraries/ImmutableClone.sol";

contract LBPairFeesTest is TestHelper {
    using PackedUint128Math for uint128;

    uint256 constant amountX = 1e18;
    uint256 constant amountY = 1e18;

    function setUp() public override {
        super.setUp();

        pairWavax = createLBPair(wavax, usdc);

        addLiquidity(DEV, DEV, pairWavax, ID_ONE, amountX, amountY, 10, 10);
        require(wavax.balanceOf(DEV) == 0 && usdc.balanceOf(DEV) == 0, "setUp::1");
    }

    function testFuzz_SwapInX(uint128 amountOut) external {
        vm.assume(amountOut > 0 && amountOut <= 1e18);

        (uint128 amountIn, uint128 amountOutLeft,) = pairWavax.getSwapIn(amountOut, true);
        assertEq(amountOutLeft, 0, "testFuzz_SwapInFeesAmounts::1");

        deal(address(wavax), ALICE, amountIn);

        vm.prank(ALICE);
        wavax.transfer(address(pairWavax), amountIn);
        pairWavax.swap(true, ALICE);

        assertEq(wavax.balanceOf(ALICE), 0, "testFuzz_SwapInFeesAmounts::2");
        assertEq(usdc.balanceOf(ALICE), amountOut, "testFuzz_SwapInFeesAmounts::3");

        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX,) = pairWavax.getProtocolFees();

        uint256 balanceX = wavax.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountIn - protocolFeeX, "testFuzz_SwapInFeesAmounts::4");
        assertEq(balanceY, amountY - amountOut, "testFuzz_SwapInFeesAmounts::5");
    }

    function testFuzz_SwapInY(uint128 amountOut) external {
        vm.assume(amountOut > 0 && amountOut <= 1e18);

        (uint128 amountIn, uint128 amountOutLeft,) = pairWavax.getSwapIn(amountOut, false);
        assertEq(amountOutLeft, 0, "testFuzz_SwapInFeesAmounts::1");

        deal(address(usdc), ALICE, amountIn);

        vm.prank(ALICE);
        usdc.transfer(address(pairWavax), amountIn);
        pairWavax.swap(false, ALICE);

        assertEq(usdc.balanceOf(ALICE), 0, "testFuzz_SwapInFeesAmounts::2");
        assertEq(wavax.balanceOf(ALICE), amountOut, "testFuzz_SwapInFeesAmounts::3");

        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);

        (, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        uint256 balanceX = wavax.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX - amountOut, "testFuzz_SwapInFeesAmounts::4");
        assertEq(balanceY, amountY + amountIn - protocolFeeY, "testFuzz_SwapInFeesAmounts::5");
    }

    function testFuzz_SwapOutX(uint128 amountIn) external {
        (uint128 amountInLeft, uint128 amountOut,) = pairWavax.getSwapOut(amountIn, true);
        vm.assume(amountOut > 0 && amountInLeft == 0);

        deal(address(wavax), ALICE, amountIn);

        vm.prank(ALICE);
        wavax.transfer(address(pairWavax), amountIn);
        pairWavax.swap(true, ALICE);

        assertEq(wavax.balanceOf(ALICE), 0, "testFuzz_SwapInFeesAmounts::2");
        assertEq(usdc.balanceOf(ALICE), amountOut, "testFuzz_SwapInFeesAmounts::3");

        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX,) = pairWavax.getProtocolFees();

        uint256 balanceX = wavax.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountIn - protocolFeeX, "testFuzz_SwapInFeesAmounts::4");
        assertEq(balanceY, amountY - amountOut, "testFuzz_SwapInFeesAmounts::5");
    }

    function testFuzz_SwapOutY(uint128 amountIn) external {
        (uint128 amountInLeft, uint128 amountOut,) = pairWavax.getSwapOut(amountIn, false);
        vm.assume(amountOut > 0 && amountInLeft == 0);

        deal(address(usdc), ALICE, amountIn);

        vm.prank(ALICE);
        usdc.transfer(address(pairWavax), amountIn);
        pairWavax.swap(false, ALICE);

        assertEq(usdc.balanceOf(ALICE), 0, "testFuzz_SwapInFeesAmounts::2");
        assertEq(wavax.balanceOf(ALICE), amountOut, "testFuzz_SwapInFeesAmounts::3");

        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);

        (, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        uint256 balanceX = wavax.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX - amountOut, "testFuzz_SwapInFeesAmounts::4");
        assertEq(balanceY, amountY + amountIn - protocolFeeY, "testFuzz_SwapInFeesAmounts::5");
    }

    function testFuzz_SwapInXAndY(uint128 amountXOut, uint128 amountYOut) external {
        vm.assume(amountXOut > 0 && amountXOut <= 1e18 && amountYOut > 0 && amountYOut <= 1e18);

        (uint128 amountXIn, uint128 amountYOutLeft,) = pairWavax.getSwapIn(amountYOut, true);
        assertEq(amountYOutLeft, 0, "testFuzz_SwapInFeesAmounts::1");

        deal(address(wavax), BOB, 1e36);
        deal(address(usdc), BOB, 1e36);

        vm.prank(BOB);
        wavax.transfer(address(pairWavax), amountXIn);
        pairWavax.swap(true, ALICE);

        assertEq(usdc.balanceOf(ALICE), amountYOut, "testFuzz_SwapInFeesAmounts::2");

        (uint128 amountYIn, uint128 amountXOutLeft,) = pairWavax.getSwapIn(amountXOut, false);
        assertEq(amountXOutLeft, 0, "testFuzz_SwapInFeesAmounts::3");

        vm.prank(BOB);
        usdc.transfer(address(pairWavax), amountYIn);
        pairWavax.swap(false, ALICE);

        uint256 realAmountXOut = wavax.balanceOf(ALICE);
        assertGe(realAmountXOut, amountXOut, "testFuzz_SwapInFeesAmounts::4");

        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        assertEq(wavax.balanceOf(address(pairWavax)), protocolFeeX, "testFuzz_SwapInFeesAmounts::5");
        assertEq(usdc.balanceOf(address(pairWavax)), protocolFeeY, "testFuzz_SwapInFeesAmounts::6");

        uint256 balanceX = wavax.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountXIn - realAmountXOut - protocolFeeX, "testFuzz_SwapInFeesAmounts::7");
        assertEq(balanceY, amountY + amountYIn - amountYOut - protocolFeeY, "testFuzz_SwapInFeesAmounts::8");
    }

    function testFuzz_SwapInYandX(uint128 amountYOut, uint128 amountXOut) external {
        vm.assume(amountXOut > 0 && amountXOut <= 1e18 && amountYOut > 0 && amountYOut <= 1e18);

        (uint128 amountYIn, uint128 amountXOutLeft,) = pairWavax.getSwapIn(amountXOut, false);
        assertEq(amountXOutLeft, 0, "testFuzz_SwapInFeesAmounts::1");

        deal(address(wavax), BOB, 1e36);
        deal(address(usdc), BOB, 1e36);

        vm.prank(BOB);
        usdc.transfer(address(pairWavax), amountYIn);
        pairWavax.swap(false, ALICE);

        assertEq(wavax.balanceOf(ALICE), amountXOut, "testFuzz_SwapInFeesAmounts::2");

        (uint128 amountXIn, uint128 amountYOutLeft,) = pairWavax.getSwapIn(amountYOut, true);
        assertEq(amountYOutLeft, 0, "testFuzz_SwapInFeesAmounts::3");

        vm.prank(BOB);
        wavax.transfer(address(pairWavax), amountXIn);
        pairWavax.swap(true, ALICE);

        uint256 realAmountYOut = usdc.balanceOf(ALICE);
        assertGe(realAmountYOut, amountYOut, "testFuzz_SwapInFeesAmounts::4");

        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        assertEq(wavax.balanceOf(address(pairWavax)), protocolFeeX, "testFuzz_SwapInFeesAmounts::5");
        assertEq(usdc.balanceOf(address(pairWavax)), protocolFeeY, "testFuzz_SwapInFeesAmounts::6");

        uint256 balanceX = wavax.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountXIn - amountXOut - protocolFeeX, "testFuzz_SwapInFeesAmounts::7");
        assertEq(balanceY, amountY + amountYIn - realAmountYOut - protocolFeeY, "testFuzz_SwapInFeesAmounts::8");
    }

    function testFuzz_SwapOutXAndY(uint128 amountXIn, uint128 amountYIn) external {
        (uint128 amountXInLeft, uint128 amountYOut,) = pairWavax.getSwapOut(amountXIn, true);
        vm.assume(amountXInLeft == 0 && amountYOut > 0);

        deal(address(wavax), BOB, 1e36);
        deal(address(usdc), BOB, 1e36);

        vm.prank(BOB);
        wavax.transfer(address(pairWavax), amountXIn);
        pairWavax.swap(true, ALICE);

        assertEq(usdc.balanceOf(ALICE), amountYOut, "testFuzz_SwapInFeesAmounts::1");

        (uint128 amountYInLeft, uint128 amountXOut,) = pairWavax.getSwapOut(amountYIn, false);
        vm.assume(amountYInLeft == 0 && amountXOut > 0);

        vm.prank(BOB);
        usdc.transfer(address(pairWavax), amountYIn);
        pairWavax.swap(false, ALICE);

        uint256 realAmountXOut = wavax.balanceOf(ALICE);
        assertGe(realAmountXOut, amountXOut, "testFuzz_SwapInFeesAmounts::2");

        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        assertEq(wavax.balanceOf(address(pairWavax)), protocolFeeX, "testFuzz_SwapInFeesAmounts::3");
        assertEq(usdc.balanceOf(address(pairWavax)), protocolFeeY, "testFuzz_SwapInFeesAmounts::4");

        uint256 balanceX = wavax.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountXIn - realAmountXOut - protocolFeeX, "testFuzz_SwapInFeesAmounts::5");
        assertEq(balanceY, amountY + amountYIn - amountYOut - protocolFeeY, "testFuzz_SwapInFeesAmounts::6");
    }

    function testFuzz_SwapOutYAndX(uint128 amountXIn, uint128 amountYIn) external {
        (uint128 amountYInLeft, uint128 amountXOut,) = pairWavax.getSwapOut(amountYIn, false);
        vm.assume(amountYInLeft == 0 && amountXOut > 0);

        deal(address(wavax), BOB, 1e36);
        deal(address(usdc), BOB, 1e36);

        vm.prank(BOB);
        usdc.transfer(address(pairWavax), amountYIn);
        pairWavax.swap(false, ALICE);

        assertEq(wavax.balanceOf(ALICE), amountXOut, "testFuzz_SwapInFeesAmounts::1");

        (uint128 amountXInLeft, uint128 amountYOut,) = pairWavax.getSwapOut(amountXIn, true);
        vm.assume(amountXInLeft == 0 && amountYOut > 0);

        vm.prank(BOB);
        wavax.transfer(address(pairWavax), amountXIn);
        pairWavax.swap(true, ALICE);

        uint256 realAmountYOut = usdc.balanceOf(ALICE);
        assertGe(realAmountYOut, amountYOut, "testFuzz_SwapInFeesAmounts::2");

        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        assertEq(wavax.balanceOf(address(pairWavax)), protocolFeeX, "testFuzz_SwapInFeesAmounts::3");
        assertEq(usdc.balanceOf(address(pairWavax)), protocolFeeY, "testFuzz_SwapInFeesAmounts::4");

        uint256 balanceX = wavax.balanceOf(DEV);
        uint256 balanceY = usdc.balanceOf(DEV);

        assertEq(balanceX, amountX + amountXIn - amountXOut - protocolFeeX, "testFuzz_SwapInFeesAmounts::5");
        assertEq(balanceY, amountY + amountYIn - realAmountYOut - protocolFeeY, "testFuzz_SwapInFeesAmounts::6");
    }

    function test_FeesX2LP() external {
        addLiquidity(ALICE, ALICE, pairWavax, ID_ONE, amountX, amountY, 10, 10);

        uint128 amountXIn = 1e18;
        (, uint128 amountYOut,) = pairWavax.getSwapOut(amountXIn, true);

        deal(address(wavax), BOB, amountXIn);

        vm.prank(BOB);
        wavax.transfer(address(pairWavax), amountXIn);
        pairWavax.swap(true, BOB);

        removeLiquidity(ALICE, ALICE, pairWavax, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        assertApproxEqAbs(
            wavax.balanceOf(address(ALICE)), amountX + (amountXIn - protocolFeeX) / 2, 2, "test_FeesX2LP::1"
        );
        assertApproxEqAbs(
            usdc.balanceOf(address(ALICE)), amountY - (amountYOut + protocolFeeY) / 2, 2, "test_FeesX2LP::2"
        );

        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);

        assertApproxEqAbs(
            wavax.balanceOf(address(DEV)), amountX + (amountXIn - protocolFeeX) / 2, 2, "test_FeesX2LP::3"
        );
        assertApproxEqAbs(
            usdc.balanceOf(address(DEV)), amountY - (amountYOut + protocolFeeY) / 2, 2, "test_FeesX2LP::4"
        );
    }

    function test_FeesY2LP() external {
        addLiquidity(ALICE, ALICE, pairWavax, ID_ONE, amountX, amountY, 10, 10);

        uint128 amountYIn = 1e18;
        (, uint128 amountXOut,) = pairWavax.getSwapOut(amountYIn, false);

        deal(address(usdc), BOB, amountYIn);

        vm.prank(BOB);
        usdc.transfer(address(pairWavax), amountYIn);
        pairWavax.swap(false, BOB);

        removeLiquidity(ALICE, ALICE, pairWavax, ID_ONE, 1e18, 10, 10);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        assertApproxEqAbs(
            wavax.balanceOf(address(ALICE)), amountX - (amountXOut + protocolFeeX) / 2, 2, "test_FeesY2LP::1"
        );
        assertApproxEqAbs(
            usdc.balanceOf(address(ALICE)), amountY + (amountYIn - protocolFeeY) / 2, 2, "test_FeesY2LP::2"
        );

        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);

        assertApproxEqAbs(
            wavax.balanceOf(address(DEV)), amountX - (amountXOut + protocolFeeX) / 2, 2, "test_FeesY2LP::3"
        );
        assertApproxEqAbs(usdc.balanceOf(address(DEV)), amountY + (amountYIn - protocolFeeY) / 2, 2, "test_FeesY2LP::4");
    }

    function test_Fees2LPFlashloan() external {
        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 10, 10);
        addLiquidity(DEV, DEV, pairWavax, ID_ONE, amountX, amountY, 1, 1);

        FlashBorrower borrower = new FlashBorrower(pairWavax);

        deal(address(wavax), address(borrower), 2e18);
        deal(address(usdc), address(borrower), 2e18);

        (uint128 feeX1, uint128 feeY1) = (1e18 + 1, 1e18);

        vm.prank(address(borrower));
        pairWavax.flashLoan(borrower, bytes32(uint256(1)), abi.encode(feeX1, feeY1, Constants.CALLBACK_SUCCESS, 0));

        (uint128 protocolFeeX1, uint128 protocolFeeY1) = pairWavax.getProtocolFees();
        (feeX1, feeY1) = (feeX1 - protocolFeeX1, feeY1 - protocolFeeY1);

        addLiquidity(ALICE, ALICE, pairWavax, ID_ONE, amountX, amountY, 1, 1);

        (uint128 feeX2, uint128 feeY2) = (1e18 + 1, 1e18);

        vm.prank(address(borrower));
        pairWavax.flashLoan(borrower, bytes32(uint256(1)), abi.encode(feeX2, feeY2, Constants.CALLBACK_SUCCESS, 0));

        {
            (uint128 protocolFeeX2, uint128 protocolFeeY2) = pairWavax.getProtocolFees();
            (feeX2, feeY2) = (feeX2 - (protocolFeeX2 - protocolFeeX1), feeY2 - (protocolFeeY2 - protocolFeeY1));
        }

        (uint256 shareAlice, uint256 shareDev) =
            (pairWavax.balanceOf(address(ALICE), ID_ONE), pairWavax.balanceOf(address(DEV), ID_ONE));

        removeLiquidity(ALICE, ALICE, pairWavax, ID_ONE, 1e18, 1, 1);
        removeLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 1, 1);

        assertApproxEqAbs(
            wavax.balanceOf(address(ALICE)),
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
            wavax.balanceOf(address(DEV)),
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
        FlashBorrower borrower = new FlashBorrower(pairWavax);

        deal(address(wavax), address(borrower), 1e36);
        deal(address(usdc), address(borrower), 1e36);

        vm.prank(address(borrower));
        pairWavax.flashLoan(borrower, uint128(1).encode(0), abi.encode(1e18 + 1, 0, Constants.CALLBACK_SUCCESS, 0));

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        address feeRecipient = factory.getFeeRecipient();

        vm.prank(feeRecipient);
        pairWavax.collectProtocolFees();

        assertEq(wavax.balanceOf(feeRecipient), protocolFeeX - 1, "test_CollectProtocolFees::1");
        assertEq(usdc.balanceOf(feeRecipient), 0, "test_CollectProtocolFees::2");

        (protocolFeeX, protocolFeeY) = pairWavax.getProtocolFees();

        assertEq(protocolFeeX, 1, "test_CollectProtocolFees::3");
        assertEq(protocolFeeY, 0, "test_CollectProtocolFees::4");
    }

    function test_CollectProtocolFeesYTokens() external {
        FlashBorrower borrower = new FlashBorrower(pairWavax);

        deal(address(wavax), address(borrower), 1e36);
        deal(address(usdc), address(borrower), 1e36);

        vm.prank(address(borrower));
        pairWavax.flashLoan(borrower, uint128(0).encode(1), abi.encode(0, 1e18 + 1, Constants.CALLBACK_SUCCESS, 0));

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        address feeRecipient = factory.getFeeRecipient();

        vm.prank(feeRecipient);
        pairWavax.collectProtocolFees();

        assertEq(wavax.balanceOf(feeRecipient), 0, "test_CollectProtocolFees::1");
        assertEq(usdc.balanceOf(feeRecipient), protocolFeeY - 1, "test_CollectProtocolFees::2");

        (protocolFeeX, protocolFeeY) = pairWavax.getProtocolFees();

        assertEq(protocolFeeX, 0, "test_CollectProtocolFees::3");
        assertEq(protocolFeeY, 1, "test_CollectProtocolFees::4");
    }

    function test_CollectProtocolFeesBothTokens() external {
        FlashBorrower borrower = new FlashBorrower(pairWavax);

        deal(address(wavax), address(borrower), 1e36);
        deal(address(usdc), address(borrower), 1e36);

        vm.prank(address(borrower));
        pairWavax.flashLoan(
            borrower, uint128(1).encode(1), abi.encode(1e18 + 1, 1e18 + 1, Constants.CALLBACK_SUCCESS, 0)
        );

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWavax.getProtocolFees();

        address feeRecipient = factory.getFeeRecipient();

        vm.prank(feeRecipient);
        pairWavax.collectProtocolFees();

        assertEq(wavax.balanceOf(feeRecipient), protocolFeeX - 1, "test_CollectProtocolFees::1");
        assertEq(usdc.balanceOf(feeRecipient), protocolFeeY - 1, "test_CollectProtocolFees::2");

        (protocolFeeX, protocolFeeY) = pairWavax.getProtocolFees();

        assertEq(protocolFeeX, 1, "test_CollectProtocolFees::3");
        assertEq(protocolFeeY, 1, "test_CollectProtocolFees::4");
    }

    function test_CollectProtocolFeesAfterSwap() external {
        deal(address(wavax), address(BOB), 1e18);

        vm.prank(BOB);
        wavax.transfer(address(pairWavax), 1e18);
        pairWavax.swap(true, BOB);

        (uint128 protocolFeeX, uint128 protocolFeeY) = pairWavax.getProtocolFees();
        uint128 previousProtocolFeeX = protocolFeeX;

        assertGt(protocolFeeX, 0, "test_CollectProtocolFees::1");
        assertEq(protocolFeeY, 0, "test_CollectProtocolFees::2");

        (uint128 reserveX, uint128 reserveY) = pairWavax.getReserves();

        address feeRecipient = factory.getFeeRecipient();

        vm.prank(feeRecipient);
        pairWavax.collectProtocolFees();

        (uint128 reserveXAfter, uint128 reserveYAfter) = pairWavax.getReserves();

        assertEq(reserveXAfter, reserveX, "test_CollectProtocolFees::3");
        assertEq(reserveYAfter, reserveY, "test_CollectProtocolFees::4");

        assertEq(wavax.balanceOf(feeRecipient), protocolFeeX - 1, "test_CollectProtocolFees::5");
        assertEq(usdc.balanceOf(feeRecipient), 0, "test_CollectProtocolFees::6");

        (protocolFeeX, protocolFeeY) = pairWavax.getProtocolFees();

        assertEq(protocolFeeX, 1, "test_CollectProtocolFees::7");
        assertEq(protocolFeeY, 0, "test_CollectProtocolFees::8");

        deal(address(usdc), address(BOB), 1e18);

        vm.prank(BOB);
        usdc.transfer(address(pairWavax), 1e18);
        pairWavax.swap(false, BOB);

        (protocolFeeX, protocolFeeY) = pairWavax.getProtocolFees();
        uint128 previousProtocolFeeY = protocolFeeY;

        assertEq(protocolFeeX, 1, "test_CollectProtocolFees::9");
        assertGt(protocolFeeY, 0, "test_CollectProtocolFees::10");

        (reserveX, reserveY) = pairWavax.getReserves();

        vm.prank(feeRecipient);
        pairWavax.collectProtocolFees();

        (reserveXAfter, reserveYAfter) = pairWavax.getReserves();

        assertEq(reserveXAfter, reserveX, "test_CollectProtocolFees::11");
        assertEq(reserveYAfter, reserveY, "test_CollectProtocolFees::12");

        assertEq(wavax.balanceOf(feeRecipient), previousProtocolFeeX - 1, "test_CollectProtocolFees::13");
        assertEq(usdc.balanceOf(feeRecipient), protocolFeeY - 1, "test_CollectProtocolFees::14");

        (protocolFeeX, protocolFeeY) = pairWavax.getProtocolFees();

        assertEq(protocolFeeX, 1, "test_CollectProtocolFees::15");
        assertEq(protocolFeeY, 1, "test_CollectProtocolFees::16");

        vm.prank(feeRecipient);
        pairWavax.collectProtocolFees();

        assertEq(wavax.balanceOf(feeRecipient), previousProtocolFeeX - 1, "test_CollectProtocolFees::19");
        assertEq(usdc.balanceOf(feeRecipient), previousProtocolFeeY - 1, "test_CollectProtocolFees::20");
    }

    function test_revert_TotalFeeExceeded(
        uint8 binStep,
        uint16 baseFactor,
        uint24 variableFeeControl,
        uint24 maxVolatilityAccumulator
    ) external {
        vm.assume(maxVolatilityAccumulator <= Encoded.MASK_UINT20);

        uint256 baseFee = uint256(baseFactor) * binStep * 5e9;
        uint256 varFee = ((uint256(binStep) * maxVolatilityAccumulator) ** 2 * variableFeeControl + 399) / 400;

        vm.assume(baseFee + varFee > 1e17);

        bytes memory data = abi.encodePacked(wavax, usdc, binStep);

        pairWavax = LBPair(ImmutableClone.cloneDeterministic(address(pairImplementation), data, keccak256(data)));

        vm.expectRevert(ILBPair.LBPair__MaxTotalFeeExceeded.selector);
        vm.prank(address(factory));
        pairWavax.setStaticFeeParameters(baseFactor, 1, 1, 1, variableFeeControl, 1, maxVolatilityAccumulator);
    }
}
