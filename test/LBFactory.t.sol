// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinFactoryTest is TestHelper {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token12D = new ERC20MockDecimals(12);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
        new LBFactoryHelper(factory);
    }

    function testConstructor() public {
        assertEq(factory.feeRecipient(), DEV);
    }

    function testCreateLBPair() public {
        ILBPair pair = createLBPairDefaultFees(token6D, token12D);

        assertEq(factory.allPairsLength(), 1);
        assertEq(address(factory.getLBPairInfo(token6D, token12D, DEFAULT_BIN_STEP).LBPair), address(pair));

        assertEq(address(pair.factory()), address(factory));
        assertEq(address(pair.tokenX()), address(token6D));
        assertEq(address(pair.tokenY()), address(token12D));

        FeeHelper.FeeParameters memory feeParameters = pair.feeParameters();
        assertEq(feeParameters.accumulator, 0);
        assertEq(feeParameters.time, 0);
        assertEq(feeParameters.maxAccumulator, DEFAULT_MAX_ACCUMULATOR);
        assertEq(feeParameters.filterPeriod, DEFAULT_FILTER_PERIOD);
        assertEq(feeParameters.decayPeriod, DEFAULT_DECAY_PERIOD);
        assertEq(feeParameters.binStep, DEFAULT_BIN_STEP);
        assertEq(feeParameters.baseFactor, DEFAULT_BASE_FACTOR);
        assertEq(feeParameters.protocolShare, DEFAULT_PROTOCOL_SHARE);
    }

    function testFailFactoryHelperCalledDirectly() public {
        ILBFactoryHelper factoryHelper = factory.factoryHelper();

        factoryHelper.createLBPair(
            token6D,
            token12D,
            keccak256(abi.encode(token6D, token12D)),
            ID_ONE,
            DEFAULT_SAMPLE_LIFETIME,
            bytes32(
                abi.encodePacked(
                    DEFAULT_MAX_ACCUMULATOR,
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

    function testFailSetFeeRecipientNotByOwner() public {
        vm.prank(ALICE);
        factory.setFeeRecipient(ALICE);
    }

    function testFailFactoryLocked() public {
        vm.prank(ALICE);
        createLBPairDefaultFees(token6D, token12D);
    }

    function testCreatePairWhenFactoryIsUnlocked() public {
        factory.setFactoryLocked(false);

        vm.prank(ALICE);
        createLBPairDefaultFees(token6D, token12D);
    }

    function testFailForIdenticalAddresses() public {
        factory.createLBPair(token6D, token6D, ID_ONE, DEFAULT_BIN_STEP);
    }

    function testFailForZeroAddressPair() public {
        factory.createLBPair(token6D, IERC20(address(0)), ID_ONE, DEFAULT_BIN_STEP);
    }

    function testFailIfPairAlreadyExists() public {
        createLBPairDefaultFees(token6D, token12D);
        createLBPairDefaultFees(token6D, token12D);
    }

    function testFailForInvalidBinStep() public {
        factory.createLBPair(token6D, token12D, ID_ONE, 150);
    }

    function testSetFeeParametersOnPair() public {
        ILBPair pair = createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR + 1,
            DEFAULT_FILTER_PERIOD + 1,
            DEFAULT_DECAY_PERIOD + 1,
            DEFAULT_REDUCTION_FACTOR + 1,
            DEFAULT_VARIABLE_FEE_CONTROL + 1,
            DEFAULT_PROTOCOL_SHARE + 1,
            DEFAULT_MAX_ACCUMULATOR + 1
        );

        FeeHelper.FeeParameters memory feeParameters = pair.feeParameters();
        assertEq(feeParameters.accumulator, 0);
        assertEq(feeParameters.time, 0);
        assertEq(feeParameters.binStep, DEFAULT_BIN_STEP);
        assertEq(feeParameters.baseFactor, DEFAULT_BASE_FACTOR + 1);
        assertEq(feeParameters.filterPeriod, DEFAULT_FILTER_PERIOD + 1);
        assertEq(feeParameters.decayPeriod, DEFAULT_DECAY_PERIOD + 1);
        assertEq(feeParameters.reductionFactor, DEFAULT_REDUCTION_FACTOR + 1);
        assertEq(feeParameters.variableFeeControl, DEFAULT_VARIABLE_FEE_CONTROL + 1);
        assertEq(feeParameters.protocolShare, DEFAULT_PROTOCOL_SHARE + 1);
        assertEq(feeParameters.maxAccumulator, DEFAULT_MAX_ACCUMULATOR + 1);
    }

    function testFailSetFeeParametersOnPairNotByOwner() public {
        createLBPairDefaultFees(token6D, token12D);

        vm.prank(ALICE);
        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_ACCUMULATOR
        );
    }

    function testFailForInvalidFilterPeriod() public {
        createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_ACCUMULATOR
        );
    }

    function testFailForInvalidBaseFactor() public {
        createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            100 + 1,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_ACCUMULATOR
        );
    }

    function testFailForInvalidProtocolShare() public {
        createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            25 + 1,
            DEFAULT_MAX_ACCUMULATOR
        );
    }

    function testFailForInvalidBaseFee() public {
        createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            0,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_ACCUMULATOR
        );
    }

    function testFailForInvalidMaxAccumulator() public {
        createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            1_777_638 + 1
        );
    }
}
