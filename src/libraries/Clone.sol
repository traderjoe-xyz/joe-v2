// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/**
 * @title Clone
 * @notice Class with helper read functions for clone with immutable args.
 * @author Trader Joe
 * @author Solady (https://github.com/vectorized/solady/blob/main/src/utils/Clone.sol)
 * @author Adapted from clones with immutable args by zefram.eth, Saw-mon & Natalie
 * (https://github.com/Saw-mon-and-Natalie/clones-with-immutable-args)
 */
abstract contract Clone {
    /**
     * @dev Reads an immutable arg with type bytes
     * @param argOffset The offset of the arg in the immutable args
     * @param length The length of the arg
     * @return arg The immutable bytes arg
     */
    function _getArgBytes(uint256 argOffset, uint256 length) internal pure returns (bytes memory arg) {
        uint256 offset = _getImmutableArgsOffset();
        /// @solidity memory-safe-assembly
        assembly {
            // Grab the free memory pointer.
            arg := mload(0x40)
            // Store the array length.
            mstore(arg, length)
            // Copy the array.
            calldatacopy(add(arg, 0x20), add(offset, argOffset), length)
            // Allocate the memory, rounded up to the next 32 byte boundary.
            mstore(0x40, and(add(add(arg, 0x3f), length), not(0x1f)))
        }
    }

    /**
     * @dev Reads an immutable arg with type address
     * @param argOffset The offset of the arg in the immutable args
     * @return arg The immutable address arg
     */
    function _getArgAddress(uint256 argOffset) internal pure returns (address arg) {
        uint256 offset = _getImmutableArgsOffset();
        /// @solidity memory-safe-assembly
        assembly {
            arg := shr(0x60, calldataload(add(offset, argOffset)))
        }
    }

    /**
     * @dev Reads an immutable arg with type uint256
     * @param argOffset The offset of the arg in the immutable args
     * @return arg The immutable uint256 arg
     */
    function _getArgUint256(uint256 argOffset) internal pure returns (uint256 arg) {
        uint256 offset = _getImmutableArgsOffset();
        /// @solidity memory-safe-assembly
        assembly {
            arg := calldataload(add(offset, argOffset))
        }
    }

    /**
     * @dev Reads a uint256 array stored in the immutable args.
     * @param argOffset The offset of the arg in the immutable args
     * @param length The length of the arg
     * @return arg The immutable uint256 array arg
     */
    function _getArgUint256Array(uint256 argOffset, uint256 length) internal pure returns (uint256[] memory arg) {
        uint256 offset = _getImmutableArgsOffset();
        /// @solidity memory-safe-assembly
        assembly {
            // Grab the free memory pointer.
            arg := mload(0x40)
            // Store the array length.
            mstore(arg, length)
            // Copy the array.
            calldatacopy(add(arg, 0x20), add(offset, argOffset), shl(5, length))
            // Allocate the memory.
            mstore(0x40, add(add(arg, 0x20), shl(5, length)))
        }
    }

    /**
     * @dev Reads an immutable arg with type uint64
     * @param argOffset The offset of the arg in the immutable args
     * @return arg The immutable uint64 arg
     */
    function _getArgUint64(uint256 argOffset) internal pure returns (uint64 arg) {
        uint256 offset = _getImmutableArgsOffset();
        /// @solidity memory-safe-assembly
        assembly {
            arg := shr(0xc0, calldataload(add(offset, argOffset)))
        }
    }

    /**
     * @dev Reads an immutable arg with type uint16
     * @param argOffset The offset of the arg in the immutable args
     * @return arg The immutable uint16 arg
     */
    function _getArgUint16(uint256 argOffset) internal pure returns (uint16 arg) {
        uint256 offset = _getImmutableArgsOffset();
        /// @solidity memory-safe-assembly
        assembly {
            arg := shr(0xf0, calldataload(add(offset, argOffset)))
        }
    }

    /**
     * @dev Reads an immutable arg with type uint8
     * @param argOffset The offset of the arg in the immutable args
     * @return arg The immutable uint8 arg
     */
    function _getArgUint8(uint256 argOffset) internal pure returns (uint8 arg) {
        uint256 offset = _getImmutableArgsOffset();
        /// @solidity memory-safe-assembly
        assembly {
            arg := shr(0xf8, calldataload(add(offset, argOffset)))
        }
    }

    /**
     * @dev Reads the offset of the packed immutable args in calldata.
     * @return offset The offset of the packed immutable args in calldata.
     */
    function _getImmutableArgsOffset() internal pure returns (uint256 offset) {
        /// @solidity memory-safe-assembly
        assembly {
            offset := sub(calldatasize(), shr(0xf0, calldataload(sub(calldatasize(), 2))))
        }
    }
}
