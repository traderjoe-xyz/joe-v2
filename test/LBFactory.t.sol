// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./helpers/TestHelper.sol";

import "src/libraries/ImmutableClone.sol";

/*
* Test scenarios:
* 1. Constructor
* 2. Set LBPair implementation
* 3. Create LBPair
* 4. Create revision
* 5. Ignore LBPair for routing
* 6. Set preset
* 7. Remove preset
* 8. Set fee parameters on pair
* 9. Set fee recipient
* 10. Set flash loan fee
* 11. Set factory locked state
* 12. Add quote asset to whitelist
* 13. Remove quote asset from whitelist

Invariant ideas:
- Presets*/

contract LiquidityBinFactoryTest is TestHelper {
    event QuoteAssetRemoved(IERC20 indexed _quoteAsset);
    event QuoteAssetAdded(IERC20 indexed _quoteAsset);
    event LBPairImplementationSet(ILBPair oldLBPairImplementation, ILBPair LBPairImplementation);
    event LBPairCreated(
        IERC20 indexed tokenX, IERC20 indexed tokenY, uint256 indexed binStep, ILBPair LBPair, uint256 pid
    );

    event StaticFeeParametersSet(
        address indexed sender,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator
    );

    event PresetSet(
        uint256 indexed binStep,
        uint256 baseFactor,
        uint256 filterPeriod,
        uint256 decayPeriod,
        uint256 reductionFactor,
        uint256 variableFeeControl,
        uint256 protocolShare,
        uint256 maxVolatilityAccumulator
    );

    event LBPairIgnoredStateChanged(ILBPair indexed LBPair, bool ignored);

    event PresetRemoved(uint256 indexed binStep);

    event FeeRecipientSet(address oldRecipient, address newRecipient);

    event FlashLoanFeeSet(uint256 oldFlashLoanFee, uint256 newFlashLoanFee);

    event FactoryLockedStatusUpdated(bool unlocked);

    struct LBPairInformation {
        uint256 binStep;
        ILBPair LBPair;
        bool createdByOwner;
        bool ignoredForRouting;
    }

    function setUp() public override {
        super.setUp();
    }

    function test_constructor() public {
        assertEq(factory.getFeeRecipient(), DEV);
        assertEq(factory.getFlashLoanFee(), DEFAULT_FLASHLOAN_FEE);

        vm.expectEmit(true, true, true, true);
        emit FlashLoanFeeSet(0, DEFAULT_FLASHLOAN_FEE);
        new LBFactory(DEV, DEFAULT_FLASHLOAN_FEE);

        // Reverts if the flash loan fee is above the max fee
        uint256 maxFee = factory.getMaxFee();
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__FlashLoanFeeAboveMax.selector, maxFee + 1, maxFee));
        new LBFactory(DEV, maxFee + 1);
    }

    function test_SetLBPairImplementation() public {
        ILBPair newImplementation = new LBPair(factory);

        // Check if the implementation is set
        vm.expectEmit(true, true, true, true);
        emit LBPairImplementationSet(pairImplementation, newImplementation);
        factory.setLBPairImplementation(address(newImplementation));
        assertEq(factory.getLBPairImplementation(), address(newImplementation), "test_setLBPairImplementation:1");
    }

    function test_reverts_SetLBPairImplementation() public {
        ILBPair newImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(newImplementation));

        // Reverts if the implementation is the same
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__SameImplementation.selector, newImplementation));
        factory.setLBPairImplementation(address(newImplementation));

        LBFactory anotherFactory = new LBFactory(DEV, DEFAULT_FLASHLOAN_FEE);

        // Reverts if there is no implementation set
        vm.expectRevert(ILBFactory.LBFactory__ImplementationNotSet.selector);
        anotherFactory.createLBPair(weth, usdc, ID_ONE, DEFAULT_BIN_STEP);

        ILBPair newImplementationForAnotherFactory = new LBPair(anotherFactory);

        // Reverts if the implementation is not linked to the factory
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBFactory.LBFactory__LBPairSafetyCheckFailed.selector, newImplementationForAnotherFactory
            )
        );
        factory.setLBPairImplementation(address(newImplementationForAnotherFactory));
    }

    function test_createLBPair() public {
        address expectedPairAddress = ImmutableClone.predictDeterministicAddress(
            address(pairImplementation),
            abi.encodePacked(usdt, usdc, DEFAULT_BIN_STEP),
            keccak256(abi.encode(usdc, usdt, DEFAULT_BIN_STEP, 1)),
            address(factory)
        );

        // Check for the correct events
        vm.expectEmit(true, true, true, true);
        emit LBPairCreated(usdt, usdc, DEFAULT_BIN_STEP, ILBPair(expectedPairAddress), 0);

        // TODO - Check if can get the event from the pair
        // vm.expectEmit(true, true, true, true);
        // emit StaticFeeParametersSet(
        //     address(factory),
        //     DEFAULT_BASE_FACTOR,
        //     DEFAULT_FILTER_PERIOD,
        //     DEFAULT_DECAY_PERIOD,
        //     DEFAULT_REDUCTION_FACTOR,
        //     DEFAULT_VARIABLE_FEE_CONTROL,
        //     DEFAULT_PROTOCOL_SHARE,
        //     DEFAULT_MAX_VOLATILITY_ACCUMULATOR
        //     );

        ILBPair pair = factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        assertEq(factory.getNumberOfLBPairs(), 1, "test_createLBPair::1");

        LBFactory.LBPairInformation memory pairInfo = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP, 1);
        assertEq(pairInfo.binStep, DEFAULT_BIN_STEP, "test_createLBPair::2");
        assertEq(address(pairInfo.LBPair), address(pair), "test_createLBPair::2");
        assertTrue(pairInfo.createdByOwner);
        assertFalse(pairInfo.ignoredForRouting);
        assertEq(pairInfo.revisionIndex, 1);
        assertEq(pairInfo.implementation, address(pairImplementation), "test_createLBPair::2");

        assertEq(factory.getNumberOfRevisions(usdt, usdc, DEFAULT_BIN_STEP), 1, "test_createLBPair::3");
        assertEq(factory.getAllLBPairs(usdt, usdc).length, 1, "test_createLBPair::4");
        assertEq(address(factory.getAllLBPairs(usdt, usdc)[0].LBPair), address(pair), "test_createLBPair::5");

        assertEq(address(pair.getFactory()), address(factory), "test_createLBPair::6");
        assertEq(address(pair.getTokenX()), address(usdt), "test_createLBPair::7");
        assertEq(address(pair.getTokenY()), address(usdc), "test_createLBPair::8");

        // FeeHelper.FeeParameters memory feeParameters = pair.feeParameters();
        // assertEq(feeParameters.volatilityAccumulator, 0, "test_createLBPair::9");
        // assertEq(feeParameters.volatilityReference, 0, "test_createLBPair::10");
        // assertEq(feeParameters.indexRef, 0, "test_createLBPair::11");
        // assertEq(feeParameters.time, 0, "test_createLBPair::12");
        // assertEq(feeParameters.maxVolatilityAccumulator, DEFAULT_MAX_VOLATILITY_ACCUMULATOR, "test_createLBPair::13");
        // assertEq(feeParameters.filterPeriod, DEFAULT_FILTER_PERIOD, "test_createLBPair::14");
        // assertEq(feeParameters.decayPeriod, DEFAULT_DECAY_PERIOD, "test_createLBPair::15");
        // assertEq(feeParameters.binStep, DEFAULT_BIN_STEP, "test_createLBPair::16");
        // assertEq(feeParameters.baseFactor, DEFAULT_BASE_FACTOR, "test_createLBPair::17");
        // assertEq(feeParameters.protocolShare, DEFAULT_PROTOCOL_SHARE, "test_createLBPair::18");
    }

    function test_createLBPairFactoryUnlocked() public {
        factory.setFactoryLockedState(false);

        // Any user should be able to create pairs
        vm.prank(ALICE);
        factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        assertFalse(factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP, 1).createdByOwner);

        vm.prank(BOB);
        factory.createLBPair(weth, usdc, ID_ONE, DEFAULT_BIN_STEP);

        assertFalse(factory.getLBPairInformation(weth, usdc, DEFAULT_BIN_STEP, 1).createdByOwner);

        factory.createLBPair(bnb, usdc, ID_ONE, DEFAULT_BIN_STEP);

        assertTrue(factory.getLBPairInformation(bnb, usdc, DEFAULT_BIN_STEP, 1).createdByOwner);

        // Should close pair creations again
        factory.setFactoryLockedState(true);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__FunctionIsLockedForUsers.selector, ALICE));
        factory.createLBPair(link, usdc, ID_ONE, DEFAULT_BIN_STEP);

        factory.createLBPair(wbtc, usdc, ID_ONE, DEFAULT_BIN_STEP);
    }

    function test_reverts_createLBPair() public {
        // Alice can't create a pair if the factory is locked
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__FunctionIsLockedForUsers.selector, ALICE));
        factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        // Can't create pair if the implementation is not set
        LBFactory newFactory = new LBFactory(DEV, DEFAULT_FLASHLOAN_FEE);
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__ImplementationNotSet.selector));
        newFactory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        // Can't create pair if the quote asset is not whitelisted
        newFactory.setLBPairImplementation(address(new LBPair(newFactory)));
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__QuoteAssetNotWhitelisted.selector, usdc));
        newFactory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        // Can't create pair if the quote asset is the same as the base asset
        newFactory.addQuoteAsset(usdc);
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__IdenticalAddresses.selector, usdc));
        newFactory.createLBPair(usdc, usdc, ID_ONE, DEFAULT_BIN_STEP);

        // Can't create a pair with an invalid bin step
        // vm.expectRevert(abi.encodeWithSelector(ILBFactory.BinHelper__BinStepOverflows.selector, type(uint16).max));
        // newFactory.createLBPair(usdt, usdc, ID_ONE, type(uint16).max);

        // Can't create a pair with address(0)
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__AddressZero.selector));
        newFactory.createLBPair(IERC20(address(0)), usdc, ID_ONE, DEFAULT_BIN_STEP);

        // Can't create a pair if the preset is not set
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__BinStepHasNoPreset.selector, DEFAULT_BIN_STEP));
        newFactory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        newFactory.setPreset(
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR
        );

        // Can't create the same pair twice (a revision should be created instead)
        newFactory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);
        vm.expectRevert(
            abi.encodeWithSelector(ILBFactory.LBFactory__LBPairAlreadyExists.selector, usdt, usdc, DEFAULT_BIN_STEP)
        );
        newFactory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);
    }

    function test_CreateRevision() public {
        ILBPair pair = factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        // Updates the pair implementation
        pairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(pairImplementation));

        address expectedPairAddress = ImmutableClone.predictDeterministicAddress(
            address(pairImplementation),
            abi.encodePacked(usdt, usdc, DEFAULT_BIN_STEP),
            keccak256(abi.encode(usdc, usdt, DEFAULT_BIN_STEP, 2)),
            address(factory)
        );

        // Check for the correct events
        vm.expectEmit(true, true, true, true);
        emit LBPairCreated(usdt, usdc, DEFAULT_BIN_STEP, ILBPair(expectedPairAddress), 1);

        // vm.expectEmit(true, true, true, true, expectedPairAddress);
        // emit StaticFeeParametersSet(
        //     address(factory),
        //     DEFAULT_BASE_FACTOR,
        //     DEFAULT_FILTER_PERIOD,
        //     DEFAULT_DECAY_PERIOD,
        //     DEFAULT_REDUCTION_FACTOR,
        //     DEFAULT_VARIABLE_FEE_CONTROL,
        //     DEFAULT_PROTOCOL_SHARE,
        //     DEFAULT_MAX_VOLATILITY_ACCUMULATOR
        //     );

        ILBPair revision = factory.createLBPairRevision(usdt, usdc, DEFAULT_BIN_STEP);

        assertEq(factory.getNumberOfLBPairs(), 2, "test_createLBPair::1");

        LBFactory.LBPairInformation memory pairInfo = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP, 2);
        assertEq(pairInfo.binStep, DEFAULT_BIN_STEP, "test_createLBPair::2");
        assertEq(address(pairInfo.LBPair), address(revision), "test_createLBPair::2");
        assertTrue(pairInfo.createdByOwner);
        assertFalse(pairInfo.ignoredForRouting);
        assertEq(pairInfo.revisionIndex, 2);
        assertEq(pairInfo.implementation, address(pairImplementation), "test_createLBPair::2");

        // Revision and previous pair should have active bin
        uint256 pairActiveId = pair.getActiveId();
        uint256 revisionActiveId = revision.getActiveId();
        assertEq(pairActiveId, revisionActiveId);

        assertEq(factory.getNumberOfRevisions(usdt, usdc, DEFAULT_BIN_STEP), 2, "test_createLBPair::3");
        assertEq(factory.getAllLBPairs(usdt, usdc).length, 2, "test_createLBPair::4");
        assertEq(address(factory.getAllLBPairs(usdt, usdc)[0].LBPair), address(pair), "test_createLBPair::5");
        assertEq(address(factory.getAllLBPairs(usdt, usdc)[1].LBPair), address(revision), "test_createLBPair::5");

        assertEq(address(revision.getFactory()), address(factory), "test_createLBPair::6");
        assertEq(address(revision.getTokenX()), address(usdt), "test_createLBPair::7");
        assertEq(address(revision.getTokenY()), address(usdc), "test_createLBPair::8");

        // FeeHelper.FeeParameters memory feeParameters = revision.feeParameters();
        // assertEq(feeParameters.volatilityAccumulator, 0, "test_createLBPair::9");
        // assertEq(feeParameters.volatilityReference, 0, "test_createLBPair::10");
        // assertEq(feeParameters.indexRef, 0, "test_createLBPair::11");
        // assertEq(feeParameters.time, 0, "test_createLBPair::12");
        // assertEq(feeParameters.maxVolatilityAccumulator, DEFAULT_MAX_VOLATILITY_ACCUMULATOR, "test_createLBPair::13");
        // assertEq(feeParameters.filterPeriod, DEFAULT_FILTER_PERIOD, "test_createLBPair::14");
        // assertEq(feeParameters.decayPeriod, DEFAULT_DECAY_PERIOD, "test_createLBPair::15");
        // assertEq(feeParameters.binStep, DEFAULT_BIN_STEP, "test_createLBPair::16");
        // assertEq(feeParameters.baseFactor, DEFAULT_BASE_FACTOR, "test_createLBPair::17");
        // assertEq(feeParameters.protocolShare, DEFAULT_PROTOCOL_SHARE, "test_createLBPair::18");
    }

    function test_reverts_CreateRevision() public {
        // Can't create a revision if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.createLBPairRevision(usdt, usdc, DEFAULT_BIN_STEP);

        // Can't create a revision if the pair doesn't exist
        vm.expectRevert(
            abi.encodeWithSelector(ILBFactory.LBFactory__LBPairDoesNotExists.selector, usdt, usdc, DEFAULT_BIN_STEP)
        );
        factory.createLBPairRevision(usdt, usdc, DEFAULT_BIN_STEP);

        factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        // Can't create a revision if the pair implementation hasn't changed
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__SameImplementation.selector, pairImplementation));
        factory.createLBPairRevision(usdt, usdc, DEFAULT_BIN_STEP);
    }

    function test_setLBPairIgnored() public {
        factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);
        factory.createLBPair(weth, usdc, ID_ONE, DEFAULT_BIN_STEP);
        factory.setLBPairImplementation(address(new LBPair(factory)));
        ILBPair revision2 = ILBPair(factory.createLBPairRevision(usdt, usdc, DEFAULT_BIN_STEP));
        factory.setLBPairImplementation(address(new LBPair(factory)));
        factory.createLBPairRevision(usdt, usdc, DEFAULT_BIN_STEP);

        // Ignoring the USDT-USDC rev 2 pair
        vm.expectEmit(true, true, true, true);
        emit LBPairIgnoredStateChanged(revision2, true);
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, 2, true);

        ILBFactory.LBPairInformation memory revision2Info =
            factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP, 2);
        assertEq(address(revision2Info.LBPair), address(revision2), "test_setLBPairIgnored::0");
        assertEq(revision2Info.ignoredForRouting, true, "test_setLBPairIgnored::1");

        // Put it back to normal
        vm.expectEmit(true, true, true, true);
        emit LBPairIgnoredStateChanged(revision2, false);
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, 2, false);

        assertEq(
            factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP, 2).ignoredForRouting,
            false,
            "test_setLBPairIgnored::1"
        );
    }

    function test_reverts_setLBPairIgnored() public {
        // Can't ignore for routing if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, 1, true);

        // Can't update a non existing pair
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__AddressZero.selector));
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, 1, true);

        factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        // Can't update a pair to the same state
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__LBPairIgnoredIsAlreadyInTheSameState.selector));
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, 1, false);

        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, 1, true);

        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__LBPairIgnoredIsAlreadyInTheSameState.selector));
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, 1, true);
    }

    function todoTestFuzz_setPreset(
        uint8 binStep,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator
    ) public {
        binStep = uint8(bound(binStep, factory.getMinBinStep(), factory.getMaxBinStep()));
        filterPeriod = uint16(bound(filterPeriod, 0, type(uint16).max - 1));
        decayPeriod = uint16(bound(decayPeriod, filterPeriod + 1, type(uint16).max));
        reductionFactor = uint16(bound(reductionFactor, 0, Constants.BASIS_POINT_MAX));
        protocolShare = uint16(bound(protocolShare, 0, factory.getMaxProtocolShare()));
        variableFeeControl = uint24(bound(variableFeeControl, 0, Constants.BASIS_POINT_MAX));

        // TODO: maxVolatilityAccumulator should be bounded but that's quite hard to calculate
        uint256 totalFeesMax;
        {
            uint256 baseFee = (uint256(baseFactor) * binStep) * 1e10;
            uint256 prod = uint256(maxVolatilityAccumulator) * binStep;
            uint256 maxVariableFee = (prod * prod * variableFeeControl) / 100;
            totalFeesMax = baseFee + maxVariableFee;
        }

        if (totalFeesMax > factory.getMaxFee()) {
            vm.expectRevert();
            factory.setPreset(
                binStep,
                baseFactor,
                filterPeriod,
                decayPeriod,
                reductionFactor,
                variableFeeControl,
                protocolShare,
                maxVolatilityAccumulator
            );
        } else {
            vm.expectEmit(true, true, true, true);
            emit PresetSet(
                binStep,
                baseFactor,
                filterPeriod,
                decayPeriod,
                reductionFactor,
                variableFeeControl,
                protocolShare,
                maxVolatilityAccumulator
                );

            factory.setPreset(
                binStep,
                baseFactor,
                filterPeriod,
                decayPeriod,
                reductionFactor,
                variableFeeControl,
                protocolShare,
                maxVolatilityAccumulator
            );

            // Bin step DEFAULT_BIN_STEP is already there
            if (binStep != DEFAULT_BIN_STEP) {
                assertEq(factory.getAllBinSteps().length, 2, "1");
                if (binStep < DEFAULT_BIN_STEP) {
                    assertEq(factory.getAllBinSteps()[0], binStep, "2");
                } else {
                    assertEq(factory.getAllBinSteps()[1], binStep, "3");
                }
            } else {
                assertEq(factory.getAllBinSteps().length, 1, "3");
                assertEq(factory.getAllBinSteps()[0], binStep, "4");
            }

            // Check splitted in two to avoid stack too deep errors
            {
                (
                    uint256 baseFactorView,
                    uint256 filterPeriodView,
                    uint256 decayPeriodView,
                    uint256 reductionFactorView,
                    ,
                    ,
                ) = factory.getPreset(binStep);

                assertEq(baseFactorView, baseFactor);
                assertEq(filterPeriodView, filterPeriod);
                assertEq(decayPeriodView, decayPeriod);
                assertEq(reductionFactorView, reductionFactor);
            }

            {
                (,,,, uint256 variableFeeControlView, uint256 protocolShareView, uint256 maxVolatilityAccumulatorView) =
                    factory.getPreset(binStep);

                assertEq(variableFeeControlView, variableFeeControl);
                assertEq(protocolShareView, protocolShare);
                assertEq(maxVolatilityAccumulatorView, maxVolatilityAccumulator);
            }
        }
    }

    // TODO - check after refactoring the checks on fee parameters
    function todoTestFuzz_reverts_setPreset(
        uint8 binStep,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator
    ) public {
        uint256 baseFee = (uint256(baseFactor) * binStep) * 1e10;
        uint256 prod = uint256(maxVolatilityAccumulator) * binStep;
        uint256 maxVariableFee = (prod * prod * variableFeeControl) / 100;

        if (binStep < factory.getMinBinStep() || binStep > factory.getMaxBinStep()) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ILBFactory.LBFactory__BinStepRequirementsBreached.selector,
                    factory.getMinBinStep(),
                    binStep,
                    factory.getMaxBinStep()
                )
            );
            factory.setPreset(
                binStep,
                baseFactor,
                filterPeriod,
                decayPeriod,
                reductionFactor,
                variableFeeControl,
                protocolShare,
                maxVolatilityAccumulator
            );
        } else if (filterPeriod >= decayPeriod) {
            vm.expectRevert(
                abi.encodeWithSelector(ILBFactory.LBFactory__DecreasingPeriods.selector, filterPeriod, decayPeriod)
            );
            factory.setPreset(
                binStep,
                baseFactor,
                filterPeriod,
                decayPeriod,
                reductionFactor,
                variableFeeControl,
                protocolShare,
                maxVolatilityAccumulator
            );
        } else if (reductionFactor > Constants.BASIS_POINT_MAX) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ILBFactory.LBFactory__ReductionFactorOverflows.selector, reductionFactor, Constants.BASIS_POINT_MAX
                )
            );
            factory.setPreset(
                binStep,
                baseFactor,
                filterPeriod,
                decayPeriod,
                reductionFactor,
                variableFeeControl,
                protocolShare,
                maxVolatilityAccumulator
            );
        } else if (protocolShare > factory.getMaxProtocolShare()) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    ILBFactory.LBFactory__ProtocolShareOverflows.selector, protocolShare, factory.getMaxProtocolShare()
                )
            );
            factory.setPreset(
                binStep,
                baseFactor,
                filterPeriod,
                decayPeriod,
                reductionFactor,
                variableFeeControl,
                protocolShare,
                maxVolatilityAccumulator
            );
        } else if (baseFee + maxVariableFee > factory.getMaxFee()) {
            vm.expectRevert();
            factory.setPreset(
                binStep,
                baseFactor,
                filterPeriod,
                decayPeriod,
                reductionFactor,
                variableFeeControl,
                protocolShare,
                maxVolatilityAccumulator
            );
        } else {
            factory.setPreset(
                binStep,
                baseFactor,
                filterPeriod,
                decayPeriod,
                reductionFactor,
                variableFeeControl,
                protocolShare,
                maxVolatilityAccumulator
            );
        }
    }

    function test_removePreset() public {
        factory.setPreset(
            DEFAULT_BIN_STEP + 1,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR
        );

        factory.setPreset(
            DEFAULT_BIN_STEP - 1,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR
        );

        assertEq(factory.getAllBinSteps().length, 3);

        vm.expectEmit(true, true, true, true);
        emit PresetRemoved(DEFAULT_BIN_STEP);
        factory.removePreset(DEFAULT_BIN_STEP);

        assertEq(factory.getAllBinSteps().length, 2);

        // getPreset should revert for the removed bin step
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__BinStepHasNoPreset.selector, DEFAULT_BIN_STEP));
        factory.getPreset(DEFAULT_BIN_STEP);

        // Revert if not owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.removePreset(DEFAULT_BIN_STEP);

        // Revert if bin step does not exist
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__BinStepHasNoPreset.selector, DEFAULT_BIN_STEP));
        factory.removePreset(DEFAULT_BIN_STEP);
    }

    function test_setFeesParametersOnPair() public {
        uint16 newBaseFactor = DEFAULT_BASE_FACTOR * 2;
        uint16 newFilterPeriod = DEFAULT_FILTER_PERIOD * 2;
        uint16 newDecayPeriod = DEFAULT_DECAY_PERIOD * 2;
        uint16 newReductionFactor = DEFAULT_REDUCTION_FACTOR * 2;
        uint24 newVariableFeeControl = DEFAULT_VARIABLE_FEE_CONTROL * 2;
        uint16 newProtocolShare = DEFAULT_PROTOCOL_SHARE * 2;
        uint24 newMaxVolatilityAccumulator = DEFAULT_MAX_VOLATILITY_ACCUMULATOR * 2;

        factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        // FeeHelper.FeeParameters memory oldFeeParameters = pair.feeParameters();

        vm.expectEmit(true, true, true, true);
        emit StaticFeeParametersSet(
            address(factory),
            newBaseFactor,
            newFilterPeriod,
            newDecayPeriod,
            newReductionFactor,
            newVariableFeeControl,
            newProtocolShare,
            newMaxVolatilityAccumulator
            );

        factory.setFeesParametersOnPair(
            usdt,
            usdc,
            DEFAULT_BIN_STEP,
            1,
            newBaseFactor,
            newFilterPeriod,
            newDecayPeriod,
            newReductionFactor,
            newVariableFeeControl,
            newProtocolShare,
            newMaxVolatilityAccumulator
        );

        // FeeHelper.FeeParameters memory feeParameters = pair.feeParameters();
        // // Paramters should be updated
        // assertEq(feeParameters.baseFactor, newBaseFactor);
        // assertEq(feeParameters.filterPeriod, newFilterPeriod);
        // assertEq(feeParameters.decayPeriod, newDecayPeriod);
        // assertEq(feeParameters.reductionFactor, newReductionFactor);
        // assertEq(feeParameters.variableFeeControl, newVariableFeeControl);
        // assertEq(feeParameters.protocolShare, newProtocolShare);
        // assertEq(feeParameters.maxVolatilityAccumulator, newMaxVolatilityAccumulator);

        // // Rest of the fee parameters slot should be the same
        // assertEq(feeParameters.volatilityAccumulator, oldFeeParameters.volatilityAccumulator);
        // assertEq(feeParameters.volatilityReference, oldFeeParameters.volatilityReference);
        // assertEq(feeParameters.indexRef, oldFeeParameters.indexRef);
        // assertEq(feeParameters.time, oldFeeParameters.time);

        // Can't update if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.setFeesParametersOnPair(
            usdt,
            usdc,
            DEFAULT_BIN_STEP,
            1,
            newBaseFactor,
            newFilterPeriod,
            newDecayPeriod,
            newReductionFactor,
            newVariableFeeControl,
            newProtocolShare,
            newMaxVolatilityAccumulator
        );

        // Can't update a pair that does not exist
        vm.expectRevert(
            abi.encodeWithSelector(ILBFactory.LBFactory__LBPairNotCreated.selector, usdc, weth, DEFAULT_BIN_STEP)
        );
        factory.setFeesParametersOnPair(
            weth,
            usdc,
            DEFAULT_BIN_STEP,
            1,
            newBaseFactor,
            newFilterPeriod,
            newDecayPeriod,
            newReductionFactor,
            newVariableFeeControl,
            newProtocolShare,
            newMaxVolatilityAccumulator
        );
    }

    function test_setFeeRecipient() public {
        vm.expectEmit(true, true, true, true);
        emit FeeRecipientSet(address(this), ALICE);
        factory.setFeeRecipient(ALICE);

        assertEq(factory.getFeeRecipient(), ALICE);

        // Can't set if not the owner
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.setFeeRecipient(BOB);

        // Can't set to the zero address
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__AddressZero.selector));
        factory.setFeeRecipient(address(0));

        // Can't set to the same recipient
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__SameFeeRecipient.selector, ALICE));
        factory.setFeeRecipient(ALICE);
    }

    function test_setFlashLoanFee() public {
        uint256 newFlashLoanFee = 1_000;
        vm.expectEmit(true, true, true, true);
        emit FlashLoanFeeSet(DEFAULT_FLASHLOAN_FEE, newFlashLoanFee);
        factory.setFlashLoanFee(newFlashLoanFee);

        assertEq(factory.getFlashLoanFee(), newFlashLoanFee);

        // Can't set if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.setFlashLoanFee(DEFAULT_FLASHLOAN_FEE);

        // Can't set to the same fee
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__SameFlashLoanFee.selector, newFlashLoanFee));
        factory.setFlashLoanFee(newFlashLoanFee);

        // Can't set to a fee greater than the maximum
        uint256 maxFlashLoanFee = factory.getMaxFee();
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBFactory.LBFactory__FlashLoanFeeAboveMax.selector, maxFlashLoanFee + 1, maxFlashLoanFee
            )
        );
        factory.setFlashLoanFee(maxFlashLoanFee + 1);
    }

    function test_setFactoryLockedState() public {
        assertEq(factory.isCreationUnlocked(), false);

        vm.expectEmit(true, true, true, true);
        emit FactoryLockedStatusUpdated(false);
        factory.setFactoryLockedState(false);

        assertEq(factory.isCreationUnlocked(), true);

        factory.setFactoryLockedState(true);
        assertEq(factory.isCreationUnlocked(), false);

        // Can't set if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.setFactoryLockedState(true);

        // Can't set to the same state
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__FactoryLockIsAlreadyInTheSameState.selector));
        factory.setFactoryLockedState(true);
    }

    function test_addQuoteAsset() public {
        uint256 numberOfQuoteAssetBefore = factory.getNumberOfQuoteAssets();

        IERC20 newToken = new ERC20Mock(18);

        assertEq(factory.isQuoteAsset(newToken), false);

        vm.expectEmit(true, true, true, true);
        emit QuoteAssetAdded(newToken);
        factory.addQuoteAsset(newToken);

        assertEq(factory.isQuoteAsset(newToken), true);
        assertEq(factory.getNumberOfQuoteAssets(), numberOfQuoteAssetBefore + 1);
        assertEq(address(newToken), address(factory.getQuoteAsset(numberOfQuoteAssetBefore)));

        // Can't add if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.addQuoteAsset(newToken);

        // Can't add if the asset is already a quote asset
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__QuoteAssetAlreadyWhitelisted.selector, newToken));
        factory.addQuoteAsset(newToken);
    }

    function test_removeQuoteAsset() public {
        uint256 numberOfQuoteAssetBefore = factory.getNumberOfQuoteAssets();

        assertEq(factory.isQuoteAsset(usdc), true);

        vm.expectEmit(true, true, true, true);
        emit QuoteAssetRemoved(usdc);
        factory.removeQuoteAsset(usdc);

        assertEq(factory.isQuoteAsset(usdc), false);
        assertEq(factory.getNumberOfQuoteAssets(), numberOfQuoteAssetBefore - 1);

        // Can't remove if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.removeQuoteAsset(usdc);

        // Can't remove if the asset is not a quote asset
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__QuoteAssetNotWhitelisted.selector, usdc));
        factory.removeQuoteAsset(usdc);
    }

    function test_forceDecay() public {
        ILBPair pair = factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        factory.forceDecay(pair);

        // Can't force decay if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.forceDecay(pair);
    }

    function test_getAllLBPairs() public {
        /* Create pairs:
        - WETH/USDC with bin step = 5
        - WETH/USDC with bin step = 20
        - WETH/USDC revision with bin step = 5
        - USDT/USDC with bin step = 5
        */

        factory.setPreset(
            5,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR
        );

        factory.setPreset(
            20,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR
        );

        ILBPair pair1 = factory.createLBPair(weth, usdc, ID_ONE, 5);
        ILBPair pair2 = factory.createLBPair(weth, usdc, ID_ONE, 20);

        factory.setLBPairImplementation(address(new LBPair(factory)));
        ILBPair pair3 = factory.createLBPairRevision(weth, usdc, 5);
        factory.createLBPair(usdt, usdc, ID_ONE, 5);

        ILBFactory.LBPairInformation[] memory LBPairsAvailable = factory.getAllLBPairs(weth, usdc);

        assertEq(LBPairsAvailable.length, 3);

        ILBFactory.LBPairInformation memory pair1Info = LBPairsAvailable[0];
        assertEq(address(pair1Info.LBPair), address(pair1));
        assertEq(pair1Info.binStep, 5);
        assertEq(pair1Info.revisionIndex, 1);
        assertEq(pair1Info.implementation, address(pairImplementation));

        ILBFactory.LBPairInformation memory pair2Info = LBPairsAvailable[2];
        assertEq(address(pair2Info.LBPair), address(pair2));
        assertEq(pair2Info.binStep, 20);
        assertEq(pair2Info.revisionIndex, 1);
        assertEq(pair2Info.implementation, address(pairImplementation));

        ILBFactory.LBPairInformation memory pair3Info = LBPairsAvailable[1];
        assertEq(address(pair3Info.LBPair), address(pair3));
        assertEq(pair3Info.binStep, 5);
        assertEq(pair3Info.revisionIndex, 2);
        assertEq(pair3Info.implementation, address(factory.getLBPairImplementation()));
    }
}
