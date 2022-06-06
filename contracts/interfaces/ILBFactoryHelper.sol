// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./ILBFactory.sol";

interface ILBFactoryHelper {
    function factory() external view returns (ILBFactory);

    function createLBPair(
        address _token0,
        address _token1,
        int256 _log2Value,
        bytes32 _salt,
        bytes32 _feeParameters
    ) external returns (address);
}
