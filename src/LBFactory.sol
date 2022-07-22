// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./interfaces/ILBFactory.sol";
import "./libraries/PendingOwnable.sol";
import "./libraries/Constants.sol";
import "./libraries/Decoder.sol";

error LBFactory__IdenticalAddresses(IERC20 token);
error LBFactory__ZeroAddress();
error LBFactory__FactoryHelperAlreadyInitialized();
error LBFactory__LBPairAlreadyExists(IERC20 tokenX, IERC20 tokenY, uint256 _binStep);
error LBFactory__DecreasingPeriods(uint16 filterPeriod, uint16 decayPeriod);
error LBFactory__BaseFactorOverflows(uint16 baseFactor, uint256 max);
error LBFactory__ReductionFactorOverflows(uint16 reductionFactor, uint256 max);
error LBFactory__VariableFeeControlOverflows(uint16 variableFeeControl, uint256 max);
error LBFactory__BaseFeesBelowMin(uint256 baseFees, uint256 minBaseFees);
error LBFactory__FeesAboveMax(uint256 fees, uint256 maxFees);
error LBFactory__BinStepRequirementsBreached(uint256 lowerBound, uint16 binStep, uint256 higherBound);
error LBFactory__ProtocolShareOverflows(uint16 protocolShare, uint256 max);
error LBFactory__FunctionIsLockedForUsers(address user);
error LBFactory__FactoryLockIsAlreadyInTheSameState();
error LBFactory__LBPairBlacklistIsAlreadyInTheSameState();
error LBFactory__BinStepHasNoPreset(uint256 binStep);

contract LBFactory is PendingOwnable, ILBFactory {
    using Decoder for bytes32;

    uint256 public constant override MIN_FEE = 1; // 0.01%
    uint256 public constant override MAX_FEE = 1_000; // 10%

    uint256 public constant override MIN_BIN_STEP = 1; // 0.01%
    uint256 public constant override MAX_BIN_STEP = 100; // 1%, can't be greater than 247 for indexing reasons

    uint256 public constant override MAX_PROTOCOL_SHARE = 25; // 25%

    ILBFactoryHelper public override factoryHelper;

    address public override feeRecipient;

    mapping(ILBPair => bool) public override LBPairBlacklists;

    /// @notice Whether the createLBPair function is unlocked and can be called by anyone or only by owner
    bool public override unlocked;

    ILBPair[] public override allLBPairs;

    mapping(IERC20 => mapping(IERC20 => mapping(uint256 => ILBPair))) private _LBPairs;

    // Whether an preset was set or not, if the bit at `index` is 1, it means that the binStep `index` was set
    // The max binStep set is 247. We use this method instead of an array to keep it ordered
    bytes32 private _availablePresets;

    // The parameters presets
    mapping(uint256 => bytes32) private _presets;

    event LBPairCreated(IERC20 indexed tokenX, IERC20 indexed tokenY, ILBPair LBPair, uint256 pid);

    event FeeRecipientChanged(address oldRecipient, address newRecipient);

    event FeeParametersSet(
        address sender,
        ILBPair indexed LBPair,
        uint256 binStep,
        uint256 baseFactor,
        uint256 filterPeriod,
        uint256 decayPeriod,
        uint256 reductionFactor,
        uint256 variableFeeControl,
        uint256 protocolShare,
        uint256 maxAccumulator
    );

    event FactoryLocked(bool unlocked);

    event LBPairBlacklisted(ILBPair LBPair, bool blacklist);

    event PresetSet(
        uint256 indexed binStep,
        uint256 baseFactor,
        uint256 filterPeriod,
        uint256 decayPeriod,
        uint256 reductionFactor,
        uint256 variableFeeControl,
        uint256 protocolShare,
        uint256 maxAccumulator,
        uint256 sampleLifetime
    );
    event PresetRemoved(uint256 binStep);

    modifier onlyOwnerIfLocked() {
        if (!unlocked && msg.sender != owner()) revert LBFactory__FunctionIsLockedForUsers(msg.sender);
        _;
    }

    /// @notice Constructor
    /// @param _feeRecipient The address of the fee recipient
    constructor(address _feeRecipient) {
        _setFeeRecipient(_feeRecipient);
    }

    /// @notice Set the factory helper address
    /// @dev Needs to be called by the factory helper
    function setFactoryHelper() external override {
        if (address(factoryHelper) != address(0)) revert LBFactory__FactoryHelperAlreadyInitialized();
        factoryHelper = ILBFactoryHelper(msg.sender);
    }

    /// @notice View function to return the number of LBPairs created
    /// @return The number of LBPair
    function allPairsLength() external view override returns (uint256) {
        return allLBPairs.length;
    }

    /// @notice Returns the address of the LBPair if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param _tokenX The address of the first token
    /// @param _tokenY The address of the second token
    /// @param _binStep The bin step of the LBPair
    /// @return The address of the LBPair
    function getLBPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _binStep
    ) external view override returns (ILBPair) {
        return _LBPairs[_tokenX][_tokenY][_binStep];
    }

    /// @notice Create a liquidity bin LBPair for _tokenX and _tokenY
    /// @param _tokenX The address of the first token
    /// @param _tokenY The address of the second token
    /// @param _activeId The active id of the pair
    /// @param _binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @return _LBPair The address of the newly created LBPair
    function createLBPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint24 _activeId,
        uint16 _binStep
    ) external override onlyOwnerIfLocked returns (ILBPair _LBPair) {
        if (_tokenX == _tokenY) revert LBFactory__IdenticalAddresses(_tokenX);
        if (address(_tokenX) == address(0) || address(_tokenY) == address(0)) revert LBFactory__ZeroAddress();
        // single check is sufficient
        if (address(_LBPairs[_tokenX][_tokenY][_binStep]) != address(0))
            revert LBFactory__LBPairAlreadyExists(_tokenX, _tokenY, _binStep);

        bytes32 _preset = _presets[_binStep];
        if (_preset == bytes32(0)) revert LBFactory__BinStepHasNoPreset(_binStep);

        uint256 _sampleLifetime = _preset.decode(type(uint16).max, 240);
        // We remove the bits that are not part of the feeParameters
        _preset &= bytes32(uint256(type(uint144).max));

        _LBPair = factoryHelper.createLBPair(
            _tokenX,
            _tokenY,
            keccak256(abi.encode(_tokenX, _tokenY, _binStep)),
            _activeId,
            uint16(_sampleLifetime),
            _preset
        );

        _LBPairs[_tokenX][_tokenY][_binStep] = _LBPair;
        _LBPairs[_tokenY][_tokenX][_binStep] = _LBPair;

        allLBPairs.push(_LBPair);

        emit LBPairCreated(_tokenX, _tokenY, _LBPair, allLBPairs.length - 1);
    }

    /// @notice Function to set the recipient of the fees. This address needs to be able to receive ERC20s.
    /// @param _feeRecipient The address of the recipient
    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        _setFeeRecipient(_feeRecipient);
    }

    /// @notice Function to set the recipient of the fees. This address needs to be able to receive ERC20s.
    /// @param _LBPair The address of the LBPair
    function setLBPairBlacklist(ILBPair _LBPair, bool _blacklist) external override onlyOwner {
        bool _isBlacklisted = LBPairBlacklists[_LBPair];
        if (_isBlacklisted == _blacklist) revert LBFactory__LBPairBlacklistIsAlreadyInTheSameState();

        LBPairBlacklists[_LBPair] = _blacklist;

        emit LBPairBlacklisted(_LBPair, _blacklist);
    }

    /// @notice Sets the preset parameters of a bin step
    /// @param _binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param _baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param _filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param _decayPeriod The period where the accumulator value is halved
    /// @param _reductionFactor The reduction factor, used to calculate the reduction of the accumulator
    /// @param _variableFeeControl The variable fee control, used to control the variable fee, can be 0 to disable them
    /// @param _protocolShare The share of the fees received by the protocol
    /// @param _maxAccumulator The max value of the accumulator
    /// @param _sampleLifetime The lifetime of an oracle's sample
    function setPreset(
        uint8 _binStep,
        uint8 _baseFactor,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint8 _reductionFactor,
        uint8 _variableFeeControl,
        uint8 _protocolShare,
        uint72 _maxAccumulator,
        uint8 _sampleLifetime
    ) external override onlyOwner {
        bytes32 _packedFeeParameters = _getPackedFeeParameters(
            _binStep,
            _baseFactor,
            _filterPeriod,
            _decayPeriod,
            _reductionFactor,
            _variableFeeControl,
            _protocolShare,
            _maxAccumulator
        );

        // The last 16 bits are reserved for sampleLifetime
        bytes32 _preset = bytes32(uint256(_packedFeeParameters) + (uint256(_sampleLifetime) << 240));

        _presets[_binStep] = _preset;

        bytes32 _avPresets = _availablePresets;
        if (_avPresets.decode(1, _binStep) == 0) {
            // We add a 1 at bit `_binStep` as this binStep is now set
            _avPresets = bytes32(uint256(_avPresets) & (1 << _binStep));

            // Increase the number of preset by 1
            _avPresets = bytes32(uint256(_avPresets) & (1 << 248));

            // Save the changes
            _availablePresets = _avPresets;
        }

        emit PresetSet(
            _binStep,
            _baseFactor,
            _filterPeriod,
            _decayPeriod,
            _reductionFactor,
            _variableFeeControl,
            _protocolShare,
            _maxAccumulator,
            _sampleLifetime
        );
    }

    function removePreset(uint16 _binStep) external override onlyOwner {
        if (_presets[_binStep] == bytes32(0)) revert LBFactory__BinStepHasNoPreset(_binStep);

        // Set the bit `_binStep` to 0
        bytes32 _avPresets = _availablePresets;

        _avPresets &= bytes32(type(uint256).max - (1 << _binStep));
        _avPresets = bytes32(uint256(_avPresets) - (1 << 248));

        // Save the changes
        _availablePresets = _avPresets;
        delete _presets[_binStep];

        emit PresetRemoved(_binStep);
    }

    function getPreset(uint16 _binStep)
        external
        view
        override
        returns (
            uint256 baseFactor,
            uint256 filterPeriod,
            uint256 decayPeriod,
            uint256 reductionFactor,
            uint256 variableFeeControl,
            uint256 protocolShare,
            uint256 maxAccumulator,
            uint256 sampleLifetime
        )
    {
        bytes32 _preset = _presets[_binStep];
        if (_preset == bytes32(0)) revert LBFactory__BinStepHasNoPreset(_binStep);

        baseFactor = _preset.decode(type(uint8).max, 8);
        filterPeriod = _preset.decode(type(uint16).max, 16);
        decayPeriod = _preset.decode(type(uint16).max, 32);
        reductionFactor = _preset.decode(type(uint8).max, 48);
        variableFeeControl = _preset.decode(type(uint8).max, 56);
        protocolShare = _preset.decode(type(uint8).max, 64);
        maxAccumulator = _preset.decode(type(uint72).max, 72);

        sampleLifetime = _preset.decode(type(uint16).max, 240);
    }

    function getAvailableBinSteps() external view override returns (uint256[] memory binSteps) {
        unchecked {
            bytes32 _avPresets = _availablePresets;
            uint256 _nbPresets = _avPresets.decode(type(uint8).max, 248);

            binSteps = new uint256[](_nbPresets);

            uint256 _index;
            for (uint256 i = MIN_BIN_STEP; i <= MAX_BIN_STEP; ++i) {
                if (_avPresets.decode(1, i) == 1) binSteps[_index] = i;
                if (++_index == _nbPresets) break;
            }
        }
    }

    /// @notice Function to lock the Factory and prevent anyone but the owner to create pairs.
    /// @param _locked The new lock state
    function setFactoryLocked(bool _locked) external onlyOwner {
        if (unlocked == !_locked) revert LBFactory__FactoryLockIsAlreadyInTheSameState();
        unlocked = !_locked;
        emit FactoryLocked(_locked);
    }

    /// @notice Function to set the fee parameter of a LBPair
    /// @param _tokenX The address of the first token
    /// @param _tokenY The address of the second token
    /// @param _binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param _baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param _filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param _decayPeriod The period where the accumulator value is halved
    /// @param _reductionFactor The reduction factor, used to calculate the reduction of the accumulator
    /// @param _variableFeeControl The variable fee control, used to control the variable fee, can be 0 to disable them
    /// @param _protocolShare The share of the fees received by the protocol
    /// @param _maxAccumulator The max value of the accumulator
    function setFeeParametersOnPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint8 _binStep,
        uint8 _baseFactor,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint8 _reductionFactor,
        uint8 _variableFeeControl,
        uint8 _protocolShare,
        uint72 _maxAccumulator
    ) external override onlyOwner {
        ILBPair _LBPair = _LBPairs[_tokenX][_tokenY][_binStep];

        bytes32 _packedFeeParameters = _getPackedFeeParameters(
            _binStep,
            _baseFactor,
            _filterPeriod,
            _decayPeriod,
            _reductionFactor,
            _variableFeeControl,
            _protocolShare,
            _maxAccumulator
        );

        _LBPair.setFeesParameters(_packedFeeParameters);

        emit FeeParametersSet(
            msg.sender,
            _LBPair,
            _binStep,
            _baseFactor,
            _filterPeriod,
            _decayPeriod,
            _reductionFactor,
            _variableFeeControl,
            _protocolShare,
            _maxAccumulator
        );
    }

    /// @notice Internal function to set the recipient of the fees
    /// @param _feeRecipient The address of the recipient
    function _setFeeRecipient(address _feeRecipient) internal {
        if (_feeRecipient == address(0)) revert LBFactory__ZeroAddress();

        address oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientChanged(oldFeeRecipient, _feeRecipient);
    }

    /// @notice Internal function to set the fee parameter of a LBPair
    /// @param _binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param _baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param _filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param _decayPeriod The period where the accumulator value is halved
    /// @param _reductionFactor The reduction factor, used to calculate the reduction of the accumulator
    /// @param _variableFeeControl The variable fee control, used to control the variable fee, can be 0 to disable them
    /// @param _protocolShare The share of the fees received by the protocol
    /// @param _maxAccumulator The max value of the accumulator
    function _getPackedFeeParameters(
        uint8 _binStep,
        uint8 _baseFactor,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint8 _reductionFactor,
        uint8 _variableFeeControl,
        uint8 _protocolShare,
        uint72 _maxAccumulator
    ) private pure returns (bytes32) {
        if (_binStep < MIN_BIN_STEP || _binStep > MAX_BIN_STEP)
            revert LBFactory__BinStepRequirementsBreached(MIN_BIN_STEP, _binStep, MAX_BIN_STEP);

        if (_baseFactor > Constants.HUNDRED_PERCENT)
            revert LBFactory__BaseFactorOverflows(_baseFactor, Constants.HUNDRED_PERCENT);

        if (_filterPeriod >= _decayPeriod) revert LBFactory__DecreasingPeriods(_filterPeriod, _decayPeriod);

        if (_reductionFactor > Constants.HUNDRED_PERCENT)
            revert LBFactory__ReductionFactorOverflows(_reductionFactor, Constants.HUNDRED_PERCENT);

        if (_variableFeeControl > Constants.HUNDRED_PERCENT)
            revert LBFactory__VariableFeeControlOverflows(_variableFeeControl, Constants.HUNDRED_PERCENT);

        if (_protocolShare > MAX_PROTOCOL_SHARE)
            revert LBFactory__ProtocolShareOverflows(_protocolShare, MAX_PROTOCOL_SHARE);

        {
            uint256 _baseFee = (uint256(_baseFactor) * uint256(_binStep)) / Constants.HUNDRED_PERCENT;
            if (_baseFee < MIN_FEE) revert LBFactory__BaseFeesBelowMin(_baseFee, MIN_FEE);

            // decimals((_variableFeeControl * (_maxAccumulator * _binStep)**2)) = 2 + (4 + 4) * 2 = 18
            // The result should use 4 decimals, so we divide it by 1e14
            uint256 _maxVariableFee = (_variableFeeControl * (_maxAccumulator * _binStep)**2) / 1e14;
            if (_baseFee + _maxVariableFee > MAX_FEE)
                revert LBFactory__FeesAboveMax(_baseFee + _maxVariableFee, MAX_FEE);
        }

        /// @dev It's very important that the sum of the sizes of those values is exactly 256 bits
        /// here, (112 + 72) + 8 + 8 + 8 + 16 + 16 + 8 + 8 = 256
        return
            bytes32(
                abi.encodePacked(
                    uint184(_maxAccumulator),
                    _protocolShare,
                    _variableFeeControl,
                    _reductionFactor,
                    _decayPeriod,
                    _filterPeriod,
                    _baseFactor,
                    _binStep
                )
            );
    }
}
