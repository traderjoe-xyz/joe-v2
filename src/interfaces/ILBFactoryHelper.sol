// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./ILBFactory.sol";
import "./ILBPair.sol";

interface ILBFactoryHelper {
    function factory() external view returns (ILBFactory);

    function createLBPair(
        IERC20 tokenX,
        IERC20 tokenY,
        bytes32 salt,
        uint24 activeId,
        uint16 sampleLifetime,
        bytes32 packedFeeParameters
    ) external returns (ILBPair);
}
