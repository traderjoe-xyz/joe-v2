// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {Constants} from "./Constants.sol";
import {SafeCast} from "./math/SafeCast.sol";

/**
 * @title Liquidity Book Fee Helper Library
 * @author Trader Joe
 * @notice This library contains functions to calculate fees
 */
library FeeHelper {
    using SafeCast for uint256;

    error FeeHelper__FeeOverflow();
    error FeeHelper__ProtocolShareOverflow();

    /**
     * @dev Modifier to check that the fee does not overflow
     * @param fee The fee
     */
    modifier checkFeeOverflow(uint128 fee) {
        if (fee > Constants.MAX_FEE) revert FeeHelper__FeeOverflow();
        _;
    }

    /**
     * @dev Modifier to check that the protocol share does not overflow
     * @param protocolShare The protocol share
     */
    modifier checkProtocolShareOverflow(uint128 protocolShare) {
        if (protocolShare > Constants.MAX_PROTOCOL_SHARE) revert FeeHelper__ProtocolShareOverflow();
        _;
    }

    /**
     * @dev Calculates the fee amount from the amount with fees, rounding up
     * @param amounWithFees The amount with fees
     * @param totalFee The total fee
     * @return feeAmount The fee amount
     */
    function getFeeAmountFrom(uint128 amounWithFees, uint128 totalFee)
        internal
        pure
        checkFeeOverflow(totalFee)
        returns (uint128)
    {
        unchecked {
            // Can't overflow, max(result) = (type(uint128).max * 0.1e18 + 1e18 - 1) / 1e18 < 2^128
            return uint128((uint256(amounWithFees) * totalFee + Constants.PRECISION - 1) / Constants.PRECISION);
        }
    }

    /**
     * @dev Calculates the fee amount that will be charged, rounding up
     * @param amount The amount
     * @param totalFee The total fee
     * @return feeAmount The fee amount
     */
    function getFeeAmount(uint128 amount, uint128 totalFee)
        internal
        pure
        checkFeeOverflow(totalFee)
        returns (uint128)
    {
        unchecked {
            uint256 denominator = Constants.PRECISION - totalFee;
            // Can't overflow, max(result) = (type(uint128).max * 0.1e18 + (1e18 - 1)) / 0.9e18 < 2^128
            return uint128((uint256(amount) * totalFee + denominator - 1) / denominator);
        }
    }

    /**
     * @dev Calculates the composition fee amount from the amount with fees, rounding down
     * @param amountWithFees The amount with fees
     * @param totalFee The total fee
     * @return The amount with fees
     */
    function getCompositionFee(uint128 amountWithFees, uint128 totalFee)
        internal
        pure
        checkFeeOverflow(totalFee)
        returns (uint128)
    {
        unchecked {
            uint256 denominator = Constants.SQUARED_PRECISION;
            // Can't overflow, max(result) = type(uint128).max * 0.1e18 * 1.1e18 / 1e36 <= 2^128 * 0.11e36 / 1e36 < 2^128
            return uint128(uint256(amountWithFees) * totalFee * (uint256(totalFee) + Constants.PRECISION) / denominator);
        }
    }

    /**
     * @dev Calculates the protocol fee amount from the fee amount and the protocol share, rounding down
     * @param feeAmount The fee amount
     * @param protocolShare The protocol share
     * @return protocolFeeAmount The protocol fee amount
     */
    function getProtocolFeeAmount(uint128 feeAmount, uint128 protocolShare)
        internal
        pure
        checkProtocolShareOverflow(protocolShare)
        returns (uint128)
    {
        unchecked {
            return uint128(uint256(feeAmount) * protocolShare / Constants.BASIS_POINT_MAX);
        }
    }
}
