// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ILBPair.sol";
import "./ILBFactoryHelper.sol";

interface ILBFactory {
    function factoryHelper() external view returns (ILBFactoryHelper);

    function feeRecipient() external view returns (address);

    function allLBPairs(uint256 _id) external returns (ILBPair);

    function allPairsLength() external view returns (uint256);

    function getLBPair(IERC20 _tokenA, IERC20 _tokenB)
        external
        view
        returns (ILBPair);

    function createLBPair(
        IERC20 _tokenA,
        IERC20 _tokenB,
        uint16 _coolDownTime,
        uint16 _binStep,
        uint16 _fF,
        uint16 _fV,
        uint16 _maxFee,
        uint16 _protocolShare
    ) external returns (ILBPair pair);

    function setFeeRecipient(address _feeRecipient) external;
}
