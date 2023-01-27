// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./math/SampleMath.sol";
import "./math/SafeCast.sol";
import "./PairParameterHelper.sol";

/**
 * @title Liquidity Book Oracle Helper Library
 * @author Trader Joe
 * @notice This library contains functions to manage the oracle
 * The oracle samples are stored in a single bytes32 array.
 * Each sample is encoded as follows:
 * 0 - 16: oracle length (16 bits)
 * 16 - 80: cumulative id (64 bits)
 * 80 - 144: cumulative volatility accumulated (64 bits)
 * 144 - 208: cumulative bin crossed (64 bits)
 * 208 - 216: sample lifetime (8 bits)
 * 216 - 256: sample creation timestamp (40 bits)
 */
library OracleHelper {
    using SampleMath for bytes32;
    using SafeCast for uint256;
    using PairParameterHelper for bytes32;

    error OracleHelper__InvalidOracleId();
    error OracleHelper__NewLengthTooSmall();
    error OracleHelper__LookUpTimestampTooOld();

    struct Oracle {
        bytes32[65535] samples;
    }

    uint256 internal constant _MAX_SAMPLE_LIFETIME = 120 seconds;

    /**
     * @dev Returns the sample at the given oracleId
     * @param oracle The oracle
     * @param oracleId The oracle id
     * @return sample The sample
     */
    function getSample(Oracle storage oracle, uint16 oracleId) internal view returns (bytes32 sample) {
        if (oracleId == 0) revert OracleHelper__InvalidOracleId();

        unchecked {
            sample = oracle.samples[oracleId - 1];
        }
    }

    /**
     * @dev Returns the sample at the given timestamp. If the timestamp is not in the oracle, it returns the closest sample
     * @param oracle The oracle
     * @param oracleId The oracle id
     * @param lookUpTimestamp The timestamp to look up
     * @return lastUpdate The last update timestamp
     * @return cumulativeId The cumulative id
     * @return cumulativeVolatility The cumulative volatility
     * @return cumulativeBinCrossed The cumulative bin crossed
     */
    function getSampleAt(Oracle storage oracle, uint16 oracleId, uint40 lookUpTimestamp)
        internal
        view
        returns (uint40 lastUpdate, uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed)
    {
        bytes32 sample = getSample(oracle, oracleId);
        uint16 length = sample.getOracleLength();

        assembly {
            oracleId := mod(oracleId, length)
        }
        bytes32 oldestSample = oracle.samples[oracleId];

        // Oreacle is not fully initialized yet
        if (oldestSample >> SampleMath.OFFSET_CUMULATIVE_ID == 0) {
            length = oracleId;
            oldestSample = oracle.samples[0];
        }

        if (oldestSample.getSampleLastUpdate() > lookUpTimestamp) revert OracleHelper__LookUpTimestampTooOld();

        lastUpdate = sample.getSampleLastUpdate();
        if (lastUpdate <= lookUpTimestamp) {
            return (
                lastUpdate, sample.getCumulativeId(), sample.getCumulativeVolatility(), sample.getCumulativeBinCrossed()
            );
        } else {
            lastUpdate = lookUpTimestamp;
        }

        (bytes32 prevSample, bytes32 nextSample) = binarySearch(oracle, oracleId, lookUpTimestamp, length);

        uint40 weightPrev = nextSample.getSampleLastUpdate() - lookUpTimestamp;
        uint40 weightNext = lookUpTimestamp - sample.getSampleLastUpdate();

        (cumulativeId, cumulativeVolatility, cumulativeBinCrossed) =
            sample.getWeightedAverage(prevSample, weightPrev, weightNext);
    }

    /**
     * @dev Binary search to find the 2 samples surrounding the given timestamp
     * @param oracle The oracle
     * @param oracleId The oracle id
     * @param lookUpTimestamp The timestamp to look up
     * @param length The oracle length
     * @return prevSample The previous sample
     * @return nextSample The next sample
     */
    function binarySearch(Oracle storage oracle, uint16 oracleId, uint40 lookUpTimestamp, uint16 length)
        internal
        view
        returns (bytes32, bytes32)
    {
        uint16 low = 0;
        uint16 high = length - 1;

        bytes32 sample;
        uint40 sampleLastUpdate;

        while (low < high) {
            uint16 mid = (low + high) / 2;

            assembly {
                oracleId := addmod(oracleId, mid, length)
            }

            sample = oracle.samples[oracleId];
            sampleLastUpdate = sample.getSampleCreation();

            if (sampleLastUpdate > lookUpTimestamp) {
                high = mid - 1;
            } else if (sampleLastUpdate < lookUpTimestamp) {
                low = mid + 1;
            } else {
                return (sample, sample);
            }
        }

        if (lookUpTimestamp < sampleLastUpdate) {
            unchecked {
                if (oracleId == 0) {
                    oracleId = length;
                }

                return (oracle.samples[oracleId - 1], sample);
            }
        } else {
            assembly {
                oracleId := addmod(oracleId, 1, length)
            }

            return (sample, oracle.samples[oracleId]);
        }
    }

    /**
     * @dev Sets the sample at the given oracleId
     * @param oracle The oracle
     * @param oracleId The oracle id
     * @param sample The sample
     */
    function setSample(Oracle storage oracle, uint16 oracleId, bytes32 sample) internal {
        if (oracleId == 0) revert OracleHelper__InvalidOracleId();

        unchecked {
            oracle.samples[oracleId - 1] = sample;
        }
    }

    /**
     * @dev Updates the oracle
     * @param oracle The oracle
     * @param parameters The parameters
     * @param activeId The active id
     */
    function update(Oracle storage oracle, bytes32 parameters, uint24 activeId) internal {
        uint16 oracleId = parameters.getOracleId();
        if (oracleId == 0) return;

        bytes32 sample = getSample(oracle, oracleId);

        uint40 createdAt = sample.getSampleCreation();
        uint40 deltaTime = block.timestamp.safe40() - createdAt;

        if (deltaTime > 0) {
            (uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed) = sample.update(
                deltaTime, activeId, parameters.getVolatilityAccumulated(), parameters.getDeltaId(activeId)
            );

            uint16 length = sample.getOracleLength();

            if (deltaTime > _MAX_SAMPLE_LIFETIME) {
                deltaTime = 0;
                createdAt = uint40(block.timestamp);
                assembly {
                    oracleId := add(mod(oracleId, length), 1)
                }
            }

            sample = SampleMath.encode(
                length, cumulativeId, cumulativeVolatility, cumulativeBinCrossed, uint8(deltaTime), createdAt
            );

            setSample(oracle, oracleId, sample);
        }
    }

    /**
     * @dev Increases the oracle length
     * @param oracle The oracle
     * @param oracleId The oracle id
     * @param newLength The new length
     */
    function inreaseLength(Oracle storage oracle, uint16 oracleId, uint16 newLength) internal {
        bytes32 sample = getSample(oracle, oracleId);
        uint16 length = sample.getOracleLength();

        if (length >= newLength) revert OracleHelper__NewLengthTooSmall();

        for (uint256 i = length; i < newLength;) {
            oracle.samples[i] = bytes32(uint256(newLength));

            unchecked {
                ++i;
            }
        }

        if (oracleId != length) {
            setSample(oracle, oracleId, (sample ^ bytes32(uint256(length))) | bytes32(uint256(newLength)));
        }
    }
}
