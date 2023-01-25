// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./Constants.sol";
import "./math/SafeCast.sol";

/**
 * @title Liquidity Book Pair Parameter Helper Library
 * @author Trader Joe
 * @dev This library contains functions to get and set parameters of a pair
 * The parameters are stored in a single bytes32 variable in the following format:
 * [0 - 16[: base factor (16 bits)
 * [16 - 28[: filter period (12 bits)
 * [28 - 40[: decay period (12 bits)
 * [40 - 54[: reduction factor (14 bits)
 * [54 - 78[: variable fee control (24 bits)
 * [78 - 92[: protocol share (14 bits)
 * [92 - 112[: max volatility accumulated (20 bits)
 * [112 - 132[: volatility accumulated (20 bits)
 * [132 - 152[: volatility reference (20 bits)
 * [152 - 176[: index reference (24 bits)
 * [176 - 216[: time of last update (40 bits)
 * [216 - 232[: oracle index (16 bits)
 * [232 - 256[: active index (24 bits)
 */
library PairParameterHelper {
    using SafeCast for uint256;

    error PairParametersHelper__InvalidParameter();

    uint256 internal constant _FILTER_PERIOD_OFFSET = 16;
    uint256 internal constant _DECAY_PERIOD_OFFSET = 28;
    uint256 internal constant _REDUCTION_FACTOR_OFFSET = 40;
    uint256 internal constant _VARIABLE_FEE_CONTROL_OFFSET = 54;
    uint256 internal constant _PROTOCOL_SHARE_OFFSET = 78;
    uint256 internal constant _MAX_VOL_ACC_OFFSET = 92;
    uint256 internal constant _VOL_ACC_OFFSET = 112;
    uint256 internal constant _VOLATILITY_REFERENCE_OFFSET = 132;
    uint256 internal constant _INDEX_REF_OFFSET = 152;
    uint256 internal constant _TIME_OFFSET = 176;
    uint256 internal constant _ORACLE_ID_OFFSET = 216;
    uint256 internal constant _ACTIVE_ID_OFFSET = 232;

    uint256 internal constant _STATIC_PARAMETER_MASK = 0xffffffffffffffffffffffffffff;
    uint256 internal constant _DYNAMIC_PARAMETER_MASK = 0xffffffffffffffffffffffffffffffffffff;

    uint256 internal constant _BASE_FACTOR_MASK = 0xffff;
    uint256 internal constant _FILTER_PERIOD_MASK = 0xfff;
    uint256 internal constant _DECAY_PERIOD_MASK = 0xfff;
    uint256 internal constant _REDUCTION_FACTOR_MASK = 0x3fff;
    uint256 internal constant _VARIABLE_FEE_CONTROL_MASK = 0xffffff;
    uint256 internal constant _PROTOCOL_SHARE_MASK = 0x3fff;
    uint256 internal constant _VOLATILITY_MASK = 0xfffff;
    uint256 internal constant _INDEX_REF_MASK = 0xffffff;
    uint256 internal constant _TIME_MASK = 0xffffffffff;
    uint256 internal constant _ORACLE_ID_MASK = 0xffff;
    uint256 internal constant _ACTIVE_ID_MASK = 0xffffff;

    uint256 internal constant _MAX_BASIS_POINTS = 10_000;
    uint256 internal constant _MAX_PROTOCOL_SHARE = 2_500;
    uint256 internal constant _PRECISION = 1e18;
    uint256 internal constant _PRECISION_SUB_ONE = _PRECISION - 1;

    /**
     * @dev Get the base factor from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return baseFactor The base factor
     */
    function getBaseFactor(bytes32 params) internal pure returns (uint16 baseFactor) {
        assembly {
            baseFactor := and(params, _BASE_FACTOR_MASK)
        }
    }

    /**
     * @dev Get the filter period from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return filterPeriod The filter period
     */
    function getFilterPeriod(bytes32 params) internal pure returns (uint16 filterPeriod) {
        assembly {
            filterPeriod := shr(_FILTER_PERIOD_OFFSET, and(params, _FILTER_PERIOD_MASK))
        }
    }

    /**
     * @dev Get the decay period from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return decayPeriod The decay period
     */
    function getDecayPeriod(bytes32 params) internal pure returns (uint16 decayPeriod) {
        assembly {
            decayPeriod := shr(_DECAY_PERIOD_OFFSET, and(params, _DECAY_PERIOD_MASK))
        }
    }

    /**
     * @dev Get the reduction factor from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return reductionFactor The reduction factor
     */
    function getReductionFactor(bytes32 params) internal pure returns (uint16 reductionFactor) {
        assembly {
            reductionFactor := shr(_REDUCTION_FACTOR_OFFSET, and(params, _REDUCTION_FACTOR_MASK))
        }
    }

    /**
     * @dev Get the variable fee control from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return variableFeeControl The variable fee control
     */
    function getVariableFeeControl(bytes32 params) internal pure returns (uint24 variableFeeControl) {
        assembly {
            variableFeeControl := shr(_VARIABLE_FEE_CONTROL_OFFSET, and(params, _VARIABLE_FEE_CONTROL_MASK))
        }
    }

    /**
     * @dev Get the protocol share from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return protocolShare The protocol share
     */
    function getProtocolShare(bytes32 params) internal pure returns (uint16 protocolShare) {
        assembly {
            protocolShare := shr(_PROTOCOL_SHARE_OFFSET, and(params, _PROTOCOL_SHARE_MASK))
        }
    }

    /**
     * @dev Get the max volatility accumulated from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return maxVolatilityAccumulated The max volatility accumulated
     */
    function getMaxVolatilityAccumulated(bytes32 params) internal pure returns (uint24 maxVolatilityAccumulated) {
        assembly {
            maxVolatilityAccumulated := shr(_MAX_VOL_ACC_OFFSET, and(params, _VOLATILITY_MASK))
        }
    }

    /**
     * @dev Get the volatility accumulated from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return volatilityAccumulated The volatility accumulated
     */
    function getVolatilityAccumulated(bytes32 params) internal pure returns (uint24 volatilityAccumulated) {
        assembly {
            volatilityAccumulated := shr(_VOL_ACC_OFFSET, and(params, _VOLATILITY_MASK))
        }
    }

    /**
     * @dev Get the volatility reference from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return volatilityReference The volatility reference
     */
    function getVolatilityReference(bytes32 params) internal pure returns (uint24 volatilityReference) {
        assembly {
            volatilityReference := shr(_VOLATILITY_REFERENCE_OFFSET, and(params, _VOLATILITY_MASK))
        }
    }

    /**
     * @dev Get the index reference from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return idReference The index reference
     */
    function getIdReference(bytes32 params) internal pure returns (uint24 idReference) {
        assembly {
            idReference := shr(_INDEX_REF_OFFSET, and(params, _INDEX_REF_MASK))
        }
    }

    /**
     * @dev Get the time of last update from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return timeOflastUpdate The time of last update
     */
    function getTimeOfLastUpdate(bytes32 params) internal pure returns (uint40 timeOflastUpdate) {
        assembly {
            timeOflastUpdate := shr(_TIME_OFFSET, and(params, _TIME_MASK))
        }
    }

    /**
     * @dev Get the oracle id from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return oracleId The oracle id
     */
    function getOracleId(bytes32 params) internal pure returns (uint16 oracleId) {
        assembly {
            oracleId := shr(_ORACLE_ID_OFFSET, params)
        }
    }

    /**
     * @dev Get the delta between the active index and the reference index
     * @param params The encoded pair parameters
     * @param activeId The active index
     * @return The delta
     */
    function getDeltaId(bytes32 params, uint24 activeId) internal pure returns (uint24) {
        uint24 id = getActiveId(params);
        unchecked {
            return activeId > id ? activeId - id : id - activeId;
        }
    }

    /**
     * @dev Get the active index from the encoded pair parameters
     * @param params The encoded pair parameters
     * @return activeId The active index
     */
    function getActiveId(bytes32 params) internal pure returns (uint24 activeId) {
        assembly {
            activeId := shr(_ACTIVE_ID_OFFSET, params)
        }
    }

    /**
     * @dev Set the oracle id in the encoded pair parameters
     * @param params The encoded pair parameters
     * @param oracleId The oracle id
     * @return The updated encoded pair parameters
     */
    function setOracleId(bytes32 params, uint16 oracleId) internal pure returns (bytes32) {
        assembly {
            params := and(params, shl(_ORACLE_ID_OFFSET, not(_ORACLE_ID_MASK)))
            params := or(params, shl(_ORACLE_ID_OFFSET, oracleId))
        }
        return params;
    }

    /**
     * @dev Set the volatility reference in the encoded pair parameters
     * @param params The encoded pair parameters
     * @param volRef The volatility reference
     * @return The updated encoded pair parameters
     */
    function setVolatilityReference(bytes32 params, uint24 volRef) internal pure returns (bytes32) {
        if (volRef > _VOLATILITY_MASK) revert PairParametersHelper__InvalidParameter();

        assembly {
            params := and(params, shl(_VOLATILITY_REFERENCE_OFFSET, not(_VOLATILITY_MASK)))
            params := or(params, shl(_VOLATILITY_REFERENCE_OFFSET, volRef))
        }
        return params;
    }

    /**
     * @dev Set the active id in the encoded pair parameters
     * @param params The encoded pair parameters
     * @param activeId The active id
     * @return newParams The updated encoded pair parameters
     */
    function setActiveId(bytes32 params, uint24 activeId) internal pure returns (bytes32 newParams) {
        assembly {
            params := and(params, shl(_ACTIVE_ID_OFFSET, not(_ACTIVE_ID_MASK)))
            newParams := or(params, shl(_ACTIVE_ID_OFFSET, activeId))
        }
    }

    /**
     * @dev Sets the static fee parameters in the encoded pair parameters
     * @param params The encoded pair parameters
     * @param baseFactor The base factor
     * @param filterPeriod The filter period
     * @param decayPeriod The decay period
     * @param reductionFactor The reduction factor
     * @param variableFeeControl The variable fee control
     * @param protocolShare The protocol share
     * @param maxVolatilityAccumulated The max volatility accumulated
     * @return The updated encoded pair parameters
     */
    function setStaticFeeParameters(
        bytes32 params,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulated
    ) internal pure returns (bytes32) {
        if (
            filterPeriod > decayPeriod || decayPeriod > _DECAY_PERIOD_MASK || reductionFactor > _MAX_BASIS_POINTS
                || protocolShare > _MAX_PROTOCOL_SHARE || maxVolatilityAccumulated > _VOLATILITY_MASK
        ) revert PairParametersHelper__InvalidParameter();

        assembly {
            params := and(params, not(_STATIC_PARAMETER_MASK))

            params := or(params, and(baseFactor, _BASE_FACTOR_MASK))
            params := or(params, shl(_FILTER_PERIOD_OFFSET, and(filterPeriod, _FILTER_PERIOD_MASK)))
            params := or(params, shl(_DECAY_PERIOD_OFFSET, and(decayPeriod, _DECAY_PERIOD_MASK)))
            params := or(params, shl(_REDUCTION_FACTOR_OFFSET, and(reductionFactor, _REDUCTION_FACTOR_MASK)))
            params := or(params, shl(_VARIABLE_FEE_CONTROL_OFFSET, and(variableFeeControl, _VARIABLE_FEE_CONTROL_MASK)))
            params := or(params, shl(_PROTOCOL_SHARE_OFFSET, and(protocolShare, _PROTOCOL_SHARE_MASK)))
            params := or(params, shl(_MAX_VOL_ACC_OFFSET, and(maxVolatilityAccumulated, _VOLATILITY_MASK)))
        }

        return params;
    }

    /**
     * @dev Updates the index reference in the encoded pair parameters
     * @param params The encoded pair parameters
     * @return newParams The updated encoded pair parameters
     */
    function updateIdReference(bytes32 params) internal pure returns (bytes32 newParams) {
        uint24 activeId = getActiveId(params);
        assembly {
            params := and(params, shl(_INDEX_REF_OFFSET, not(_INDEX_REF_MASK)))
            newParams := or(params, shl(_INDEX_REF_OFFSET, activeId))
        }
    }

    /**
     * @dev Updates the time of last update in the encoded pair parameters
     * @param params The encoded pair parameters
     * @return newParams The updated encoded pair parameters
     */
    function updateTimeOfLastUpdate(bytes32 params) internal view returns (bytes32 newParams) {
        uint40 currentTime = block.timestamp.safe40();
        assembly {
            params := and(params, shl(_TIME_OFFSET, not(_TIME_MASK)))
            newParams := or(params, shl(_TIME_OFFSET, currentTime))
        }
    }

    /**
     * @dev Updates the volatility reference in the encoded pair parameters
     * @param params The encoded pair parameters
     * @return The updated encoded pair parameters
     */
    function updateVolatilityReference(bytes32 params) internal pure returns (bytes32) {
        uint256 volAcc = getVolatilityAccumulated(params);
        uint256 reductionFactor = getReductionFactor(params);

        uint24 volRef;
        unchecked {
            volRef = uint24(volAcc * reductionFactor / _MAX_BASIS_POINTS);
        }

        return setVolatilityReference(params, volRef);
    }

    /**
     * @dev Calculates the base fee
     * @param params The encoded pair parameters
     * @param binStep The bin step
     * @return baseFee The base fee
     */
    function getBaseFee(bytes32 params, uint8 binStep) internal pure returns (uint256) {
        unchecked {
            return uint256(getBaseFactor(params)) * binStep * 1e10;
        }
    }

    /**
     * @dev Calculates the variable fee
     * @param params The encoded pair parameters
     * @param binStep The bin step
     * @return variableFee The variable fee
     */
    function getVariableFee(bytes32 params, uint8 binStep) internal pure returns (uint256 variableFee) {
        uint256 variableFeeControl = getVariableFeeControl(params);

        if (variableFeeControl != 0) {
            unchecked {
                uint256 prod = uint256(getVolatilityAccumulated(params)) * binStep;
                variableFee = (prod * prod * variableFeeControl + 99) / 100;
            }
        }
    }

    /**
     * @dev Calculates the total fee, which is the sum of the base fee and the variable fee
     * @param params The encoded pair parameters
     * @param binStep The bin step
     * @return totalFee The total fee
     */
    function getTotalFee(bytes32 params, uint8 binStep) internal pure returns (uint128) {
        unchecked {
            return (getBaseFee(params, binStep) + getVariableFee(params, binStep)).safe128();
        }
    }

    /**
     * @dev Updates the volatility accumulated in the encoded pair parameters
     * @param params The encoded pair parameters
     * @param activeId The active id
     * @return The updated encoded pair parameters
     */
    function updateVolatilityAccumulated(bytes32 params, uint24 activeId) internal pure returns (bytes32) {
        uint24 deltaId = getDeltaId(params, activeId);

        uint256 volAcc;
        unchecked {
            volAcc = (uint256(getVolatilityAccumulated(params)) + deltaId * _MAX_BASIS_POINTS);
        }

        uint24 maxVolAcc = getMaxVolatilityAccumulated(params);

        if (volAcc > maxVolAcc) volAcc = maxVolAcc;

        assembly {
            params := and(params, shl(_VOL_ACC_OFFSET, not(_VOLATILITY_MASK)))
            params := or(params, shl(_VOL_ACC_OFFSET, volAcc))
        }
        return params;
    }

    /**
     * @dev Updates the volatility reference and the volatility accumulated in the encoded pair parameters
     * @param params The encoded pair parameters
     * @return The updated encoded pair parameters
     */
    function updateReferences(bytes32 params) internal view returns (bytes32) {
        uint256 deltaT = block.timestamp - getTimeOfLastUpdate(params);

        if (deltaT >= getFilterPeriod(params)) {
            params = updateIdReference(params);
            if (deltaT < getDecayPeriod(params)) params = updateVolatilityReference(params);
            else params = setVolatilityReference(params, 0);
        }

        return updateTimeOfLastUpdate(params);
    }

    /**
     * @dev Updates the volatility reference and the volatility accumulated in the encoded pair parameters
     * @param params The encoded pair parameters
     * @param activeId The active id
     * @return The updated encoded pair parameters
     */
    function updateVolatilityParameters(bytes32 params, uint24 activeId) internal view returns (bytes32) {
        params = updateReferences(params);
        return updateVolatilityAccumulated(params, activeId);
    }
}
