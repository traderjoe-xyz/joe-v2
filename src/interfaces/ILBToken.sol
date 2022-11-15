// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "openzeppelin/token/ERC1155/IERC1155.sol";
import "openzeppelin/token/ERC1155/extensions/IERC1155MetadataURI.sol";

/// @title Liquidity Book Token Interface
/// @author Trader Joe
/// @notice Required interface of LBToken contract
interface ILBToken is IERC1155, IERC1155MetadataURI {
    function totalSupply(uint256 id) external view returns (uint256);
}
