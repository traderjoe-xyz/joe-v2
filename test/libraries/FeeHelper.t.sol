// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/libraries/FeeHelper.sol";
import "../../src/libraries/math/Uint256x256Math.sol";

contract FeeHelperTest is Test {
    using FeeHelper for uint128;
    using Uint256x256Math for uint256;

    function testFuzz_GetFeeAmountFrom(uint128 amountWithFee, uint128 fee) external {
        if (fee > Constants.MAX_FEE) {
            vm.expectRevert(FeeHelper.FeeHelper__FeeTooLarge.selector);
            amountWithFee.getFeeAmountFrom(fee);
        } else {
            uint256 expectedFeeAmount = (uint256(amountWithFee) * fee + 1e18 - 1) / 1e18;
            uint128 feeAmount = amountWithFee.getFeeAmountFrom(fee);

            assertEq(feeAmount, expectedFeeAmount, "testFuzz_GetFeeAmountFrom::1");
        }
    }

    function testFuzz_GetFeeAmount(uint128 amount, uint128 fee) external {
        if (fee > Constants.MAX_FEE) {
            vm.expectRevert(FeeHelper.FeeHelper__FeeTooLarge.selector);
            amount.getFeeAmount(fee);
        } else {
            uint128 denominator = 1e18 - fee;
            uint256 expectedFeeAmount = (uint256(amount) * fee + denominator - 1) / denominator;

            uint128 feeAmount = amount.getFeeAmount(fee);

            assertEq(feeAmount, expectedFeeAmount, "testFuzz_GetFeeAmount::1");
        }
    }

    function testFuzz_GetCompositionFee(uint128 amountWithFee, uint128 fee) external {
        if (fee > Constants.MAX_FEE) {
            vm.expectRevert(FeeHelper.FeeHelper__FeeTooLarge.selector);
            amountWithFee.getCompositionFee(fee);
        }

        uint256 denominator = 1e36;
        uint256 expectedCompositionFee =
            (uint256(amountWithFee) * fee).mulDivRoundDown(uint256(fee) + 1e18, denominator);

        uint128 compositionFee = amountWithFee.getCompositionFee(fee);

        assertEq(compositionFee, expectedCompositionFee, "testFuzz_GetCompositionFee::1");
    }

    function testFuzz_GetProtocolFeeAmount(uint128 amount, uint128 fee) external {
        if (fee > Constants.MAX_PROTOCOL_SHARE) {
            vm.expectRevert(FeeHelper.FeeHelper__ProtocolShareTooLarge.selector);
            amount.getProtocolFeeAmount(fee);
        } else {
            uint256 expectedProtocolFeeAmount = (uint256(amount) * fee) / 1e4;
            uint128 protocolFeeAmount = amount.getProtocolFeeAmount(fee);

            assertEq(protocolFeeAmount, expectedProtocolFeeAmount, "testFuzz_GetProtocolFeeAmount::1");
        }
    }
}
