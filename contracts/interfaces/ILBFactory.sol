// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./ILBFactoryHelper.sol";

interface ILBFactory {
    function factoryHelper() external view returns (ILBFactoryHelper);

    function feeRecipient() external view returns (address);

    function allPairsLength() external view returns (uint256);

    function getLBPair(address _tokenA, address _tokenB)
        external
        view
        returns (address);

    function allLBPairs(uint256 _id) external returns (address);

    function createLBPair(
        address _tokenA,
        address _tokenB,
        uint16 _baseFee,
        uint16 _bp
    ) external returns (address pair);

    function setFeeRecipient(address _feeRecipient) external;
}
