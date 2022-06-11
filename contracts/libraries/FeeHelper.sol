// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./SafeCast.sol";
import "./MathS40x36.sol";

error FeeHelper__AccumulatorOverflows();

library FeeHelper {
    using SafeCast for uint256;
    using MathS40x36 for int256;

    uint256 internal constant BASIS_POINT_MAX = 10_000;

    /// @dev Structure to store the protocol fees:
    /// - accumulator: The value of the accumulator
    /// - time: The last time the accumulator was called
    /// - coolDownTime: The time it needs to the accumulator to cool down
    /// - baseFee: The baseFee added to each swap. Max is 100 (1%)
    /// - maxFee: The maxFee that a user will pay. Max is 1000 (10%)
    struct FeeParameters {
        uint176 accumulator;
        uint80 time;
        uint176 maxAccumulator;
        uint16 filterPeriod;
        uint16 decayPeriod;
        uint16 binStep;
        uint16 baseFactor;
        uint16 protocolShare;
    }

    /// @dev Structure used during swaps to distributes the fees:
    /// - total: The total amount of fees
    /// - protocol: The fees reserved for the protocol
    struct FeesDistribution {
        uint128 total;
        uint128 protocol;
    }

    /// @notice Update the value of the accumulator
    /// @param _fp The current fee parameters
    function updateAccumulatorValue(FeeParameters memory _fp) internal view {
        unchecked {
            uint256 deltaT = block.timestamp - _fp.time;

            uint176 _accumulator; // Can't overflow as _accumulator <= _fp.accumulator <= _fp.maxAccumulator < 2**176
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

            if (_accumulator > type(uint128).max)
                revert FeeHelper__AccumulatorOverflows();

            assembly {
                sstore(_fp.slot, add(shl(176, timestamp()), _accumulator))
            }
        }
    }

    /// @notice Returns the base fee added to a swap in basis point
    /// @param _fp The current fee parameters
    /// @return The fee
    function getBaseFeeBP(FeeParameters memory _fp)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            return (_fp.baseFactor * _fp.binStep) / BASIS_POINT_MAX;
        }
    }

    /// @notice Returns the variable fee added to a swap in basis point
    /// @param _fp The current fee parameters
    /// @param _binCrossed The current number of bin crossed
    /// @return The variable fee
    function getVariableFeeBP(FeeParameters memory _fp, uint256 _binCrossed)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            uint256 _acc = _fp.accumulator + _binCrossed * BASIS_POINT_MAX;

            if (_acc > _fp.maxAccumulator) _acc = _fp.maxAccumulator;

            // The multiplication can't overflow as 176 + 16 < 256
            if (_acc * _fp.binStep > type(uint128).max)
                revert FeeHelper__AccumulatorOverflows();

            // decimals((_acc * _fp.binStep)**2) = (4 + 4) * 2 = 16
            // The result should use 4 decimals, but as we divide it by 2, 5e11
            return (_acc * _fp.binStep)**2 / 5e11; // 0.5 * (v_k * s) ** 2
        }
    }

    function getFees(
        FeeParameters memory _fp,
        uint256 _amount,
        uint256 _binCrossed
    ) internal pure returns (uint256 fee) {
        unchecked {
            uint256 _feeBP = getBaseFeeBP(_fp) +
                getVariableFeeBP(_fp, _binCrossed);
            return (_amount * _feeBP) / (BASIS_POINT_MAX - _feeBP);
        }
    }
}