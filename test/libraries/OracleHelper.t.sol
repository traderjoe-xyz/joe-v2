// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../src/libraries/OracleHelper.sol";
import "../../src/libraries/math/Encoded.sol";

contract OracleHelperTest is Test {
    using OracleHelper for OracleHelper.Oracle;
    using SampleMath for bytes32;
    using PairParameterHelper for bytes32;
    using Encoded for bytes32;

    OracleHelper.Oracle private oracle;

    function testFuzz_SetAndGetSample(uint16 oracleId, bytes32 sample) external {
        vm.assume(oracleId > 0);

        oracle.setSample(oracleId, sample);
        assertEq(oracle.getSample(oracleId), sample, "test_SetSample::1");
        assertEq(oracle.samples[oracleId - 1], sample, "test_SetSample::2");
    }

    function testFuzz_revert_SetAndGetSample(bytes32 sample) external {
        uint16 oracleId = 0;

        vm.expectRevert(OracleHelper.OracleHelper__InvalidOracleId.selector);
        oracle.setSample(oracleId, sample);

        vm.expectRevert(OracleHelper.OracleHelper__InvalidOracleId.selector);
        oracle.getSample(oracleId);
    }

    function test_BinarySearchSimple() external {
        bytes32 sample1 = SampleMath.encode(3, 1, 2, 3, 0, 0);
        bytes32 sample2 = SampleMath.encode(3, 2, 3, 4, 0, 10);
        bytes32 sample3 = SampleMath.encode(3, 3, 4, 5, 0, 20);

        oracle.setSample(1, sample1);
        oracle.setSample(2, sample2);
        oracle.setSample(3, sample3);

        (bytes32 previous, bytes32 next) = oracle.binarySearch(3, 0, 3);

        assertEq(previous, sample1, "test_binarySearch::1");
        assertEq(next, sample1, "test_binarySearch::2");

        (previous, next) = oracle.binarySearch(3, 1, 3);

        assertEq(previous, sample1, "test_binarySearch::3");
        assertEq(next, sample2, "test_binarySearch::4");

        (previous, next) = oracle.binarySearch(3, 9, 3);

        assertEq(previous, sample1, "test_binarySearch::5");
        assertEq(next, sample2, "test_binarySearch::6");

        (previous, next) = oracle.binarySearch(3, 10, 3);

        assertEq(previous, sample2, "test_binarySearch::7");
        assertEq(next, sample2, "test_binarySearch::8");

        (previous, next) = oracle.binarySearch(3, 11, 3);

        assertEq(previous, sample2, "test_binarySearch::9");
        assertEq(next, sample3, "test_binarySearch::10");

        (previous, next) = oracle.binarySearch(3, 20, 3);

        assertEq(previous, sample3, "test_binarySearch::11");
        assertEq(next, sample3, "test_binarySearch::12");
    }

    function test_BinarySearchCircular() external {
        bytes32 sample1 = SampleMath.encode(3, 1, 2, 3, 3, 30); // sample at timestamp 0 got overriden
        bytes32 sample2 = SampleMath.encode(3, 2, 3, 4, 9, 10);
        bytes32 sample3 = SampleMath.encode(3, 3, 4, 5, 9, 20);

        oracle.setSample(1, sample1);
        oracle.setSample(2, sample2);
        oracle.setSample(3, sample3);

        (bytes32 previous, bytes32 next) = oracle.binarySearch(1, 19, 3);

        assertEq(previous, sample2, "test_binarySearch::1");
        assertEq(next, sample2, "test_binarySearch::2");

        (previous, next) = oracle.binarySearch(1, 24, 3);

        assertEq(previous, sample2, "test_binarySearch::3");
        assertEq(next, sample3, "test_binarySearch::4");

        (previous, next) = oracle.binarySearch(1, 29, 3);

        assertEq(previous, sample3, "test_binarySearch::5");
        assertEq(next, sample3, "test_binarySearch::6");

        (previous, next) = oracle.binarySearch(1, 30, 3);

        assertEq(previous, sample3, "test_binarySearch::7");
        assertEq(next, sample1, "test_binarySearch::8");

        (previous, next) = oracle.binarySearch(1, 33, 3);

        assertEq(previous, sample1, "test_binarySearch::9");
        assertEq(next, sample1, "test_binarySearch::10");
    }

    function test_revert_BinarySearch() external {
        bytes32 sample1 = SampleMath.encode(3, 1, 2, 3, 0, 30); // sample at timestamp 0 got overriden
        bytes32 sample2 = SampleMath.encode(3, 2, 3, 4, 5, 10);

        vm.expectRevert();
        oracle.binarySearch(0, 20, 3); // invalid oracleId

        vm.expectRevert();
        oracle.binarySearch(1, 20, 0); // invalid length

        oracle.setSample(1, sample1);
        oracle.setSample(2, sample2);

        vm.expectRevert();
        oracle.binarySearch(0, 20, 3); // invalid oracleId

        vm.expectRevert();
        oracle.binarySearch(1, 20, 0); // invalid length

        vm.expectRevert();
        oracle.binarySearch(1, 9, 2); // invalid timestamp

        vm.expectRevert();
        oracle.binarySearch(1, 31, 2); // invalid timestamp
    }

    function test_GetSampleAtFullyInitialized() external {
        bytes32 sample1 = SampleMath.encode(3, 40, 50, 60, 3, 30); // sample at timestamp 0 got overriden
        bytes32 sample2 = SampleMath.encode(3, 20, 30, 40, 5, 10);
        bytes32 sample3 = SampleMath.encode(3, 30, 40, 50, 5, 20);

        oracle.setSample(1, sample1);
        oracle.setSample(2, sample2);
        oracle.setSample(3, sample3);

        (uint40 lastUpdate, uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed) =
            oracle.getSampleAt(1, 15);

        assertEq(lastUpdate, 15, "test_GetSampleAt::1");
        assertEq(cumulativeId, 20, "test_GetSampleAt::2");
        assertEq(cumulativeVolatility, 30, "test_GetSampleAt::3");
        assertEq(cumulativeBinCrossed, 40, "test_GetSampleAt::4");

        (lastUpdate, cumulativeId, cumulativeVolatility, cumulativeBinCrossed) = oracle.getSampleAt(1, 20);

        assertEq(lastUpdate, 20, "test_GetSampleAt::5");
        assertEq(cumulativeId, 25, "test_GetSampleAt::6");
        assertEq(cumulativeVolatility, 35, "test_GetSampleAt::7");
        assertEq(cumulativeBinCrossed, 45, "test_GetSampleAt::8");

        (lastUpdate, cumulativeId, cumulativeVolatility, cumulativeBinCrossed) = oracle.getSampleAt(1, 25);

        assertEq(lastUpdate, 25, "test_GetSampleAt::9");
        assertEq(cumulativeId, 30, "test_GetSampleAt::10");
        assertEq(cumulativeVolatility, 40, "test_GetSampleAt::11");
        assertEq(cumulativeBinCrossed, 50, "test_GetSampleAt::12");

        (lastUpdate, cumulativeId, cumulativeVolatility, cumulativeBinCrossed) = oracle.getSampleAt(1, 30);

        assertEq(lastUpdate, 30, "test_GetSampleAt::13");
        assertEq(cumulativeId, 36, "test_GetSampleAt::14");
        assertEq(cumulativeVolatility, 46, "test_GetSampleAt::15");
        assertEq(cumulativeBinCrossed, 56, "test_GetSampleAt::16");

        (lastUpdate, cumulativeId, cumulativeVolatility, cumulativeBinCrossed) = oracle.getSampleAt(1, 40);

        assertEq(lastUpdate, 33, "test_GetSampleAt::17");
        assertEq(cumulativeId, 40, "test_GetSampleAt::18");
        assertEq(cumulativeVolatility, 50, "test_GetSampleAt::19");
        assertEq(cumulativeBinCrossed, 60, "test_GetSampleAt::20");
    }

    struct Updateinputs {
        uint16 oracleLength;
        uint16 oracleId;
        uint24 previousActiveId;
        uint24 activeId;
        uint24 previousVolatility;
        uint24 volatility;
        uint24 previousBinCrossed;
        uint40 createdAt;
        uint40 timestamp;
    }

    function testFuzz_UpdateDeltaTsLowerThan2Minutes(Updateinputs memory inputs) external {
        vm.assume(
            inputs.oracleId > 0 && inputs.oracleLength >= inputs.oracleId && inputs.createdAt <= inputs.timestamp
                && inputs.timestamp - inputs.createdAt <= 120 && inputs.volatility <= Encoded.MASK_UINT20
                && inputs.previousVolatility <= Encoded.MASK_UINT20
        );

        vm.warp(inputs.createdAt);

        bytes32 sample = SampleMath.encode(
            inputs.oracleLength,
            uint64(inputs.previousActiveId) * inputs.createdAt,
            uint64(inputs.previousVolatility) * inputs.createdAt,
            uint64(inputs.previousBinCrossed) * inputs.createdAt,
            0,
            inputs.createdAt
        );

        oracle.setSample(inputs.oracleId, sample);

        bytes32 parameters = bytes32(0).setOracleId(inputs.oracleId).setActiveId(inputs.previousActiveId).set(
            inputs.volatility, Encoded.MASK_UINT20, PairParameterHelper.OFFSET_VOL_ACC
        );

        vm.warp(inputs.timestamp);

        bytes32 newParams = oracle.update(parameters, inputs.activeId);

        assertEq(newParams, parameters, "test_Update::1");

        sample = oracle.getSample(inputs.oracleId);

        uint64 dt = uint64(inputs.timestamp - inputs.createdAt);

        uint24 dId = inputs.activeId > inputs.previousActiveId
            ? inputs.activeId - inputs.previousActiveId
            : inputs.previousActiveId - inputs.activeId;

        uint64 cumulativeId = uint64(inputs.previousActiveId) * inputs.createdAt + uint64(inputs.activeId) * dt;
        uint64 cumulativeVolatility =
            uint64(inputs.previousVolatility) * inputs.createdAt + uint64(inputs.volatility) * dt;
        uint64 cumulativeBinCrossed = uint64(inputs.previousBinCrossed) * inputs.createdAt + uint64(dId) * dt;

        assertEq(sample.getOracleLength(), inputs.oracleLength, "test_Update::3");
        assertEq(sample.getCumulativeId(), cumulativeId, "test_Update::4");
        assertEq(sample.getCumulativeVolatility(), cumulativeVolatility, "test_Update::5");
        assertEq(sample.getCumulativeBinCrossed(), cumulativeBinCrossed, "test_Update::6");
    }

    function testFuzz_UpdateDeltaTsGreaterThan2Minutes(Updateinputs memory inputs) external {
        vm.assume(
            inputs.oracleId > 0 && inputs.oracleLength >= inputs.oracleId && inputs.createdAt <= inputs.timestamp
                && inputs.timestamp - inputs.createdAt > 120 && inputs.volatility <= Encoded.MASK_UINT20
                && inputs.previousVolatility <= Encoded.MASK_UINT20
        );

        vm.warp(inputs.createdAt);

        bytes32 sample = SampleMath.encode(
            inputs.oracleLength,
            uint64(inputs.previousActiveId) * inputs.createdAt,
            uint64(inputs.previousVolatility) * inputs.createdAt,
            uint64(inputs.previousBinCrossed) * inputs.createdAt,
            0,
            inputs.createdAt
        );

        oracle.setSample(inputs.oracleId, sample);

        bytes32 parameters = bytes32(0).setOracleId(inputs.oracleId).setActiveId(inputs.previousActiveId).set(
            inputs.volatility, Encoded.MASK_UINT20, PairParameterHelper.OFFSET_VOL_ACC
        );

        vm.warp(inputs.timestamp);

        bytes32 newParameters = oracle.update(parameters, inputs.activeId);

        uint16 nextId = uint16(uint256(inputs.oracleId % inputs.oracleLength) + 1);

        assertEq(newParameters, parameters.setOracleId(nextId), "test_Update::1");
        if (inputs.oracleLength > 1) assertEq(oracle.getSample(inputs.oracleId), sample, "test_Update::2");

        sample = oracle.getSample(nextId);

        uint64 dt = uint64(inputs.timestamp - inputs.createdAt);

        uint24 dId = inputs.activeId > inputs.previousActiveId
            ? inputs.activeId - inputs.previousActiveId
            : inputs.previousActiveId - inputs.activeId;

        uint64 cumulativeId = uint64(inputs.previousActiveId) * inputs.createdAt + uint64(inputs.activeId) * dt;
        uint64 cumulativeVolatility =
            uint64(inputs.previousVolatility) * inputs.createdAt + uint64(inputs.volatility) * dt;
        uint64 cumulativeBinCrossed = uint64(inputs.previousBinCrossed) * inputs.createdAt + uint64(dId) * dt;

        assertEq(sample.getOracleLength(), inputs.oracleLength, "test_Update::3");
        assertEq(sample.getCumulativeId(), cumulativeId, "test_Update::4");
        assertEq(sample.getCumulativeVolatility(), cumulativeVolatility, "test_Update::5");
        assertEq(sample.getCumulativeBinCrossed(), cumulativeBinCrossed, "test_Update::6");
    }

    function testFuzz_IncreaseOracleLength(uint16 length, uint16 newLength) external {
        vm.assume(length > 0 && newLength > length && newLength <= 100); // 100 is arbitrary to avoid tests taking too long

        uint16 oracleId = 1;

        oracle.increaseLength(oracleId, length);

        oracle.increaseLength(oracleId, newLength);

        assertEq(oracle.getSample(oracleId).getOracleLength(), newLength, "test_IncreaseOracleLength::1");
    }

    function testFuzz_revert_IncreaseOracleLength(uint16 length, uint16 newLength) external {
        vm.assume(newLength <= length && length > 0);

        oracle.increaseLength(1, length);

        vm.expectRevert(OracleHelper.OracleHelper__NewLengthTooSmall.selector);
        oracle.increaseLength(1, newLength);
    }

    function test_revert_IncreaseOracleLength() external {
        vm.expectRevert(OracleHelper.OracleHelper__InvalidOracleId.selector);
        oracle.increaseLength(0, 10);
    }

    function test_GetSampleAtNotFullyInitialized() external {
        bytes32 parameters = bytes32(0).setOracleId(1).setActiveId(1000).set(
            1000, Encoded.MASK_UINT20, PairParameterHelper.OFFSET_VOL_ACC
        );
        oracle.increaseLength(parameters.getOracleId(), 3);
        _verifyTimestampsIdsAndSize(parameters, 1, hex"030101", 1); // id : 1, oracle: 3 1 1, activeSize: 1

        vm.warp(100);

        parameters = oracle.update(parameters, 1000);
        _verifyTimestampsIdsAndSize(parameters, 1, hex"030101", 1); // id : 1, oracle: 3 1 1, activeSize: 1

        vm.warp(221);

        parameters = oracle.update(parameters, 1000);
        _verifyTimestampsIdsAndSize(parameters, 2, hex"030301", 2); // id : 2, oracle: 3 3 1, activeSize: 2

        oracle.increaseLength(parameters.getOracleId(), 4);
        _verifyTimestampsIdsAndSize(parameters, 2, hex"03040102", 2); // id : 2, oracle: 3 4 1 2, activeSize: 2

        vm.warp(222);

        parameters = oracle.update(parameters, 1000);
        _verifyTimestampsIdsAndSize(parameters, 2, hex"03040102", 2); // id : 2, oracle: 3 4 1 2, activeSize: 2

        vm.warp(342);

        parameters = oracle.update(parameters, 1000);
        _verifyTimestampsIdsAndSize(parameters, 3, hex"03040402", 3); // id : 3, oracle: 3 4 4 2, activeSize: 3

        oracle.increaseLength(parameters.getOracleId(), 5);
        _verifyTimestampsIdsAndSize(parameters, 3, hex"0304050203", 3); // id : 3, oracle: 3 4 5 2 3, activeSize: 3

        vm.warp(463);

        parameters = oracle.update(parameters, 1000);
        _verifyTimestampsIdsAndSize(parameters, 4, hex"0304050503", 4); // id : 4, oracle: 3 4 5 5 3, activeSize: 4

        vm.warp(584);

        parameters = oracle.update(parameters, 1000);
        _verifyTimestampsIdsAndSize(parameters, 5, hex"0304050505", 5); // id : 5, oracle: 3 4 5 5 5, activeSize: 5

        oracle.increaseLength(parameters.getOracleId(), 7);
        _verifyTimestampsIdsAndSize(parameters, 5, hex"03040505070505", 5); // id : 5, oracle: 3 4 5 5 7 5 5, activeSize: 5

        vm.warp(705);

        parameters = oracle.update(parameters, 1000);
        _verifyTimestampsIdsAndSize(parameters, 6, hex"03040505070705", 6); // id : 6, oracle: 3 4 5 5 7 7 5, activeSize: 6

        vm.warp(826);

        parameters = oracle.update(parameters, 1000);
        _verifyTimestampsIdsAndSize(parameters, 7, hex"03040505070707", 7); // id : 7, oracle: 3 4 5 5 7 7 7, activeSize: 7

        vm.warp(947);

        parameters = oracle.update(parameters, 1000);
        _verifyTimestampsIdsAndSize(parameters, 1, hex"07040505070707", 7); // id : 1, oracle: 7 4 5 5 7 7 7, activeSize: 7

        oracle.increaseLength(parameters.getOracleId(), 8);
        _verifyTimestampsIdsAndSize(parameters, 1, hex"0804050507070707", 7); // id : 1, oracle: 8 4 5 5 7 7 7 7, activeSize: 7

        vm.warp(1068);

        parameters = oracle.update(parameters, 1000);
        _verifyTimestampsIdsAndSize(parameters, 2, hex"0808050507070707", 7); // id : 2, oracle: 8 8 5 5 7 7 7 7, activeSize: 7
    }

    function _verifyTimestampsIdsAndSize(bytes32 parameters, uint16 oracleId, bytes memory times, uint16 activeSize)
        internal
    {
        assertEq(parameters.getOracleId(), oracleId, "_verifyTimestampsIdsAndSize::id");

        for (uint16 i = 0; i < times.length; i++) {
            bytes32 sample = oracle.getSample(i + 1);

            assertEq(
                sample.getOracleLength(),
                uint256(uint8(times[i])),
                string(abi.encodePacked("_verifyTimestampsIdsAndSize::", vm.toString(i)))
            );
        }

        (, uint16 aSize) = oracle.getActiveSampleAndSize(oracleId);

        assertEq(aSize, activeSize, "_verifyTimestampsIdsAndSize::activeSize");
    }
}
