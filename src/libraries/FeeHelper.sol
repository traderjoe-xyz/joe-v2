// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Constants.sol";
import "./math/SafeCast.sol";

/**
 * @title Liquidity Book Fee Helper Library
 * @author Trader Joe
 * @notice This library contains functions to calculate fees
 */
library FeeHelper {
    using SafeCast for uint256;

    /**
     * @dev Calculates the fee amount from the amount with fees
     * @param amounWithFees The amount with fees
     * @param totalFee The total fee
     * @return feeAmount The fee amount
     */
    function getFeeAmountFrom(uint128 amounWithFees, uint256 totalFee) internal pure returns (uint128) {
        unchecked {
            return ((uint256(amounWithFees) * totalFee + Constants.PRECISION - 1) / Constants.PRECISION).safe128();
        }
    }

    /**
     * @dev Calculates the fee amount that will be charged
     * @param amount The amount
     * @param totalFee The total fee
     * @return feeAmount The fee amount
     */
    function getFeeAmount(uint128 amount, uint256 totalFee) internal pure returns (uint128) {
        unchecked {
            uint256 denominator = Constants.PRECISION - totalFee;
            return ((uint256(amount) * totalFee + denominator - 1) / denominator).safe128();
        }
    }

    /**
     * @dev Calculates the composition fee amount from the amount with fees
     * @param amountWithFees The amount with fees
     * @param totalFee The total fee
     * @return The amount with fees
     */
    function getCompositionFee(uint128 amountWithFees, uint256 totalFee) internal pure returns (uint128) {
        unchecked {
            uint256 denominator = Constants.PRECISION * Constants.PRECISION;
            return (uint256(amountWithFees) * totalFee * (totalFee + Constants.PRECISION) / denominator).safe128();
        }
    }

    /**
     * @dev Calculates the protocol fee amount from the fee amount and the protocol share
     * @param feeAmount The fee amount
     * @param protocolShare The protocol share
     * @return protocolFeeAmount The protocol fee amount
     */
    function getProtocolFeeAmount(uint128 feeAmount, uint128 protocolShare) internal pure returns (uint128) {
        unchecked {
            return (uint256(feeAmount) * protocolShare / Constants.BASIS_POINT_MAX).safe128();
        }
    }
}
