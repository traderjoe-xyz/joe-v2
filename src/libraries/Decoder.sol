// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

library Decoder {
    ///@notice Internal function to decode a bytes32 sample using a mask and offset
    /// @param _sample The sample as a bytes32
    /// @param _mask The mask
    /// @param _offset The offset
    /// @return value The decoded value
    function decode(
        bytes32 _sample,
        uint256 _mask,
        uint256 _offset
    ) internal pure returns (uint256 value) {
        assembly {
            value := and(shr(_offset, _sample), _mask)
        }
    }
}
