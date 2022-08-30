// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./TestHelper.sol";

contract LiquidityBinFactoryTest is TestHelper {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token12D = new ERC20MockDecimals(12);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV, 8e14);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
        new LBFactoryHelper(factory);
    }

    function testConstructor() public {
        assertEq(factory.feeRecipient(), DEV);
        assertEq(factory.flashLoanFee(), 8e14);
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

    function testFactoryHelperCalledDirectly() public {
        ILBFactoryHelper factoryHelper = factory.factoryHelper();

        vm.expectRevert(LBFactoryHelper__CallerIsNotFactory.selector);
        factoryHelper.createLBPair(
            token6D,
            token12D,
            keccak256(abi.encode(token6D, token12D)),
            ID_ONE,
            DEFAULT_SAMPLE_LIFETIME,
            bytes32(
                abi.encodePacked(
                    uint136(DEFAULT_MAX_VOLATILITY_ACCUMULATED), // The first 112 bits are reserved for the dynamic parameters
                    DEFAULT_PROTOCOL_SHARE,
                    DEFAULT_VARIABLE_FEE_CONTROL,
                    DEFAULT_REDUCTION_FACTOR,
                    DEFAULT_DECAY_PERIOD,
                    DEFAULT_FILTER_PERIOD,
                    DEFAULT_BASE_FACTOR,
                    DEFAULT_BIN_STEP
                )
            )
        );
    }

    function testSetFeeRecipient() public {
        factory.setFeeRecipient(ALICE);

        assertEq(factory.feeRecipient(), ALICE);
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
        vm.expectRevert(LBFactory__ZeroAddress.selector);
        factory.createLBPair(token6D, IERC20(address(0)), ID_ONE, DEFAULT_BIN_STEP);
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
}
