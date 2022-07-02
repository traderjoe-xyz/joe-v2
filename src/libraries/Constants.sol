// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

library Constants {
    uint256 internal constant SCALE = 1e36;
    uint256 internal constant DOUBLE_SCALE = SCALE**2;
    int256 internal constant S_SCALE = int256(SCALE);
    int256 internal constant S_HALF_SCALE = S_SCALE / 2;
    uint256 internal constant BASIS_POINT_MAX = 10_000;
}
