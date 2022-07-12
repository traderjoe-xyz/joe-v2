// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

library Encoder {
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
