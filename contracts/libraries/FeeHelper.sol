// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./SafeCast.sol";
import "./MathS40x36.sol";

library FeeHelper {
    using SafeCast for uint256;
    using MathS40x36 for int256;

    uint256 internal constant BASIS_POINT_MAX = 10_000;

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
        uint168 accumulator;
        uint88 time;
        uint168 maxAccumulator;
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

            uint168 _accumulator; // Can't overflow as _accumulator <= _fp.accumulator <= _fp.maxAccumulator < 2**168
            if (deltaT < _fp.filterPeriod) {
                _accumulator = _fp.accumulator;
            } else if (deltaT < _fp.decayPeriod) {
                _accumulator = _fp.accumulator / 2;
            } // else _accumulator = 0

            _fp.accumulator = _accumulator;
        }
    }

    /// @notice Update the accumulator and the timestamp
    /// @dev This is done in assembly to save some gas, be very cautious if you change this
    /// @param _fp The stored fee parameters
    /// @param _accumulator The current accumulator (the one in memory)
    /// @param _binCrossed The current number of bin crossed
    function updateStoredFeeParameters(
        FeeParameters storage _fp,
        uint256 _accumulator,
        uint256 _binCrossed
    ) internal {
        unchecked {
            // This equation can't overflow
            _accumulator += _binCrossed * BASIS_POINT_MAX;

            if (_accumulator > _fp.maxAccumulator)
                _accumulator = _fp.maxAccumulator;

            assembly {
                sstore(_fp.slot, add(shl(168, timestamp()), _accumulator))
            }
        }
    }

    /// @notice Returns the base fee added to a swap in basis point squared (100% is 100_000_000)
    /// @param _fp The current fee parameters
    /// @return The fee
    function getBaseFeeBP2(FeeParameters memory _fp)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            return _fp.baseFactor * _fp.binStep;
        }
    }

    /// @notice Returns the variable fee added to a swap in basis point squared (100% is 100_000_000)
    /// @param _fp The current fee parameters
    /// @param _binCrossed The current number of bin crossed
    /// @return The variable fee
    function getVariableFeeBP2(FeeParameters memory _fp, uint256 _binCrossed)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            if (_fp.variableFeeDisabled != 0) {
                return 0;
            }

            uint256 _acc = _fp.accumulator + _binCrossed * BASIS_POINT_MAX;

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
        uint256 _feeBP = getBaseFeeBP2(_fp) +
            getVariableFeeBP2(_fp, _binCrossed);

        return
            (_amount * _feeBP) / ((BASIS_POINT_MAX - _feeBP) * BASIS_POINT_MAX);
    }

    /// @notice Return the fees distribution added to an amount
    /// @param _fp The current fee parameter
    /// @param _amount The amount of token sent
    /// @param _binCrossed The current number of bin crossed
    /// @return The fee amount
    function getFeesDistribution(
        FeeParameters memory _fp,
        uint256 _amount,
        uint256 _binCrossed
    ) internal pure returns (FeesDistribution memory) {
        uint256 _fees = getFees(_fp, _amount, _binCrossed);
        uint256 _protocolFees = (_fees * _fp.protocolShare) / BASIS_POINT_MAX;
        return
            FeesDistribution({
                total: _fees.safe128(),
                protocol: _protocolFees.safe128()
            });
    }
}
