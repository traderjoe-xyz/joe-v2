// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/**
 * @title Liquidity Book Encoded Library
 * @author Trader Joe
 * @notice Helper contract used for decoding bytes32 sample
 */
library Encoded {
    uint256 internal constant MASK_UINT1 = 0x1;
    uint256 internal constant MASK_UINT8 = 0xff;
    uint256 internal constant MASK_UINT12 = 0xfff;
    uint256 internal constant MASK_UINT14 = 0x3fff;
    uint256 internal constant MASK_UINT16 = 0xffff;
    uint256 internal constant MASK_UINT20 = 0xfffff;
    uint256 internal constant MASK_UINT24 = 0xffffff;
    uint256 internal constant MASK_UINT40 = 0xffffffffff;
    uint256 internal constant MASK_UINT64 = 0xffffffffffffffff;
    uint256 internal constant MASK_UINT128 = 0xffffffffffffffffffffffffffffffff;

    /**
     * @notice Internal function to set a value in an encoded bytes32 using a mask and offset
     * @dev This function can overflow
     * @param encoded The previous encoded value
     * @param value The value to encode
     * @param mask The mask
     * @param offset The offset
     * @return newEncoded The new encoded value
     */
    function set(bytes32 encoded, uint256 value, uint256 mask, uint256 offset)
        internal
        pure
        returns (bytes32 newEncoded)
    {
        assembly {
            newEncoded := and(encoded, not(shl(offset, mask)))
            newEncoded := or(newEncoded, shl(offset, and(value, mask)))
        }
    }

    /**
     * @notice Internal function to set a bool in an encoded bytes32 using an offset
     * @dev This function can overflow
     * @param encoded The previous encoded value
     * @param boolean The bool to encode
     * @param offset The offset
     * @return newEncoded The new encoded value
     */
    function setBool(bytes32 encoded, bool boolean, uint256 offset) internal pure returns (bytes32 newEncoded) {
        return set(encoded, boolean ? 1 : 0, MASK_UINT1, offset);
    }

    /**
     * @notice Internal function to decode a bytes32 sample using a mask and offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param mask The mask
     * @param offset The offset
     * @return value The decoded value
     */
    function decode(bytes32 encoded, uint256 mask, uint256 offset) internal pure returns (uint256 value) {
        assembly {
            value := and(shr(offset, encoded), mask)
        }
    }

    /**
     * @notice Internal function to decode a bytes32 sample into a bool using an offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param offset The offset
     * @return boolean The decoded value as a bool
     */
    function decodeBool(bytes32 encoded, uint256 offset) internal pure returns (bool boolean) {
        assembly {
            boolean := and(shr(offset, encoded), MASK_UINT1)
        }
    }

    /**
     * @notice Internal function to decode a bytes32 sample into a uint8 using an offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param offset The offset
     * @return value The decoded value
     */
    function decodeUint8(bytes32 encoded, uint256 offset) internal pure returns (uint8 value) {
        assembly {
            value := and(shr(offset, encoded), MASK_UINT8)
        }
    }

    /**
     * @notice Internal function to decode a bytes32 sample into a uint12 using an offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param offset The offset
     * @return value The decoded value as a uint16, since uint12 is not supported
     */
    function decodeUint12(bytes32 encoded, uint256 offset) internal pure returns (uint16 value) {
        assembly {
            value := and(shr(offset, encoded), MASK_UINT12)
        }
    }

    /**
     * @notice Internal function to decode a bytes32 sample into a uint14 using an offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param offset The offset
     * @return value The decoded value as a uint16, since uint14 is not supported
     */
    function decodeUint14(bytes32 encoded, uint256 offset) internal pure returns (uint16 value) {
        assembly {
            value := and(shr(offset, encoded), MASK_UINT14)
        }
    }

    /**
     * @notice Internal function to decode a bytes32 sample into a uint16 using an offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param offset The offset
     * @return value The decoded value
     */
    function decodeUint16(bytes32 encoded, uint256 offset) internal pure returns (uint16 value) {
        assembly {
            value := and(shr(offset, encoded), MASK_UINT16)
        }
    }

    /**
     * @notice Internal function to decode a bytes32 sample into a uint20 using an offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param offset The offset
     * @return value The decoded value as a uint24, since uint20 is not supported
     */
    function decodeUint20(bytes32 encoded, uint256 offset) internal pure returns (uint24 value) {
        assembly {
            value := and(shr(offset, encoded), MASK_UINT20)
        }
    }

    /**
     * @notice Internal function to decode a bytes32 sample into a uint24 using an offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param offset The offset
     * @return value The decoded value
     */
    function decodeUint24(bytes32 encoded, uint256 offset) internal pure returns (uint24 value) {
        assembly {
            value := and(shr(offset, encoded), MASK_UINT24)
        }
    }

    /**
     * @notice Internal function to decode a bytes32 sample into a uint40 using an offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param offset The offset
     * @return value The decoded value
     */
    function decodeUint40(bytes32 encoded, uint256 offset) internal pure returns (uint40 value) {
        assembly {
            value := and(shr(offset, encoded), MASK_UINT40)
        }
    }

    /**
     * @notice Internal function to decode a bytes32 sample into a uint64 using an offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param offset The offset
     * @return value The decoded value
     */
    function decodeUint64(bytes32 encoded, uint256 offset) internal pure returns (uint64 value) {
        assembly {
            value := and(shr(offset, encoded), MASK_UINT64)
        }
    }

    /**
     * @notice Internal function to decode a bytes32 sample into a uint128 using an offset
     * @dev This function can overflow
     * @param encoded The encoded value
     * @param offset The offset
     * @return value The decoded value
     */
    function decodeUint128(bytes32 encoded, uint256 offset) internal pure returns (uint128 value) {
        assembly {
            value := and(shr(offset, encoded), MASK_UINT128)
        }
    }
}
