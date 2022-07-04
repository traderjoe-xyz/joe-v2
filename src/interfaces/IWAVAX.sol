// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "openzeppelin/token/ERC20/IERC20.sol";

interface IWAVAX is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}
