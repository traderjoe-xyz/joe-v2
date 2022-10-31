// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "openzeppelin/token/ERC20/IERC20.sol";

/// @title WAVAX Interface
/// @notice Required interface of Wrapped AVAX contract
interface IWAVAX is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}
