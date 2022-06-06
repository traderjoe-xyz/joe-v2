// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./ILBFactoryHelper.sol";

interface ILBFactory {
    function factoryHelper() external view returns (ILBFactoryHelper);

    function feeRecipient() external view returns (address);

    function allLBPairs(uint256 _id) external returns (address);

    function allPairsLength() external view returns (uint256);

    function getLBPair(address _tokenA, address _tokenB)
        external
        view
        returns (address);

    function createLBPair(
        address _tokenA,
        address _tokenB,
        uint16 _coolDownTime,
        uint16 _binStep,
        uint16 _fF,
        uint16 _fV,
        uint16 _maxFee,
        uint16 _protocolShare
    ) external returns (address pair);

    function setFeeRecipient(address _feeRecipient) external;
}
