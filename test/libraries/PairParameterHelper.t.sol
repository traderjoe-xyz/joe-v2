// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../src/libraries/PairParameterHelper.sol";

contract PairParameterHelperTest is Test {
    using PairParameterHelper for bytes32;

    struct StaticFeeParameters {
        uint16 baseFactor;
        uint16 filterPeriod;
        uint16 decayPeriod;
        uint16 reductionFactor;
        uint24 variableFeeControl;
        uint16 protocolShare;
        uint24 maxVolatilityAccumulator;
    }

    function testFuzz_StaticFeeParameters(bytes32 params, StaticFeeParameters memory sfp) external {
        vm.assume(
            sfp.filterPeriod <= sfp.decayPeriod && sfp.decayPeriod <= Encoded.MASK_UINT12
                && sfp.reductionFactor <= Constants.BASIS_POINT_MAX
                && sfp.protocolShare <= PairParameterHelper.MAX_PROTOCOL_SHARE
                && sfp.maxVolatilityAccumulator <= Encoded.MASK_UINT20
        );

        bytes32 newParams = params.setStaticFeeParameters(
            sfp.baseFactor,
            sfp.filterPeriod,
            sfp.decayPeriod,
            sfp.reductionFactor,
            sfp.variableFeeControl,
            sfp.protocolShare,
            sfp.maxVolatilityAccumulator
        );

        assertEq(
            newParams >> PairParameterHelper.OFFSET_VOL_ACC,
            params >> PairParameterHelper.OFFSET_VOL_ACC,
            "testFuzz_StaticFeeParameters::1"
        );

        assertEq(newParams.getBaseFactor(), sfp.baseFactor, "testFuzz_StaticFeeParameters::2");
        assertEq(newParams.getFilterPeriod(), sfp.filterPeriod, "testFuzz_StaticFeeParameters::3");
        assertEq(newParams.getDecayPeriod(), sfp.decayPeriod, "testFuzz_StaticFeeParameters::4");
        assertEq(newParams.getReductionFactor(), sfp.reductionFactor, "testFuzz_StaticFeeParameters::5");
        assertEq(newParams.getVariableFeeControl(), sfp.variableFeeControl, "testFuzz_StaticFeeParameters::6");
        assertEq(newParams.getProtocolShare(), sfp.protocolShare, "testFuzz_StaticFeeParameters::7");
        assertEq(
            newParams.getMaxVolatilityAccumulator(), sfp.maxVolatilityAccumulator, "testFuzz_StaticFeeParameters::8"
        );
    }

    function testFuzz_revert_StaticFeeParameters(bytes32 params, StaticFeeParameters memory sfp) external {
        vm.assume(
            sfp.filterPeriod > sfp.decayPeriod || sfp.decayPeriod > Encoded.MASK_UINT12
                || sfp.reductionFactor > Constants.BASIS_POINT_MAX
                || sfp.protocolShare > PairParameterHelper.MAX_PROTOCOL_SHARE
                || sfp.maxVolatilityAccumulator > Encoded.MASK_UINT20
        );

        vm.expectRevert(PairParameterHelper.PairParametersHelper__InvalidParameter.selector);
        params.setStaticFeeParameters(
            sfp.baseFactor,
            sfp.filterPeriod,
            sfp.decayPeriod,
            sfp.reductionFactor,
            sfp.variableFeeControl,
            sfp.protocolShare,
            sfp.maxVolatilityAccumulator
        );
    }

    function testFuzz_SetOracleId(bytes32 params, uint16 oracleId) external {
        bytes32 newParams = params.setOracleId(oracleId);

        assertEq(newParams.getOracleId(), oracleId, "testFuzz_SetOracleId::1");
        assertEq(
            newParams & bytes32(~Encoded.MASK_UINT16 << PairParameterHelper.OFFSET_ORACLE_ID),
            params & bytes32(~Encoded.MASK_UINT16 << PairParameterHelper.OFFSET_ORACLE_ID),
            "testFuzz_SetOracleId::2"
        );
    }

    function testFuzz_SetVolatilityReference(bytes32 params, uint24 volatilityReference) external {
        vm.assume(volatilityReference <= Encoded.MASK_UINT20);

        bytes32 newParams = params.setVolatilityReference(volatilityReference);

        assertEq(newParams.getVolatilityReference(), volatilityReference, "testFuzz_SetVolatilityReference::1");
        assertEq(
            newParams & bytes32(~Encoded.MASK_UINT20 << PairParameterHelper.OFFSET_VOL_REF),
            params & bytes32(~Encoded.MASK_UINT20 << PairParameterHelper.OFFSET_VOL_REF),
            "testFuzz_SetVolatilityReference::2"
        );
    }

    function testFuzz_revert_SetVolatilityReference(bytes32 params, uint24 volatilityReference) external {
        vm.assume(volatilityReference > Encoded.MASK_UINT20);

        vm.expectRevert(PairParameterHelper.PairParametersHelper__InvalidParameter.selector);
        params.setVolatilityReference(volatilityReference);
    }

    function testFuzz_SetVolatilityAccumulator(bytes32 params, uint24 volatilityAccumulator) external {
        vm.assume(volatilityAccumulator <= Encoded.MASK_UINT20);

        bytes32 newParams = params.setVolatilityAccumulator(volatilityAccumulator);

        assertEq(newParams.getVolatilityAccumulator(), volatilityAccumulator, "testFuzz_SetVolatilityAccumulator::1");
        assertEq(
            newParams & bytes32(~Encoded.MASK_UINT20 << PairParameterHelper.OFFSET_VOL_ACC),
            params & bytes32(~Encoded.MASK_UINT20 << PairParameterHelper.OFFSET_VOL_ACC),
            "testFuzz_SetVolatilityAccumulator::2"
        );
    }

    function testFuzz_revert_SetVolatilityAccumulator(bytes32 params, uint24 volatilityAccumulator) external {
        vm.assume(volatilityAccumulator > Encoded.MASK_UINT20);

        vm.expectRevert(PairParameterHelper.PairParametersHelper__InvalidParameter.selector);
        params.setVolatilityAccumulator(volatilityAccumulator);
    }

    function testFuzz_SetActiveId(bytes32 params, uint24 activeId) external {
        uint24 previousActiveId = params.getActiveId();
        uint24 deltaId = previousActiveId > activeId ? previousActiveId - activeId : activeId - previousActiveId;
        assertEq(params.getDeltaId(activeId), deltaId, "testFuzz_SetActiveId::1");

        bytes32 newParams = params.setActiveId(activeId);

        assertEq(newParams.getActiveId(), activeId, "testFuzz_SetActiveId::2");
        assertEq(newParams.getDeltaId(activeId), 0, "testFuzz_SetActiveId::3");
        assertEq(newParams.getDeltaId(previousActiveId), deltaId, "testFuzz_SetActiveId::4");
        assertEq(
            newParams & bytes32(~Encoded.MASK_UINT24 << PairParameterHelper.OFFSET_ACTIVE_ID),
            params & bytes32(~Encoded.MASK_UINT24 << PairParameterHelper.OFFSET_ACTIVE_ID),
            "testFuzz_SetActiveId::5"
        );
    }

    function testFuzz_getBaseAndVariableFees(bytes32 params, uint8 binStep) external {
        uint256 baseFee = params.getBaseFee(binStep);
        uint256 variableFee = params.getVariableFee(binStep);

        assertEq(baseFee, uint256(params.getBaseFactor()) * binStep * 5e9, "test_getBaseAndVariableFees::1");

        uint256 prod = uint256(params.getVolatilityAccumulator()) * binStep;
        assertEq(
            variableFee, (prod * prod * params.getVariableFeeControl() + 399) / 400, "test_getBaseAndVariableFees::2"
        );

        if (baseFee + variableFee < type(uint128).max) {
            assertEq(params.getTotalFee(binStep), baseFee + variableFee, "test_getBaseAndVariableFees::3");
        } else {
            vm.expectRevert(SafeCast.SafeCast__Exceeds128Bits.selector);
            params.getTotalFee(binStep);
        }
    }

    function testFuzz_UpdateIdReference(bytes32 params) external {
        uint24 activeId = params.getActiveId();

        bytes32 newParams = params.updateIdReference();

        assertEq(newParams.getIdReference(), activeId, "test_UpdateIdReference::1");
        assertEq(
            newParams & bytes32(~Encoded.MASK_UINT24 << PairParameterHelper.OFFSET_ACTIVE_ID),
            params & bytes32(~Encoded.MASK_UINT24 << PairParameterHelper.OFFSET_ACTIVE_ID),
            "test_UpdateIdReference::2"
        );
    }

    function testFuzz_UpdateTimeOfLastUpdate(bytes32 params) external {
        bytes32 newParams = params.updateTimeOfLastUpdate();

        assertEq(newParams.getTimeOfLastUpdate(), block.timestamp, "test_UpdateTimeOfLastUpdate::1");
        assertEq(
            newParams & bytes32(~Encoded.MASK_UINT40 << PairParameterHelper.OFFSET_TIME_LAST_UPDATE),
            params & bytes32(~Encoded.MASK_UINT40 << PairParameterHelper.OFFSET_TIME_LAST_UPDATE),
            "test_UpdateTimeOfLastUpdate::2"
        );
    }

    function testFuzz_UpdateVolatilityReference(bytes32 params) external {
        uint256 volAccumulator = params.getVolatilityAccumulator();
        uint256 reductionFactor = params.getReductionFactor();

        uint256 newVolAccumulator = volAccumulator * reductionFactor / Constants.BASIS_POINT_MAX;

        if (newVolAccumulator > Encoded.MASK_UINT20) {
            vm.expectRevert(PairParameterHelper.PairParametersHelper__InvalidParameter.selector);
            params.updateVolatilityReference();
        } else {
            bytes32 newParams = params.updateVolatilityReference();

            assertEq(newParams.getVolatilityReference(), newVolAccumulator, "test_UpdateVolatilityReference::1");
            assertEq(
                newParams & bytes32(~Encoded.MASK_UINT20 << PairParameterHelper.OFFSET_VOL_REF),
                params & bytes32(~Encoded.MASK_UINT20 << PairParameterHelper.OFFSET_VOL_REF),
                "test_UpdateVolatilityReference::2"
            );
        }
    }

    function testFuzz_UpdateVolatilityAccumulator(bytes32 params, uint24 activeId) external {
        uint256 idReference = params.getIdReference();
        uint256 deltaId = activeId > idReference ? activeId - idReference : idReference - activeId;

        uint256 volAccumulator = params.getVolatilityReference() + deltaId * Constants.BASIS_POINT_MAX;
        volAccumulator = volAccumulator > params.getMaxVolatilityAccumulator()
            ? params.getMaxVolatilityAccumulator()
            : volAccumulator;

        bytes32 newParams = params.updateVolatilityAccumulator(activeId);

        assertEq(newParams.getVolatilityAccumulator(), volAccumulator, "test_UpdateVolatilityAccumulator::1");
        assertEq(
            newParams & bytes32(~Encoded.MASK_UINT20 << PairParameterHelper.OFFSET_VOL_ACC),
            params & bytes32(~Encoded.MASK_UINT20 << PairParameterHelper.OFFSET_VOL_ACC),
            "test_UpdateVolatilityAccumulator::2"
        );
    }

    function testFuzz_UpdateReferences(bytes32 params, StaticFeeParameters memory sfp, uint40 previousTime, uint40 time)
        external
    {
        vm.assume(
            previousTime <= time && sfp.filterPeriod <= sfp.decayPeriod && sfp.decayPeriod <= Encoded.MASK_UINT12
                && sfp.reductionFactor <= Constants.BASIS_POINT_MAX
                && sfp.protocolShare <= PairParameterHelper.MAX_PROTOCOL_SHARE
                && sfp.maxVolatilityAccumulator <= Encoded.MASK_UINT20
        );

        vm.warp(previousTime);

        params = params.setStaticFeeParameters(
            sfp.baseFactor,
            sfp.filterPeriod,
            sfp.decayPeriod,
            sfp.reductionFactor,
            sfp.variableFeeControl,
            sfp.protocolShare,
            sfp.maxVolatilityAccumulator
        ).updateTimeOfLastUpdate();

        vm.warp(time);

        uint256 deltaTime = time - previousTime;

        uint256 idReference = deltaTime >= sfp.filterPeriod ? params.getActiveId() : params.getIdReference();

        uint256 volReference = params.getVolatilityReference();
        if (deltaTime >= sfp.filterPeriod) {
            volReference =
                deltaTime >= sfp.decayPeriod ? 0 : params.updateVolatilityReference().getVolatilityReference();
        }

        bytes32 newParams = params.updateReferences();

        assertEq(newParams.getIdReference(), idReference, "test_UpdateReferences::1");
        assertEq(newParams.getVolatilityReference(), volReference, "test_UpdateReferences::2");
        assertEq(newParams.getTimeOfLastUpdate(), time, "test_UpdateReferences::3");

        assertEq(
            newParams & bytes32(~(uint256(1 << 84) - 1) << PairParameterHelper.OFFSET_VOL_REF),
            params & bytes32(~(uint256(1 << 84) - 1) << PairParameterHelper.OFFSET_VOL_REF),
            "test_UpdateReferences::4"
        );
    }

    function testFuzz_revert_UpdateReferences(uint40 previousTime, uint40 time) external {
        vm.assume(previousTime > time);

        vm.warp(previousTime);

        bytes32 params = bytes32(0).updateTimeOfLastUpdate();

        vm.warp(time);

        vm.expectRevert();
        params.updateReferences();
    }

    function testFuzz_UpdateVolatilityParameters(
        bytes32 params,
        StaticFeeParameters memory sfp,
        uint40 previousTime,
        uint40 time,
        uint24 activeId
    ) external {
        vm.assume(
            previousTime <= time && sfp.filterPeriod <= sfp.decayPeriod && sfp.decayPeriod <= Encoded.MASK_UINT12
                && sfp.reductionFactor <= Constants.BASIS_POINT_MAX
                && sfp.protocolShare <= PairParameterHelper.MAX_PROTOCOL_SHARE
                && sfp.maxVolatilityAccumulator <= Encoded.MASK_UINT20
        );

        vm.warp(previousTime);

        params = params.setStaticFeeParameters(
            sfp.baseFactor,
            sfp.filterPeriod,
            sfp.decayPeriod,
            sfp.reductionFactor,
            sfp.variableFeeControl,
            sfp.protocolShare,
            sfp.maxVolatilityAccumulator
        ).updateTimeOfLastUpdate();

        vm.warp(time);

        bytes32 trustedParams = params.updateReferences().updateVolatilityAccumulator(activeId);
        bytes32 newParams = params.updateVolatilityParameters(activeId);

        assertEq(newParams.getIdReference(), trustedParams.getIdReference(), "test_UpdateVolatilityParameters::1");
        assertEq(
            newParams.getVolatilityReference(),
            trustedParams.getVolatilityReference(),
            "test_UpdateVolatilityParameters::2"
        );
        assertEq(
            newParams.getVolatilityAccumulator(),
            trustedParams.getVolatilityAccumulator(),
            "test_UpdateVolatilityParameters::3"
        );
        assertEq(newParams.getTimeOfLastUpdate(), time, "test_UpdateVolatilityParameters::4");

        assertEq(
            newParams & bytes32(~uint256(type(uint104).max) << PairParameterHelper.OFFSET_VOL_ACC),
            params & bytes32(~uint256(type(uint104).max) << PairParameterHelper.OFFSET_VOL_ACC),
            "test_UpdateVolatilityParameters::5"
        );
    }
}
