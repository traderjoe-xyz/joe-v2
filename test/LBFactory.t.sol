// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinFactoryTest is TestHelper {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token12D = new ERC20MockDecimals(12);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV);
    }

    function testConstructor() public {
        assertEq(factory.feeRecipient(), DEV);
    }

    function testCreateLBPair() public {
        ILBPair pair = createLBPairDefaultFees(token6D, token12D);

        assertEq(factory.allPairsLength(), 1);
        assertEq(address(factory.getLBPair(token6D, token12D)), address(pair));

        assertEq(address(pair.factory()), address(factory));
        assertEq(address(pair.token0()), address(token6D));
        assertEq(address(pair.token1()), address(token12D));
        assertEq(pair.log2Value(), DEFAULT_LOG2_VALUE);

        FeeHelper.FeeParameters memory feeParameters = pair.feeParameters();
        assertEq(feeParameters.accumulator, 0);
        assertEq(feeParameters.time, 0);
        assertEq(feeParameters.maxAccumulator, DEFAULT_MAX_ACCUMULATOR);
        assertEq(feeParameters.filterPeriod, DEFAULT_FILTER_PERIOD);
        assertEq(feeParameters.decayPeriod, DEFAULT_DECAY_PERIOD);
        assertEq(feeParameters.binStep, DEFAULT_BIN_STEP);
        assertEq(feeParameters.baseFactor, DEFAULT_BASE_FACTOR);
        assertEq(feeParameters.protocolShare, DEFAULT_PROTOCOL_SHARE);
        assertEq(feeParameters.variableFeeDisabled, DEFAULT_VARIABLEFEE_STATE);
    }

    function testFailFactoryHelperCalledDirectly() public {
        ILBFactoryHelper factoryHelper = factory.factoryHelper();

        factoryHelper.createLBPair(
            token6D,
            token12D,
            DEFAULT_LOG2_VALUE,
            keccak256(abi.encode(token6D, token12D)),
            bytes32(
                abi.encodePacked(
                    DEFAULT_VARIABLEFEE_STATE,
                    DEFAULT_PROTOCOL_SHARE,
                    DEFAULT_BASE_FACTOR,
                    DEFAULT_BIN_STEP,
                    DEFAULT_DECAY_PERIOD,
                    DEFAULT_FILTER_PERIOD,
                    DEFAULT_MAX_ACCUMULATOR
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
        factory.createLBPair(
            token6D,
            token6D,
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_PROTOCOL_SHARE
        );
    }

    function testFailForZeroAddressPair() public {
        factory.createLBPair(
            token6D,
            IERC20(address(0)),
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_BIN_STEP,
            DEFAULT_BASE_FACTOR,
            DEFAULT_PROTOCOL_SHARE
        );
    }

    function testFailIfPairAlreadyExists() public {
        createLBPairDefaultFees(token6D, token12D);
        createLBPairDefaultFees(token6D, token12D);
    }

    function testFailForInvalidBinStep() public {
        factory.createLBPair(
            token6D,
            token12D,
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            150,
            DEFAULT_BASE_FACTOR,
            DEFAULT_PROTOCOL_SHARE
        );
    }

    function testSetFeeParametersOnPair() public {
        ILBPair pair = createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_MAX_ACCUMULATOR + 1,
            DEFAULT_FILTER_PERIOD + 1,
            DEFAULT_DECAY_PERIOD + 1,
            DEFAULT_BASE_FACTOR + 1,
            DEFAULT_PROTOCOL_SHARE + 1,
            1
        );

        FeeHelper.FeeParameters memory feeParameters = pair.feeParameters();
        assertEq(feeParameters.accumulator, 0);
        assertEq(feeParameters.time, 0);
        assertEq(feeParameters.maxAccumulator, DEFAULT_MAX_ACCUMULATOR + 1);
        assertEq(feeParameters.filterPeriod, DEFAULT_FILTER_PERIOD + 1);
        assertEq(feeParameters.decayPeriod, DEFAULT_DECAY_PERIOD + 1);
        assertEq(feeParameters.binStep, DEFAULT_BIN_STEP);
        assertEq(feeParameters.baseFactor, DEFAULT_BASE_FACTOR + 1);
        assertEq(feeParameters.protocolShare, DEFAULT_PROTOCOL_SHARE + 1);
        assertEq(feeParameters.variableFeeDisabled, 1);
    }

    function testFailSetFeeParametersOnPairNotByOwner() public {
        createLBPairDefaultFees(token6D, token12D);

        vm.prank(ALICE);
        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_VARIABLEFEE_STATE
        );
    }

    function testFailForInvalidFilterPeriod() public {
        createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_FILTER_PERIOD, // Filter and base perionds switched
            DEFAULT_BASE_FACTOR,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_VARIABLEFEE_STATE
        );
    }

    function testFailForInvalidBaseFactor() public {
        createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            10_001,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_VARIABLEFEE_STATE
        );
    }

    function testFailForInvalidProtocolShare() public {
        createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_BASE_FACTOR,
            0,
            DEFAULT_VARIABLEFEE_STATE
        );
    }

    function testFailForInvalidBaseFee() public {
        createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            0,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_VARIABLEFEE_STATE
        );
    }

    function testFailForInvalidMaxFee() public {
        createLBPairDefaultFees(token6D, token12D);

        factory.setFeeParametersOnPair(
            token6D,
            token12D,
            50_000,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            50_000,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_VARIABLEFEE_STATE
        );
    }
}
