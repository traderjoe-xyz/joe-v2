// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "test/helpers/TestHelper.sol";

contract LiquidityBinFactoryTestM is TestHelper {
    LBPair internal pair0;
    LBPair internal pair1;
    LBPair internal pair2;

    function setUp() public override {
        factory = new LBFactory(DEV, 8e14);
        addAllAssetsToQuoteWhitelist(factory);

        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));

        router = new LBRouter(factory, IJoeFactory(address(0)), IWAVAX(address(wavax)));

        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
        pair0 = createLBPairDefaultFeesFromStartIdAndBinStep(usdc, weth, ID_ONE, DEFAULT_BIN_STEP);
        factory.setPreset(
            75,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            5,
            10,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED,
            DEFAULT_SAMPLE_LIFETIME
        );
        pair1 = createLBPairDefaultFeesFromStartIdAndBinStep(usdc, weth, ID_ONE, 75);
        factory.setPreset(
            98,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            5,
            5,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED,
            DEFAULT_SAMPLE_LIFETIME
        );
        pair2 = createLBPairDefaultFeesFromStartIdAndBinStep(usdc, weth, ID_ONE, 98);
    }

    function testSetPresets() public {
        (
            uint256 baseFactor,
            uint256 filterPeriod,
            uint256 decayPeriod,
            uint256 reductionFactor,
            uint256 variableFeeControl,
            uint256 protocolShare,
            uint256 maxVolatilityAccumulated,
            uint256 sampleLifetime
        ) = factory.getPreset(DEFAULT_BIN_STEP);

        assertEq(baseFactor, DEFAULT_BASE_FACTOR);
        assertEq(filterPeriod, DEFAULT_FILTER_PERIOD);
        assertEq(decayPeriod, DEFAULT_DECAY_PERIOD);
        assertEq(reductionFactor, DEFAULT_REDUCTION_FACTOR);
        assertEq(variableFeeControl, DEFAULT_VARIABLE_FEE_CONTROL);
        assertEq(protocolShare, DEFAULT_PROTOCOL_SHARE);
        assertEq(maxVolatilityAccumulated, DEFAULT_MAX_VOLATILITY_ACCUMULATED);
        assertEq(sampleLifetime, DEFAULT_SAMPLE_LIFETIME);

        factory.setPreset(
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR - 1,
            DEFAULT_FILTER_PERIOD - 1,
            DEFAULT_DECAY_PERIOD - 1,
            DEFAULT_REDUCTION_FACTOR - 1,
            DEFAULT_VARIABLE_FEE_CONTROL - 1,
            DEFAULT_PROTOCOL_SHARE - 1,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED - 1,
            DEFAULT_SAMPLE_LIFETIME - 1
        );

        (
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulated,
            sampleLifetime
        ) = factory.getPreset(DEFAULT_BIN_STEP);

        assertEq(baseFactor, DEFAULT_BASE_FACTOR - 1);
        assertEq(filterPeriod, DEFAULT_FILTER_PERIOD - 1);
        assertEq(decayPeriod, DEFAULT_DECAY_PERIOD - 1);
        assertEq(reductionFactor, DEFAULT_REDUCTION_FACTOR - 1);
        assertEq(variableFeeControl, DEFAULT_VARIABLE_FEE_CONTROL - 1);
        assertEq(protocolShare, DEFAULT_PROTOCOL_SHARE - 1);
        assertEq(maxVolatilityAccumulated, DEFAULT_MAX_VOLATILITY_ACCUMULATED - 1);
        assertEq(sampleLifetime, DEFAULT_SAMPLE_LIFETIME - 1);

        vm.expectRevert(abi.encodeWithSelector(LBFactory__BinStepHasNoPreset.selector, 3));
        factory.getPreset(3);
    }

    function testAddRemovePresets() public {
        uint256[] memory binSteps = factory.getAllBinSteps();
        assertEq(binSteps.length, 3);
        assertEq(binSteps[0], DEFAULT_BIN_STEP);
        assertEq(binSteps[1], 75);
        assertEq(binSteps[2], 98);

        setDefaultFactoryPresets(12);
        binSteps = factory.getAllBinSteps();
        assertEq(binSteps.length, 4);
        assertEq(binSteps[0], 12);
        assertEq(binSteps[1], DEFAULT_BIN_STEP);
        assertEq(binSteps[2], 75);
        assertEq(binSteps[3], 98);

        factory.removePreset(75);
        binSteps = factory.getAllBinSteps();
        assertEq(binSteps.length, 3);
        assertEq(binSteps[0], 12);
        assertEq(binSteps[1], DEFAULT_BIN_STEP);
        assertEq(binSteps[2], 98);

        vm.expectRevert(abi.encodeWithSelector(LBFactory__BinStepHasNoPreset.selector, 75));
        factory.removePreset(75);
    }

    function testAvailableBinSteps() public {
        ILBFactory.LBPairInformation[] memory LBPairBinSteps = factory.getAllLBPairs(usdc, weth);
        assertEq(LBPairBinSteps.length, 3);
        assertEq(LBPairBinSteps[0].binStep, DEFAULT_BIN_STEP);
        assertEq(LBPairBinSteps[1].binStep, 75);
        assertEq(LBPairBinSteps[2].binStep, 98);
        assertEq(LBPairBinSteps[0].createdByOwner, true);
        assertEq(LBPairBinSteps[1].createdByOwner, true);
        assertEq(LBPairBinSteps[2].createdByOwner, true);

        ILBFactory.LBPairInformation[] memory LBPairBinStepsReversed = factory.getAllLBPairs(weth, usdc);
        assertEq(LBPairBinStepsReversed.length, 3);
        assertEq(LBPairBinStepsReversed[0].binStep, DEFAULT_BIN_STEP);
        assertEq(LBPairBinStepsReversed[1].binStep, 75);
        assertEq(LBPairBinStepsReversed[2].binStep, 98);

        factory.removePreset(75);
        factory.removePreset(98);

        ILBFactory.LBPairInformation[] memory LBPairBinStepsAfterPresetRemoval = factory.getAllLBPairs(usdc, weth);
        assertEq(LBPairBinStepsAfterPresetRemoval.length, 3);
        assertEq(LBPairBinStepsAfterPresetRemoval[0].binStep, DEFAULT_BIN_STEP);
        assertEq(LBPairBinStepsAfterPresetRemoval[1].binStep, 75);
        assertEq(LBPairBinStepsAfterPresetRemoval[2].binStep, 98);

        factory.setLBPairIgnored(usdc, weth, DEFAULT_BIN_STEP, true);
        factory.setLBPairIgnored(weth, usdc, 98, true);

        ILBFactory.LBPairInformation[] memory LBPairBinStepsAfterIgnored = factory.getAllLBPairs(usdc, weth);
        assertEq(LBPairBinStepsAfterIgnored.length, 3);
        assertEq(LBPairBinStepsAfterIgnored[0].ignoredForRouting, true);
        assertEq(LBPairBinStepsAfterIgnored[1].ignoredForRouting, false);
        assertEq(LBPairBinStepsAfterIgnored[2].ignoredForRouting, true);

        factory.setLBPairIgnored(usdc, weth, DEFAULT_BIN_STEP, false);

        ILBFactory.LBPairInformation[] memory LBPairBinStepsAfterRemovalOfIgnored = factory.getAllLBPairs(usdc, weth);
        assertEq(LBPairBinStepsAfterRemovalOfIgnored.length, 3);
        assertEq(LBPairBinStepsAfterRemovalOfIgnored[0].ignoredForRouting, false);
        assertEq(LBPairBinStepsAfterRemovalOfIgnored[1].ignoredForRouting, false);
        assertEq(LBPairBinStepsAfterRemovalOfIgnored[2].ignoredForRouting, true);
    }
}
