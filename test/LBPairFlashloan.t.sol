// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./helpers/TestHelper.sol";

import "./mocks/FlashBorrower.sol";

contract LBPairFlashloanTest is TestHelper {
    using SafeCast for uint256;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;

    FlashBorrower borrower;

    function setUp() public override {
        super.setUp();

        pairWavax = createLBPair(wavax, usdc);

        addLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 1e18, 50, 50);

        borrower = new FlashBorrower(pairWavax);

        // Make sure the borrower can pay back the flash loan
        deal(address(wavax), address(borrower), 1e18);
        deal(address(usdc), address(borrower), 1e18);
    }

    function testFuzz_FlashLoan(uint128 amountX, uint128 amountY) external {
        vm.assume(amountX <= 1e18 && amountY <= 1e18 && (amountX > 0 || amountY > 0));

        bytes32 amountsBorrowed = amountX.encode(amountY);
        bytes memory data = abi.encode(type(uint128).max, type(uint128).max, Constants.CALLBACK_SUCCESS, 0);

        uint256 balanceX = wavax.balanceOf(address(pairWavax));
        uint256 balanceY = usdc.balanceOf(address(pairWavax));

        uint256 flashLoanFee = factory.getFlashLoanFee();

        uint256 feeX = (amountX * flashLoanFee + 1e18 - 1) / 1e18;
        uint256 feeY = (amountY * flashLoanFee + 1e18 - 1) / 1e18;

        pairWavax.flashLoan(borrower, amountsBorrowed, data);

        assertEq(wavax.balanceOf(address(pairWavax)), balanceX + feeX, "TestFuzz_Flashloan::1");
        assertEq(usdc.balanceOf(address(pairWavax)), balanceY + feeY, "TestFuzz_Flashloan::2");

        (uint256 reserveX, uint256 reserveY) = pairWavax.getReserves();
        (uint256 protocolFeeX, uint256 protocolFeeY) = pairWavax.getProtocolFees();

        assertEq(reserveX + protocolFeeX, balanceX + feeX, "TestFuzz_Flashloan::3");
        assertEq(reserveY + protocolFeeY, balanceY + feeY, "TestFuzz_Flashloan::4");
    }

    function testFuzz_revert_FlashLoanInsufficientAmount(uint128 amountX, uint128 amountY) external {
        vm.assume(amountX > 0 && amountY > 0 && amountX <= 1e18 && amountY <= 1e18);

        uint256 flashLoanFee = factory.getFlashLoanFee();

        uint256 feeX = (amountX * flashLoanFee + 1e18 - 1) / 1e18;
        uint256 feeY = (amountY * flashLoanFee + 1e18 - 1) / 1e18;

        bytes32 amountsBorrowed = amountX.encode(amountY);
        bytes memory data = abi.encode(amountX + feeX - 1, amountY + feeY, Constants.CALLBACK_SUCCESS, 0);

        vm.expectRevert(ILBPair.LBPair__FlashLoanInsufficientAmount.selector);
        pairWavax.flashLoan(borrower, amountsBorrowed, data);

        data = abi.encode(amountX + feeX, amountY + feeY - 1, Constants.CALLBACK_SUCCESS, 0);

        vm.expectRevert(ILBPair.LBPair__FlashLoanInsufficientAmount.selector);
        pairWavax.flashLoan(borrower, amountsBorrowed, data);

        data = abi.encode(amountX + feeX - 1, amountY + feeY - 1, Constants.CALLBACK_SUCCESS, 0);

        vm.expectRevert(ILBPair.LBPair__FlashLoanInsufficientAmount.selector);
        pairWavax.flashLoan(borrower, amountsBorrowed, data);
    }

    function testFuzz_revert_FlashLoanCallbackFailed(bytes32 callback) external {
        vm.assume(callback != Constants.CALLBACK_SUCCESS);

        bytes32 amountsBorrowed = bytes32(uint256(1));
        bytes memory data = abi.encode(0, 0, callback, 0);

        vm.expectRevert(ILBPair.LBPair__FlashLoanCallbackFailed.selector);
        pairWavax.flashLoan(borrower, amountsBorrowed, data);
    }

    function testFuzz_revert_FlashLoanReentrant(bytes32 callback) external {
        vm.assume(callback != Constants.CALLBACK_SUCCESS);

        bytes32 amountsBorrowed = bytes32(uint256(1));
        bytes memory data = abi.encode(0, 0, callback, 1);

        vm.expectRevert(ReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        pairWavax.flashLoan(borrower, amountsBorrowed, data);
    }

    function test_revert_FlashLoan0Amounts() external {
        vm.expectRevert(ILBPair.LBPair__ZeroBorrowAmount.selector);
        pairWavax.flashLoan(borrower, 0, "");
    }
}
