// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./FeeHelper.sol";
import "./Constants.sol";
import "./TokenHelper.sol";
import "./SafeCast.sol";

error FeeDistributionHelper__FlashLoanUnderflow(uint256 expectedBalance, uint256 balance);

library FeeDistributionHelper {
    using TokenHelper for IERC20;
    using SafeCast for uint256;

    /// @notice Checks that the flash loan was done accordingly and update fees
    /// @param _fees The fees received by the pair
    /// @param _pairFees The fees of the pair
    /// @param _token The address of the token received
    /// @param _reserve The stored reserve of the current bin
    function flashLoanHelper(
        FeeHelper.FeesDistribution memory _fees,
        FeeHelper.FeesDistribution storage _pairFees,
        IERC20 _token,
        uint256 _reserve
    ) internal {
        uint128 _totalFees = _pairFees.total;
        uint256 _amountReceived = _token.received(_reserve, _totalFees);

        if (_fees.total > _amountReceived)
            revert FeeDistributionHelper__FlashLoanUnderflow(_fees.total, _amountReceived);

        _fees.total = _amountReceived.safe128();

        _pairFees.total = _totalFees + _fees.total;
        // unsafe math is fine because total >= protocol
        unchecked {
            _pairFees.protocol += _fees.protocol;
        }
    }

    function getTokenPerShare(FeeHelper.FeesDistribution memory _fees, uint256 _totalSupply)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            return (uint256(_fees.total - _fees.protocol) << Constants.SCALE_OFFSET) / _totalSupply;
        }
    }
}
