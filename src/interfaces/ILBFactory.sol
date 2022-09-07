// SPDX-License-Identifier: MIT

pragma solidity >=0.8.7;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./ILBPair.sol";
import "./IPendingOwnable.sol";

interface ILBFactory is IPendingOwnable {
    /// @dev Structure to store LBPair information, such as:
    /// - LBPair: The address of the LBPair
    /// - createdByOwner: Whether the pair was created by the owner of the factory
    /// - isBlacklisted: Whether the pair is blacklisted or not. A blacklisted pair will not be usable within the router
    struct LBPairInfo {
        ILBPair LBPair;
        bool createdByOwner;
        bool isBlacklisted;
    }

    /// @dev Structure to store the LBPair available, such as:
    /// - binStep: The bin step of the LBPair
    /// - LBPair: The address of the LBPair
    /// - createdByOwner: Whether the pair was created by the owner of the factory
    /// - isBlacklisted: Whether the pair is blacklisted or not. A blacklisted pair will not be usable within the router
    struct LBPairAvailable {
        uint256 binStep;
        ILBPair LBPair;
        bool createdByOwner;
        bool isBlacklisted;
    }

    event LBPairCreated(
        IERC20 indexed tokenX,
        IERC20 indexed tokenY,
        uint256 indexed binStep,
        ILBPair LBPair,
        uint256 pid
    );

    event FeeRecipientSet(address oldRecipient, address newRecipient);

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
        uint256 maxVolatilityAccumulated
    );

    event FactoryLocked(bool unlocked);

    event LBPairImplementationSet(ILBPair oldLBPairImplementation, ILBPair LBPairImplementation);

    event LBPairBlacklistedStateChanged(ILBPair LBPair, bool blacklist);

    event PresetSet(
        uint256 indexed binStep,
        uint256 baseFactor,
        uint256 filterPeriod,
        uint256 decayPeriod,
        uint256 reductionFactor,
        uint256 variableFeeControl,
        uint256 protocolShare,
        uint256 maxVolatilityAccumulated,
        uint256 sampleLifetime
    );

    event PresetRemoved(uint256 indexed binStep);

    function MAX_FEE() external pure returns (uint256);

    function MIN_BIN_STEP() external pure returns (uint256);

    function MAX_BIN_STEP() external pure returns (uint256);

    function MAX_PROTOCOL_SHARE() external pure returns (uint256);

    function LBPairImplementation() external view returns (ILBPair);

    function feeRecipient() external view returns (address);

    function flashLoanFee() external view returns (uint256);

    function unlocked() external view returns (bool);

    function allLBPairs(uint256 id) external returns (ILBPair);

    function allPairsLength() external view returns (uint256);

    function getLBPairInfo(
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 binStep
    ) external view returns (LBPairInfo memory);

    function getPreset(uint16 binStep)
        external
        view
        returns (
            uint256 baseFactor,
            uint256 filterPeriod,
            uint256 decayPeriod,
            uint256 reductionFactor,
            uint256 variableFeeControl,
            uint256 protocolShare,
            uint256 maxAccumulator,
            uint256 sampleLifetime
        );

    function getAvailablePresetsBinStep() external view returns (uint256[] memory presetsBinStep);

    function getAvailableLBPairsBinStep(IERC20 tokenX, IERC20 tokenY)
        external
        view
        returns (LBPairAvailable[] memory LBPairsBinStep);

    function setLBPairImplementation(ILBPair LBPairImplementation) external;

    function createLBPair(
        IERC20 tokenX,
        IERC20 tokenY,
        uint24 activeId,
        uint16 binStep
    ) external returns (ILBPair pair);

    function setLBPairBlacklist(
        IERC20 tokenX,
        IERC20 tokenY,
        uint256 binStep,
        bool blacklisted
    ) external;

    function setPreset(
        uint16 binStep,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulated,
        uint16 sampleLifetime
    ) external;

    function removePreset(uint16 binStep) external;

    function setFeesParametersOnPair(
        IERC20 tokenX,
        IERC20 tokenY,
        uint16 binStep,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulated
    ) external;

    function setFeeRecipient(address feeRecipient) external;

    function setFlashLoanFee(uint256 _flashLoanFee) external;

    function setFactoryLocked(bool locked) external;

    function forceDecay(ILBPair _LBPair) external;
}
