// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./helpers/TestHelper.sol";

contract LBPairInitialState is TestHelper {
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
        assertEq(idReference, 0, "test_GetParameters::3");
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

    function testFuzz_GetPriceAndId(uint24 deltaId) external {
        // 82_834 is the maximum deltaId that can be used to get a valid price
        vm.assume(deltaId < 82_834);
        uint24 id = ID_ONE + deltaId;

        uint256 price = pairWavax.getPriceFromId(id);
        uint24 calculatedId = pairWavax.getIdFromPrice(price);

        assertApproxEqAbs(calculatedId, id, 1, "testFuzz_GetPriceFromid::1");

        id = ID_ONE - deltaId;

        price = pairWavax.getPriceFromId(id);
        calculatedId = pairWavax.getIdFromPrice(price);

        assertApproxEqAbs(calculatedId, id, 1, "testFuzz_GetPriceFromid::2");
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
}
