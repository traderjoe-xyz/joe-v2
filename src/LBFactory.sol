// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {EnumerableSet} from "openzeppelin/utils/structs/EnumerableSet.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {BinHelper, PairParameterHelper} from "./libraries/BinHelper.sol";
import {Constants} from "./libraries/Constants.sol";
import {Encoded} from "./libraries/math/Encoded.sol";
import {ImmutableClone} from "./libraries/ImmutableClone.sol";
import {PendingOwnable} from "./libraries/PendingOwnable.sol";
import {PriceHelper} from "./libraries/PriceHelper.sol";
import {SafeCast} from "./libraries/math/SafeCast.sol";

import {ILBFactory} from "./interfaces/ILBFactory.sol";
import {ILBPair} from "./interfaces/ILBPair.sol";

/// @title Liquidity Book Factory
/// @author Trader Joe
/// @notice Contract used to deploy and register new LBPairs.
/// Enables setting fee parameters, flashloan fees and LBPair implementation.
/// Unless the `_creationUnlocked` is `true`, only the owner of the factory can create pairs.
contract LBFactory is PendingOwnable, ILBFactory {
    using SafeCast for uint256;
    using Encoded for bytes32;
    using PairParameterHelper for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant _MIN_BIN_STEP = 1; // 0.01%
    uint256 private constant _MAX_BIN_STEP = 100; // 1%, can't be greater than 247 for indexing reasons

    /// @notice Whether the createLBPair function is unlocked and can be called by anyone (true) or only by owner (false)
    bool private _creationUnlocked;

    uint256 private constant _MAX_FEE = 0.1e18; // 10%
    uint256 private constant _MAX_PROTOCOL_SHARE = 2_500; // 25%
    address private _feeRecipient;
    uint256 private _flashLoanFee;

    address private _LBPairImplementation;

    ILBPair[] private _allLBPairs;

    /// @dev Mapping from a (tokenA, tokenB, binStep) to a LBPair. The tokens are ordered to save gas, but they can be
    /// in the reverse order in the actual pair. Always query one of the 2 tokens of the pair to assert the order of the 2 tokens
    mapping(IERC20 => mapping(IERC20 => mapping(uint256 => LBPairInformation[]))) private _LBPairsInfos;

    /// @dev Whether a preset was set or not, if the bit at `index` is 1, it means that the binStep `index` was set
    /// The max binStep set is 247. We use this method instead of an array to keep it ordered and to reduce gas
    bytes32 private _availablePresets;

    // The parameters presets
    mapping(uint256 => bytes32) private _presets;

    EnumerableSet.AddressSet private _quoteAssetWhitelist;

    /// @dev Whether a LBPair was created with a bin step, if the bit at `index` is 1, it means that the LBPair with binStep `index` exists
    /// The max binStep set is 247. We use this method instead of an array to keep it ordered and to reduce gas
    mapping(IERC20 => mapping(IERC20 => bytes32)) private _availableLBPairBinSteps;

    uint256 private constant _REVISION_START_INDEX = 1;

    /// @notice Constructor
    /// @param feeRecipient The address of the fee recipient
    /// @param flashLoanFee The value of the fee for flash loan
    constructor(address feeRecipient, uint256 flashLoanFee) {
        if (flashLoanFee > _MAX_FEE) revert LBFactory__FlashLoanFeeAboveMax(flashLoanFee, _MAX_FEE);

        _setFeeRecipient(feeRecipient);

        _flashLoanFee = flashLoanFee;
        emit FlashLoanFeeSet(0, flashLoanFee);
    }

    // TODO: Natspecs
    function isCreationUnlocked() external view returns (bool unlocked) {
        return _creationUnlocked;
    }

    function getMinBinStep() external pure returns (uint256 minBinStep) {
        return _MIN_BIN_STEP;
    }

    function getMaxBinStep() external pure returns (uint256 maxBinStep) {
        return _MAX_BIN_STEP;
    }

    function getFeeRecipient() external view returns (address feeRecipient) {
        return _feeRecipient;
    }

    function getMaxFee() external pure returns (uint256 maxFee) {
        return _MAX_FEE;
    }

    function getMaxProtocolShare() external pure returns (uint256 maxProtocolShare) {
        return _MAX_PROTOCOL_SHARE;
    }

    function getFlashloanFee() external view returns (uint256 flashloanFee) {
        return _flashLoanFee;
    }

    function getLBPairImplementation() external view returns (address LBPairImplementation) {
        return _LBPairImplementation;
    }

    /// @notice View function to return the number of LBPairs created
    /// @return The number of LBPair
    function getNumberOfLBPairs() external view override returns (uint256) {
        return _allLBPairs.length;
    }

    function getLBPairAtIndex(uint256 index) external view returns (ILBPair pair) {
        return _allLBPairs[index];
    }

    /// @notice View function to return the number of quote assets whitelisted
    /// @return The number of quote assets
    function getNumberOfQuoteAssets() external view override returns (uint256) {
        return _quoteAssetWhitelist.length();
    }

    /// @notice View function to return the quote asset whitelisted at index `index`
    /// @param index The index
    /// @return The address of the quoteAsset at index `index`
    function getQuoteAsset(uint256 index) external view override returns (IERC20) {
        return IERC20(_quoteAssetWhitelist.at(index));
    }

    /// @notice View function to return whether a token is a quotedAsset (true) or not (false)
    /// @param token The address of the asset
    /// @return Whether the token is a quote asset or not
    function isQuoteAsset(IERC20 token) external view override returns (bool) {
        return _quoteAssetWhitelist.contains(address(token));
    }

    /// @notice View function to return the number of revisions of a LBPair
    /// @param tokenA The address of the first token of the pair. The order doesn't matter
    /// @param tokenB The address of the second token of the pair
    /// @param binStep The bin step of the LBPair
    /// @return The number of revisions
    function getNumberOfRevisions(IERC20 tokenA, IERC20 tokenB, uint256 binStep)
        external
        view
        override
        returns (uint256)
    {
        (tokenA, tokenB) = _sortTokens(tokenA, tokenB);

        return _LBPairsInfos[tokenA][tokenB][binStep].length;
    }

    /// @notice Returns the LBPairInformation if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param tokenA The address of the first token of the pair
    /// @param tokenB The address of the second token of the pair
    /// @param binStep The bin step of the LBPair
    /// @return The LBPairInformation
    function getLBPairInformation(IERC20 tokenA, IERC20 tokenB, uint256 binStep, uint256 revision)
        external
        view
        returns (LBPairInformation memory)
    {
        return _getLBPairInformation(tokenA, tokenB, binStep, revision);
    }

    /// @notice View function to return the different parameters of the preset
    /// @param binStep The bin step of the preset
    /// @return baseFactor The base factor
    /// @return filterPeriod The filter period of the preset
    /// @return decayPeriod The decay period of the preset
    /// @return reductionFactor The reduction factor of the preset
    /// @return variableFeeControl The variable fee control of the preset
    /// @return protocolShare The protocol share of the preset
    /// @return maxVolatilityAccumulated The max volatility accumulated of the preset
    function getPreset(uint256 binStep)
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
            uint256 maxVolatilityAccumulated
        )
    {
        bytes32 _preset = _presets[binStep];
        if (_preset == bytes32(0)) revert LBFactory__BinStepHasNoPreset(binStep);

        baseFactor = _preset.getBaseFactor();
        filterPeriod = _preset.getFilterPeriod();
        decayPeriod = _preset.getDecayPeriod();
        reductionFactor = _preset.getReductionFactor();
        variableFeeControl = _preset.getVariableFeeControl();
        protocolShare = _preset.getProtocolShare();
        maxVolatilityAccumulated = _preset.getMaxVolatilityAccumulated();
    }

    /// @notice View function to return the list of available binStep with a preset
    /// @return presetsBinStep The list of binStep
    function getAllBinSteps() external view override returns (uint256[] memory presetsBinStep) {
        unchecked {
            bytes32 _avPresets = _availablePresets;
            uint256 _nbPresets = _avPresets.decode(type(uint8).max, 248);

            if (_nbPresets > 0) {
                presetsBinStep = new uint256[](_nbPresets);

                uint256 _index;
                for (uint256 i = _MIN_BIN_STEP; i <= _MAX_BIN_STEP; ++i) {
                    if (_avPresets.decode(1, i) == 1) {
                        presetsBinStep[_index] = i;
                        if (++_index == _nbPresets) break;
                    }
                }
            }
        }
    }

    /// @notice View function to return all the LBPair of a pair of tokens
    /// @param tokenX The first token of the pair
    /// @param tokenY The second token of the pair
    /// @return LBPairsAvailable The list of available LBPairs
    function getAllLBPairs(IERC20 tokenX, IERC20 tokenY)
        external
        view
        override
        returns (LBPairInformation[] memory LBPairsAvailable)
    {
        unchecked {
            (IERC20 _tokenA, IERC20 _tokenB) = _sortTokens(tokenX, tokenY);

            bytes32 _avLBPairBinSteps = _availableLBPairBinSteps[_tokenA][_tokenB];
            uint256 _nbExistingBinSteps = _avLBPairBinSteps.decode(type(uint8).max, 248);

            uint256 totalPairs;

            if (_nbExistingBinSteps > 0) {
                uint256 _index;
                // Loops a first time to know how many pairs are available
                for (uint256 i = _MIN_BIN_STEP; i <= _MAX_BIN_STEP; ++i) {
                    if (_avLBPairBinSteps.decode(1, i) == 1) {
                        totalPairs += _LBPairsInfos[_tokenA][_tokenB][i].length;

                        if (++_index == _nbExistingBinSteps) break;
                    }
                }

                LBPairsAvailable = new LBPairInformation[](totalPairs);

                _index = 0;
                // Loops a second time to fill the array
                for (uint256 i = _MIN_BIN_STEP; i <= _MAX_BIN_STEP; ++i) {
                    if (_avLBPairBinSteps.decode(1, i) == 1) {
                        uint256 revisionNumber = _LBPairsInfos[_tokenA][_tokenB][i].length;
                        for (uint256 j = 0; j < revisionNumber; ++j) {
                            LBPairInformation memory _LBPairInformation = _LBPairsInfos[_tokenA][_tokenB][i][j];

                            LBPairsAvailable[_index++] = LBPairInformation({
                                binStep: i.safe8(),
                                LBPair: _LBPairInformation.LBPair,
                                createdByOwner: _LBPairInformation.createdByOwner,
                                ignoredForRouting: _LBPairInformation.ignoredForRouting,
                                revisionIndex: _LBPairInformation.revisionIndex,
                                implementation: _LBPairInformation.implementation
                            });
                        }

                        if (_index == totalPairs) break;
                    }
                }
            }
        }
    }

    /// @notice Set the LBPair implementation address
    /// @dev Needs to be called by the owner
    /// @param newLBPairImplementation The address of the implementation
    function setLBPairImplementation(address newLBPairImplementation) external override onlyOwner {
        if (ILBPair(newLBPairImplementation).getFactory() != this) {
            revert LBFactory__LBPairSafetyCheckFailed(newLBPairImplementation);
        }

        address _oldLBPairImplementation = _LBPairImplementation;
        if (_oldLBPairImplementation == newLBPairImplementation) {
            revert LBFactory__SameImplementation(newLBPairImplementation);
        }

        _LBPairImplementation = newLBPairImplementation;

        emit LBPairImplementationSet(_oldLBPairImplementation, newLBPairImplementation);
    }

    /// @notice Create a liquidity bin LBPair for tokenX and tokenY
    /// @param tokenX The address of the first token
    /// @param tokenY The address of the second token
    /// @param activeId The active id of the pair
    /// @param binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @return pair The address of the newly created LBPair
    function createLBPair(IERC20 tokenX, IERC20 tokenY, uint24 activeId, uint8 binStep)
        external
        override
        returns (ILBPair pair)
    {
        // TODO: fix stack too deep to cache owner
        // address _owner = owner();
        if (!_creationUnlocked && msg.sender != owner()) revert LBFactory__FunctionIsLockedForUsers(msg.sender);

        address LBPairImplementation_ = _LBPairImplementation;

        if (LBPairImplementation_ == address(0)) revert LBFactory__ImplementationNotSet();

        if (!_quoteAssetWhitelist.contains(address(tokenY))) revert LBFactory__QuoteAssetNotWhitelisted(tokenY);

        if (tokenX == tokenY) revert LBFactory__IdenticalAddresses(tokenX);

        // safety check, making sure that the price can be calculated
        PriceHelper.getPriceFromId(activeId, binStep);

        // We sort token for storage efficiency, only one input needs to be stored because they are sorted
        (IERC20 _tokenA, IERC20 _tokenB) = _sortTokens(tokenX, tokenY);
        // single check is sufficient
        if (address(_tokenA) == address(0)) revert LBFactory__AddressZero();
        if (_LBPairsInfos[_tokenA][_tokenB][binStep].length != 0) {
            revert LBFactory__LBPairAlreadyExists(tokenX, tokenY, binStep);
        }

        // We remove the bits that are not part of the feeParameters
        {
            bytes32 _salt = keccak256(abi.encode(_tokenA, _tokenB, binStep, _REVISION_START_INDEX));
            pair = ILBPair(
                ImmutableClone.cloneDeterministic(
                    LBPairImplementation_, abi.encodePacked(tokenX, tokenY, binStep), _salt
                )
            );
        }

        {
            bytes32 _preset = _presets[binStep];

            if (_preset == bytes32(0)) revert LBFactory__BinStepHasNoPreset(binStep);

            pair.initialize(
                _preset.getBaseFactor(),
                _preset.getFilterPeriod(),
                _preset.getDecayPeriod(),
                _preset.getReductionFactor(),
                _preset.getVariableFeeControl(),
                _preset.getProtocolShare(),
                _preset.getMaxVolatilityAccumulated(),
                activeId
            );
        }

        _LBPairsInfos[_tokenA][_tokenB][binStep].push(
            LBPairInformation({
                binStep: binStep,
                LBPair: pair,
                createdByOwner: msg.sender == owner(),
                ignoredForRouting: false,
                revisionIndex: uint16(_REVISION_START_INDEX),
                implementation: LBPairImplementation_
            })
        );

        _allLBPairs.push(pair);

        {
            bytes32 _avLBPairBinSteps = _availableLBPairBinSteps[_tokenA][_tokenB];
            // We add a 1 at bit `binStep` as this binStep is now set
            _avLBPairBinSteps = bytes32(uint256(_avLBPairBinSteps) | (1 << binStep));

            // Increase the number of lb pairs by 1
            _avLBPairBinSteps = bytes32(uint256(_avLBPairBinSteps) + (1 << 248));

            // Save the changes
            _availableLBPairBinSteps[_tokenA][_tokenB] = _avLBPairBinSteps;
        }

        emit LBPairCreated(tokenX, tokenY, binStep, pair, _allLBPairs.length - 1);
    }

    /// @notice Function to create a new revision of a pair
    /// Restricted to the owner
    /// @param tokenX The first token of the pair
    /// @param tokenY The second token of the pair
    /// @param binStep The binStep of the pair
    /// @return pair The new LBPair
    function createLBPairRevision(IERC20 tokenX, IERC20 tokenY, uint8 binStep)
        external
        override
        onlyOwner
        returns (ILBPair pair)
    {
        (IERC20 _tokenA, IERC20 _tokenB) = _sortTokens(tokenX, tokenY);

        uint256 currentVersionNumber = _LBPairsInfos[_tokenA][_tokenB][binStep].length;
        if (currentVersionNumber == 0) revert LBFactory__LBPairDoesNotExists(tokenX, tokenY, binStep);

        address LBPairImplementation_ = _LBPairImplementation;

        // Get latest version
        LBPairInformation memory _LBPairInformation =
            _LBPairsInfos[_tokenA][_tokenB][binStep][currentVersionNumber - _REVISION_START_INDEX];

        if (_LBPairInformation.implementation == LBPairImplementation_) {
            revert LBFactory__SameImplementation(LBPairImplementation_);
        }

        ILBPair _oldLBPair = _LBPairInformation.LBPair;

        bytes32 _preset = _presets[binStep];

        bytes32 _salt = keccak256(abi.encode(_tokenA, _tokenB, binStep, ++currentVersionNumber));
        pair = ILBPair(
            ImmutableClone.cloneDeterministic(LBPairImplementation_, abi.encodePacked(tokenX, tokenY, binStep), _salt)
        );

        {
            pair.initialize(
                _preset.getBaseFactor(),
                _preset.getFilterPeriod(),
                _preset.getDecayPeriod(),
                _preset.getReductionFactor(),
                _preset.getVariableFeeControl(),
                _preset.getProtocolShare(),
                _preset.getMaxVolatilityAccumulated(),
                _oldLBPair.getActiveId()
            );

            _LBPairsInfos[_tokenA][_tokenB][binStep].push(
                LBPairInformation({
                    binStep: binStep,
                    LBPair: pair,
                    createdByOwner: true,
                    ignoredForRouting: false,
                    revisionIndex: uint16(currentVersionNumber),
                    implementation: LBPairImplementation_
                })
            );
        }

        _allLBPairs.push(pair);

        emit LBPairCreated(tokenX, tokenY, binStep, pair, _allLBPairs.length - 1);
    }

    /// @notice Function to set whether the pair is ignored or not for routing, it will make the pair unusable by the router
    /// @param tokenX The address of the first token of the pair
    /// @param tokenY The address of the second token of the pair
    /// @param binStep The bin step in basis point of the pair
    /// @param revision The revision of the pair
    /// @param ignored Whether to ignore (true) or not (false) the pair for routing
    function setLBPairIgnored(IERC20 tokenX, IERC20 tokenY, uint256 binStep, uint256 revision, bool ignored)
        external
        override
        onlyOwner
    {
        (IERC20 _tokenA, IERC20 _tokenB) = _sortTokens(tokenX, tokenY);

        uint256 revisionAmount = _LBPairsInfos[_tokenA][_tokenB][binStep].length;
        if (revisionAmount == 0 || revision > revisionAmount) {
            revert LBFactory__AddressZero();
        }

        LBPairInformation memory _LBPairInformation =
            _LBPairsInfos[_tokenA][_tokenB][binStep][revision - _REVISION_START_INDEX];

        if (_LBPairInformation.ignoredForRouting == ignored) revert LBFactory__LBPairIgnoredIsAlreadyInTheSameState();

        _LBPairsInfos[_tokenA][_tokenB][binStep][revision - _REVISION_START_INDEX].ignoredForRouting = ignored;

        emit LBPairIgnoredStateChanged(_LBPairInformation.LBPair, ignored);
    }

    /// @notice Sets the preset parameters of a bin step
    /// @param binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param decayPeriod The period where the accumulator value is halved
    /// @param reductionFactor The reduction factor, used to calculate the reduction of the accumulator
    /// @param variableFeeControl The variable fee control, used to control the variable fee, can be 0 to disable it
    /// @param protocolShare The share of the fees received by the protocol
    /// @param maxVolatilityAccumulated The max value of the volatility accumulated
    function setPreset(
        uint8 binStep,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulated
    ) external override onlyOwner {
        bytes32 _packedFeeParameters = _getPackedFeeParameters(
            binStep,
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulated
        );

        bytes32 _preset = bytes32((uint256(_packedFeeParameters)));

        _presets[binStep] = _preset;

        bytes32 _avPresets = _availablePresets;
        if (_avPresets.decode(1, binStep) == 0) {
            // We add a 1 at bit `binStep` as this binStep is now set
            _avPresets = bytes32(uint256(_avPresets) | (1 << binStep));

            // Increase the number of preset by 1
            _avPresets = bytes32(uint256(_avPresets) + (1 << 248));

            // Save the changes
            _availablePresets = _avPresets;
        }

        emit PresetSet(
            binStep,
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulated
            );
    }

    /// @notice Remove the preset linked to a binStep
    /// @param binStep The bin step to remove
    function removePreset(uint8 binStep) external override onlyOwner {
        if (_presets[binStep] == bytes32(0)) revert LBFactory__BinStepHasNoPreset(binStep);

        // Set the bit `binStep` to 0
        bytes32 _avPresets = _availablePresets;

        _avPresets &= bytes32(type(uint256).max - (1 << binStep));
        _avPresets = bytes32(uint256(_avPresets) - (1 << 248));

        // Save the changes
        _availablePresets = _avPresets;
        delete _presets[binStep];

        emit PresetRemoved(binStep);
    }

    /// @notice Function to set the fee parameter of a LBPair
    /// @param tokenX The address of the first token
    /// @param tokenY The address of the second token
    /// @param binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param revision The revision of the LBPair
    /// @param baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param decayPeriod The period where the accumulator value is halved
    /// @param reductionFactor The reduction factor, used to calculate the reduction of the accumulator
    /// @param variableFeeControl The variable fee control, used to control the variable fee, can be 0 to disable it
    /// @param protocolShare The share of the fees received by the protocol
    /// @param maxVolatilityAccumulated The max value of volatility accumulated
    function setFeesParametersOnPair(
        IERC20 tokenX,
        IERC20 tokenY,
        uint8 binStep,
        uint16 revision,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulated
    ) external override onlyOwner {
        ILBPair _LBPair = _getLBPairInformation(tokenX, tokenY, binStep, revision).LBPair;

        _LBPair.setStaticFeeParameters(
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulated
        );

        emit FeeParametersSet(
            msg.sender,
            _LBPair,
            binStep,
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulated
            );
    }

    /// @notice Function to set the recipient of the fees. This address needs to be able to receive ERC20s
    /// @param feeRecipient The address of the recipient
    function setFeeRecipient(address feeRecipient) external override onlyOwner {
        _setFeeRecipient(feeRecipient);
    }

    /// @notice Function to set the flash loan fee
    /// @param flashLoanFee The value of the fee for flash loan
    function setFlashLoanFee(uint256 flashLoanFee) external override onlyOwner {
        uint256 _oldFlashLoanFee = _flashLoanFee;

        if (_oldFlashLoanFee == flashLoanFee) revert LBFactory__SameFlashLoanFee(flashLoanFee);
        if (flashLoanFee > _MAX_FEE) revert LBFactory__FlashLoanFeeAboveMax(flashLoanFee, _MAX_FEE);

        _flashLoanFee = flashLoanFee;
        emit FlashLoanFeeSet(_oldFlashLoanFee, flashLoanFee);
    }

    /// @notice Function to set the creation restriction of the Factory
    /// @param locked If the creation is restricted (true) or not (false)
    function setFactoryLockedState(bool locked) external override onlyOwner {
        if (_creationUnlocked != locked) revert LBFactory__FactoryLockIsAlreadyInTheSameState();
        _creationUnlocked = !locked;
        emit FactoryLockedStatusUpdated(locked);
    }

    /// @notice Function to add an asset to the whitelist of quote assets
    /// @param quoteAsset The quote asset (e.g: AVAX, USDC...)
    function addQuoteAsset(IERC20 quoteAsset) external override onlyOwner {
        if (!_quoteAssetWhitelist.add(address(quoteAsset))) {
            revert LBFactory__QuoteAssetAlreadyWhitelisted(quoteAsset);
        }

        emit QuoteAssetAdded(quoteAsset);
    }

    /// @notice Function to remove an asset from the whitelist of quote assets
    /// @param quoteAsset The quote asset (e.g: AVAX, USDC...)
    function removeQuoteAsset(IERC20 quoteAsset) external override onlyOwner {
        if (!_quoteAssetWhitelist.remove(address(quoteAsset))) revert LBFactory__QuoteAssetNotWhitelisted(quoteAsset);

        emit QuoteAssetRemoved(quoteAsset);
    }

    /// @notice Internal function to set the recipient of the fee
    /// @param feeRecipient The address of the recipient
    function _setFeeRecipient(address feeRecipient) internal {
        if (feeRecipient == address(0)) revert LBFactory__AddressZero();

        address _oldFeeRecipient = _feeRecipient;
        if (_oldFeeRecipient == feeRecipient) revert LBFactory__SameFeeRecipient(_feeRecipient);

        _feeRecipient = feeRecipient;
        emit FeeRecipientSet(_oldFeeRecipient, feeRecipient);
    }

    function forceDecay(ILBPair pair) external override onlyOwner {
        pair.forceDecay();
    }

    /// @notice Internal function to set the fee parameter of a LBPair
    /// @param binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param decayPeriod The period where the accumulator value is halved
    /// @param reductionFactor The reduction factor, used to calculate the reduction of the accumulator
    /// @param variableFeeControl The variable fee control, used to control the variable fee, can be 0 to disable it
    /// @param protocolShare The share of the fees received by the protocol
    /// @param maxVolatilityAccumulated The max value of volatility accumulated
    function _getPackedFeeParameters(
        uint8 binStep,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulated
    ) private pure returns (bytes32 preset) {
        if (binStep < _MIN_BIN_STEP || binStep > _MAX_BIN_STEP) {
            revert LBFactory__BinStepRequirementsBreached(_MIN_BIN_STEP, binStep, _MAX_BIN_STEP);
        }

        if (filterPeriod >= decayPeriod) revert LBFactory__DecreasingPeriods(filterPeriod, decayPeriod);

        if (reductionFactor > Constants.BASIS_POINT_MAX) {
            revert LBFactory__ReductionFactorOverflows(reductionFactor, Constants.BASIS_POINT_MAX);
        }

        if (protocolShare > _MAX_PROTOCOL_SHARE) {
            revert LBFactory__ProtocolShareOverflows(protocolShare, _MAX_PROTOCOL_SHARE);
        }

        {
            uint256 _baseFee = (uint256(baseFactor) * binStep) * 1e10;

            // Can't overflow as the max value is `max(uint24) * (max(uint24) * max(uint16)) ** 2 < max(uint104)`
            // It returns 18 decimals as:
            // decimals(variableFeeControl * (volatilityAccumulated * binStep)**2 / 100) = 4 + (4 + 4) * 2 - 2 = 18
            uint256 _prod = uint256(maxVolatilityAccumulated) * binStep;
            uint256 _maxVariableFee = (_prod * _prod * variableFeeControl) / 100;

            if (_baseFee + _maxVariableFee > _MAX_FEE) {
                revert LBFactory__FeesAboveMax(_baseFee + _maxVariableFee, _MAX_FEE);
            }
        }

        return preset.setStaticFeeParameters(
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulated
        );
    }

    /// @notice Returns the LBPairInformation if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param tokenA The address of the first token of the pair
    /// @param tokenB The address of the second token of the pair
    /// @param binStep The bin step of the LBPair
    /// @param revision The revision of the LBPair
    /// @return The LBPairInformation
    function _getLBPairInformation(IERC20 tokenA, IERC20 tokenB, uint256 binStep, uint256 revision)
        private
        view
        returns (LBPairInformation memory)
    {
        (tokenA, tokenB) = _sortTokens(tokenA, tokenB);

        if (_LBPairsInfos[tokenA][tokenB][binStep].length == 0) {
            revert LBFactory__LBPairNotCreated(tokenA, tokenB, binStep);
        }

        return _LBPairsInfos[tokenA][tokenB][binStep][revision - _REVISION_START_INDEX];
    }

    /// @notice Private view function to sort 2 tokens in ascending order
    /// @param tokenA The first token
    /// @param tokenB The second token
    /// @return The sorted first token
    /// @return The sorted second token
    function _sortTokens(IERC20 tokenA, IERC20 tokenB) private pure returns (IERC20, IERC20) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return (tokenA, tokenB);
    }
}
