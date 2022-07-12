// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

library Buffer {
    /// @notice Internal function to do (x + y) % n
    /// @param x The first value
    /// @param y The second value
    /// @param n The modulo value
    /// @return The result
    function addMod(
        uint256 x,
        uint256 y,
        uint256 n
    ) internal pure returns (uint256) {
        unchecked {
            return (x + y) % n;
        }
    }

    /// @notice Internal function to do positive (x - y) % n
    /// @param x The first value
    /// @param y The second value
    /// @param n The modulo value
    /// @return The result
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
