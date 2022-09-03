// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "../LBErrors.sol";

library SafeCast {
    /// @notice Returns x on uint248 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint248
    function safe248(uint256 x) internal pure returns (uint248) {
        if (x > type(uint248).max) revert SafeCast__Exceeds248Bits(x);
        return uint248(x);
    }

    /// @notice Returns x on uint240 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint240
    function safe240(uint256 x) internal pure returns (uint240) {
        if (x > type(uint240).max) revert SafeCast__Exceeds240Bits(x);
        return uint240(x);
    }

    /// @notice Returns x on uint232 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint232
    function safe232(uint256 x) internal pure returns (uint232) {
        if (x > type(uint232).max) revert SafeCast__Exceeds232Bits(x);
        return uint232(x);
    }

    /// @notice Returns x on uint224 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint224
    function safe224(uint256 x) internal pure returns (uint224) {
        if (x > type(uint224).max) revert SafeCast__Exceeds224Bits(x);
        return uint224(x);
    }

    /// @notice Returns x on uint216 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint216
    function safe216(uint256 x) internal pure returns (uint216) {
        if (x > type(uint216).max) revert SafeCast__Exceeds216Bits(x);
        return uint216(x);
    }

    /// @notice Returns x on uint208 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint208
    function safe208(uint256 x) internal pure returns (uint208) {
        if (x > type(uint208).max) revert SafeCast__Exceeds208Bits(x);
        return uint208(x);
    }

    /// @notice Returns x on uint200 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint200
    function safe200(uint256 x) internal pure returns (uint200) {
        if (x > type(uint200).max) revert SafeCast__Exceeds200Bits(x);
        return uint200(x);
    }

    /// @notice Returns x on uint192 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint192
    function safe192(uint256 x) internal pure returns (uint192) {
        if (x > type(uint192).max) revert SafeCast__Exceeds192Bits(x);
        return uint192(x);
    }

    /// @notice Returns x on uint184 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint184
    function safe184(uint256 x) internal pure returns (uint184) {
        if (x > type(uint184).max) revert SafeCast__Exceeds184Bits(x);
        return uint184(x);
    }

    /// @notice Returns x on uint176 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint176
    function safe176(uint256 x) internal pure returns (uint176) {
        if (x > type(uint176).max) revert SafeCast__Exceeds176Bits(x);
        return uint176(x);
    }

    /// @notice Returns x on uint168 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint168
    function safe168(uint256 x) internal pure returns (uint168) {
        if (x > type(uint168).max) revert SafeCast__Exceeds168Bits(x);
        return uint168(x);
    }

    /// @notice Returns x on uint160 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint160
    function safe160(uint256 x) internal pure returns (uint160) {
        if (x > type(uint160).max) revert SafeCast__Exceeds160Bits(x);
        return uint160(x);
    }

    /// @notice Returns x on uint152 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint152
    function safe152(uint256 x) internal pure returns (uint152) {
        if (x > type(uint152).max) revert SafeCast__Exceeds152Bits(x);
        return uint152(x);
    }

    /// @notice Returns x on uint144 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint144
    function safe144(uint256 x) internal pure returns (uint144) {
        if (x > type(uint144).max) revert SafeCast__Exceeds144Bits(x);
        return uint144(x);
    }

    /// @notice Returns x on uint136 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint136
    function safe136(uint256 x) internal pure returns (uint136) {
        if (x > type(uint136).max) revert SafeCast__Exceeds136Bits(x);
        return uint136(x);
    }

    /// @notice Returns x on uint128 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint128
    function safe128(uint256 x) internal pure returns (uint128) {
        if (x > type(uint128).max) revert SafeCast__Exceeds128Bits(x);
        return uint128(x);
    }

    /// @notice Returns x on uint120 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint120
    function safe120(uint256 x) internal pure returns (uint120) {
        if (x > type(uint120).max) revert SafeCast__Exceeds120Bits(x);
        return uint120(x);
    }

    /// @notice Returns x on uint112 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint112
    function safe112(uint256 x) internal pure returns (uint112) {
        if (x > type(uint112).max) revert SafeCast__Exceeds112Bits(x);
        return uint112(x);
    }

    /// @notice Returns x on uint104 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint104
    function safe104(uint256 x) internal pure returns (uint104) {
        if (x > type(uint104).max) revert SafeCast__Exceeds104Bits(x);
        return uint104(x);
    }

    /// @notice Returns x on uint96 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint96
    function safe96(uint256 x) internal pure returns (uint96) {
        if (x > type(uint96).max) revert SafeCast__Exceeds96Bits(x);
        return uint96(x);
    }

    /// @notice Returns x on uint88 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint88
    function safe88(uint256 x) internal pure returns (uint88) {
        if (x > type(uint88).max) revert SafeCast__Exceeds88Bits(x);
        return uint88(x);
    }

    /// @notice Returns x on uint80 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint80
    function safe80(uint256 x) internal pure returns (uint80) {
        if (x > type(uint80).max) revert SafeCast__Exceeds80Bits(x);
        return uint80(x);
    }

    /// @notice Returns x on uint72 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint72
    function safe72(uint256 x) internal pure returns (uint72) {
        if (x > type(uint72).max) revert SafeCast__Exceeds72Bits(x);
        return uint72(x);
    }

    /// @notice Returns x on uint64 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint64
    function safe64(uint256 x) internal pure returns (uint64) {
        if (x > type(uint64).max) revert SafeCast__Exceeds64Bits(x);
        return uint64(x);
    }

    /// @notice Returns x on uint56 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint56
    function safe56(uint256 x) internal pure returns (uint56) {
        if (x > type(uint56).max) revert SafeCast__Exceeds56Bits(x);
        return uint56(x);
    }

    /// @notice Returns x on uint48 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint48
    function safe48(uint256 x) internal pure returns (uint48) {
        if (x > type(uint48).max) revert SafeCast__Exceeds48Bits(x);
        return uint48(x);
    }

    /// @notice Returns x on uint40 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint40
    function safe40(uint256 x) internal pure returns (uint40) {
        if (x > type(uint40).max) revert SafeCast__Exceeds40Bits(x);
        return uint40(x);
    }

    /// @notice Returns x on uint32 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint32
    function safe32(uint256 x) internal pure returns (uint32) {
        if (x > type(uint32).max) revert SafeCast__Exceeds32Bits(x);
        return uint32(x);
    }

    /// @notice Returns x on uint24 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint24
    function safe24(uint256 x) internal pure returns (uint24) {
        if (x > type(uint24).max) revert SafeCast__Exceeds24Bits(x);
        return uint24(x);
    }

    /// @notice Returns x on uint16 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint16
    function safe16(uint256 x) internal pure returns (uint16) {
        if (x > type(uint16).max) revert SafeCast__Exceeds16Bits(x);
        return uint16(x);
    }

    /// @notice Returns x on uint8 and check that it does not overflow
    /// @param x The value as an uint256
    /// @return The value as an uint8
    function safe8(uint256 x) internal pure returns (uint8) {
        if (x > type(uint8).max) revert SafeCast__Exceeds8Bits(x);
        return uint8(x);
    }
}
