// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./TestHelper.sol";

contract LiquidityBinFactoryTest is TestHelper {
    event QuoteAssetRemoved(IERC20 indexed _quoteAsset);
    event QuoteAssetAdded(IERC20 indexed _quoteAsset);
    event LBPairImplementationSet(ILBPair oldLBPairImplementation, ILBPair LBPairImplementation);

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token12D = new ERC20MockDecimals(12);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(_LBPairImplementation);
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
    }

    function testConstructor() public {
        assertEq(factory.feeRecipient(), DEV);
        assertEq(factory.flashLoanFee(), 8e14);
    }

    function testSetLBPairImplementation() public {
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(_LBPairImplementation);
        vm.expectRevert(abi.encodeWithSelector(LBFactory__SameImplementation.selector, _LBPairImplementation));
        factory.setLBPairImplementation(_LBPairImplementation);

        LBFactory anotherFactory = new LBFactory(DEV, 7e14);
        ILBPair _LBPairImplementationAnotherFactory = new LBPair(anotherFactory);
        vm.expectRevert(
            abi.encodeWithSelector(LBFactory__LBPairSafetyCheckFailed.selector, _LBPairImplementationAnotherFactory)
        );
        factory.setLBPairImplementation(_LBPairImplementationAnotherFactory);

        ILBPair _LBPairImplementationNew = new LBPair(factory);
        vm.expectEmit(true, true, true, true);
        emit LBPairImplementationSet(_LBPairImplementation, _LBPairImplementationNew);
        factory.setLBPairImplementation(_LBPairImplementationNew);
    }

    function testCreateLBPair() public {
        ILBPair pair = createLBPairDefaultFees(token6D, token12D);

        assertEq(factory.allPairsLength(), 1);
        assertEq(address(factory.getLBPairInfo(token6D, token12D, DEFAULT_BIN_STEP).LBPair), address(pair));

        assertEq(address(pair.factory()), address(factory));
        assertEq(address(pair.tokenX()), address(token6D));
        assertEq(address(pair.tokenY()), address(token12D));

        FeeHelper.FeeParameters memory feeParameters = pair.feeParameters();
        assertEq(feeParameters.volatilityAccumulated, 0);
        assertEq(feeParameters.volatilityReference, 0);
        assertEq(feeParameters.indexRef, 0);
        assertEq(feeParameters.time, 0);
        assertEq(feeParameters.maxVolatilityAccumulated, DEFAULT_MAX_VOLATILITY_ACCUMULATED);
        assertEq(feeParameters.filterPeriod, DEFAULT_FILTER_PERIOD);
        assertEq(feeParameters.decayPeriod, DEFAULT_DECAY_PERIOD);
        assertEq(feeParameters.binStep, DEFAULT_BIN_STEP);
        assertEq(feeParameters.baseFactor, DEFAULT_BASE_FACTOR);
        assertEq(feeParameters.protocolShare, DEFAULT_PROTOCOL_SHARE);
    }

    function testSetFeeRecipient() public {
        vm.expectRevert(LBFactory__ZeroAddress.selector);
        factory.setFeeRecipient(address(0));

        factory.setFeeRecipient(ALICE);
        assertEq(factory.feeRecipient(), ALICE);

        vm.expectRevert(abi.encodeWithSelector(LBFactory__SameFeeRecipient.selector, ALICE));
        factory.setFeeRecipient(ALICE);
    }

    function testSetFeeRecipientNotByOwnerReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(PendingOwnable__NotOwner.selector);
        factory.setFeeRecipient(ALICE);
    }

    function testFactoryLockedReverts() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(LBFactory__FunctionIsLockedForUsers.selector, ALICE));
        createLBPairDefaultFees(token6D, token12D);
    }

    function testCreatePairWhenFactoryIsUnlocked() public {
        factory.setFactoryLocked(false);

        vm.prank(ALICE);
        createLBPairDefaultFees(token6D, token12D);

        ILBFactory.LBPairAvailable[] memory LBPairBinSteps = factory.getAvailableLBPairsBinStep(token6D, token12D);
        assertEq(LBPairBinSteps.length, 1);
        assertEq(LBPairBinSteps[0].binStep, DEFAULT_BIN_STEP);
        assertEq(LBPairBinSteps[0].isBlacklisted, false);
        assertEq(LBPairBinSteps[0].createdByOwner, false);
    }

    function testForIdenticalAddressesReverts() public {
        vm.expectRevert(abi.encodeWithSelector(LBFactory__IdenticalAddresses.selector, token6D));
        factory.createLBPair(token6D, token6D, ID_ONE, DEFAULT_BIN_STEP);
    }

    function testForZeroAddressPairReverts() public {
        factory.AddQuoteAsset(IERC20(address(0)));
        vm.expectRevert(LBFactory__ZeroAddress.selector);
        factory.createLBPair(token6D, IERC20(address(0)), ID_ONE, DEFAULT_BIN_STEP);

        vm.expectRevert(LBFactory__ZeroAddress.selector);
        factory.createLBPair(IERC20(address(0)), token6D, ID_ONE, DEFAULT_BIN_STEP);
    }

    function testIfPairAlreadyExistsReverts() public {
        createLBPairDefaultFees(token6D, token12D);
        vm.expectRevert(
            abi.encodeWithSelector(LBFactory__LBPairAlreadyExists.selector, token6D, token12D, DEFAULT_BIN_STEP)
        );
        createLBPairDefaultFees(token6D, token12D);
    }

    function testForInvalidBinStepOverflowReverts() public {
        uint16 invalidBinStepOverflow = uint16(factory.MAX_BIN_STEP() + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBFactory__BinStepRequirementsBreached.selector,
                factory.MIN_BIN_STEP(),
                invalidBinStepOverflow,
                factory.MAX_BIN_STEP()
            )
        );

        factory.setPreset(
            invalidBinStepOverflow,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED,
            DEFAULT_SAMPLE_LIFETIME
        );
    }

    function testForInvalidBinStepUnderflowReverts() public {
        uint16 invalidBinStepUnderflow = uint16(factory.MIN_BIN_STEP() - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBFactory__BinStepRequirementsBreached.selector,
                factory.MIN_BIN_STEP(),
                invalidBinStepUnderflow,
                factory.MAX_BIN_STEP()
            )
        );
        factory.setPreset(
            invalidBinStepUnderflow,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED,
            DEFAULT_SAMPLE_LIFETIME
        );
    }

    function testSetFeesParametersOnPair() public {
        ILBPair pair = createLBPairDefaultFees(token6D, token12D);

        factory.setFeesParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR - 1,
            DEFAULT_FILTER_PERIOD - 1,
            DEFAULT_DECAY_PERIOD - 1,
            DEFAULT_REDUCTION_FACTOR - 1,
            DEFAULT_VARIABLE_FEE_CONTROL - 1,
            DEFAULT_PROTOCOL_SHARE - 1,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED - 1
        );

        FeeHelper.FeeParameters memory feeParameters = pair.feeParameters();
        assertEq(feeParameters.volatilityAccumulated, 0);
        assertEq(feeParameters.time, 0);
        assertEq(feeParameters.binStep, DEFAULT_BIN_STEP);
        assertEq(feeParameters.baseFactor, DEFAULT_BASE_FACTOR - 1);
        assertEq(feeParameters.filterPeriod, DEFAULT_FILTER_PERIOD - 1);
        assertEq(feeParameters.decayPeriod, DEFAULT_DECAY_PERIOD - 1);
        assertEq(feeParameters.reductionFactor, DEFAULT_REDUCTION_FACTOR - 1);
        assertEq(feeParameters.variableFeeControl, DEFAULT_VARIABLE_FEE_CONTROL - 1);
        assertEq(feeParameters.protocolShare, DEFAULT_PROTOCOL_SHARE - 1);
        assertEq(feeParameters.maxVolatilityAccumulated, DEFAULT_MAX_VOLATILITY_ACCUMULATED - 1);
    }

    function testSetFeesParametersOnPairNotByOwner() public {
        createLBPairDefaultFees(token6D, token12D);
        vm.prank(ALICE);
        vm.expectRevert(PendingOwnable__NotOwner.selector);
        factory.setFeesParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED
        );
    }

    function testForInvalidFilterPeriod() public {
        createLBPairDefaultFees(token6D, token12D);

        uint16 invalidFilterPeriod = DEFAULT_DECAY_PERIOD;
        vm.expectRevert(
            abi.encodeWithSelector(LBFactory__DecreasingPeriods.selector, invalidFilterPeriod, DEFAULT_DECAY_PERIOD)
        );

        factory.setFeesParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            invalidFilterPeriod,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED
        );
    }

    function testForInvalidBaseFactor() public {
        createLBPairDefaultFees(token6D, token12D);
        uint16 invalidBaseFactor = uint16(Constants.BASIS_POINT_MAX + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBFactory__BaseFactorOverflows.selector,
                invalidBaseFactor,
                Constants.BASIS_POINT_MAX
            )
        );

        factory.setFeesParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            invalidBaseFactor,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED
        );
    }

    function testForInvalidProtocolShare() public {
        createLBPairDefaultFees(token6D, token12D);
        uint16 invalidProtocolShare = uint16(factory.MAX_PROTOCOL_SHARE() + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBFactory__ProtocolShareOverflows.selector,
                invalidProtocolShare,
                factory.MAX_PROTOCOL_SHARE()
            )
        );

        factory.setFeesParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            invalidProtocolShare,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED
        );
    }

    function testForInvalidReductionFactor() public {
        uint16 invalidReductionFactor = uint16(Constants.BASIS_POINT_MAX + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBFactory__ReductionFactorOverflows.selector,
                invalidReductionFactor,
                Constants.BASIS_POINT_MAX
            )
        );

        factory.setPreset(
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            invalidReductionFactor,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED,
            DEFAULT_SAMPLE_LIFETIME
        );
    }

    function testForDoubleBlacklisting() public {
        factory.setLBPairBlacklist(token6D, token18D, DEFAULT_BIN_STEP, true);
        vm.expectRevert(LBFactory__LBPairBlacklistIsAlreadyInTheSameState.selector);
        factory.setLBPairBlacklist(token6D, token18D, DEFAULT_BIN_STEP, true);
    }

    function testForSettingFlashloanFee() public {
        uint256 flashFee = 7e14;
        factory.setFlashLoanFee(flashFee);
        assertEq(factory.flashLoanFee(), flashFee);
        vm.expectRevert(abi.encodeWithSelector(LBFactory__SameFlashLoanFee.selector, flashFee));
        factory.setFlashLoanFee(flashFee);
    }

    function testForInvalidFeeRecipient() public {
        vm.expectRevert(LBFactory__ZeroAddress.selector);
        factory = new LBFactory(address(0), 8e14);
    }

    function testSetFactoryLocked() public {
        vm.expectRevert(LBFactory__FactoryLockIsAlreadyInTheSameState.selector);
        factory.setFactoryLocked(true);
    }

    function testFeesAboveMaxBaseFactorReverts(uint8 baseFactorIncrement) public {
        vm.assume(baseFactorIncrement > 0);
        uint16 baseFactorIncreased = DEFAULT_BASE_FACTOR + baseFactorIncrement;

        //copy of part of factory._getPackedFeeParameters function
        uint256 _baseFee = (uint256(baseFactorIncreased) * DEFAULT_BIN_STEP) * 1e10;
        uint256 _maxVariableFee = (DEFAULT_VARIABLE_FEE_CONTROL *
            (uint256(DEFAULT_MAX_VOLATILITY_ACCUMULATED) * DEFAULT_BIN_STEP) *
            (uint256(DEFAULT_MAX_VOLATILITY_ACCUMULATED) * DEFAULT_BIN_STEP)) / 100;

        uint256 fee = _baseFee + _maxVariableFee;
        vm.expectRevert(abi.encodeWithSelector(LBFactory__FeesAboveMax.selector, fee, factory.MAX_FEE()));
        factory.setPreset(
            DEFAULT_BIN_STEP,
            baseFactorIncreased,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED,
            DEFAULT_SAMPLE_LIFETIME
        );
    }

    function testFeesAboveMaxVolatilityReverts(uint8 maxVolatilityIncrement) public {
        vm.assume(maxVolatilityIncrement > 0);
        uint24 volatilityAccumulated = DEFAULT_MAX_VOLATILITY_ACCUMULATED + maxVolatilityIncrement;

        //copy of part of factory._getPackedFeeParameters function
        uint256 _baseFee = (uint256(DEFAULT_BASE_FACTOR) * DEFAULT_BIN_STEP) * 1e10;
        uint256 _maxVariableFee = (DEFAULT_VARIABLE_FEE_CONTROL *
            (uint256(volatilityAccumulated) * DEFAULT_BIN_STEP) *
            (uint256(volatilityAccumulated) * DEFAULT_BIN_STEP)) / 100;
        uint256 fee = _baseFee + _maxVariableFee;

        vm.expectRevert(abi.encodeWithSelector(LBFactory__FeesAboveMax.selector, fee, factory.MAX_FEE()));
        factory.setPreset(
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            volatilityAccumulated,
            DEFAULT_SAMPLE_LIFETIME
        );
    }

    function testInvalidBinStepWhileCreatingLBPair() public {
        vm.expectRevert(abi.encodeWithSelector(LBFactory__BinStepHasNoPreset.selector, DEFAULT_BIN_STEP + 1));
        createLBPairDefaultFeesFromStartIdAndBinStep(token6D, token12D, ID_ONE, DEFAULT_BIN_STEP + 1);
    }

    function testQuoteAssets() public {
        assertEq(factory.getQuoteAssetCount(), 3);
        assertEq(address(factory.getQuoteAsset(0)), address(token6D));
        assertEq(address(factory.getQuoteAsset(1)), address(token12D));
        assertEq(address(factory.getQuoteAsset(2)), address(token18D));
        assertEq(factory.isQuoteAsset(token6D), true);
        assertEq(factory.isQuoteAsset(token12D), true);
        assertEq(factory.isQuoteAsset(token18D), true);

        vm.expectRevert(abi.encodeWithSelector(LBFactory__QuoteAssetAlreadyWhitelisted.selector, token12D));
        factory.AddQuoteAsset(token12D);

        token24D = new ERC20MockDecimals(24);
        vm.expectRevert(abi.encodeWithSelector(LBFactory__QuoteAssetNotWhitelisted.selector, token24D));
        factory.RemoveQuoteAsset(token24D);

        assertEq(factory.isQuoteAsset(token24D), false);

        vm.expectEmit(true, true, true, true);
        emit QuoteAssetAdded(token24D);
        factory.AddQuoteAsset(token24D);
        assertEq(factory.isQuoteAsset(token24D), true);
        assertEq(address(factory.getQuoteAsset(3)), address(token24D));

        vm.expectEmit(true, true, true, true);
        emit QuoteAssetRemoved(token24D);
        factory.RemoveQuoteAsset(token24D);
        assertEq(factory.isQuoteAsset(token24D), false);
    }
}
