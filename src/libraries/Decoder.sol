// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

library Decoder {
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
