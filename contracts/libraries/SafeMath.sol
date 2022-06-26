// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

/// @notice This library is made to be used inside unchecked code blocks where a specific operation
/// should be checked. We use this library to avoid having to close the unchecked block and reopen it right after
library SafeMath {
    function add(uint256 x, uint256 y) internal pure returns (uint256) {
        return x + y;
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256) {
        return x - y;
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256) {
        return x * y;
    }
}
