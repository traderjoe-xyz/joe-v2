// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./SafeCast.sol";
import "./Constants.sol";

library FeeHelper {
    using SafeCast for uint256;

    /// @dev Structure to store the protocol fees:
    /// - accumulator: The value of the accumulator
    /// - time: The last time the accumulator was called
    /// - maxAccumulator: The max value of the accumulator
    /// - filterPeriod: The filter period, where the fees stays constant
    /// - decayPeriod: The decay period, where the fees are halved
    /// - binStep: The bin step
    /// - baseFactor: The base factor
    /// - protocolShare: The share of fees sent to protocol
    /// - variableFeeDisabled: Whether the fees are disabled or not
    struct FeeParameters {
        uint64 accumulator;
        uint40 time;
        uint64 maxAccumulator;
        uint16 filterPeriod;
        uint16 decayPeriod;
        uint16 binStep;
        uint16 baseFactor;
        uint16 protocolShare;
        uint8 variableFeeDisabled;
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

            uint256 _accumulator; // Can't overflow as _accumulator <= _fp.accumulator <= _fp.maxAccumulator < 2**64
            if (deltaT < _fp.filterPeriod) {
                _accumulator = _fp.accumulator;
            } else if (deltaT < _fp.decayPeriod) {
                _accumulator = _fp.accumulator / 2;
            } // else _accumulator = 0;

            _fp.accumulator = uint64(_accumulator);
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

            _fp.accumulator = _accumulator.safe64();
            _fp.time = block.timestamp.safe40();
        }
    }

    /// @notice Returns the base fee added to a swap in basis point squared (100% is 100_000_000)
    /// @param _fp The current fee parameters
    /// @return The fee
    function getBaseFeeBP2(FeeParameters memory _fp) internal pure returns (uint256) {
        unchecked {
            return _fp.baseFactor * _fp.binStep;
        }
    }

    /// @notice Returns the variable fee added to a swap in basis point squared (100% is 100_000_000)
    /// @param _fp The current fee parameters
    /// @param _binCrossed The current number of bin crossed
    /// @return The variable fee
    function getVariableFeeBP2(FeeParameters memory _fp, uint256 _binCrossed) internal pure returns (uint256) {
        unchecked {
            if (_fp.variableFeeDisabled != 0) {
                return 0;
            }

            uint256 _acc = _fp.accumulator + _binCrossed * Constants.BASIS_POINT_MAX;

            if (_acc > _fp.maxAccumulator) _acc = _fp.maxAccumulator;

            // decimals((_acc * _fp.binStep)**2) = (4 + 4) * 2 = 16
            // The result should use 8 decimals, but as we divide it by 2, 5e7
            return (_acc * _fp.binStep)**2 / 5e7; // 0.5 * (v_k * s) ** 2
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
        uint256 _feeBP2 = getBaseFeeBP2(_fp) + getVariableFeeBP2(_fp, _binCrossed);

        return (_amount * _feeBP2) / (Constants.BASIS_POINT_MAX_SQUARED);
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
        uint256 _feeBP2 = getBaseFeeBP2(_fp) + getVariableFeeBP2(_fp, _binCrossed);

        return (_amountPlusFee * _feeBP2) / (Constants.BASIS_POINT_MAX_SQUARED + _feeBP2);
    }

    /// @notice Return the fees distribution added to an amount
    /// @param _fp The current fee parameter
    /// @param _fees The fee amount
    /// @return The fee amount
    function getFeesDistribution(FeeParameters memory _fp, uint256 _fees)
        internal
        pure
        returns (FeesDistribution memory)
    {
        uint256 _protocolFees = (_fees * _fp.protocolShare) / Constants.BASIS_POINT_MAX;
        return FeesDistribution({total: _fees.safe128(), protocol: uint128(_protocolFees)});
    }
}
