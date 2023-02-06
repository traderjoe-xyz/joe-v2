// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./helpers/TestHelper.sol";

import "src/libraries/ImmutableClone.sol";

/**
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
 */

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
    event OpenPresetChanged(uint8 indexed binStep, bool open);

    function setUp() public override {
        super.setUp();
    }

    function test_Constructor() public {
        assertEq(factory.getFeeRecipient(), DEV, "test_Constructor::1");
        assertEq(factory.getFlashLoanFee(), DEFAULT_FLASHLOAN_FEE, "test_Constructor::2");

        assertEq(factory.getLBPairImplementation(), address(pairImplementation), "test_Constructor::3");
        assertEq(factory.getMinBinStep(), 1, "test_Constructor::4");
        assertEq(factory.getMaxBinStep(), 200, "test_Constructor::5");
        assertEq(factory.getFeeRecipient(), DEV, "test_Constructor::6");
        assertEq(factory.getMaxFlashLoanFee(), 0.1e18, "test_Constructor::7");

        vm.expectEmit(true, true, true, true);
        emit FlashLoanFeeSet(0, DEFAULT_FLASHLOAN_FEE);
        new LBFactory(DEV, DEFAULT_FLASHLOAN_FEE);

        // Reverts if the flash loan fee is above the max fee
        uint256 maxFee = factory.getMaxFlashLoanFee();
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

    function test_revert_SetLBPairImplementation() public {
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

    function test_CreateLBPair() public {
        address expectedPairAddress = ImmutableClone.predictDeterministicAddress(
            address(pairImplementation),
            abi.encodePacked(usdt, usdc, DEFAULT_BIN_STEP),
            keccak256(abi.encode(usdc, usdt, DEFAULT_BIN_STEP)),
            address(factory)
        );

        // Check for the correct events
        vm.expectEmit(true, true, true, true);
        emit LBPairCreated(usdt, usdc, DEFAULT_BIN_STEP, ILBPair(expectedPairAddress), 0);

        ILBPair pair = factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        assertEq(factory.getNumberOfLBPairs(), 1, "test_CreateLBPair::1");

        LBFactory.LBPairInformation memory pairInfo = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP);
        assertEq(pairInfo.binStep, DEFAULT_BIN_STEP, "test_CreateLBPair::2");
        assertEq(address(pairInfo.LBPair), address(pair), "test_CreateLBPair::3");
        assertTrue(pairInfo.createdByOwner, "test_CreateLBPair::4");
        assertFalse(pairInfo.ignoredForRouting, "test_CreateLBPair::5");

        assertEq(factory.getAllLBPairs(usdt, usdc).length, 1, "test_CreateLBPair::6");
        assertEq(address(factory.getAllLBPairs(usdt, usdc)[0].LBPair), address(pair), "test_CreateLBPair::7");

        assertEq(address(pair.getFactory()), address(factory), "test_CreateLBPair::8");
        assertEq(address(pair.getTokenX()), address(usdt), "test_CreateLBPair::9");
        assertEq(address(pair.getTokenY()), address(usdc), "test_CreateLBPair::10");

        (
            uint16 baseFactor,
            uint16 filterPeriod,
            uint16 decayPeriod,
            uint16 reductionFactor,
            uint24 variableFeeControl,
            uint16 protocolShare,
            uint24 maxVolatilityAccumulator
        ) = pair.getStaticFeeParameters();

        assertEq(baseFactor, DEFAULT_BASE_FACTOR, "test_createLBPair::11");
        assertEq(filterPeriod, DEFAULT_FILTER_PERIOD, "test_createLBPair::12");
        assertEq(decayPeriod, DEFAULT_DECAY_PERIOD, "test_createLBPair::13");
        assertEq(reductionFactor, DEFAULT_REDUCTION_FACTOR, "test_createLBPair::14");
        assertEq(variableFeeControl, DEFAULT_VARIABLE_FEE_CONTROL, "test_createLBPair::15");
        assertEq(protocolShare, DEFAULT_PROTOCOL_SHARE, "test_createLBPair::16");
        assertEq(maxVolatilityAccumulator, DEFAULT_MAX_VOLATILITY_ACCUMULATOR, "test_createLBPair::17");

        (uint24 volatilityAccumulator, uint24 volatilityReference, uint24 idReference, uint40 timeOfLastUpdate) =
            pair.getVariableFeeParameters();

        assertEq(volatilityAccumulator, 0, "test_createLBPair::18");
        assertEq(volatilityReference, 0, "test_createLBPair::19");
        assertEq(idReference, ID_ONE, "test_createLBPair::20");
        assertEq(timeOfLastUpdate, 0, "test_createLBPair::21");
    }

    function test_CreateLBPairFactoryUnlocked() public {
        // Users should not be able to create pairs by default
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(ILBFactory.LBFactory__FunctionIsLockedForUsers.selector, ALICE, DEFAULT_BIN_STEP)
        );
        factory.createLBPair(link, usdc, ID_ONE, DEFAULT_BIN_STEP);

        factory.setOpenPreset(DEFAULT_BIN_STEP, true);

        // Any user should be able to create pairs
        vm.prank(ALICE);
        factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        assertFalse(
            factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).createdByOwner,
            "test_CreateLBPairFactoryUnlocked::1"
        );

        vm.prank(BOB);
        factory.createLBPair(weth, usdc, ID_ONE, DEFAULT_BIN_STEP);

        assertFalse(
            factory.getLBPairInformation(weth, usdc, DEFAULT_BIN_STEP).createdByOwner,
            "test_CreateLBPairFactoryUnlocked::2"
        );

        factory.createLBPair(bnb, usdc, ID_ONE, DEFAULT_BIN_STEP);

        assertTrue(
            factory.getLBPairInformation(bnb, usdc, DEFAULT_BIN_STEP).createdByOwner,
            "test_CreateLBPairFactoryUnlocked::3"
        );

        // Should close pair creations again
        factory.setOpenPreset(DEFAULT_BIN_STEP, false);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(ILBFactory.LBFactory__FunctionIsLockedForUsers.selector, ALICE, DEFAULT_BIN_STEP)
        );
        factory.createLBPair(link, usdc, ID_ONE, DEFAULT_BIN_STEP);

        factory.createLBPair(wbtc, usdc, ID_ONE, DEFAULT_BIN_STEP);
    }

    function test_revert_CreateLBPair() public {
        // Alice can't create a pair if the factory is locked
        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(ILBFactory.LBFactory__FunctionIsLockedForUsers.selector, ALICE, DEFAULT_BIN_STEP)
        );
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

        // TODO Can't create a pair with an invalid bin step
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

    function test_SetLBPairIgnoredForRouting() public {
        ILBPair pair = factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        // Ignoring the USDT-USDC rev 2 pair
        vm.expectEmit(true, true, true, true);
        emit LBPairIgnoredStateChanged(pair, true);
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, true);

        ILBFactory.LBPairInformation memory pairInfo = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP);
        assertEq(address(pairInfo.LBPair), address(pair), "test_SetLBPairIgnoredForRouting::1");
        assertEq(pairInfo.ignoredForRouting, true, "test_SetLBPairIgnoredForRouting::2");

        // Put it back to normal
        vm.expectEmit(true, true, true, true);
        emit LBPairIgnoredStateChanged(pair, false);
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, false);

        assertEq(
            factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).ignoredForRouting,
            false,
            "test_SetLBPairIgnoredForRouting::3"
        );
    }

    function test_revert_SetLBPairIgnoredForRouting() public {
        // Can't ignore for routing if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, true);

        // Can't update a non existing pair
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__AddressZero.selector));
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, true);

        factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        // Can't update a pair to the same state
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__LBPairIgnoredIsAlreadyInTheSameState.selector));
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, false);

        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, true);

        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__LBPairIgnoredIsAlreadyInTheSameState.selector));
        factory.setLBPairIgnored(usdt, usdc, DEFAULT_BIN_STEP, true);
    }

    function testFuzz_SetPreset(
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
        filterPeriod = uint16(bound(filterPeriod, 0, Encoded.MASK_UINT12 - 1));
        decayPeriod = uint16(bound(decayPeriod, filterPeriod + 1, Encoded.MASK_UINT12));
        reductionFactor = uint16(bound(reductionFactor, 0, Constants.BASIS_POINT_MAX));
        variableFeeControl = uint24(bound(variableFeeControl, 0, Constants.BASIS_POINT_MAX));
        protocolShare = uint16(bound(protocolShare, 0, 2_500));
        maxVolatilityAccumulator = uint24(bound(maxVolatilityAccumulator, 0, Encoded.MASK_UINT20));

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
            (uint256 baseFactorView, uint256 filterPeriodView, uint256 decayPeriodView, uint256 reductionFactorView,,,)
            = factory.getPreset(binStep);

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

    function test_RemovePreset() public {
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

        assertEq(factory.getAllBinSteps().length, 3, "test_RemovePreset::1");

        vm.expectEmit(true, true, true, true);
        emit PresetRemoved(DEFAULT_BIN_STEP);
        factory.removePreset(DEFAULT_BIN_STEP);

        assertEq(factory.getAllBinSteps().length, 2, "test_RemovePreset::2");

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

    function test_SetFeesParametersOnPair() public {
        ILBPair pair = factory.createLBPair(wavax, usdc, ID_ONE, DEFAULT_BIN_STEP);
        addLiquidity(DEV, DEV, LBPair(address(pair)), ID_ONE, 100e18, 100e18, 10, 10);

        // Do swaps to increase the variable fee parameters
        {
            deal(address(usdc), DEV, 60e18);
            ILBRouter.Path memory path;
            path.pairBinSteps = new uint256[](1);
            path.pairBinSteps[0] = DEFAULT_BIN_STEP;

            path.versions = new ILBRouter.Version[](1);
            path.versions[0] = ILBRouter.Version.V2_1;

            path.tokenPath = new IERC20[](2);
            path.tokenPath[0] = usdc;
            path.tokenPath[1] = wavax;
            router.swapExactTokensForTokens(50e18, 0, path, address(this), block.timestamp + 1);
            vm.warp(100);
            router.swapExactTokensForTokens(10e18, 0, path, address(this), block.timestamp + 1);
        }

        (
            uint24 oldVolatilityAccumulator,
            uint24 oldVolatilityReference,
            uint24 oldIdReference,
            uint40 oldTimeOfLastUpdate
        ) = pair.getVariableFeeParameters();

        vm.expectEmit(true, true, true, true);
        emit StaticFeeParametersSet(
            address(factory),
            DEFAULT_BASE_FACTOR * 2,
            DEFAULT_FILTER_PERIOD * 2,
            DEFAULT_DECAY_PERIOD * 2,
            DEFAULT_REDUCTION_FACTOR * 2,
            DEFAULT_VARIABLE_FEE_CONTROL * 2,
            DEFAULT_PROTOCOL_SHARE * 2,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR * 2
            );

        factory.setFeesParametersOnPair(
            wavax,
            usdc,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR * 2,
            DEFAULT_FILTER_PERIOD * 2,
            DEFAULT_DECAY_PERIOD * 2,
            DEFAULT_REDUCTION_FACTOR * 2,
            DEFAULT_VARIABLE_FEE_CONTROL * 2,
            DEFAULT_PROTOCOL_SHARE * 2,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR * 2
        );

        {
            (
                uint16 baseFactor,
                uint16 filterPeriod,
                uint16 decayPeriod,
                uint16 reductionFactor,
                uint24 variableFeeControl,
                uint16 protocolShare,
                uint24 maxVolatilityAccumulator
            ) = pair.getStaticFeeParameters();

            assertEq(baseFactor, DEFAULT_BASE_FACTOR * 2, "test_SetFeesParametersOnPair::1");
            assertEq(filterPeriod, DEFAULT_FILTER_PERIOD * 2, "test_SetFeesParametersOnPair::2");
            assertEq(decayPeriod, DEFAULT_DECAY_PERIOD * 2, "test_SetFeesParametersOnPair::3");
            assertEq(reductionFactor, DEFAULT_REDUCTION_FACTOR * 2, "test_SetFeesParametersOnPair::4");
            assertEq(variableFeeControl, DEFAULT_VARIABLE_FEE_CONTROL * 2, "test_SetFeesParametersOnPair::5");
            assertEq(protocolShare, DEFAULT_PROTOCOL_SHARE * 2, "test_SetFeesParametersOnPair::6");
            assertEq(
                maxVolatilityAccumulator, DEFAULT_MAX_VOLATILITY_ACCUMULATOR * 2, "test_SetFeesParametersOnPair::7"
            );
        }

        {
            (uint24 volatilityAccumulator, uint24 volatilityReference, uint24 idReference, uint40 timeOfLastUpdate) =
                pair.getVariableFeeParameters();

            assertEq(volatilityAccumulator, oldVolatilityAccumulator, "test_SetFeesParametersOnPair::8");
            assertEq(volatilityReference, oldVolatilityReference, "test_SetFeesParametersOnPair::9");
            assertEq(idReference, oldIdReference, "test_SetFeesParametersOnPair::10");
            assertEq(timeOfLastUpdate, oldTimeOfLastUpdate, "test_SetFeesParametersOnPair::11");
        }

        // Can't update if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.setFeesParametersOnPair(
            wavax,
            usdc,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR * 2,
            DEFAULT_FILTER_PERIOD * 2,
            DEFAULT_DECAY_PERIOD * 2,
            DEFAULT_REDUCTION_FACTOR * 2,
            DEFAULT_VARIABLE_FEE_CONTROL * 2,
            DEFAULT_PROTOCOL_SHARE * 2,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR * 2
        );

        // Can't update a pair that does not exist
        vm.expectRevert(
            abi.encodeWithSelector(ILBFactory.LBFactory__LBPairNotCreated.selector, weth, usdc, DEFAULT_BIN_STEP)
        );
        factory.setFeesParametersOnPair(
            weth,
            usdc,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR * 2,
            DEFAULT_FILTER_PERIOD * 2,
            DEFAULT_DECAY_PERIOD * 2,
            DEFAULT_REDUCTION_FACTOR * 2,
            DEFAULT_VARIABLE_FEE_CONTROL * 2,
            DEFAULT_PROTOCOL_SHARE * 2,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR * 2
        );
    }

    function test_SetFeeRecipient() public {
        vm.expectEmit(true, true, true, true);
        emit FeeRecipientSet(address(this), ALICE);
        factory.setFeeRecipient(ALICE);

        assertEq(factory.getFeeRecipient(), ALICE, "test_SetFeeRecipient::1");

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

    function test_SetFlashLoanFee() public {
        uint256 newFlashLoanFee = 1_000;
        vm.expectEmit(true, true, true, true);
        emit FlashLoanFeeSet(DEFAULT_FLASHLOAN_FEE, newFlashLoanFee);
        factory.setFlashLoanFee(newFlashLoanFee);

        assertEq(factory.getFlashLoanFee(), newFlashLoanFee, "test_SetFlashLoanFee::1");

        // Can't set if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.setFlashLoanFee(DEFAULT_FLASHLOAN_FEE);

        // Can't set to the same fee
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__SameFlashLoanFee.selector, newFlashLoanFee));
        factory.setFlashLoanFee(newFlashLoanFee);

        // Can't set to a fee greater than the maximum
        uint256 maxFlashLoanFee = factory.getMaxFlashLoanFee();
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBFactory.LBFactory__FlashLoanFeeAboveMax.selector, maxFlashLoanFee + 1, maxFlashLoanFee
            )
        );
        factory.setFlashLoanFee(maxFlashLoanFee + 1);
    }

    function testFuzz_OpenPresets(uint8 binStep) public {
        uint256 minBinStep = factory.getMinBinStep();
        uint256 maxBinStep = factory.getMaxBinStep();

        binStep = uint8(bound(binStep, minBinStep, maxBinStep));

        // Preset are not open to the public by default
        assertFalse(factory.isPresetOpen(binStep), "testFuzz_OpenPresets::1");

        // Can be opened
        vm.expectEmit(true, true, true, true);
        emit OpenPresetChanged(binStep, true);
        factory.setOpenPreset(binStep, true);

        for (uint256 i = minBinStep; i < maxBinStep; i++) {
            if (i == binStep) {
                assertTrue(factory.isPresetOpen(uint8(i)), "testFuzz_OpenPresets::2");
            } else {
                assertFalse(factory.isPresetOpen(uint8(i)), "testFuzz_OpenPresets::3");
            }
        }

        // Setting neighboring presets to true does not change the state of the preset
        uint8 nextBinStep = uint8(bound(binStep + 1, minBinStep, maxBinStep));
        uint8 previousBinStep = uint8(bound(binStep + maxBinStep - minBinStep - 1, minBinStep, maxBinStep));

        factory.setOpenPreset(nextBinStep, true);
        factory.setOpenPreset(previousBinStep, true);

        assertTrue(factory.isPresetOpen(binStep), "testFuzz_OpenPresets::4");
        assertTrue(factory.isPresetOpen(nextBinStep), "testFuzz_OpenPresets::5");
        assertTrue(factory.isPresetOpen(previousBinStep), "testFuzz_OpenPresets::6");

        // Can't set to the same state
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__SamePresetOpenState.selector));
        factory.setOpenPreset(binStep, true);

        // Can be closed
        vm.expectEmit(true, true, true, true);
        emit OpenPresetChanged(binStep, false);
        factory.setOpenPreset(binStep, false);

        assertFalse(factory.isPresetOpen(binStep), "testFuzz_OpenPresets::7");
        assertTrue(factory.isPresetOpen(nextBinStep), "testFuzz_OpenPresets::8");
        assertTrue(factory.isPresetOpen(previousBinStep), "testFuzz_OpenPresets::9");

        // Can't open if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.setOpenPreset(binStep, true);

        // Can't set to the same state
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__SamePresetOpenState.selector));
        factory.setOpenPreset(binStep, false);
    }

    function test_AddQuoteAsset() public {
        uint256 numberOfQuoteAssetBefore = factory.getNumberOfQuoteAssets();

        IERC20 newToken = new ERC20Mock(18);

        assertEq(factory.isQuoteAsset(newToken), false, "test_AddQuoteAsset::1");

        vm.expectEmit(true, true, true, true);
        emit QuoteAssetAdded(newToken);
        factory.addQuoteAsset(newToken);

        assertEq(factory.isQuoteAsset(newToken), true, "test_AddQuoteAsset::2");
        assertEq(factory.getNumberOfQuoteAssets(), numberOfQuoteAssetBefore + 1, "test_AddQuoteAsset::3");
        assertEq(
            address(newToken), address(factory.getQuoteAssetAtIndex(numberOfQuoteAssetBefore)), "test_AddQuoteAsset::4"
        );

        // Can't add if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.addQuoteAsset(newToken);

        // Can't add if the asset is already a quote asset
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__QuoteAssetAlreadyWhitelisted.selector, newToken));
        factory.addQuoteAsset(newToken);
    }

    function test_RemoveQuoteAsset() public {
        uint256 numberOfQuoteAssetBefore = factory.getNumberOfQuoteAssets();

        assertEq(factory.isQuoteAsset(usdc), true, "test_RemoveQuoteAsset::1");

        vm.expectEmit(true, true, true, true);
        emit QuoteAssetRemoved(usdc);
        factory.removeQuoteAsset(usdc);

        assertEq(factory.isQuoteAsset(usdc), false, "test_RemoveQuoteAsset::2");
        assertEq(factory.getNumberOfQuoteAssets(), numberOfQuoteAssetBefore - 1, "test_RemoveQuoteAsset::3");

        // Can't remove if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.removeQuoteAsset(usdc);

        // Can't remove if the asset is not a quote asset
        vm.expectRevert(abi.encodeWithSelector(ILBFactory.LBFactory__QuoteAssetNotWhitelisted.selector, usdc));
        factory.removeQuoteAsset(usdc);
    }

    function test_ForceDecay() public {
        ILBPair pair = factory.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);

        factory.forceDecay(pair);

        // Can't force decay if not the owner
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IPendingOwnable.PendingOwnable__NotOwner.selector));
        factory.forceDecay(pair);
    }

    function test_GetAllLBPairs() public {
        /* Create pairs:
        - WETH/USDC with bin step = 5
        - WETH/USDC with bin step = 20
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
        factory.createLBPair(usdt, usdc, ID_ONE, 5);

        ILBFactory.LBPairInformation[] memory LBPairsAvailable = factory.getAllLBPairs(weth, usdc);

        assertEq(LBPairsAvailable.length, 2, "test_GetAllLBPairs::1");

        ILBFactory.LBPairInformation memory pair1Info = LBPairsAvailable[0];
        assertEq(address(pair1Info.LBPair), address(pair1), "test_GetAllLBPairs::2");
        assertEq(pair1Info.binStep, 5, "test_GetAllLBPairs::3");

        ILBFactory.LBPairInformation memory pair2Info = LBPairsAvailable[1];
        assertEq(address(pair2Info.LBPair), address(pair2), "test_GetAllLBPairs::4");
        assertEq(pair2Info.binStep, 20, "test_GetAllLBPairs::5");
    }
}
