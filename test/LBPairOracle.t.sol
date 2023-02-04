// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./helpers/TestHelper.sol";

contract LBPairOracleTest is TestHelper {
    using PairParameterHelper for bytes32;

    function setUp() public override {
        super.setUp();

        pairWavax = createLBPair(wavax, usdc);

        addLiquidity(DEV, DEV, pairWavax, ID_ONE, 1e18, 1e18, 10, 10);
    }

    function testFuzz_IncreaseOracleLength(uint16 newLength) external {
        vm.assume(newLength > 0 && newLength < 100); // 100 is arbitrary, but a reasonable upper bound

        (, uint16 size, uint16 activeSize, uint40 lastUpdated, uint40 firstTimestamp) = pairWavax.getOracleParameters();

        assertEq(size, 0, "TestFuzz_IncreaseOracleLength::1");
        assertEq(activeSize, 0, "TestFuzz_IncreaseOracleLength::2");
        assertEq(lastUpdated, 0, "TestFuzz_IncreaseOracleLength::3");
        assertEq(firstTimestamp, 0, "TestFuzz_IncreaseOracleLength::4");

        pairWavax.increaseOracleLength(newLength);

        (, size, activeSize, lastUpdated, firstTimestamp) = pairWavax.getOracleParameters();

        assertEq(size, newLength, "TestFuzz_IncreaseOracleLength::5");
        assertEq(activeSize, 0, "TestFuzz_IncreaseOracleLength::6");
        assertEq(lastUpdated, 0, "TestFuzz_IncreaseOracleLength::7");
        assertEq(firstTimestamp, 0, "TestFuzz_IncreaseOracleLength::8");
    }

    function test_1SampleAdded() external {
        pairWavax.increaseOracleLength(100);

        deal(address(wavax), BOB, 1e18);
        vm.prank(BOB);
        wavax.transfer(address(pairWavax), 1e16);
        pairWavax.swap(true, BOB);

        (, uint16 size, uint16 activeSize, uint40 lastUpdated, uint40 firstTimestamp) = pairWavax.getOracleParameters();

        assertEq(size, 100, "Test_1SampleAdded::1");
        assertEq(activeSize, 1, "Test_1SampleAdded::2");
        assertEq(lastUpdated, block.timestamp, "Test_1SampleAdded::3");
        assertEq(firstTimestamp, block.timestamp, "Test_1SampleAdded::4");

        vm.warp(block.timestamp + 1);

        vm.prank(BOB);
        wavax.transfer(address(pairWavax), 1e16);
        pairWavax.swap(true, BOB);

        (, size, activeSize, lastUpdated, firstTimestamp) = pairWavax.getOracleParameters();

        assertEq(size, 100, "Test_1SampleAdded::5");
        assertEq(activeSize, 1, "Test_1SampleAdded::6");
        assertEq(lastUpdated, block.timestamp, "Test_1SampleAdded::7");
        assertEq(firstTimestamp, block.timestamp, "Test_1SampleAdded::8");
    }

    function test_CircularOracleWith2Samples() external {
        pairWavax.increaseOracleLength(2);

        deal(address(wavax), BOB, 1e18);
        vm.prank(BOB);
        wavax.transfer(address(pairWavax), 1e16);
        pairWavax.swap(true, BOB);

        (, uint16 size, uint16 activeSize, uint40 lastUpdated, uint40 firstTimestamp) = pairWavax.getOracleParameters();

        assertEq(size, 2, "Test_CircularOracle::1");
        assertEq(activeSize, 1, "Test_CircularOracle::2");
        assertEq(lastUpdated, block.timestamp, "Test_CircularOracle::3");
        assertEq(firstTimestamp, block.timestamp, "Test_CircularOracle::4");

        vm.warp(block.timestamp + 121);

        vm.prank(BOB);
        wavax.transfer(address(pairWavax), 1e16);
        pairWavax.swap(true, BOB);

        (, size, activeSize, lastUpdated, firstTimestamp) = pairWavax.getOracleParameters();

        assertEq(size, 2, "Test_CircularOracle::5");
        assertEq(activeSize, 2, "Test_CircularOracle::6");
        assertEq(lastUpdated, block.timestamp, "Test_CircularOracle::7");
        assertEq(firstTimestamp, block.timestamp - 121, "Test_CircularOracle::8");

        vm.warp(block.timestamp + 1000);

        vm.prank(BOB);
        wavax.transfer(address(pairWavax), 1e16);
        pairWavax.swap(true, BOB);

        (, size, activeSize, lastUpdated, firstTimestamp) = pairWavax.getOracleParameters();

        assertEq(size, 2, "Test_CircularOracle::9");
        assertEq(activeSize, 2, "Test_CircularOracle::10");
        assertEq(lastUpdated, block.timestamp, "Test_CircularOracle::11");
        assertEq(firstTimestamp, block.timestamp - 1000, "Test_CircularOracle::12");

        vm.warp(block.timestamp + 100);

        (, size, activeSize, lastUpdated, firstTimestamp) = pairWavax.getOracleParameters();

        assertEq(size, 2, "Test_CircularOracle::13");
        assertEq(activeSize, 2, "Test_CircularOracle::14");
        assertEq(lastUpdated, block.timestamp - 100, "Test_CircularOracle::15");
        assertEq(firstTimestamp, block.timestamp - 1100, "Test_CircularOracle::16");
    }

    function test_CircularOracleGetSampleAt() external {
        pairWavax.increaseOracleLength(2);

        deal(address(wavax), BOB, 1e18);
        vm.prank(BOB);
        wavax.transfer(address(pairWavax), 1e16);
        pairWavax.swap(true, BOB);

        uint256 dt = block.timestamp;

        (uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed) =
            pairWavax.getOracleSampleAt(uint40(block.timestamp));

        uint24 activeId = pairWavax.getActiveId();

        assertEq(cumulativeId, activeId * dt, "Test_CircularOracleGetSampleAt::1");
        assertEq(cumulativeVolatility, 0, "Test_CircularOracleGetSampleAt::2");
        assertEq(cumulativeBinCrossed, 0, "Test_CircularOracleGetSampleAt::3");

        dt = block.timestamp;
        vm.warp(block.timestamp + 121);

        vm.prank(BOB);
        wavax.transfer(address(pairWavax), 1e16);
        pairWavax.swap(true, BOB);

        dt = block.timestamp - dt;

        (uint64 previousCumulativeId, uint64 previousCumulativeVolatility, uint64 previousCumulativeBinCrossed) =
            (cumulativeId, cumulativeVolatility, cumulativeBinCrossed);
        (cumulativeId, cumulativeVolatility, cumulativeBinCrossed) =
            pairWavax.getOracleSampleAt(uint40(block.timestamp));

        activeId = pairWavax.getActiveId();

        assertEq(cumulativeId, previousCumulativeId + activeId * dt, "Test_CircularOracleGetSampleAt::4");
        assertEq(cumulativeVolatility, 0, "Test_CircularOracleGetSampleAt::5");
        assertEq(cumulativeBinCrossed, 0, "Test_CircularOracleGetSampleAt::6");

        dt = block.timestamp;
        vm.warp(block.timestamp + 1000);

        deal(address(usdc), BOB, 1e18);
        vm.prank(BOB);
        usdc.transfer(address(pairWavax), 1e18);
        pairWavax.swap(false, BOB);

        dt = block.timestamp - dt;

        (previousCumulativeId, previousCumulativeVolatility, previousCumulativeBinCrossed) =
            (cumulativeId, cumulativeVolatility, cumulativeBinCrossed);

        (cumulativeId, cumulativeVolatility, cumulativeBinCrossed) =
            pairWavax.getOracleSampleAt(uint40(block.timestamp));

        (uint24 volatilityAccumulator,,,) = pairWavax.getVariableFeeParameters();

        assertEq(cumulativeId, previousCumulativeId + pairWavax.getActiveId() * dt, "Test_CircularOracleGetSampleAt::7");
        assertEq(cumulativeVolatility, volatilityAccumulator * dt, "Test_CircularOracleGetSampleAt::8");
        assertEq(cumulativeBinCrossed, (pairWavax.getActiveId() - activeId) * dt, "Test_CircularOracleGetSampleAt::9");
    }

    function test_MaxLengthOracle() external {
        deal(address(wavax), BOB, 1e36);
        deal(address(usdc), BOB, 1e36);

        pairWavax.increaseOracleLength(65535);

        vm.warp(1_000);

        vm.startPrank(BOB);
        for (uint256 i = 0; i < 65535; i++) {
            wavax.transfer(address(pairWavax), 1e10);
            pairWavax.swap(true, BOB);

            vm.warp(block.timestamp + 121);
        }
        vm.stopPrank();

        (, uint256 size, uint256 activeSize, uint256 lastUpdated, uint256 firstTimestamp) =
            pairWavax.getOracleParameters();

        assertEq(size, 65535, "Test_MaxLengthOracle::1");
        assertEq(activeSize, 65535, "Test_MaxLengthOracle::2");
        assertEq(lastUpdated, block.timestamp - 121, "Test_MaxLengthOracle::3");
        assertEq(firstTimestamp, block.timestamp - 65535 * 121, "Test_MaxLengthOracle::4");

        uint24 activeId = pairWavax.getActiveId();

        {
            (uint64 cumulativeId1, uint64 cumulativeVolatility1, uint64 cumulativeBinCrossed1) =
                pairWavax.getOracleSampleAt(uint40(block.timestamp));
            (uint64 cumulativeId2, uint64 cumulativeVolatility2, uint64 cumulativeBinCrossed2) =
                pairWavax.getOracleSampleAt(uint40(block.timestamp - 121));

            assertEq(cumulativeId1, cumulativeId2 + uint64(activeId) * 121, "Test_MaxLengthOracle::5");

            // True as the active id never changed:
            assertEq(cumulativeVolatility1, 0, "Test_MaxLengthOracle::6");
            assertEq(cumulativeBinCrossed1, 0, "Test_MaxLengthOracle::7");
            assertEq(cumulativeVolatility2, 0, "Test_MaxLengthOracle::8");
            assertEq(cumulativeBinCrossed2, 0, "Test_MaxLengthOracle::9");
            assertEq((cumulativeId1 - cumulativeId2) / 121, activeId, "Test_MaxLengthOracle::10");
            assertEq(cumulativeBinCrossed1, 0, "Test_MaxLengthOracle::11");

            (cumulativeId2,,) = pairWavax.getOracleSampleAt(uint40(block.timestamp / 2));
            assertEq(
                uint256(cumulativeId1) * 1e18 / block.timestamp,
                uint256(cumulativeId2) * 1e18 / (block.timestamp / 2),
                "Test_MaxLengthOracle::10"
            );
        }

        // now a swap that moves ids:
        vm.warp(block.timestamp + 1000 - 121);

        vm.prank(BOB);
        usdc.transfer(address(pairWavax), 1e18);
        pairWavax.swap(false, BOB);

        uint64 newActiveId = pairWavax.getActiveId();

        (uint64 cumulativeIdNow, uint64 cumulativeVolatilityNow, uint64 cumulativeBinCrossedNow) =
            pairWavax.getOracleSampleAt(uint40(block.timestamp));

        (uint64 cumulativeIdPastHour, uint64 cumulativeVolatilityPastHour, uint64 cumulativeBinCrossedPastHour) =
            pairWavax.getOracleSampleAt(uint40(block.timestamp - 3600));

        (uint64 cumulativeIdPastDay, uint64 cumulativeVolatilityPastDay, uint64 cumulativeBinCrossedPastDay) =
            pairWavax.getOracleSampleAt(uint40(block.timestamp - 86400));

        assertEq(cumulativeVolatilityPastDay, 0, "Test_MaxLengthOracle::13");
        assertEq(cumulativeBinCrossedPastDay, 0, "Test_MaxLengthOracle::14");

        assertEq(cumulativeVolatilityPastHour, 0, "Test_MaxLengthOracle::15");
        assertEq(cumulativeBinCrossedPastHour, 0, "Test_MaxLengthOracle::16");

        assertEq(cumulativeIdPastDay + uint64(activeId) * 3600 * 23, cumulativeIdPastHour, "Test_MaxLengthOracle::17");

        assertEq(
            cumulativeIdPastHour + uint64(activeId) * 2600 + uint64(newActiveId) * 1000,
            cumulativeIdNow,
            "Test_MaxLengthOracle::18"
        );
        assertEq(cumulativeVolatilityNow, (newActiveId - activeId) * 10_000 * 1000, "Test_MaxLengthOracle::19");
        assertEq(cumulativeBinCrossedNow, (newActiveId - activeId) * 1000, "Test_MaxLengthOracle::20");
    }

    function test_GetOracleParametersEmptyOracle() external {
        (, uint256 size, uint256 activeSize, uint256 lastUpdated, uint256 firstTimestamp) =
            pairWavax.getOracleParameters();

        assertEq(size, 0, "Test_GetOracleParametersEmptyOracle::1");
        assertEq(activeSize, 0, "Test_GetOracleParametersEmptyOracle::2");
        assertEq(lastUpdated, 0, "Test_GetOracleParametersEmptyOracle::3");
        assertEq(firstTimestamp, 0, "Test_GetOracleParametersEmptyOracle::4");
    }
}
