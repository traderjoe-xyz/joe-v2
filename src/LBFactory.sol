// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

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

    uint256 public constant override MAX_FEE = 1e17; // 10%

    uint256 public constant override MIN_BIN_STEP = 1; // 0.01%
    uint256 public constant override MAX_BIN_STEP = 100; // 1%, can't be greater than 247 for indexing reasons

    uint256 public constant override MAX_PROTOCOL_SHARE = 2_500; // 25%

    ILBFactoryHelper public override factoryHelper;

    address public override feeRecipient;

    uint256 public override flashLoanFee;

    /// @notice Whether the createLBPair function is unlocked and can be called by anyone or only by owner
    bool public override unlocked;

    ILBPair[] public override allLBPairs;

    mapping(IERC20 => mapping(IERC20 => mapping(uint256 => LBPairInfo))) private _LBPairsInfo;

    // Whether a preset was set or not, if the bit at `index` is 1, it means that the binStep `index` was set
    // The max binStep set is 247. We use this method instead of an array to keep it ordered and to reduce gas
    bytes32 private _availablePresets;

    // Whether a LBPair was created with a bin step, if the bit at `index` is 1, it means that the LBPair with binStep `index` exists
    // The max binStep set is 247. We use this method instead of an array to keep it ordered and to reduce gas
    mapping(IERC20 => mapping(IERC20 => bytes32)) private _availableLBPairBinSteps;

    // The parameters presets
    mapping(uint256 => bytes32) private _presets;

    event LBPairCreated(IERC20 indexed tokenX, IERC20 indexed tokenY, ILBPair LBPair, uint256 pid);

    event FeeRecipientChanged(address oldRecipient, address newRecipient);

    event FlashLoanFeeSet(uint256 oldFlashLoanFee, uint256 newFlashLoanFee);

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
        uint256 maxVK
    );

    event FactoryLocked(bool unlocked);

    event LBPairBlacklistedStateChanged(ILBPair LBPair, bool blacklist);

    event PresetSet(
        uint256 indexed binStep,
        uint256 baseFactor,
        uint256 filterPeriod,
        uint256 decayPeriod,
        uint256 reductionFactor,
        uint256 variableFeeControl,
        uint256 protocolShare,
        uint256 maxVK,
        uint256 sampleLifetime
    );
    event PresetRemoved(uint256 binStep);

    /// @notice Constructor
    /// @param _feeRecipient The address of the fee recipient
    constructor(address _feeRecipient, uint256 _flashLoanFee) {
        _setFeeRecipient(_feeRecipient);
        _setFlashLoanFee(_flashLoanFee);
    }

    /// @notice View function to return the number of LBPairs created
    /// @return The number of LBPair
    function allPairsLength() external view override returns (uint256) {
        return allLBPairs.length;
    }

    /// @notice Returns the address of the LBPair if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param _tokenA The address of the first token of the pair
    /// @param _tokenB The address of the second token of the pair
    /// @param _binStep The bin step of the LBPair
    /// @return The LBPairInfo
    function getLBPairInfo(
        IERC20 _tokenA,
        IERC20 _tokenB,
        uint256 _binStep
    ) external view override returns (LBPairInfo memory) {
        return _getLBPairInfo(_tokenA, _tokenB, _binStep);
    }

    /// @notice View function to return the different parameters of the preset
    /// @param _binStep The bin step of the preset
    /// @return baseFactor The base factor
    /// @return filterPeriod The filter period of the preset
    /// @return decayPeriod The decay period of the preset
    /// @return reductionFactor The reduction factor of the preset
    /// @return variableFeeControl The variable fee control of the preset
    /// @return protocolShare The protocol share of the preset
    /// @return maxVK The max VK of the preset
    /// @return sampleLifetime The sample lifetime of the preset
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
            uint256 maxVK,
            uint256 sampleLifetime
        )
    {
        bytes32 _preset = _presets[_binStep];
        if (_preset == bytes32(0)) revert LBFactory__BinStepHasNoPreset(_binStep);

        uint256 _shift;

        // Safety check
        assert(_binStep == _preset.decode(type(uint16).max, _shift));

        baseFactor = _preset.decode(type(uint16).max, _shift += 16);
        filterPeriod = _preset.decode(type(uint16).max, _shift += 16);
        decayPeriod = _preset.decode(type(uint16).max, _shift += 16);
        reductionFactor = _preset.decode(type(uint16).max, _shift += 16);
        variableFeeControl = _preset.decode(type(uint24).max, _shift += 16);
        protocolShare = _preset.decode(type(uint16).max, _shift += 24);
        maxVK = _preset.decode(type(uint24).max, _shift += 16);

        sampleLifetime = _preset.decode(type(uint16).max, 240);
    }

    /// @notice View function to return the list of available binStep with a preset
    /// @return presetsBinStep The list of binStep
    function getAvailablePresetsBinStep() external view override returns (uint256[] memory presetsBinStep) {
        unchecked {
            bytes32 _avPresets = _availablePresets;
            uint256 _nbPresets = _avPresets.decode(type(uint8).max, 248);

            presetsBinStep = new uint256[](_nbPresets);

            uint256 _index;
            for (uint256 i = MIN_BIN_STEP; i <= MAX_BIN_STEP; ++i) {
                if (_avPresets.decode(1, i) == 1) {
                    presetsBinStep[_index] = i;
                    if (++_index == _nbPresets) break;
                }
            }
        }
    }

    /// @notice View function to return the list of available binStep with a preset
    /// @param _tokenX The first token of the pair
    /// @param _tokenY The second token of the pair
    /// @return LBPairsAvailable The list of available LBPairs
    function getAvailableLBPairsBinStep(IERC20 _tokenX, IERC20 _tokenY)
        external
        view
        override
        returns (LBPairAvailable[] memory LBPairsAvailable)
    {
        unchecked {
            (_tokenX, _tokenY) = _sortTokens(_tokenX, _tokenY);
            bytes32 _avLBPairBinSteps = _availableLBPairBinSteps[_tokenX][_tokenY];
            uint256 _nbAvailable = _avLBPairBinSteps.decode(type(uint8).max, 248);

            LBPairsAvailable = new LBPairAvailable[](_nbAvailable);

            uint256 _index;
            for (uint256 i = MIN_BIN_STEP; i <= MAX_BIN_STEP; ++i) {
                if (_avLBPairBinSteps.decode(1, i) == 1) {
                    LBPairInfo memory _LBPairInfo = _LBPairsInfo[_tokenX][_tokenY][i];

                    LBPairsAvailable[_index] = LBPairAvailable({
                        binStep: i,
                        LBPair: _LBPairInfo.LBPair,
                        createdByOwner: _LBPairInfo.createdByOwner,
                        isBlacklisted: _LBPairInfo.isBlacklisted
                    });
                    if (++_index == _nbAvailable) break;
                }
            }
        }
    }

    /// @notice Set the factory helper address
    /// @dev Needs to be called by the factory helper
    function setFactoryHelper() external override {
        if (address(factoryHelper) != address(0)) revert LBFactory__FactoryHelperAlreadyInitialized();
        factoryHelper = ILBFactoryHelper(msg.sender);
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
    ) external override returns (ILBPair _LBPair) {
        address _owner = owner();
        if (!unlocked && msg.sender != _owner) revert LBFactory__FunctionIsLockedForUsers(msg.sender);

        if (_tokenX == _tokenY) revert LBFactory__IdenticalAddresses(_tokenX);
        if (address(_tokenX) == address(0) || address(_tokenY) == address(0)) revert LBFactory__ZeroAddress();
        (IERC20 _tokenA, IERC20 _tokenB) = _sortTokens(_tokenX, _tokenY);
        // single check is sufficient
        if (address(_LBPairsInfo[_tokenA][_tokenB][_binStep].LBPair) != address(0))
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

        _LBPair.increaseOracleLength(2);

        _LBPairsInfo[_tokenA][_tokenB][_binStep] = LBPairInfo({
            LBPair: _LBPair,
            createdByOwner: msg.sender == _owner,
            isBlacklisted: false
        });

        allLBPairs.push(_LBPair);

        {
            bytes32 _avLBPairBinSteps = _availableLBPairBinSteps[_tokenA][_tokenB];
            // We add a 1 at bit `_binStep` as this binStep is now set
            _avLBPairBinSteps = bytes32(uint256(_avLBPairBinSteps) | (1 << _binStep));

            // Increase the number of lb pairs by 1
            _avLBPairBinSteps = bytes32(uint256(_avLBPairBinSteps) + (1 << 248));

            // Save the changes
            _availableLBPairBinSteps[_tokenA][_tokenB] = _avLBPairBinSteps;
        }

        emit LBPairCreated(_tokenX, _tokenY, _LBPair, allLBPairs.length - 1);
    }

    /// @notice Function to set the blacklist state of a pair, it will make the pair unusable by the router
    /// @param _tokenX The address of the first token of the pair
    /// @param _tokenY The address of the second token of the pair
    /// @param _binStep The bin step in basis point of the pair
    /// @param _blacklisted Whether to blacklist (true) or not (false) the pair
    function setLBPairBlacklist(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _binStep,
        bool _blacklisted
    ) external override onlyOwner {
        (_tokenX, _tokenY) = _sortTokens(_tokenX, _tokenY);
        LBPairInfo memory _LBPairInfo = _LBPairsInfo[_tokenX][_tokenY][_binStep];
        if (_LBPairInfo.isBlacklisted == _blacklisted) revert LBFactory__LBPairBlacklistIsAlreadyInTheSameState();

        _LBPairsInfo[_tokenX][_tokenY][_binStep].isBlacklisted = _blacklisted;

        emit LBPairBlacklistedStateChanged(_LBPairInfo.LBPair, _blacklisted);
    }

    /// @notice Sets the preset parameters of a bin step
    /// @param _binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param _baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param _filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param _decayPeriod The period where the accumulator value is halved
    /// @param _reductionFactor The reduction factor, used to calculate the reduction of the accumulator
    /// @param _variableFeeControl The variable fee control, used to control the variable fee, can be 0 to disable them
    /// @param _protocolShare The share of the fees received by the protocol
    /// @param _maxVK The max value of VK
    /// @param _sampleLifetime The lifetime of an oracle's sample
    function setPreset(
        uint16 _binStep,
        uint16 _baseFactor,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint16 _reductionFactor,
        uint24 _variableFeeControl,
        uint16 _protocolShare,
        uint24 _maxVK,
        uint16 _sampleLifetime
    ) external override onlyOwner {
        bytes32 _packedFeeParameters = _getPackedFeeParameters(
            _binStep,
            _baseFactor,
            _filterPeriod,
            _decayPeriod,
            _reductionFactor,
            _variableFeeControl,
            _protocolShare,
            _maxVK
        );

        // The last 16 bits are reserved for sampleLifetime
        bytes32 _preset = bytes32(
            (uint256(_packedFeeParameters) & type(uint240).max) | (uint256(_sampleLifetime) << 240)
        );

        _presets[_binStep] = _preset;

        bytes32 _avPresets = _availablePresets;
        if (_avPresets.decode(1, _binStep) == 0) {
            // We add a 1 at bit `_binStep` as this binStep is now set
            _avPresets = bytes32(uint256(_avPresets) | (1 << _binStep));

            // Increase the number of preset by 1
            _avPresets = bytes32(uint256(_avPresets) + (1 << 248));

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
            _maxVK,
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
    /// @param _maxVK The max value of VK
    function setFeesParametersOnPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint16 _binStep,
        uint16 _baseFactor,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint16 _reductionFactor,
        uint24 _variableFeeControl,
        uint16 _protocolShare,
        uint24 _maxVK
    ) external override onlyOwner {
        ILBPair _LBPair = _getLBPairInfo(_tokenX, _tokenY, _binStep).LBPair;

        bytes32 _packedFeeParameters = _getPackedFeeParameters(
            _binStep,
            _baseFactor,
            _filterPeriod,
            _decayPeriod,
            _reductionFactor,
            _variableFeeControl,
            _protocolShare,
            _maxVK
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
            _maxVK
        );
    }

    /// @notice Function to set the recipient of the fees. This address needs to be able to receive ERC20s
    /// @param _feeRecipient The address of the recipient
    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        _setFeeRecipient(_feeRecipient);
    }

    /// @notice Function to set the flash loan fee
    /// @param _flashLoanFee The value of the fee for flash loan
    function setFlashLoanFee(uint256 _flashLoanFee) external override onlyOwner {
        _setFlashLoanFee(_flashLoanFee);
    }

    /// @notice Function to lock the Factory and prevent anyone but the owner to create pairs.
    /// @param _locked The new lock state
    function setFactoryLocked(bool _locked) external override onlyOwner {
        if (unlocked == !_locked) revert LBFactory__FactoryLockIsAlreadyInTheSameState();
        unlocked = !_locked;
        emit FactoryLocked(_locked);
    }

    /// @notice Internal function to set the recipient of the fee
    /// @param _feeRecipient The address of the recipient
    function _setFeeRecipient(address _feeRecipient) internal {
        if (_feeRecipient == address(0)) revert LBFactory__ZeroAddress();

        address _oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientChanged(_oldFeeRecipient, _feeRecipient);
    }

    function forceDecay(ILBPair _LBPair) external override onlyOwner {
        _LBPair.forceDecay();
    }

    /// @notice Internal function to set the fee for flash loan
    /// @param _flashLoanFee The fee value for flash loan
    function _setFlashLoanFee(uint256 _flashLoanFee) internal {
        uint256 _oldFlashLoanFee = flashLoanFee;
        flashLoanFee = _flashLoanFee;
        emit FlashLoanFeeSet(_oldFlashLoanFee, _flashLoanFee);
    }

    /// @notice Internal function to set the fee parameter of a LBPair
    /// @param _binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param _baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param _filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param _decayPeriod The period where the accumulator value is halved
    /// @param _reductionFactor The reduction factor, used to calculate the reduction of the accumulator
    /// @param _variableFeeControl The variable fee control, used to control the variable fee, can be 0 to disable them
    /// @param _protocolShare The share of the fees received by the protocol
    /// @param _maxVK The max value of VK
    function _getPackedFeeParameters(
        uint16 _binStep,
        uint16 _baseFactor,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint16 _reductionFactor,
        uint24 _variableFeeControl,
        uint16 _protocolShare,
        uint24 _maxVK
    ) private pure returns (bytes32) {
        if (_binStep < MIN_BIN_STEP || _binStep > MAX_BIN_STEP)
            revert LBFactory__BinStepRequirementsBreached(MIN_BIN_STEP, _binStep, MAX_BIN_STEP);

        if (_baseFactor > Constants.BASIS_POINT_MAX)
            revert LBFactory__BaseFactorOverflows(_baseFactor, Constants.BASIS_POINT_MAX);

        if (_filterPeriod >= _decayPeriod) revert LBFactory__DecreasingPeriods(_filterPeriod, _decayPeriod);

        if (_reductionFactor > Constants.BASIS_POINT_MAX)
            revert LBFactory__ReductionFactorOverflows(_reductionFactor, Constants.BASIS_POINT_MAX);

        if (_protocolShare > MAX_PROTOCOL_SHARE)
            revert LBFactory__ProtocolShareOverflows(_protocolShare, MAX_PROTOCOL_SHARE);

        {
            uint256 _baseFee = (uint256(_baseFactor) * _binStep) * 1e10;

            // decimals((_variableFeeControl * (_maxVK * _binStep)**2)) = 4 + (4 + 4) * 2 - 2 = 18
            // The result should use 18 decimals
            uint256 _maxVariableFee = (_variableFeeControl *
                (uint256(_maxVK) * _binStep) *
                (uint256(_maxVK) * _binStep)) / 100;
            if (_baseFee + _maxVariableFee > MAX_FEE)
                revert LBFactory__FeesAboveMax(_baseFee + _maxVariableFee, MAX_FEE);
        }

        /// @dev It's very important that the sum of the sizes of those values is exactly 256 bits
        /// here, (112 + 24) + 16 + 24 + 16 + 16 + 16 + 16 + 16 = 256
        return
            bytes32(
                abi.encodePacked(
                    uint136(_maxVK), // The first 112 bits are reserved for the dynamic parameters
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

    /// @notice Returns the address of the LBPair if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param _tokenA The address of the first token of the pair
    /// @param _tokenB The address of the second token of the pair
    /// @param _binStep The bin step of the LBPair
    /// @return The LBPairInfo
    function _getLBPairInfo(
        IERC20 _tokenA,
        IERC20 _tokenB,
        uint256 _binStep
    ) private view returns (LBPairInfo memory) {
        (_tokenA, _tokenB) = _sortTokens(_tokenA, _tokenB);
        return _LBPairsInfo[_tokenA][_tokenB][_binStep];
    }

    /// @notice Private view function to sort 2 tokens in ascending order
    /// @param _tokenA The first token
    /// @param _tokenA The second token
    /// @return The sorted first token
    /// @return The sorted second token
    function _sortTokens(IERC20 _tokenA, IERC20 _tokenB) private pure returns (IERC20, IERC20) {
        if (_tokenA > _tokenB) (_tokenA, _tokenB) = (_tokenB, _tokenA);
        return (_tokenA, _tokenB);
    }
}
