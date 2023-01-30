// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "openzeppelin/token/ERC20/IERC20.sol";

/// @title Liquidity Book Pair V2 Interface
/// @author Trader Joe
/// @notice Required interface of LBPair contract
interface ILBLegacyPair {
    function tokenX() external view returns (IERC20);

    function tokenY() external view returns (IERC20);

    function getReservesAndId() external view returns (uint256 reserveX, uint256 reserveY, uint256 activeId);
}
