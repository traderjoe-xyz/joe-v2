// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../src/libraries/math/SampleMath.sol";

contract SampleMathTest is Test {
    using SampleMath for bytes32;

    function testFuzz_GetOracleLength(bytes32 sample) external pure {
        uint256 oracleLength = sample.getOracleLength();
        assertLe(oracleLength, type(uint16).max, "testFuzz_GetOracleLength::1");
        assertEq(uint16(uint256(sample)), oracleLength, "testFuzz_GetOracleLength::2");
    }

    function testFuzz_GetCumulativeId(bytes32 sample) external pure {
        uint256 cumulativeId = sample.getCumulativeId();
        assertLe(cumulativeId, type(uint64).max, "testFuzz_GetCumulativeId::1");
        assertEq(uint64(uint256(sample) >> 16), cumulativeId, "testFuzz_GetCumulativeId::2");
    }

    function testFuzz_GetCumulativeVolatility(bytes32 sample) external pure {
        uint256 cumulativeVolatility = sample.getCumulativeVolatility();
        assertLe(cumulativeVolatility, type(uint64).max, "testFuzz_GetCumulativeVolatility::1");
        assertEq(uint64(uint256(sample) >> 80), cumulativeVolatility, "testFuzz_GetCumulativeVolatility::2");
    }

    function testFuzz_GetCumulativeBinCrossed(bytes32 sample) external pure {
        uint256 cumulativeBinCrossed = sample.getCumulativeBinCrossed();
        assertLe(cumulativeBinCrossed, type(uint64).max, "testFuzz_GetCumulativeBinCrossed::1");
        assertEq(uint64(uint256(sample) >> 144), cumulativeBinCrossed, "testFuzz_GetCumulativeBinCrossed::2");
    }

    function testFuzz_GetSampleLifetime(bytes32 sample) external pure {
        uint256 sampleLifetime = sample.getSampleLifetime();
        assertLe(sampleLifetime, type(uint8).max, "testFuzz_GetSampleLifetime::1");
        assertEq(uint8(uint256(sample) >> 208), sampleLifetime, "testFuzz_GetSampleLifetime::2");
    }

    function testFuzz_GetSampleCreation(bytes32 sample) external pure {
        uint256 sampleCreation = sample.getSampleCreation();
        assertLe(sampleCreation, type(uint40).max, "testFuzz_GetSampleCreation::1");
        assertEq(uint40(uint256(sample) >> 216), sampleCreation, "testFuzz_GetSampleCreation::2");
    }

    function testFuzz_GetSampleLastUpdate(bytes32 sample) external {
        uint40 sampleCreation = sample.getSampleCreation();
        uint8 sampleLifetime = sample.getSampleLifetime();

        if (sampleCreation > type(uint40).max - sampleLifetime) {
            vm.expectRevert();
            sample.getSampleLastUpdate();
        } else {
            uint40 sampleLastUpdate = sample.getSampleLastUpdate();
            assertEq(sampleLastUpdate, sampleCreation + sampleLifetime, "testFuzz_GetSampleLastUpdate::1");
        }
    }

    function testFuzz_encode(
        uint16 oracleLength,
        uint64 cumulativeId,
        uint64 cumulativeVolatility,
        uint64 cumulativeBinCrossed,
        uint8 sampleLifetime,
        uint40 createdAt
    ) external pure {
        bytes32 sample = SampleMath.encode(
            oracleLength, cumulativeId, cumulativeVolatility, cumulativeBinCrossed, sampleLifetime, createdAt
        );

        assertEq(sample.getOracleLength(), oracleLength, "testFuzz_encode::1");
        assertEq(sample.getCumulativeId(), cumulativeId, "testFuzz_encode::2");
        assertEq(sample.getCumulativeVolatility(), cumulativeVolatility, "testFuzz_encode::3");
        assertEq(sample.getCumulativeBinCrossed(), cumulativeBinCrossed, "testFuzz_encode::4");
        assertEq(sample.getSampleLifetime(), sampleLifetime, "testFuzz_encode::5");
        assertEq(sample.getSampleCreation(), createdAt, "testFuzz_encode::6");
    }

    function testFuzz_GetWeightedAverage(bytes32 sample1, bytes32 sample2, uint40 weight1, uint40 weight2) external {
        uint256 totalWeight = uint256(weight1) + weight2;

        if (totalWeight == 0) {
            vm.expectRevert();
            sample1.getWeightedAverage(sample2, weight1, weight2);
        }

        (uint256 wAverageId, uint256 wAverageVolatility, uint256 wAverageBinCrossed) = (0, 0, 0);

        {
            uint256 cId1 = sample1.getCumulativeId();
            uint256 cVol1 = sample1.getCumulativeVolatility();
            uint256 cBin1 = sample1.getCumulativeBinCrossed();

            uint256 cId2 = sample2.getCumulativeId();
            uint256 cVol2 = sample2.getCumulativeVolatility();
            uint256 cBin2 = sample2.getCumulativeBinCrossed();

            wAverageId = (cId1 * weight1 + cId2 * weight2) / totalWeight;
            wAverageVolatility = (cVol1 * weight1 + cVol2 * weight2) / totalWeight;
            wAverageBinCrossed = (cBin1 * weight1 + cBin2 * weight2) / totalWeight;
        }

        if (
            wAverageId > type(uint64).max || wAverageVolatility > type(uint64).max
                || wAverageBinCrossed > type(uint64).max
        ) {
            vm.expectRevert();
            sample1.getWeightedAverage(sample2, weight1, weight2);
        } else {
            (uint64 weightedAverageId, uint64 weightedAverageVolatility, uint64 weightedAverageBinCrossed) =
                sample1.getWeightedAverage(sample2, weight1, weight2);

            assertEq(weightedAverageId, wAverageId, "testFuzz_GetWeightedAverage::1");
            assertEq(weightedAverageVolatility, wAverageVolatility, "testFuzz_GetWeightedAverage::2");
            assertEq(weightedAverageBinCrossed, wAverageBinCrossed, "testFuzz_GetWeightedAverage::3");
        }
    }

    function testFuzz_update(uint40 deltaTime, uint24 activeId, uint24 volatilityAccumulator, uint24 binCrossed)
        external
        pure
    {
        (uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed) =
            bytes32(0).update(deltaTime, activeId, volatilityAccumulator, binCrossed);

        assertEq(cumulativeId, uint64(activeId) * deltaTime, "testFuzz_update::1");
        assertEq(cumulativeVolatility, uint64(volatilityAccumulator) * deltaTime, "testFuzz_update::2");
        assertEq(cumulativeBinCrossed, uint64(binCrossed) * deltaTime, "testFuzz_update::3");
    }

    function testFuzz_updateWithSample(
        bytes32 sample,
        uint40 deltaTime,
        uint24 activeId,
        uint24 volatilityAccumulator,
        uint24 binCrossed
    ) external {
        uint64 currentCumulativeId = sample.getCumulativeId();
        uint64 currentCumulativeVolatility = sample.getCumulativeVolatility();
        uint64 currentCumulativeBinCrossed = sample.getCumulativeBinCrossed();

        uint64(deltaTime) * activeId;
        uint64(deltaTime) * volatilityAccumulator;
        uint64(deltaTime) * binCrossed;

        if (
            uint64(deltaTime) * activeId > type(uint64).max - currentCumulativeId
                || uint64(deltaTime) * volatilityAccumulator > type(uint64).max - currentCumulativeVolatility
                || uint64(deltaTime) * binCrossed > type(uint64).max - currentCumulativeBinCrossed
        ) {
            vm.expectRevert();
            sample.update(deltaTime, activeId, volatilityAccumulator, binCrossed);
        } else {
            (uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed) =
                sample.update(deltaTime, activeId, volatilityAccumulator, binCrossed);

            assertEq(
                uint64(cumulativeId), currentCumulativeId + uint64(activeId) * deltaTime, "testFuzz_updateWithSample::1"
            );
            assertEq(
                uint64(cumulativeVolatility),
                currentCumulativeVolatility + uint64(volatilityAccumulator) * deltaTime,
                "testFuzz_updateWithSample::2"
            );
            assertEq(
                uint64(cumulativeBinCrossed),
                currentCumulativeBinCrossed + uint64(binCrossed) * deltaTime,
                "testFuzz_updateWithSample::3"
            );
        }
    }
}
