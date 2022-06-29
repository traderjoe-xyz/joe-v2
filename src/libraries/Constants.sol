// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

library Constants {
    uint256 internal constant PRICE_PRECISION = 1e36;
    uint256 internal constant DOUBLE_PRICE_PRECISION = PRICE_PRECISION**2;
    int256 internal constant S_PRICE_PRECISION = int256(PRICE_PRECISION);
    int256 internal constant S_HALF_PRICE_PRECISION = S_PRICE_PRECISION / 2;
    uint256 internal constant BASIS_POINT_MAX = 10_000;
}
