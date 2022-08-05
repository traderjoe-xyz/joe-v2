// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./SafeCast.sol";
import "./Constants.sol";

library FeeHelper {
    using SafeCast for uint256;

    /// @dev Structure to store the protocol fees:
    /// - binStep: The bin step
    /// - baseFactor: The base factor
    /// - filterPeriod: The filter period, where the fees stays constant
    /// - decayPeriod: The decay period, where the fees are halved
    /// - reductionFactor: The reduction factor, used to calculate the reduction of the accumulator
    /// - variableFeeControl: The variable fee control, used to control the variable fee, can be 0 to disable them
    /// - protocolShare: The share of fees sent to protocol
    /// - maxAccumulator: The max value of the accumulator
    /// - accumulator: The value of the accumulator
    /// - time: The last time the accumulator was called
    struct FeeParameters {
        uint8 binStep;
        uint8 baseFactor;
        uint16 filterPeriod;
        uint16 decayPeriod;
        uint8 reductionFactor;
        uint8 variableFeeControl;
        uint8 protocolShare;
        uint72 maxAccumulator;
        uint72 accumulator;
        uint40 time;
    }

    /// @dev Structure used during swaps to distributes the fees:
    /// - total: The total amount of fees
    /// - protocol: The amount of fees reserved for protocol
    struct FeesDistribution {
        uint128 total;
        uint128 protocol;
    }

    /// @notice Update the value of the accumulator
    /// @param _fp The current fee parameters
    function updateAccumulatorValue(FeeParameters memory _fp) internal view {
        unchecked {
            uint256 deltaT = block.timestamp - _fp.time;

            uint256 _accumulator; // Can't overflow as _accumulator <= _fp.accumulator <= _fp.maxAccumulator < 2**72
            if (deltaT < _fp.filterPeriod) {
                _accumulator = _fp.accumulator;
            } else if (deltaT < _fp.decayPeriod) {
                _accumulator = (_fp.accumulator * _fp.reductionFactor) / Constants.HUNDRED_PERCENT;
            } // else _accumulator = 0;

            _fp.accumulator = uint72(_accumulator);
        }
    }

    /// @notice Update the accumulator and the timestamp
    /// @param _fp The fee parameter
    /// @param _binCrossed The current number of bin crossed
    function updateFeeParameters(FeeParameters memory _fp, uint256 _binCrossed) internal view {
        unchecked {
            // This equation can't overflow
            uint256 _accumulator = uint256(_fp.accumulator) + _binCrossed * Constants.BASIS_POINT_MAX;

            if (_accumulator > uint256(_fp.maxAccumulator)) _accumulator = _fp.maxAccumulator;

            _fp.accumulator = _accumulator.safe72();
            _fp.time = block.timestamp.safe40();
        }
    }

    /// @notice Returns the base fee added to a swap, with 18 decimals
    /// @param _fp The current fee parameters
    /// @return The fee in basis point squared
    function getBaseFee(FeeParameters memory _fp) internal pure returns (uint256) {
        unchecked {
            return uint256(_fp.baseFactor) * _fp.binStep * 1e12;
        }
    }

    /// @notice Returns the variable fee added to a swap, with 18 decimals
    /// @param _fp The current fee parameters
    /// @param _binCrossed The current number of bin crossed
    /// @return The variable fee in basis point squared
    function getVariableFee(FeeParameters memory _fp, uint256 _binCrossed) internal pure returns (uint256) {
        unchecked {
            if (_fp.reductionFactor == 0) return 0;

            uint256 _acc = _fp.accumulator + _binCrossed * Constants.BASIS_POINT_MAX;

            if (_acc > _fp.maxAccumulator) _acc = _fp.maxAccumulator;

            // decimals(_fp.reductionFactor * (_acc * _fp.binStep)**2) = 2 + (4 + 4) * 2 = 18
            return (_fp.reductionFactor * ((_acc * _fp.binStep) * (_acc * _fp.binStep)));
        }
    }

    /// @notice Return the fees added to an amount
    /// @param _fp The current fee parameter
    /// @param _amount The amount of token sent
    /// @param _binCrossed The current number of bin crossed
    /// @return The fee amount
    function getFees(
        FeeParameters memory _fp,
        uint256 _amount,
        uint256 _binCrossed
    ) internal pure returns (uint256) {
        unchecked {
            uint256 _feeShares = getFeeShares(_fp, _binCrossed);
            return (_amount * _feeShares) / (Constants.PRECISION);
        }
    }

    /// @notice Return the fees from an amount
    /// @param _fp The current fee parameter
    /// @param _amountPlusFee The amount of token sent
    /// @param _binCrossed The current number of bin crossed
    /// @return The fee amount
    function getFeesFrom(
        FeeParameters memory _fp,
        uint256 _amountPlusFee,
        uint256 _binCrossed
    ) internal pure returns (uint256) {
        unchecked {
            uint256 _feeShares = getFeeShares(_fp, _binCrossed);
            return (_amountPlusFee * _feeShares) / (Constants.PRECISION + _feeShares);
        }
    }

    /// @notice Return the fees added when an user adds liquidity and change c in the active bin
    /// @param _fp The current fee parameter
    /// @param _amountPlusFee The amount of token sent
    /// @return The fee amount
    function getFeesForC(
        FeeParameters memory _fp,
        uint256 _amountPlusFee,
        uint256 _binCrossed
    ) internal pure returns (uint256) {
        unchecked {
            uint256 _feeShares = getFeeShares(_fp, _binCrossed);
            return
                (_amountPlusFee * _feeShares * (_feeShares + Constants.PRECISION)) /
                (Constants.PRECISION * Constants.PRECISION);
        }
    }

    /// @notice Return the fees distribution added to an amount
    /// @param _fp The current fee parameter
    /// @param _fees The fee amount
    /// @return fees The fee distribution
    function getFeesDistribution(FeeParameters memory _fp, uint256 _fees)
        internal
        pure
        returns (FeesDistribution memory fees)
    {
        unchecked {
            fees.total = _fees.safe128();
            fees.protocol = uint128((_fees * _fp.protocolShare) / Constants.HUNDRED_PERCENT);
        }
    }

    /// @notice Return the fee share
    /// @param _fp The current fee parameter
    /// @param _binCrossed The current number of bin crossed
    /// @return feeShares The fee share, with 18 decimals
    function getFeeShares(FeeParameters memory _fp, uint256 _binCrossed) private pure returns (uint256 feeShares) {
        unchecked {
            feeShares = getBaseFee(_fp) + getVariableFee(_fp, _binCrossed);
        }
    }
}
