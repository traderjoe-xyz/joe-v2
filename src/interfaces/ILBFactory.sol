// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./ILBPair.sol";
import "./ILBFactoryHelper.sol";
import "./IPendingOwnable.sol";

interface ILBFactory is IPendingOwnable {
    struct LBPairInfo {
        ILBPair LBPair;
        bool createdByOwner;
        bool isBlacklisted;
    }

    struct LBPairAvailable {
        uint256 binStep;
        ILBPair LBPair;
        bool createdByOwner;
        bool isBlacklisted;
    }

    function MIN_FEE() external pure returns (uint256);

    function MAX_FEE() external pure returns (uint256);

    function MIN_BIN_STEP() external pure returns (uint256);

    function MAX_BIN_STEP() external pure returns (uint256);

    function MAX_PROTOCOL_SHARE() external pure returns (uint256);

    function factoryHelper() external view returns (ILBFactoryHelper);

    function feeRecipient() external view returns (address);

    function unlocked() external view returns (bool);

    function allLBPairs(uint256 id) external returns (ILBPair);

    function allPairsLength() external view returns (uint256);

    function getLBPairInfo(
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 binStep
    ) external view returns (LBPairInfo memory);

    function setFactoryHelper() external;

    function createLBPair(
        IERC20 tokenX,
        IERC20 tokenY,
        uint24 activeId,
        uint16 binStep
    ) external returns (ILBPair pair);

    function setFeeRecipient(address feeRecipient) external;

    function setLBPairBlacklist(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _binStep,
        bool _blacklisted
    ) external;

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
    ) external;

    function removePreset(uint16 binStep) external;

    function getPreset(uint16 _binStep)
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

    function getAvailableLBPairsBinStep(IERC20 _tokenX, IERC20 _tokenY)
        external
        view
        returns (LBPairAvailable[] memory LBPairsBinStep);

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
    ) external;
}
