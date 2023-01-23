// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "test/helpers/TestHelper.sol";

contract LiquidityBinFactoryTest is TestHelper {
    event QuoteAssetRemoved(IERC20 indexed _quoteAsset);
    event QuoteAssetAdded(IERC20 indexed _quoteAsset);
    event LBPairImplementationSet(ILBPair oldLBPairImplementation, ILBPair LBPairImplementation);

    struct LBPairInformation {
        uint256 binStep;
        ILBPair LBPair;
        bool createdByOwner;
        bool ignoredForRouting;
    }

    function setUp() public override {
        usdc = new ERC20Mock(6);
        wbtc = new ERC20Mock(12);
        weth = new ERC20Mock(18);
        wavax = new WAVAX();
        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
    }

    function testConstructor() public {
        assertEq(factory.feeRecipient(), DEV);
        assertEq(factory.flashLoanFee(), 8e14);
    }

    function testSetLBPairImplementation() public {
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        vm.expectRevert(abi.encodeWithSelector(LBFactory__SameImplementation.selector, _LBPairImplementation));
        factory.setLBPairImplementation(address(_LBPairImplementation));

        LBFactory anotherFactory = new LBFactory(DEV, 7e14);
        vm.expectRevert(LBFactory__ImplementationNotSet.selector);
        anotherFactory.createLBPair(usdc, weth, ID_ONE, DEFAULT_BIN_STEP);

        ILBPair _LBPairImplementationAnotherFactory = new LBPair(anotherFactory);
        vm.expectRevert(
            abi.encodeWithSelector(LBFactory__LBPairSafetyCheckFailed.selector, _LBPairImplementationAnotherFactory)
        );
        factory.setLBPairImplementation(address(_LBPairImplementationAnotherFactory));

        ILBPair _LBPairImplementationNew = new LBPair(factory);
        vm.expectEmit(true, true, true, true);
        emit LBPairImplementationSet(_LBPairImplementation, _LBPairImplementationNew);
        factory.setLBPairImplementation(address(_LBPairImplementationNew));
    }

    function testgetAllLBPairs() public {
        assertEq(factory.getAllLBPairs(usdc, weth).length, 0);
        ILBPair pair25 = createLBPairDefaultFees(usdc, weth);
        assertEq(factory.getAllLBPairs(usdc, weth).length, 1);
        setDefaultFactoryPresets(1);
        ILBPair pair1 = factory.createLBPair(usdc, weth, ID_ONE, 1);
        assertEq(factory.getAllLBPairs(usdc, weth).length, 2);

        factory.setPreset(
            50,
            DEFAULT_BASE_FACTOR / 4,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL / 4,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED,
            DEFAULT_SAMPLE_LIFETIME
        );
        router = new LBRouter(factory, IJoeFactory(address(0)), IWAVAX(address(0)));
        factory.setFactoryLockedState(false);
        ILBPair pair50 = router.createLBPair(usdc, weth, ID_ONE, 50);
        factory.setLBPairIgnored(usdc, weth, 50, true);
        assertEq(factory.getAllLBPairs(usdc, weth).length, 3);

        ILBFactory.LBPairInformation[] memory LBPairsAvailable = factory.getAllLBPairs(usdc, weth);

        assertEq(LBPairsAvailable[0].binStep, 1);
        assertEq(address(LBPairsAvailable[0].LBPair), address(pair1));
        assertEq(LBPairsAvailable[0].createdByOwner, true);
        assertEq(LBPairsAvailable[0].ignoredForRouting, false);

        assertEq(LBPairsAvailable[1].binStep, 25);
        assertEq(address(LBPairsAvailable[1].LBPair), address(pair25));
        assertEq(LBPairsAvailable[1].createdByOwner, true);
        assertEq(LBPairsAvailable[1].ignoredForRouting, false);

        assertEq(LBPairsAvailable[2].binStep, 50);
        assertEq(address(LBPairsAvailable[2].LBPair), address(pair50));
        assertEq(LBPairsAvailable[2].createdByOwner, false);
        assertEq(LBPairsAvailable[2].ignoredForRouting, true);
    }

    function testCreateLBPair() public {
        ILBPair pair = createLBPairDefaultFees(usdc, wbtc);

        assertEq(factory.getNumberOfLBPairs(), 1);
        assertEq(address(factory.getLBPairInformation(usdc, wbtc, DEFAULT_BIN_STEP).LBPair), address(pair));

        assertEq(address(pair.factory()), address(factory));
        assertEq(address(pair.tokenX()), address(usdc));
        assertEq(address(pair.tokenY()), address(wbtc));

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
        vm.expectRevert(LBFactory__AddressZero.selector);
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
        createLBPairDefaultFees(usdc, wbtc);
    }

    function testCreatePairWhenFactoryIsUnlocked() public {
        factory.setFactoryLockedState(false);

        vm.prank(ALICE);
        createLBPairDefaultFees(usdc, wbtc);

        ILBFactory.LBPairInformation[] memory LBPairBinSteps = factory.getAllLBPairs(usdc, wbtc);
        assertEq(LBPairBinSteps.length, 1);
        assertEq(LBPairBinSteps[0].binStep, DEFAULT_BIN_STEP);
        assertEq(LBPairBinSteps[0].ignoredForRouting, false);
        assertEq(LBPairBinSteps[0].createdByOwner, false);
    }

    function testForIdenticalAddressesReverts() public {
        vm.expectRevert(abi.encodeWithSelector(LBFactory__IdenticalAddresses.selector, usdc));
        factory.createLBPair(usdc, usdc, ID_ONE, DEFAULT_BIN_STEP);
    }

    function testForZeroAddressPairReverts() public {
        factory.addQuoteAsset(IERC20(address(0)));
        vm.expectRevert(LBFactory__AddressZero.selector);
        factory.createLBPair(usdc, IERC20(address(0)), ID_ONE, DEFAULT_BIN_STEP);

        vm.expectRevert(LBFactory__AddressZero.selector);
        factory.createLBPair(IERC20(address(0)), usdc, ID_ONE, DEFAULT_BIN_STEP);
    }

    function testIfPairAlreadyExistsReverts() public {
        createLBPairDefaultFees(usdc, wbtc);
        vm.expectRevert(abi.encodeWithSelector(LBFactory__LBPairAlreadyExists.selector, usdc, wbtc, DEFAULT_BIN_STEP));
        createLBPairDefaultFees(usdc, wbtc);
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
        ILBPair pair = createLBPairDefaultFees(usdc, wbtc);

        factory.setFeesParametersOnPair(
            usdc,
            wbtc,
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

    function testSetFeesParametersOnPairReverts() public {
        createLBPairDefaultFees(usdc, wbtc);
        vm.prank(ALICE);
        vm.expectRevert(PendingOwnable__NotOwner.selector);
        factory.setFeesParametersOnPair(
            usdc,
            wbtc,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED
        );
        vm.expectRevert(abi.encodeWithSelector(LBFactory__LBPairNotCreated.selector, usdc, weth, DEFAULT_BIN_STEP));
        factory.setFeesParametersOnPair(
            usdc,
            weth,
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
        createLBPairDefaultFees(usdc, wbtc);

        uint16 invalidFilterPeriod = DEFAULT_DECAY_PERIOD;
        vm.expectRevert(
            abi.encodeWithSelector(LBFactory__DecreasingPeriods.selector, invalidFilterPeriod, DEFAULT_DECAY_PERIOD)
        );

        factory.setFeesParametersOnPair(
            usdc,
            wbtc,
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

    function testForInvalidProtocolShare() public {
        createLBPairDefaultFees(usdc, wbtc);
        uint16 invalidProtocolShare = uint16(factory.MAX_PROTOCOL_SHARE() + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBFactory__ProtocolShareOverflows.selector, invalidProtocolShare, factory.MAX_PROTOCOL_SHARE()
            )
        );

        factory.setFeesParametersOnPair(
            usdc,
            wbtc,
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
                LBFactory__ReductionFactorOverflows.selector, invalidReductionFactor, Constants.BASIS_POINT_MAX
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

    function testForSetLBPairIgnoredReverts() public {
        createLBPairDefaultFees(usdc, weth);

        factory.setLBPairIgnored(usdc, weth, DEFAULT_BIN_STEP, true);
        vm.expectRevert(LBFactory__LBPairIgnoredIsAlreadyInTheSameState.selector);
        factory.setLBPairIgnored(usdc, weth, DEFAULT_BIN_STEP, true);

        vm.expectRevert(LBFactory__AddressZero.selector);
        factory.setLBPairIgnored(usdc, weth, DEFAULT_BIN_STEP + 1, true);
    }

    function testForSettingFlashloanFee() public {
        uint256 flashFee = 7e14;
        factory.setFlashLoanFee(flashFee);
        assertEq(factory.flashLoanFee(), flashFee);
        vm.expectRevert(abi.encodeWithSelector(LBFactory__SameFlashLoanFee.selector, flashFee));
        factory.setFlashLoanFee(flashFee);
        flashFee = 0.1e18 + 1;
        vm.expectRevert(abi.encodeWithSelector(LBFactory__FlashLoanFeeAboveMax.selector, flashFee, 0.1e18));
        factory.setFlashLoanFee(flashFee);
    }

    function testForInvalidFeeRecipient() public {
        vm.expectRevert(LBFactory__AddressZero.selector);
        factory = new LBFactory(address(0), 8e14);
    }

    function testsetFactoryLockedState() public {
        vm.expectRevert(LBFactory__FactoryLockIsAlreadyInTheSameState.selector);
        factory.setFactoryLockedState(true);
    }

    function testFeesAboveMaxBaseFactorReverts(uint8 baseFactorIncrement) public {
        vm.assume(baseFactorIncrement > 0);
        uint16 baseFactorIncreased = DEFAULT_BASE_FACTOR + baseFactorIncrement;

        //copy of part of factory._getPackedFeeParameters function
        uint256 _baseFee = (uint256(baseFactorIncreased) * DEFAULT_BIN_STEP) * 1e10;
        uint256 _maxVariableFee = (
            DEFAULT_VARIABLE_FEE_CONTROL * (uint256(DEFAULT_MAX_VOLATILITY_ACCUMULATED) * DEFAULT_BIN_STEP)
                * (uint256(DEFAULT_MAX_VOLATILITY_ACCUMULATED) * DEFAULT_BIN_STEP)
        ) / 100;

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
        uint256 _maxVariableFee = (
            DEFAULT_VARIABLE_FEE_CONTROL * (uint256(volatilityAccumulated) * DEFAULT_BIN_STEP)
                * (uint256(volatilityAccumulated) * DEFAULT_BIN_STEP)
        ) / 100;
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
        createLBPairDefaultFeesFromStartIdAndBinStep(usdc, wbtc, ID_ONE, DEFAULT_BIN_STEP + 1);
    }

    function testQuoteAssets() public {
        assertEq(factory.getNumberOfQuoteAssets(), 4);
        assertEq(address(factory.getQuoteAsset(0)), address(wavax));
        assertEq(address(factory.getQuoteAsset(1)), address(usdc));
        assertEq(address(factory.getQuoteAsset(2)), address(wbtc));
        assertEq(address(factory.getQuoteAsset(3)), address(weth));
        assertEq(factory.isQuoteAsset(wavax), true);
        assertEq(factory.isQuoteAsset(usdc), true);
        assertEq(factory.isQuoteAsset(wbtc), true);
        assertEq(factory.isQuoteAsset(weth), true);

        vm.expectRevert(abi.encodeWithSelector(LBFactory__QuoteAssetAlreadyWhitelisted.selector, wbtc));
        factory.addQuoteAsset(wbtc);

        wbtc = new ERC20Mock(24);
        vm.expectRevert(abi.encodeWithSelector(LBFactory__QuoteAssetNotWhitelisted.selector, wbtc));
        factory.removeQuoteAsset(wbtc);

        assertEq(factory.isQuoteAsset(wbtc), false);
        vm.expectRevert(abi.encodeWithSelector(LBFactory__QuoteAssetNotWhitelisted.selector, wbtc));
        factory.createLBPair(usdc, wbtc, ID_ONE, DEFAULT_BIN_STEP);

        vm.expectEmit(true, true, true, true);
        emit QuoteAssetAdded(wbtc);
        factory.addQuoteAsset(wbtc);
        assertEq(factory.isQuoteAsset(wbtc), true);
        assertEq(address(factory.getQuoteAsset(4)), address(wbtc));

        vm.expectEmit(true, true, true, true);
        emit QuoteAssetRemoved(wbtc);
        factory.removeQuoteAsset(wbtc);
        assertEq(factory.isQuoteAsset(wbtc), false);
    }
}
