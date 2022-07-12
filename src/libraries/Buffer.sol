// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

library Buffer {
    function addMod(
        uint256 x,
        uint256 y,
        uint256 n
    ) internal pure returns (uint256) {
        unchecked {
            return (x + y) % n;
        }
    }

    function subMod(
        uint256 x,
        uint256 y,
        uint256 n
    ) internal pure returns (uint256) {
        unchecked {
            return (x + n - y) % n;
        }
    }
}
