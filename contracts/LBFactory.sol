// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./LBPair.sol";
import "./LBFactoryHelper.sol";
import "./interfaces/ILBFactory.sol";
import "./libraries/MathS40x36.sol";
import "./libraries/PendingOwnable.sol";

error LBFactory__IdenticalAddresses(IERC20 token);
error LBFactory__ZeroAddress();
error LBFactory__LBPairAlreadyExists(IERC20 token0, IERC20 token1);
error LBFactory__DecreasingPeriods(uint16 filterPeriod, uint16 decayPeriod);
error LBFactory__BaseFactorExceedsBP(uint16 baseFactor, uint256 maxBP);
error LBFactory__BaseFeesBelowMin(uint256 baseFees, uint256 minBaseFees);
error LBFactory__FeesAboveMax(uint256 fees, uint256 maxFees);
error LBFactory__BinStepRequirementsBreached(
    uint256 lowerBound,
    uint16 binStep,
    uint256 higherBound
);
error LBFactory___ProtocolShareRequirementsBreached(
    uint256 lowerBound,
    uint16 protocolShare,
    uint256 higherBound
);
error LBFactory__FunctionIsLockedForUsers(address user);

contract LBFactory is PendingOwnable, ILBFactory {
    using MathS40x36 for int256;

    uint256 public constant override MAX_BASIS_POINT = 10_000; // 100%

    uint256 public constant override MIN_FEE = 1; // 0.01%
    uint256 public constant override MAX_FEE = 1_000; // 10%

    uint256 public constant override MIN_BIN_STEP = 1; // 0.0001
    uint256 public constant override MAX_BIN_STEP = 100; // 0.01

    uint256 public constant override MIN_PROTOCOL_SHARE = 1_000; // 10%
    uint256 public constant override MAX_PROTOCOL_SHARE = 5_000; // 50%

    ILBFactoryHelper public immutable override factoryHelper;

    address public override feeRecipient;

    /// @notice Whether the createLBPair function is unlocked and can be called by anyone or only by owner
    bool public override unlocked;

    ILBPair[] public override allLBPairs;
    mapping(IERC20 => mapping(IERC20 => ILBPair)) private _LBPair;

    event PairCreated(
        IERC20 indexed _token0,
        IERC20 indexed _token1,
        ILBPair pair,
        uint256 pid
    );

    event FeeRecipientChanged(address oldRecipient, address newRecipient);

    modifier onlyOwnerIfLocked() {
        if (!unlocked && msg.sender != owner())
            revert LBFactory__FunctionIsLockedForUsers(msg.sender);
        _;
    }

    /// @notice Constructor
    /// @param _feeRecipient The address of the fee recipient
    constructor(address _feeRecipient) {
        factoryHelper = ILBFactoryHelper(address(new LBFactoryHelper()));
        _setFeeRecipient(_feeRecipient);
    }

    /// @notice View function to return the number of LBPairs created
    /// @return The number of pair
    function allPairsLength() external view override returns (uint256) {
        return allLBPairs.length;
    }

    /// @notice Returns the address of the pair if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param _token0 The address of the first token
    /// @param _token1 The address of the second token
    /// @return pair The address of the pair
    function getLBPair(IERC20 _token0, IERC20 _token1)
        external
        view
        override
        returns (ILBPair)
    {
        return _LBPair[_token0][_token1];
    }

    /// @notice Create a liquidity bin pair for _token0 and _token1
    /// @param _token0 The address of the first token
    /// @param _token1 The address of the second token
    /// @param _maxAccumulator The max value of the accumulator
    /// @param _filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param _decayPeriod The period where the accumulator value is halved
    /// @param _binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param _baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param _protocolShare The share of the fees received by the protocol
    /// @return pair The address of the newly created pair
    function createLBPair(
        IERC20 _token0,
        IERC20 _token1,
        uint176 _maxAccumulator,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint16 _binStep,
        uint16 _baseFactor,
        uint16 _protocolShare
    ) external override onlyOwnerIfLocked returns (ILBPair pair) {
        if (_token0 == _token1) revert LBFactory__IdenticalAddresses(_token0);
        if (address(_token0) == address(0) || address(_token1) == address(0))
            revert LBFactory__ZeroAddress();
        // single check is sufficient
        if (address(_LBPair[_token0][_token1]) != address(0))
            revert LBFactory__LBPairAlreadyExists(_token0, _token1);

        bytes32 _packedFeeParameters = _getPackedFeeParameters(
            _maxAccumulator,
            _filterPeriod,
            _decayPeriod,
            _binStep,
            _baseFactor,
            _protocolShare
        );

        int256 _log2Value = (MathS40x36.SCALE +
            (MathS40x36.SCALE * int256(uint256(_binStep))) /
            int256(MAX_BASIS_POINT)).log2();

        pair = factoryHelper.createLBPair(
            _token0,
            _token1,
            _log2Value,
            keccak256(abi.encode(_token0, _token1)),
            _packedFeeParameters
        );

        _LBPair[_token0][_token1] = pair;
        _LBPair[_token1][_token0] = pair;

        allLBPairs.push(pair);

        emit PairCreated(_token0, _token1, pair, allLBPairs.length - 1);
    }

    /// @notice Function to set the recipient of the fees. This address needs to be able to receive ERC20s.
    /// @param _feeRecipient The address of the recipient
    function setFeeRecipient(address _feeRecipient)
        external
        override
        onlyOwner
    {
        _setFeeRecipient(_feeRecipient);
    }

    /// @notice Function to set the fee parameter of a pair
    /// @param _token0 The address of the first token
    /// @param _token1 The address of the second token
    /// @param _maxAccumulator The max value of the accumulator
    /// @param _filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param _decayPeriod The period where the accumulator value is halved
    /// @param _binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param _baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param _protocolShare The share of the fees received by the protocol
    function setFeeParametersOnPair(
        IERC20 _token0,
        IERC20 _token1,
        uint176 _maxAccumulator,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint16 _binStep,
        uint16 _baseFactor,
        uint16 _protocolShare
    ) external override onlyOwner {
        bytes32 _packedFeeParameters = _getPackedFeeParameters(
            _maxAccumulator,
            _filterPeriod,
            _decayPeriod,
            _binStep,
            _baseFactor,
            _protocolShare
        );

        ILBPair _lbPair = _LBPair[_token0][_token1];
        _lbPair.setFeesParameters(_packedFeeParameters);
    }

    /// @notice Internal function to set the recipient of the fees
    /// @param _feeRecipient The address of the recipient
    function _setFeeRecipient(address _feeRecipient) internal {
        if (_feeRecipient == address(0)) revert LBFactory__ZeroAddress();

        address oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientChanged(oldFeeRecipient, _feeRecipient);
    }

    /// @notice Internal function to set the fee parameter of a pair
    /// @param _maxAccumulator The max value of the accumulator
    /// @param _filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param _decayPeriod The period where the accumulator value is halved
    /// @param _binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param _baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param _protocolShare The share of the fees received by the protocol
    function _getPackedFeeParameters(
        uint176 _maxAccumulator,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint16 _binStep,
        uint16 _baseFactor,
        uint16 _protocolShare
    ) private pure returns (bytes32) {
        if (_filterPeriod >= _decayPeriod)
            revert LBFactory__DecreasingPeriods(_filterPeriod, _decayPeriod);

        if (_binStep < MIN_BIN_STEP || _binStep > MAX_BIN_STEP)
            revert LBFactory__BinStepRequirementsBreached(
                MIN_BIN_STEP,
                _binStep,
                MAX_BIN_STEP
            );

        if (_baseFactor > MAX_BASIS_POINT)
            revert LBFactory__BaseFactorExceedsBP(_binStep, MAX_BASIS_POINT);

        if (
            _protocolShare < MIN_PROTOCOL_SHARE ||
            _protocolShare > MAX_PROTOCOL_SHARE
        )
            revert LBFactory___ProtocolShareRequirementsBreached(
                MIN_PROTOCOL_SHARE,
                _protocolShare,
                MAX_PROTOCOL_SHARE
            );
        {
            uint256 _baseFee = (uint256(_baseFactor) * uint256(_binStep)) /
                MAX_BASIS_POINT;
            if (_baseFee < MIN_FEE)
                revert LBFactory__BaseFeesBelowMin(_baseFee, MIN_FEE);

            uint256 _maxVariableFee = (uint256(_maxAccumulator) *
                uint256(_binStep)) / MAX_BASIS_POINT;
            if (_baseFee + _maxVariableFee > MAX_FEE)
                revert LBFactory__FeesAboveMax(
                    _baseFee + _maxVariableFee,
                    MAX_FEE
                );
        }

        /// @dev It's very important that the sum of the sizes of those values is exactly 256 bits
        /// here, 176 + 16 + 16 + 16 + 16 + 16 = 256
        return
            bytes32(
                abi.encodePacked(
                    _protocolShare,
                    _baseFactor,
                    _binStep,
                    _decayPeriod,
                    _filterPeriod,
                    _maxAccumulator
                )
            );
    }
}
