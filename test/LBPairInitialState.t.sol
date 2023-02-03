// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./helpers/TestHelper.sol";

contract LBPairInitialStateTest is TestHelper {
    function setUp() public override {
        super.setUp();

        pairWavax = createLBPair(wavax, usdc);
    }

    function test_GetFactory() external {
        assertEq(address(pairWavax.getFactory()), address(factory), "test_GetFactory::1");
    }

    function test_GetTokenX() external {
        assertEq(address(pairWavax.getTokenX()), address(wavax), "test_GetTokenX::1");
    }

    function test_GetTokenY() external {
        assertEq(address(pairWavax.getTokenY()), address(usdc), "test_GetTokenY::1");
    }

    function test_GetBinStep() external {
        assertEq(pairWavax.getBinStep(), DEFAULT_BIN_STEP, "test_GetBinStep::1");
    }

    function test_GetReserves() external {
        (uint128 reserveX, uint128 reserveY) = pairWavax.getReserves();

        assertEq(reserveX, 0, "test_GetReserves::1");
        assertEq(reserveY, 0, "test_GetReserves::2");
    }

    function test_GetActiveId() external {
        assertEq(pairWavax.getActiveId(), ID_ONE, "test_GetActiveId::1");
    }

    function testFuzz_GetBin(uint24 id) external {
        (uint128 reserveX, uint128 reserveY) = pairWavax.getBin(id);

        assertEq(reserveX, 0, "test_GetBin::1");
        assertEq(reserveY, 0, "test_GetBin::2");
    }

    function test_GetNextNonEmptyBin() external {
        assertEq(pairWavax.getNextNonEmptyBin(false, 0), 0, "test_GetNextNonEmptyBin::1");
        assertEq(pairWavax.getNextNonEmptyBin(true, 0), type(uint24).max, "test_GetNextNonEmptyBin::2");

        assertEq(pairWavax.getNextNonEmptyBin(false, type(uint24).max), 0, "test_GetNextNonEmptyBin::3");
        assertEq(pairWavax.getNextNonEmptyBin(true, type(uint24).max), type(uint24).max, "test_GetNextNonEmptyBin::4");
    }

    function test_GetProtocolFees() external {
        (uint128 protocolFeesX, uint128 protocolFeesY) = pairWavax.getProtocolFees();

        assertEq(protocolFeesX, 0, "test_GetProtocolFees::1");
        assertEq(protocolFeesY, 0, "test_GetProtocolFees::2");
    }

    function test_GetStaticFeeParameters() external {
        (
            uint16 baseFactor,
            uint16 filterPeriod,
            uint16 decayPeriod,
            uint16 reductionFactor,
            uint24 variableFeeControl,
            uint16 protocolShare,
            uint24 maxVolatilityAccumulator
        ) = pairWavax.getStaticFeeParameters();

        assertEq(baseFactor, DEFAULT_BASE_FACTOR, "test_GetParameters::1");
        assertEq(filterPeriod, DEFAULT_FILTER_PERIOD, "test_GetParameters::2");
        assertEq(decayPeriod, DEFAULT_DECAY_PERIOD, "test_GetParameters::3");
        assertEq(reductionFactor, DEFAULT_REDUCTION_FACTOR, "test_GetParameters::4");
        assertEq(variableFeeControl, DEFAULT_VARIABLE_FEE_CONTROL, "test_GetParameters::5");
        assertEq(protocolShare, DEFAULT_PROTOCOL_SHARE, "test_GetParameters::6");
        assertEq(maxVolatilityAccumulator, DEFAULT_MAX_VOLATILITY_ACCUMULATOR, "test_GetParameters::7");
    }

    function test_GetVariableFeeParameters() external {
        (uint24 volatilityAccumulator, uint24 volatilityReference, uint24 idReference, uint40 timeOfLastUpdate) =
            pairWavax.getVariableFeeParameters();

        assertEq(volatilityAccumulator, 0, "test_GetParameters::1");
        assertEq(volatilityReference, 0, "test_GetParameters::2");
        assertEq(idReference, ID_ONE, "test_GetParameters::3");
        assertEq(timeOfLastUpdate, 0, "test_GetParameters::4");
    }

    function test_GetOracleParameters() external {
        (uint8 sampleLifetime, uint16 size, uint16 activeSize, uint40 lastUpdated, uint40 firstTimestamp) =
            pairWavax.getOracleParameters();

        assertEq(sampleLifetime, OracleHelper._MAX_SAMPLE_LIFETIME, "test_GetParameters::1");
        assertEq(size, 0, "test_GetParameters::2");
        assertEq(activeSize, 0, "test_GetParameters::3");
        assertEq(lastUpdated, 0, "test_GetParameters::4");
        assertEq(firstTimestamp, 0, "test_GetParameters::5");
    }

    function test_GetOracleSampleAt() external {
        (uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed) = pairWavax.getOracleSampleAt(1);

        assertEq(cumulativeId, 0, "test_GetParameters::1");
        assertEq(cumulativeVolatility, 0, "test_GetParameters::2");
        assertEq(cumulativeBinCrossed, 0, "test_GetParameters::3");
    }

    function test_GetPriceFromId() external {
        uint256 delta = uint256(DEFAULT_BIN_STEP) * 5e13;

        assertApproxEqRel(
            pairWavax.getPriceFromId(1_000 + 2 ** 23),
            924521306405372907020063908180274956666,
            delta,
            "test_GetPriceFromId::1"
        );
        assertApproxEqRel(
            pairWavax.getPriceFromId(2 ** 23 - 1_000),
            125245452360126660303600960578690115355,
            delta,
            "test_GetPriceFromId::2"
        );
        assertApproxEqRel(
            pairWavax.getPriceFromId(2 ** 23 + 10_000),
            7457860201113570250644758522304565438757805,
            delta,
            "test_GetPriceFromId::3"
        );
        assertApproxEqRel(
            pairWavax.getPriceFromId(2 ** 23 - 10_000),
            15526181252368702469753297095319515,
            delta,
            "test_GetPriceFromId::4"
        );
        // avoid overflow of assertApproxEqRel with a too high price
        assertLe(
            pairWavax.getPriceFromId(2 ** 23 + 80_000),
            18133092123953330812316154041959812232388892985347108730495479426840526848,
            "test_GetPriceFromId::5"
        );
        assertGe(
            pairWavax.getPriceFromId(2 ** 23 + 80_000),
            18096880266539986845478224721407196147811144510344442837666495029900738560,
            "test_GetPriceFromId::6"
        );
        assertApproxEqRel(pairWavax.getPriceFromId(2 ** 23 - 80_000), 6392, 1e8, "test_GetPriceFromId::7");
        assertApproxEqRel(
            pairWavax.getPriceFromId(2 ** 23 + 12_345),
            77718771515321296819382407317364352468140333,
            delta,
            "test_GetPriceFromId::8"
        );
        assertApproxEqRel(
            pairWavax.getPriceFromId(2 ** 23 - 12_345),
            1489885737765286392982993705955521,
            delta,
            "test_GetPriceFromId::9"
        );
    }

    function test_GetIdFromPrice() external {
        assertApproxEqAbs(
            pairWavax.getIdFromPrice(924521306405372907020063908180274956666),
            1_000 + 2 ** 23,
            1,
            "test_GetPriceFromId::1"
        );
        assertApproxEqAbs(
            pairWavax.getIdFromPrice(125245452360126660303600960578690115355),
            2 ** 23 - 1_000,
            1,
            "test_GetPriceFromId::2"
        );
        assertApproxEqAbs(
            pairWavax.getIdFromPrice(7457860201113570250644758522304565438757805),
            2 ** 23 + 10_000,
            1,
            "test_GetPriceFromId::3"
        );
        assertApproxEqAbs(
            pairWavax.getIdFromPrice(15526181252368702469753297095319515), 2 ** 23 - 10_000, 1, "test_GetPriceFromId::4"
        );
        assertApproxEqAbs(
            pairWavax.getIdFromPrice(18114977146806524168130684952726477124021312024291123319263609183005067158),
            2 ** 23 + 80_000,
            1,
            "test_GetPriceFromId::5"
        );
        assertApproxEqAbs(pairWavax.getIdFromPrice(6392), 2 ** 23 - 80_000, 1, "test_GetPriceFromId::6");
        assertApproxEqAbs(
            pairWavax.getIdFromPrice(77718771515321296819382407317364352468140333),
            2 ** 23 + 12_345,
            1,
            "test_GetPriceFromId::7"
        );
        assertApproxEqAbs(
            pairWavax.getIdFromPrice(1489885737765286392982993705955521), 2 ** 23 - 12_345, 1, "test_GetPriceFromId::8"
        );
    }

    function testFuzz_GetSwapOut(uint128 amountOut, bool swapForY) external {
        (uint128 amountIn, uint128 amountOutLeft, uint128 fee) = pairWavax.getSwapIn(amountOut, swapForY);

        assertEq(amountIn, 0, "testFuzz_GetSwapInOut::1");
        assertEq(amountOutLeft, amountOut, "testFuzz_GetSwapInOut::2");
        assertEq(fee, 0, "testFuzz_GetSwapInOut::3");
    }

    function testFuzz_GetSwapIn(uint128 amountIn, bool swapForY) external {
        (uint128 amountInLeft, uint128 amountOut, uint128 fee) = pairWavax.getSwapOut(amountIn, swapForY);

        assertEq(amountInLeft, amountIn, "testFuzz_GetSwapInOut::1");
        assertEq(amountOut, 0, "testFuzz_GetSwapInOut::2");
        assertEq(fee, 0, "testFuzz_GetSwapInOut::3");
    }

    function test_revert_SetStaticFeeParameters() external {
        vm.expectRevert(ILBPair.LBPair__InvalidStaticFeeParameters.selector);
        vm.prank(address(factory));
        pairWavax.setStaticFeeParameters(0, 0, 0, 0, 0, 0, 0);
    }
}
