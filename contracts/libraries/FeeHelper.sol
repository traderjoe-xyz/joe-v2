// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./SafeCast.sol";
import "./MathS40x36.sol";

library FeeHelper {
    using SafeCast for uint256;
    using MathS40x36 for int256;

    uint256 internal constant BASIS_POINT_MAX = 10_000;
    uint256 internal constant PRECISION = 1e18;

    /// @dev Structure to store the protocol fees:
    /// - accumulator: The value of the accumulator
    /// - time: The last time the accumulator was called
    /// - coolDownTime: The time it needs to the accumulator to cool down
    /// - baseFee: The baseFee added to each swap. Max is 100 (1%)
    /// - maxFee: The maxFee that a user will pay. Max is 1000 (10%)
    struct FeeParameters {
        uint192 accumulator;
        uint64 time;
        uint16 coolDownTime;
        uint16 maxFee;
        uint16 binStep;
        uint16 fF;
        uint16 fV;
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
    /// @param _fee The current fee parameters
    function updateAccumulatorValue(FeeParameters memory _fee) internal view {
        unchecked {
            uint256 _deltaT = block.timestamp - _fee.time;
            if (_deltaT >= _fee.coolDownTime) _fee.accumulator = 0;
            else {
                // uint256 _coolDown = (_deltaT * PRECISION) / _fee.coolDownTime;
                uint256 _coolDown = uint256(
                    int256(1e36 - (_deltaT * 1e36) / _fee.coolDownTime).log2()
                );
                _fee.accumulator = ((_fee.accumulator *
                    (PRECISION - _coolDown)) / PRECISION).safe192();
            }
        }
    }

    /// @notice Returns the variable fee added to a swap
    /// @param _fee The current fee parameters
    /// @param _binCrossed The current number of bin crossed
    /// @return The fee
    function getVariableFee(FeeParameters memory _fee, uint256 _binCrossed)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            uint256 _a = _fee.accumulator + _binCrossed * PRECISION;
            return (_fee.fV * (_fee.binStep * _a)**2) / 1e44; // 1e4 * (1e4 * PRECISION)**2 = 1e48
        }
    }

    /// @notice Returns the fees (base + variable) added to a swap
    /// @param _fee The current fee parameters
    /// @param _binCrossed The current number of bin crossed
    /// @return fee The fee
    function getFees(FeeParameters memory _fee, uint256 _binCrossed)
        internal
        pure
        returns (uint256 fee)
    {
        fee =
            (uint256(_fee.binStep) * _fee.fF) /
            BASIS_POINT_MAX +
            getVariableFee(_fee, _binCrossed);
        return fee > _fee.maxFee ? _fee.maxFee : fee;
    }

    function getFeesDistribution(
        FeeParameters memory _feeParameters,
        uint256 _amount,
        uint256 _binCrossed
    ) internal pure returns (FeesDistribution memory feesDistribution) {
        uint256 _fee = BASIS_POINT_MAX - getFees(_feeParameters, _binCrossed);
        feesDistribution.total = ((uint256(_amount) * BASIS_POINT_MAX) /
            _fee -
            _amount).safe128();
        feesDistribution.protocol = ((uint256(feesDistribution.total) *
            _feeParameters.protocolShare) / BASIS_POINT_MAX).safe128();
    }
}
