// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/**
 * @title Liquidity Book Sample Math Library
 * @author Trader Joe
 * @notice This library contains functions to encode and decode a sample into a single bytes32
 * and interact with the encoded bytes32
 * The sample is encoded as follows:
 * 0 - 16: oracle length (16 bits)
 * 16 - 80: cumulative id (64 bits)
 * 80 - 144: cumulative volatility accumulated (64 bits)
 * 144 - 208: cumulative bin crossed (64 bits)
 * 208 - 216: sample lifetime (8 bits)
 * 216 - 256: sample creation timestamp (40 bits)
 */
library SampleMath {
    uint256 internal constant _SHIFT_CUMULATIVE_ID = 16;
    uint256 internal constant _SHIFT_CUMULATIVE_VOLATILITY = 80;
    uint256 internal constant _SHIFT_CUMULATIVE_BIN_CROSSED = 144;
    uint256 internal constant _SHIFT_SAMPLE_LIFETIME = 208;
    uint256 internal constant _SHIFT_SAMPLE_CREATION = 216;

    /**
     * @dev Encodes a sample
     * @param oracleLength The oracle length
     * @param cumulativeId The cumulative id
     * @param cumulativeVolatility The cumulative volatility
     * @param cumulativeBinCrossed The cumulative bin crossed
     * @param sampleLifetime The sample lifetime
     * @param createdAt The sample creation timestamp
     * @return sample The encoded sample
     */
    function encode(
        uint16 oracleLength,
        uint64 cumulativeId,
        uint64 cumulativeVolatility,
        uint64 cumulativeBinCrossed,
        uint8 sampleLifetime,
        uint40 createdAt
    ) internal pure returns (bytes32 sample) {
        assembly {
            sample := or(oracleLength, shl(_SHIFT_CUMULATIVE_ID, cumulativeId))
            sample := or(sample, shl(_SHIFT_CUMULATIVE_VOLATILITY, cumulativeVolatility))
            sample := or(sample, shl(_SHIFT_CUMULATIVE_BIN_CROSSED, cumulativeBinCrossed))
            sample := or(sample, shl(_SHIFT_SAMPLE_LIFETIME, sampleLifetime))
            sample := or(sample, shl(_SHIFT_SAMPLE_CREATION, createdAt))
        }
    }

    /**
     * @dev Decodes an encoded sample and return all the values
     * @param sample The encoded sample
     * @return oracleLength The oracle length
     * @return cumulativeId The cumulative id
     * @return cumulativeVolatility The cumulative volatility
     * @return cumulativeBinCrossed The cumulative bin crossed
     * @return sampleLifetime The sample lifetime
     * @return createdAt The sample creation timestamp
     */
    function decode(bytes32 sample)
        internal
        pure
        returns (
            uint16 oracleLength,
            uint64 cumulativeId,
            uint64 cumulativeVolatility,
            uint64 cumulativeBinCrossed,
            uint8 sampleLifetime,
            uint40 createdAt
        )
    {
        oracleLength = getOracleLength(sample);
        cumulativeId = getCumulativeId(sample);
        cumulativeVolatility = getCumulativeVolatility(sample);
        cumulativeBinCrossed = getCumulativeBinCrossed(sample);
        sampleLifetime = getSampleLifetime(sample);
        createdAt = getSampleCreation(sample);
    }

    /**
     * @dev Gets the oracle length from an encoded sample
     * @param sample The encoded sample
     * @return length The oracle length
     */
    function getOracleLength(bytes32 sample) internal pure returns (uint16 length) {
        assembly {
            length := sample
        }
    }

    /**
     * @dev Gets the cumulative id from an encoded sample
     * @param sample The encoded sample as follows:
     * [0 - 16[: oracle length (16 bits)
     * [16 - 256[: any (240 bits)
     * @return id The cumulative id
     */
    function getCumulativeId(bytes32 sample) internal pure returns (uint64 id) {
        assembly {
            id := shr(_SHIFT_CUMULATIVE_ID, sample)
        }
    }

    /**
     * @dev Gets the cumulative volatility accumulated from an encoded sample
     * @param sample The encoded sample as follows:
     * [0 - 16[: any (16 bits)
     * [16 - 80[: cumulative id (64 bits)
     * [80 - 256[: any (176 bits)
     * @return volatilityAccumulated The cumulative volatility
     */
    function getCumulativeVolatility(bytes32 sample) internal pure returns (uint64 volatilityAccumulated) {
        assembly {
            volatilityAccumulated := shr(_SHIFT_CUMULATIVE_VOLATILITY, sample)
        }
    }

    /**
     * @dev Gets the cumulative bin crossed from an encoded sample
     * @param sample The encoded sample as follows:
     * [0 - 80[: any (80 bits)
     * [80 - 144[: cumulative volatility accumulated (64 bits)
     * [144 - 256[: any (112 bits)
     * @return binCrossed The cumulative bin crossed
     */
    function getCumulativeBinCrossed(bytes32 sample) internal pure returns (uint64 binCrossed) {
        assembly {
            binCrossed := shr(_SHIFT_CUMULATIVE_BIN_CROSSED, sample)
        }
    }

    /**
     * @dev Gets the sample lifetime from an encoded sample
     * @param sample The encoded sample as follows:
     * [0 - 144[: any (144 bits)
     * [144 - 208[: cumulative bin crossed (64 bits)
     * [208 - 256[: any (48 bits)
     * @return lifetime The sample lifetime
     */
    function getSampleLifetime(bytes32 sample) internal pure returns (uint8 lifetime) {
        assembly {
            lifetime := shr(_SHIFT_SAMPLE_LIFETIME, sample)
        }
    }

    /**
     * @dev Gets the sample creation timestamp from an encoded sample
     * @param sample The encoded sample as follows:
     * [0 - 208[: any (208 bits)
     * [208 - 216[: sample lifetime (8 bits)
     * [216 - 256[: any (40 bits)
     * @return creation The sample creation timestamp
     */
    function getSampleCreation(bytes32 sample) internal pure returns (uint40 creation) {
        assembly {
            creation := shr(_SHIFT_SAMPLE_CREATION, sample)
        }
    }

    /**
     * @dev Gets the sample last update timestamp from an encoded sample
     * @param sample The encoded sample as follows:
     * [0 - 216[: any (216 bits)
     * [216 - 256[: sample creation timestamp (40 bits)
     * @return lastUpdate The sample last update timestamp
     */
    //TODO lastupdate 48 bits?
    function getSampleLastUpdate(bytes32 sample) internal pure returns (uint40 lastUpdate) {
        lastUpdate = getSampleCreation(sample) + getSampleLifetime(sample);
    }

    /**
     * @dev Gets the weighted average of two samples and their respective weights
     * @param sample1 The first encoded sample
     * @param sample2 The second encoded sample
     * @param weight1 The weight of the first sample
     * @param weight2 The weight of the second sample
     * @return weightedAverageId The weighted average id
     * @return weightedAverageVolatility The weighted average volatility
     * @return weightedAverageBinCrossed The weighted average bin crossed
     */
    function getWeightedAverage(bytes32 sample1, bytes32 sample2, uint40 weight1, uint40 weight2)
        internal
        pure
        returns (uint64 weightedAverageId, uint64 weightedAverageVolatility, uint64 weightedAverageBinCrossed)
    {
        uint256 cId1 = getCumulativeId(sample1);
        uint256 cVolatility1 = getCumulativeVolatility(sample1);
        uint256 cBinCrossed1 = getCumulativeBinCrossed(sample1);

        if (weight2 == 0) return (uint64(cId1), uint64(cVolatility1), uint64(cBinCrossed1));

        uint256 cId2 = getCumulativeId(sample2);
        uint256 cVolatility2 = getCumulativeVolatility(sample2);
        uint256 cBinCrossed2 = getCumulativeBinCrossed(sample2);

        if (weight1 == 0) return (uint64(cId2), uint64(cVolatility2), uint64(cBinCrossed2));

        uint256 totalWeight = uint256(weight1) + weight2;

        unchecked {
            weightedAverageId = uint64((cId1 * weight1 + cId2 * weight2) / totalWeight);
            weightedAverageVolatility = uint64((cVolatility1 * weight1 + cVolatility2 * weight2) / totalWeight);
            weightedAverageBinCrossed = uint64((cBinCrossed1 * weight1 + cBinCrossed2 * weight2) / totalWeight);
        }
    }

    /**
     * @dev Updates a sample with the given values
     * @param sample The encoded sample
     * @param deltaTime The time elapsed since the last update
     * @param activeId The active id
     * @param volatilityAccumulated The volatility accumulated
     * @param binCrossed The bin crossed
     * @return cumulativeId The cumulative id
     * @return cumulativeVolatility The cumulative volatility
     * @return cumulativeBinCrossed The cumulative bin crossed
     */
    function update(bytes32 sample, uint40 deltaTime, uint24 activeId, uint24 volatilityAccumulated, uint24 binCrossed)
        internal
        pure
        returns (uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed)
    {
        unchecked {
            cumulativeId = uint64(activeId) * deltaTime;
            cumulativeVolatility = uint64(volatilityAccumulated) * deltaTime;
            cumulativeBinCrossed = uint64(binCrossed) * deltaTime;
        }

        cumulativeId += getCumulativeId(sample);
        cumulativeVolatility += getCumulativeVolatility(sample);
        cumulativeBinCrossed += getCumulativeBinCrossed(sample);
    }
}
