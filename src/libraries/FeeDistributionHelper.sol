// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "../LBErrors.sol";
import "./Constants.sol";
import "./FeeHelper.sol";

/// @title Liquidity Book Fee Distribution Helper Library
/// @author Trader Joe
/// @notice Helper contract used for fees distribution calculations
library FeeDistributionHelper {
    /// @notice Calculate the tokenPerShare when fees are added
    /// @param _fees The fees received by the pair
    /// @param _totalSupply the total supply of a specific bin
    function getTokenPerShare(FeeHelper.FeesDistribution memory _fees, uint256 _totalSupply)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            // This can't overflow as `totalFees >= protocolFees`,
            // shift can't overflow as we shift fees that are a uint128, by 128 bits.
            // The result will always be smaller than max(uint256)
            return ((uint256(_fees.total) - _fees.protocol) << Constants.SCALE_OFFSET) / _totalSupply;
        }
    }
}
