// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./SafeCast.sol";
import "./SafeMath.sol";
import "./Constants.sol";

library FeeHelper {
    using SafeCast for uint256;
    using SafeMath for uint256;

    /// @dev Structure to store the protocol fees:
    /// - binStep: The bin step
    /// - baseFactor: The base factor
    /// - filterPeriod: The filter period, where the fees stays constant
    /// - decayPeriod: The decay period, where the fees are halved
    /// - reductionFactor: The reduction factor, used to calculate the reduction of the accumulator
    /// - variableFeeControl: The variable fee control, used to control the variable fee, can be 0 to disable them
    /// - protocolShare: The share of fees sent to protocol
    /// - maxVolatilityAccumulated: The max value of volatility accumulated
    /// - volatilityAccumulated: The value of volatility accumulated
    /// - volatilityReference: The value of volatility reference
    /// - indexRef: The index reference
    /// - time: The last time the accumulator was called
    struct FeeParameters {
        uint16 binStep;
        uint16 baseFactor;
        uint16 filterPeriod;
        uint16 decayPeriod;
        uint16 reductionFactor;
        uint24 variableFeeControl;
        uint16 protocolShare;
        uint24 maxVolatilityAccumulated;
        uint24 volatilityAccumulated;
        uint24 volatilityReference;
        uint24 indexRef;
        uint40 time;
    }

    /// @dev Structure used during swaps to distributes the fees:
    /// - total: The total amount of fees
    /// - protocol: The amount of fees reserved for protocol
    struct FeesDistribution {
        uint128 total;
        uint128 protocol;
    }

    /// @notice Update the value of the volatility accumulated
    /// @param _fp The current fee parameters
    /// @param _activeId The current active id
    function updateVariableFeeParameters(FeeParameters memory _fp, uint256 _activeId) internal view {
        unchecked {
            uint256 _deltaT = block.timestamp - _fp.time;

            if (_deltaT >= _fp.filterPeriod || _fp.time == 0) {
                _fp.indexRef = uint24(_activeId);
                if (_deltaT < _fp.decayPeriod) {
                    _fp.volatilityReference = uint24(
                        (_fp.reductionFactor * _fp.volatilityAccumulated) / Constants.BASIS_POINT_MAX
                    );
                } else {
                    _fp.volatilityReference = 0;
                }
            }

            _fp.time = (block.timestamp).safe40();

            updateVolatilityAccumulated(_fp, _activeId);
        }
    }

    /// @notice Update the volatility accumulated
    /// @param _fp The fee parameter
    /// @param _activeId The current active id
    function updateVolatilityAccumulated(FeeParameters memory _fp, uint256 _activeId) internal pure {
        unchecked {
            uint256 volatilityAccumulated = _fp.volatilityReference +
                _activeId.absSub(_fp.indexRef) *
                Constants.BASIS_POINT_MAX;
            _fp.volatilityAccumulated = volatilityAccumulated > _fp.maxVolatilityAccumulated
                ? _fp.maxVolatilityAccumulated
                : uint16(volatilityAccumulated);
        }
    }

    /// @notice Returns the base fee added to a swap, with 18 decimals
    /// @param _fp The current fee parameters
    /// @return The fee with 18 decimals precision
    function getBaseFee(FeeParameters memory _fp) internal pure returns (uint256) {
        unchecked {
            return uint256(_fp.baseFactor) * _fp.binStep * 1e10;
        }
    }

    /// @notice Returns the variable fee added to a swap, with 18 decimals
    /// @param _fp The current fee parameters
    /// @return The variable fee with 18 decimals precision
    function getVariableFee(FeeParameters memory _fp) internal pure returns (uint256) {
        unchecked {
            if (_fp.variableFeeControl == 0) return 0;

            // decimals(_fp.reductionFactor * (_fp.volatilityAccumulated * _fp.binStep)**2) = 4 + (4 + 4) * 2 - 2 = 18
            return
                (_fp.variableFeeControl *
                    ((_fp.volatilityAccumulated * _fp.binStep) * (_fp.volatilityAccumulated * _fp.binStep))) / 100;
        }
    }

    /// @notice Return the fees added to an amount
    /// @param _fp The current fee parameter
    /// @param _amount The amount of token sent
    /// @return The fee amount
    function getFees(FeeParameters memory _fp, uint256 _amount) internal pure returns (uint256) {
        unchecked {
            uint256 _feeShares = getFeeShares(_fp);
            return (_amount * _feeShares) / (Constants.PRECISION);
        }
    }

    /// @notice Return the fees from an amount
    /// @param _fp The current fee parameter
    /// @param _amountPlusFee The amount of token sent
    /// @return The fee amount
    function getFeesFrom(FeeParameters memory _fp, uint256 _amountPlusFee) internal pure returns (uint256) {
        unchecked {
            uint256 _feeShares = getFeeShares(_fp);
            return (_amountPlusFee * _feeShares) / (Constants.PRECISION + _feeShares);
        }
    }

    /// @notice Return the fees added when an user adds liquidity and change c in the active bin
    /// @param _fp The current fee parameter
    /// @param _amountPlusFee The amount of token sent
    /// @return The fee amount
    function getFeesForC(FeeParameters memory _fp, uint256 _amountPlusFee) internal pure returns (uint256) {
        unchecked {
            uint256 _feeShares = getFeeShares(_fp);
            return
                (_amountPlusFee * _feeShares * (_feeShares + Constants.PRECISION)) /
                (Constants.PRECISION * Constants.PRECISION);
        }
    }

    /// @notice Return the fees added when an user do a flashloan
    /// @param _fp The current fee parameter
    /// @param _amount The amount of token
    /// @param _fee The flash loan fee
    /// @return The flash loan fee amount
    function getFlashLoanFee(
        FeeParameters memory _fp,
        uint256 _amount,
        uint256 _fee
    ) internal pure returns (uint256) {
        unchecked {
            return (_amount * _fee) / (Constants.PRECISION);
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
            fees.protocol = uint128((_fees * _fp.protocolShare) / Constants.BASIS_POINT_MAX);
        }
    }

    /// @notice Return the fee share
    /// @param _fp The current fee parameter
    /// @return feeShares The fee share, with 18 decimals
    function getFeeShares(FeeParameters memory _fp) private pure returns (uint256 feeShares) {
        unchecked {
            feeShares = getBaseFee(_fp) + getVariableFee(_fp);
        }
    }
}
