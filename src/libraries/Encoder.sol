// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

library Encoder {
    ///@notice Internal function to encode a uint256 value using a mask and offset
    /// @param _value The value as a uint256
    /// @param _mask The mask
    /// @param _offset The offset
    /// @return sample The encoded bytes32 sample
    function encode(
        uint256 _value,
        uint256 _mask,
        uint256 _offset
    ) internal pure returns (bytes32 sample) {
        assembly {
            sample := shl(_offset, and(_value, _mask))
        }
    }
}
