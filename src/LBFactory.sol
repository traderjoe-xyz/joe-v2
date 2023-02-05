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
/// Unless the `_isPresetOpen` is `true`, only the owner of the factory can create pairs.
contract LBFactory is PendingOwnable, ILBFactory {
    using SafeCast for uint256;
    using Encoded for bytes32;
    using PairParameterHelper for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 private constant _MIN_BIN_STEP = 1; // 0.01%
    uint256 private constant _MAX_BIN_STEP = 200; // 1%, can't be greater than 247 for indexing reasons

    uint256 private constant _MAX_FEE = 0.1e18; // 10%
    uint256 private constant _MAX_PROTOCOL_SHARE = 2_500; // 25%
    address private _feeRecipient;
    uint256 private _flashLoanFee;

    address private _lbPairImplementation;

    ILBPair[] private _allLBPairs;

    /// @dev Mapping from a (tokenA, tokenB, binStep) to a LBPair. The tokens are ordered to save gas, but they can be
    /// in the reverse order in the actual pair. Always query one of the 2 tokens of the pair to assert the order of the 2 tokens
    mapping(IERC20 => mapping(IERC20 => mapping(uint256 => LBPairInformation))) private _lbPairsInfo;

    /// @dev Whether a preset was set or not, if the bit at `index` is 1, it means that the binStep `index` was set
    /// The max binStep set is 247. We use this method instead of an array to keep it ordered and to reduce gas
    bytes32 private _availablePresets;

    bytes32 private _openPresets;

    // The parameters presets
    mapping(uint256 => bytes32) private _presets;

    EnumerableSet.AddressSet private _quoteAssetWhitelist;

    /// @dev Whether a LBPair was created with a bin step, if the bit at `index` is 1, it means that the LBPair with binStep `index` exists
    /// The max binStep set is 247. We use this method instead of an array to keep it ordered and to reduce gas
    mapping(IERC20 => mapping(IERC20 => bytes32)) private _availableLBPairBinSteps;

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

    function getFlashLoanFee() external view returns (uint256 flashloanFee) {
        return _flashLoanFee;
    }

    function getLBPairImplementation() external view returns (address LBPairImplementation) {
        return _lbPairImplementation;
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

    /// @notice Returns the LBPairInformation if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param tokenA The address of the first token of the pair
    /// @param tokenB The address of the second token of the pair
    /// @param binStep The bin step of the LBPair
    /// @return The LBPairInformation
    function getLBPairInformation(IERC20 tokenA, IERC20 tokenB, uint256 binStep)
        external
        view
        returns (LBPairInformation memory)
    {
        return _getLBPairInformation(tokenA, tokenB, binStep);
    }

    /// @notice View function to return the different parameters of the preset
    /// @param binStep The bin step of the preset
    /// @return baseFactor The base factor
    /// @return filterPeriod The filter period of the preset
    /// @return decayPeriod The decay period of the preset
    /// @return reductionFactor The reduction factor of the preset
    /// @return variableFeeControl The variable fee control of the preset
    /// @return protocolShare The protocol share of the preset
    /// @return maxVolatilityAccumulator The max volatility accumulator of the preset
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
            uint256 maxVolatilityAccumulator
        )
    {
        bytes32 preset = _presets[binStep];
        if (preset == bytes32(0)) revert LBFactory__BinStepHasNoPreset(binStep);

        baseFactor = preset.getBaseFactor();
        filterPeriod = preset.getFilterPeriod();
        decayPeriod = preset.getDecayPeriod();
        reductionFactor = preset.getReductionFactor();
        variableFeeControl = preset.getVariableFeeControl();
        protocolShare = preset.getProtocolShare();
        maxVolatilityAccumulator = preset.getMaxVolatilityAccumulator();
    }

    function getIsPresetOpen(uint8 binStep) external view returns (bool) {
        bytes32 openPresets = _openPresets;

        return _isPresetOpen(openPresets, binStep);
    }

    /// @notice View function to return the list of available binStep with a preset
    /// @return presetsBinStep The list of binStep
    function getAllBinSteps() external view override returns (uint256[] memory presetsBinStep) {
        unchecked {
            bytes32 avPresets = _availablePresets;
            uint256 nbPresets = avPresets.decodeUint8(248);

            if (nbPresets > 0) {
                presetsBinStep = new uint256[](nbPresets);

                uint256 index;
                for (uint256 i = _MIN_BIN_STEP; i <= _MAX_BIN_STEP; ++i) {
                    if (avPresets.decodeUint1(i) == 1) {
                        presetsBinStep[index] = i;
                        if (++index == nbPresets) break;
                    }
                }
            }
        }
    }

    /// @notice View function to return all the LBPair of a pair of tokens
    /// @param tokenX The first token of the pair
    /// @param tokenY The second token of the pair
    /// @return lbPairsAvailable The list of available LBPairs
    function getAllLBPairs(IERC20 tokenX, IERC20 tokenY)
        external
        view
        override
        returns (LBPairInformation[] memory lbPairsAvailable)
    {
        unchecked {
            (IERC20 tokenA, IERC20 tokenB) = _sortTokens(tokenX, tokenY);

            bytes32 avLBPairBinSteps = _availableLBPairBinSteps[tokenA][tokenB];
            uint256 nbAvailable = avLBPairBinSteps.decodeUint8(248);

            if (nbAvailable > 0) {
                lbPairsAvailable = new LBPairInformation[](nbAvailable);

                uint256 index;
                for (uint256 i = _MIN_BIN_STEP; i <= _MAX_BIN_STEP; ++i) {
                    if (avLBPairBinSteps.decodeUint1(i) == 1) {
                        LBPairInformation memory pairInformation = _lbPairsInfo[tokenA][tokenB][i];

                        lbPairsAvailable[index] = LBPairInformation({
                            binStep: i.safe8(),
                            LBPair: pairInformation.LBPair,
                            createdByOwner: pairInformation.createdByOwner,
                            ignoredForRouting: pairInformation.ignoredForRouting
                        });
                        if (++index == nbAvailable) break;
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

        address oldLBPairImplementation = _lbPairImplementation;
        if (oldLBPairImplementation == newLBPairImplementation) {
            revert LBFactory__SameImplementation(newLBPairImplementation);
        }

        _lbPairImplementation = newLBPairImplementation;

        emit LBPairImplementationSet(oldLBPairImplementation, newLBPairImplementation);
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
        if (!_isPresetOpen(_openPresets, binStep) && msg.sender != owner()) {
            revert LBFactory__FunctionIsLockedForUsers(msg.sender, binStep);
        }

        address implementation = _lbPairImplementation;

        if (implementation == address(0)) revert LBFactory__ImplementationNotSet();

        if (!_quoteAssetWhitelist.contains(address(tokenY))) revert LBFactory__QuoteAssetNotWhitelisted(tokenY);

        if (tokenX == tokenY) revert LBFactory__IdenticalAddresses(tokenX);

        // safety check, making sure that the price can be calculated
        PriceHelper.getPriceFromId(activeId, binStep);

        // We sort token for storage efficiency, only one input needs to be stored because they are sorted
        (IERC20 tokenA, IERC20 tokenB) = _sortTokens(tokenX, tokenY);
        // single check is sufficient
        if (address(tokenA) == address(0)) revert LBFactory__AddressZero();
        if (address(_lbPairsInfo[tokenA][tokenB][binStep].LBPair) != address(0)) {
            revert LBFactory__LBPairAlreadyExists(tokenX, tokenY, binStep);
        }

        // We remove the bits that are not part of the feeParameters
        {
            bytes32 salt = keccak256(abi.encode(tokenA, tokenB, binStep));
            pair = ILBPair(
                ImmutableClone.cloneDeterministic(implementation, abi.encodePacked(tokenX, tokenY, binStep), salt)
            );
        }

        {
            bytes32 preset = _presets[binStep];

            if (preset == bytes32(0)) revert LBFactory__BinStepHasNoPreset(binStep);

            pair.initialize(
                preset.getBaseFactor(),
                preset.getFilterPeriod(),
                preset.getDecayPeriod(),
                preset.getReductionFactor(),
                preset.getVariableFeeControl(),
                preset.getProtocolShare(),
                preset.getMaxVolatilityAccumulator(),
                activeId
            );
        }

        _lbPairsInfo[tokenA][tokenB][binStep] = LBPairInformation({
            binStep: binStep,
            LBPair: pair,
            createdByOwner: msg.sender == owner(),
            ignoredForRouting: false
        });

        _allLBPairs.push(pair);

        {
            bytes32 avLBPairBinSteps = _availableLBPairBinSteps[tokenA][tokenB];
            // We add a 1 at bit `binStep` as this binStep is now set
            avLBPairBinSteps = avLBPairBinSteps.set(1, 1, binStep);

            // Increase the number of lb pairs by 1
            avLBPairBinSteps = bytes32(uint256(avLBPairBinSteps) + (1 << 248));

            // Save the changes
            _availableLBPairBinSteps[tokenA][tokenB] = avLBPairBinSteps;
        }

        emit LBPairCreated(tokenX, tokenY, binStep, pair, _allLBPairs.length - 1);
    }

    /// @notice Function to set whether the pair is ignored or not for routing, it will make the pair unusable by the router
    /// @param tokenX The address of the first token of the pair
    /// @param tokenY The address of the second token of the pair
    /// @param binStep The bin step in basis point of the pair
    /// @param ignored Whether to ignore (true) or not (false) the pair for routing
    function setLBPairIgnored(IERC20 tokenX, IERC20 tokenY, uint256 binStep, bool ignored)
        external
        override
        onlyOwner
    {
        (IERC20 tokenA, IERC20 tokenB) = _sortTokens(tokenX, tokenY);

        LBPairInformation memory pairInformation = _lbPairsInfo[tokenA][tokenB][binStep];
        if (address(pairInformation.LBPair) == address(0)) revert LBFactory__AddressZero();

        if (pairInformation.ignoredForRouting == ignored) revert LBFactory__LBPairIgnoredIsAlreadyInTheSameState();

        _lbPairsInfo[tokenA][tokenB][binStep].ignoredForRouting = ignored;

        emit LBPairIgnoredStateChanged(pairInformation.LBPair, ignored);
    }

    /// @notice Sets the preset parameters of a bin step
    /// @param binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param decayPeriod The period where the accumulator value is halved
    /// @param reductionFactor The reduction factor, used to calculate the reduction of the accumulator
    /// @param variableFeeControl The variable fee control, used to control the variable fee, can be 0 to disable it
    /// @param protocolShare The share of the fees received by the protocol
    /// @param maxVolatilityAccumulator The max value of the volatility accumulator
    function setPreset(
        uint8 binStep,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator
    ) external override onlyOwner {
        bytes32 packedFeeParameters = _getPackedFeeParameters(
            binStep,
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulator
        );

        bytes32 preset = bytes32((uint256(packedFeeParameters)));

        _presets[binStep] = preset;

        bytes32 avPresets = _availablePresets;
        if (avPresets.decodeUint1(binStep) == 0) {
            // We add a 1 at bit `binStep` as this binStep is now set
            avPresets = avPresets.set(1, 1, binStep);

            // Increase the number of preset by 1
            avPresets = bytes32(uint256(avPresets) + (1 << 248));

            // Save the changes
            _availablePresets = avPresets;
        }

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
    }

    function setOpenPreset(uint8 binStep, bool isOpen) external onlyOwner {
        bytes32 openPresets = _openPresets;
        bool isPresetOpen = _isPresetOpen(openPresets, binStep);

        if (isOpen) {
            if (isPresetOpen) revert LBFactory__SamePresetOpenState();

            // We add a 1 at bit `binStep` as this binStep is now open
            _openPresets = _openPresets.set(1, 1, binStep);
        } else {
            if (!isPresetOpen) revert LBFactory__SamePresetOpenState();

            // We remove a 1 at bit `binStep` as this binStep is now closed
            _openPresets = _openPresets.set(0, 1, binStep);
        }

        emit OpenPresetChanged(binStep, isOpen);
    }

    /// @notice Remove the preset linked to a binStep
    /// @param binStep The bin step to remove
    function removePreset(uint8 binStep) external override onlyOwner {
        if (_presets[binStep] == bytes32(0)) revert LBFactory__BinStepHasNoPreset(binStep);

        // Set the bit `binStep` to 0
        bytes32 avPresets = _availablePresets;

        avPresets = avPresets.set(0, 1, binStep);
        avPresets = bytes32(uint256(avPresets) - (1 << 248));

        // Save the changes
        _availablePresets = avPresets;
        delete _presets[binStep];

        emit PresetRemoved(binStep);
    }

    /// @notice Function to set the fee parameter of a LBPair
    /// @param tokenX The address of the first token
    /// @param tokenY The address of the second token
    /// @param binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param decayPeriod The period where the accumulator value is halved
    /// @param reductionFactor The reduction factor, used to calculate the reduction of the accumulator
    /// @param variableFeeControl The variable fee control, used to control the variable fee, can be 0 to disable it
    /// @param protocolShare The share of the fees received by the protocol
    /// @param maxVolatilityAccumulator The max value of volatility accumulator
    function setFeesParametersOnPair(
        IERC20 tokenX,
        IERC20 tokenY,
        uint8 binStep,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator
    ) external override onlyOwner {
        ILBPair lbPair = _getLBPairInformation(tokenX, tokenY, binStep).LBPair;

        if (address(lbPair) == address(0)) revert LBFactory__LBPairNotCreated(tokenX, tokenY, binStep);

        lbPair.setStaticFeeParameters(
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulator
        );

        emit FeeParametersSet(
            msg.sender,
            lbPair,
            binStep,
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulator
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
        uint256 oldFlashLoanFee = _flashLoanFee;

        if (oldFlashLoanFee == flashLoanFee) revert LBFactory__SameFlashLoanFee(flashLoanFee);
        if (flashLoanFee > _MAX_FEE) revert LBFactory__FlashLoanFeeAboveMax(flashLoanFee, _MAX_FEE);

        _flashLoanFee = flashLoanFee;
        emit FlashLoanFeeSet(oldFlashLoanFee, flashLoanFee);
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

    function _isPresetOpen(bytes32 openPresets, uint8 binStep) internal pure returns (bool) {
        return openPresets.decodeUint1(binStep) == 1;
    }

    /// @notice Internal function to set the recipient of the fee
    /// @param feeRecipient The address of the recipient
    function _setFeeRecipient(address feeRecipient) internal {
        if (feeRecipient == address(0)) revert LBFactory__AddressZero();

        address oldFeeRecipient = _feeRecipient;
        if (oldFeeRecipient == feeRecipient) revert LBFactory__SameFeeRecipient(_feeRecipient);

        _feeRecipient = feeRecipient;
        emit FeeRecipientSet(oldFeeRecipient, feeRecipient);
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
    /// @param maxVolatilityAccumulator The max value of volatility accumulator
    function _getPackedFeeParameters(
        uint8 binStep,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulator
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
            uint256 baseFee = (uint256(baseFactor) * binStep) * 1e10;

            // Can't overflow as the max value is `max(uint24) * (max(uint24) * max(uint16)) ** 2 < max(uint104)`
            // It returns 18 decimals as:
            // decimals(variableFeeControl * (volatilityAccumulator * binStep)**2 / 100) = 4 + (4 + 4) * 2 - 2 = 18
            uint256 prod = uint256(maxVolatilityAccumulator) * binStep;
            uint256 maxVariableFee = (prod * prod * variableFeeControl) / 100;

            if (baseFee + maxVariableFee > _MAX_FEE) {
                revert LBFactory__FeesAboveMax(baseFee + maxVariableFee, _MAX_FEE);
            }
        }

        return preset.setStaticFeeParameters(
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulator
        );
    }

    /// @notice Returns the LBPairInformation if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param tokenA The address of the first token of the pair
    /// @param tokenB The address of the second token of the pair
    /// @param binStep The bin step of the LBPair
    /// @return The LBPairInformation
    function _getLBPairInformation(IERC20 tokenA, IERC20 tokenB, uint256 binStep)
        private
        view
        returns (LBPairInformation memory)
    {
        (tokenA, tokenB) = _sortTokens(tokenA, tokenB);
        return _lbPairsInfo[tokenA][tokenB][binStep];
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
