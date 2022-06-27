// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ILBFactory.sol";
import "./ILBPair.sol";

interface ILBFactoryHelper {
    function factory() external view returns (ILBFactory);

    function createLBPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        int256 _log2Value,
        bytes32 _salt,
        bytes32 _packedFeeParameters
    ) external returns (ILBPair);
}
