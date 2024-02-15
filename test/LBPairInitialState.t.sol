// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./helpers/TestHelper.sol";

contract LBPairInitialStateTest is TestHelper {
    function setUp() public override {
        super.setUp();

        pairWnative = createLBPair(wnative, usdc);
    }

    function test_GetFactory() external view {
        assertEq(address(pairWnative.getFactory()), address(factory), "test_GetFactory::1");
    }

    function test_GetTokenX() external view {
        assertEq(address(pairWnative.getTokenX()), address(wnative), "test_GetTokenX::1");
    }

    function test_GetTokenY() external view {
        assertEq(address(pairWnative.getTokenY()), address(usdc), "test_GetTokenY::1");
    }

    function test_GetBinStep() external view {
        assertEq(pairWnative.getBinStep(), DEFAULT_BIN_STEP, "test_GetBinStep::1");
    }

    function test_GetReserves() external view {
        (uint128 reserveX, uint128 reserveY) = pairWnative.getReserves();

        assertEq(reserveX, 0, "test_GetReserves::1");
        assertEq(reserveY, 0, "test_GetReserves::2");
    }

    function test_GetActiveId() external view {
        assertEq(pairWnative.getActiveId(), ID_ONE, "test_GetActiveId::1");
    }

    function testFuzz_GetBin(uint24 id) external view {
        (uint128 reserveX, uint128 reserveY) = pairWnative.getBin(id);

        assertEq(reserveX, 0, "testFuzz_GetBin::1");
        assertEq(reserveY, 0, "testFuzz_GetBin::2");
    }

    function test_GetNextNonEmptyBin() external view {
        assertEq(pairWnative.getNextNonEmptyBin(false, 0), 0, "test_GetNextNonEmptyBin::1");
        assertEq(pairWnative.getNextNonEmptyBin(true, 0), type(uint24).max, "test_GetNextNonEmptyBin::2");

        assertEq(pairWnative.getNextNonEmptyBin(false, type(uint24).max), 0, "test_GetNextNonEmptyBin::3");
        assertEq(pairWnative.getNextNonEmptyBin(true, type(uint24).max), type(uint24).max, "test_GetNextNonEmptyBin::4");
    }

    function test_GetProtocolFees() external view {
        (uint128 protocolFeesX, uint128 protocolFeesY) = pairWnative.getProtocolFees();

        assertEq(protocolFeesX, 0, "test_GetProtocolFees::1");
        assertEq(protocolFeesY, 0, "test_GetProtocolFees::2");
    }

    function test_GetStaticFeeParameters() external view {
        (
            uint16 baseFactor,
            uint16 filterPeriod,
            uint16 decayPeriod,
            uint16 reductionFactor,
            uint24 variableFeeControl,
            uint16 protocolShare,
            uint24 maxVolatilityAccumulator
        ) = pairWnative.getStaticFeeParameters();

        assertEq(baseFactor, DEFAULT_BASE_FACTOR, "test_GetStaticFeeParameters::1");
        assertEq(filterPeriod, DEFAULT_FILTER_PERIOD, "test_GetStaticFeeParameters::2");
        assertEq(decayPeriod, DEFAULT_DECAY_PERIOD, "test_GetStaticFeeParameters::3");
        assertEq(reductionFactor, DEFAULT_REDUCTION_FACTOR, "test_GetStaticFeeParameters::4");
        assertEq(variableFeeControl, DEFAULT_VARIABLE_FEE_CONTROL, "test_GetStaticFeeParameters::5");
        assertEq(protocolShare, DEFAULT_PROTOCOL_SHARE, "test_GetStaticFeeParameters::6");
        assertEq(maxVolatilityAccumulator, DEFAULT_MAX_VOLATILITY_ACCUMULATOR, "test_GetStaticFeeParameters::7");
    }

    function test_GetVariableFeeParameters() external view {
        (uint24 volatilityAccumulator, uint24 volatilityReference, uint24 idReference, uint40 timeOfLastUpdate) =
            pairWnative.getVariableFeeParameters();

        assertEq(volatilityAccumulator, 0, "test_GetVariableFeeParameters::1");
        assertEq(volatilityReference, 0, "test_GetVariableFeeParameters::2");
        assertEq(idReference, ID_ONE, "test_GetVariableFeeParameters::3");
        assertEq(timeOfLastUpdate, 0, "test_GetVariableFeeParameters::4");
    }

    function test_GetOracleParameters() external view {
        (uint8 sampleLifetime, uint16 size, uint16 activeSize, uint40 lastUpdated, uint40 firstTimestamp) =
            pairWnative.getOracleParameters();

        assertEq(sampleLifetime, OracleHelper._MAX_SAMPLE_LIFETIME, "test_GetOracleParameters::1");
        assertEq(size, 0, "test_GetOracleParameters::2");
        assertEq(activeSize, 0, "test_GetOracleParameters::3");
        assertEq(lastUpdated, 0, "test_GetOracleParameters::4");
        assertEq(firstTimestamp, 0, "test_GetOracleParameters::5");
    }

    function test_GetOracleSampleAt() external view {
        (uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed) =
            pairWnative.getOracleSampleAt(1);

        assertEq(cumulativeId, 0, "test_GetOracleSampleAt::1");
        assertEq(cumulativeVolatility, 0, "test_GetOracleSampleAt::2");
        assertEq(cumulativeBinCrossed, 0, "test_GetOracleSampleAt::3");
    }

    function test_GetPriceFromId() external view {
        uint256 delta = uint256(DEFAULT_BIN_STEP) * 5e13;

        assertApproxEqRel(
            pairWnative.getPriceFromId(1_000 + 2 ** 23),
            924521306405372907020063908180274956666,
            delta,
            "test_GetPriceFromId::1"
        );
        assertApproxEqRel(
            pairWnative.getPriceFromId(2 ** 23 - 1_000),
            125245452360126660303600960578690115355,
            delta,
            "test_GetPriceFromId::2"
        );
        assertApproxEqRel(
            pairWnative.getPriceFromId(2 ** 23 + 10_000),
            7457860201113570250644758522304565438757805,
            delta,
            "test_GetPriceFromId::3"
        );
        assertApproxEqRel(
            pairWnative.getPriceFromId(2 ** 23 - 10_000),
            15526181252368702469753297095319515,
            delta,
            "test_GetPriceFromId::4"
        );
        // avoid overflow of assertApproxEqRel with a too high price
        assertLe(
            pairWnative.getPriceFromId(2 ** 23 + 80_000),
            18133092123953330812316154041959812232388892985347108730495479426840526848,
            "test_GetPriceFromId::5"
        );
        assertGe(
            pairWnative.getPriceFromId(2 ** 23 + 80_000),
            18096880266539986845478224721407196147811144510344442837666495029900738560,
            "test_GetPriceFromId::6"
        );
        assertApproxEqRel(pairWnative.getPriceFromId(2 ** 23 - 80_000), 6392, 1e8, "test_GetPriceFromId::7");
        assertApproxEqRel(
            pairWnative.getPriceFromId(2 ** 23 + 12_345),
            77718771515321296819382407317364352468140333,
            delta,
            "test_GetPriceFromId::8"
        );
        assertApproxEqRel(
            pairWnative.getPriceFromId(2 ** 23 - 12_345),
            1489885737765286392982993705955521,
            delta,
            "test_GetPriceFromId::9"
        );
    }

    function test_GetIdFromPrice() external view {
        assertApproxEqAbs(
            pairWnative.getIdFromPrice(924521306405372907020063908180274956666),
            1_000 + 2 ** 23,
            1,
            "test_GetIdFromPrice::1"
        );
        assertApproxEqAbs(
            pairWnative.getIdFromPrice(125245452360126660303600960578690115355),
            2 ** 23 - 1_000,
            1,
            "test_GetIdFromPrice::2"
        );
        assertApproxEqAbs(
            pairWnative.getIdFromPrice(7457860201113570250644758522304565438757805),
            2 ** 23 + 10_000,
            1,
            "test_GetIdFromPrice::3"
        );
        assertApproxEqAbs(
            pairWnative.getIdFromPrice(15526181252368702469753297095319515),
            2 ** 23 - 10_000,
            1,
            "test_GetIdFromPrice::4"
        );
        assertApproxEqAbs(
            pairWnative.getIdFromPrice(18114977146806524168130684952726477124021312024291123319263609183005067158),
            2 ** 23 + 80_000,
            1,
            "test_GetIdFromPrice::5"
        );
        assertApproxEqAbs(pairWnative.getIdFromPrice(6392), 2 ** 23 - 80_000, 1, "test_GetIdFromPrice::6");
        assertApproxEqAbs(
            pairWnative.getIdFromPrice(77718771515321296819382407317364352468140333),
            2 ** 23 + 12_345,
            1,
            "test_GetIdFromPrice::7"
        );
        assertApproxEqAbs(
            pairWnative.getIdFromPrice(1489885737765286392982993705955521),
            2 ** 23 - 12_345,
            1,
            "test_GetIdFromPrice::8"
        );
    }

    function testFuzz_GetSwapOut(uint128 amountOut, bool swapForY) external view {
        (uint128 amountIn, uint128 amountOutLeft, uint128 fee) = pairWnative.getSwapIn(amountOut, swapForY);

        assertEq(amountIn, 0, "testFuzz_GetSwapOut::1");
        assertEq(amountOutLeft, amountOut, "testFuzz_GetSwapOut::2");
        assertEq(fee, 0, "testFuzz_GetSwapOut::3");
    }

    function testFuzz_GetSwapIn(uint128 amountIn, bool swapForY) external view {
        (uint128 amountInLeft, uint128 amountOut, uint128 fee) = pairWnative.getSwapOut(amountIn, swapForY);

        assertEq(amountInLeft, amountIn, "testFuzz_GetSwapIn::1");
        assertEq(amountOut, 0, "testFuzz_GetSwapIn::2");
        assertEq(fee, 0, "testFuzz_GetSwapIn::3");
    }

    function test_revert_SetStaticFeeParameters() external {
        vm.expectRevert(ILBPair.LBPair__InvalidStaticFeeParameters.selector);
        vm.prank(address(factory));
        pairWnative.setStaticFeeParameters(0, 0, 0, 0, 0, 0, 0);
    }
}
