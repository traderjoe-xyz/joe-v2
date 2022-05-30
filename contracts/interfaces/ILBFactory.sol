// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ILBFactory {
    function feeRecipient() external returns (address);

    function implementation() external returns (address);

    function allPairsLength() external returns (uint256);

    function getLBPair(address _tokenA, address _tokenB)
        external
        returns (address);

    function createLBPair(
        address _tokenA,
        address _tokenB,
        uint256 _baseFee
    ) external returns (address pair);

    function setFeeRecipient(address _feeRecipient) external;
}
