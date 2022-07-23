// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinFactoryTestM is TestHelper {
    LBPair internal pair0;
    LBPair internal pair1;
    LBPair internal pair2;

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV);
        new LBFactoryHelper(factory);

        router = new LBRouter(factory, IJoeFactory(JOE_V1_FACTORY_ADDRESS), IWAVAX(address(wavax)));

        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
        pair0 = createLBPairDefaultFeesFromStartIdAndBinStep(token6D, token18D, ID_ONE, DEFAULT_BIN_STEP);
        factory.setPreset(
            75,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            5,
            10,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_SAMPLE_LIFETIME
        );
        pair1 = createLBPairDefaultFeesFromStartIdAndBinStep(token6D, token18D, ID_ONE, 75);
        factory.setPreset(
            98,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            5,
            5,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_SAMPLE_LIFETIME
        );
        pair2 = createLBPairDefaultFeesFromStartIdAndBinStep(token6D, token18D, ID_ONE, 98);
    }

    function testSetPresets() public {
        (
            uint256 baseFactor,
            uint256 filterPeriod,
            uint256 decayPeriod,
            uint256 reductionFactor,
            uint256 variableFeeControl,
            uint256 protocolShare,
            uint256 maxAccumulator,
            uint256 sampleLifetime
        ) = factory.getPreset(DEFAULT_BIN_STEP);

        assertEq(baseFactor, DEFAULT_BASE_FACTOR);
        assertEq(filterPeriod, DEFAULT_FILTER_PERIOD);
        assertEq(decayPeriod, DEFAULT_DECAY_PERIOD);
        assertEq(reductionFactor, DEFAULT_REDUCTION_FACTOR);
        assertEq(variableFeeControl, DEFAULT_VARIABLE_FEE_CONTROL);
        assertEq(protocolShare, DEFAULT_PROTOCOL_SHARE);
        assertEq(maxAccumulator, DEFAULT_MAX_ACCUMULATOR);
        assertEq(sampleLifetime, DEFAULT_SAMPLE_LIFETIME);

        factory.setPreset(
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR + 1,
            DEFAULT_FILTER_PERIOD + 1,
            DEFAULT_DECAY_PERIOD + 1,
            DEFAULT_REDUCTION_FACTOR + 1,
            DEFAULT_VARIABLE_FEE_CONTROL + 1,
            DEFAULT_PROTOCOL_SHARE + 1,
            DEFAULT_MAX_ACCUMULATOR + 1,
            DEFAULT_SAMPLE_LIFETIME + 1
        );

        (
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxAccumulator,
            sampleLifetime
        ) = factory.getPreset(DEFAULT_BIN_STEP);

        assertEq(baseFactor, DEFAULT_BASE_FACTOR + 1);
        assertEq(filterPeriod, DEFAULT_FILTER_PERIOD + 1);
        assertEq(decayPeriod, DEFAULT_DECAY_PERIOD + 1);
        assertEq(reductionFactor, DEFAULT_REDUCTION_FACTOR + 1);
        assertEq(variableFeeControl, DEFAULT_VARIABLE_FEE_CONTROL + 1);
        assertEq(protocolShare, DEFAULT_PROTOCOL_SHARE + 1);
        assertEq(maxAccumulator, DEFAULT_MAX_ACCUMULATOR + 1);
        assertEq(sampleLifetime, DEFAULT_SAMPLE_LIFETIME + 1);

        vm.expectRevert(abi.encodeWithSelector(LBFactory__BinStepHasNoPreset.selector, 3));
        factory.getPreset(3);
    }

    function testAddRemovePresets() public {
        uint256[] memory binSteps = factory.getAvailableBinSteps();
        assertEq(binSteps.length, 3);
        assertEq(binSteps[0], DEFAULT_BIN_STEP);
        assertEq(binSteps[1], 75);
        assertEq(binSteps[2], 98);

        setDefaultFactoryPresets(12);
        binSteps = factory.getAvailableBinSteps();
        assertEq(binSteps.length, 4);
        assertEq(binSteps[0], 12);
        assertEq(binSteps[1], DEFAULT_BIN_STEP);
        assertEq(binSteps[2], 75);
        assertEq(binSteps[3], 98);

        factory.removePreset(75);
        binSteps = factory.getAvailableBinSteps();
        assertEq(binSteps.length, 3);
        assertEq(binSteps[0], 12);
        assertEq(binSteps[1], DEFAULT_BIN_STEP);
        assertEq(binSteps[2], 98);

        vm.expectRevert(abi.encodeWithSelector(LBFactory__BinStepHasNoPreset.selector, 75));
        factory.removePreset(75);
    }
}
