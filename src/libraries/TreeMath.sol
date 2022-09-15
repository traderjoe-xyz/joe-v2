// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./BitMath.sol";

import "../LBErrors.sol";

library TreeMath {
    using BitMath for uint256;

    /// @notice Returns the first id that is non zero, corresponding to a bin with
    /// liquidity in it
    /// @param _tree The storage slot of the tree
    /// @param _binId the binId to start searching
    /// @param _rightSide Whether we're searching in the right side of the tree (true) or the left side (false)
    /// for the closest non zero bit on the right or the left
    /// @return The closest non zero bit on the right (or left) side of the tree
    function findFirstBin(
        mapping(uint256 => uint256)[3] storage _tree,
        uint256 _binId,
        bool _rightSide
    ) internal view returns (uint256) {
        unchecked {
            uint256 current;

            uint256 bit = _binId & 255;
            _binId >>= 8;

            // Search in depth 2
            if ((_rightSide && bit != 0) || (!_rightSide && bit != 255)) {
                current = _tree[2][_binId];
                bit = current.closestBit(uint8(bit), _rightSide);
                if (bit != type(uint256).max) {
                    return _binId * 256 + bit;
                }
            }

            bit = _binId & 255;
            _binId >>= 8;

            // Search in depth 1
            if ((_rightSide && bit != 0) || (!_rightSide && bit != 255)) {
                current = _tree[1][_binId];
                bit = current.closestBit(uint8(bit), _rightSide);
                if (bit != type(uint256).max) {
                    _binId = 256 * _binId + bit;
                    current = _tree[2][_binId];
                    bit = current.significantBit(_rightSide);
                    return _binId * 256 + bit;
                }
            }

            // Search in depth 0
            current = _tree[0][0];
            _binId = current.closestBit(uint8(_binId), _rightSide);
            if (_binId == type(uint256).max) revert TreeMath__ErrorDepthSearch();
            current = _tree[1][_binId];
            _binId = 256 * _binId + current.significantBit(_rightSide);
            current = _tree[2][_binId];
            bit = current.significantBit(_rightSide);
            return _binId * 256 + bit;
        }
    }

    function addToTree(mapping(uint256 => uint256)[3] storage _tree, uint256 _id) internal {
        // add 1 at the right indices
        uint256 _idDepth2 = _id >> 8;
        uint256 _idDepth1 = _id >> 16;

        _tree[2][_idDepth2] |= 1 << (_id & 255);
        _tree[1][_idDepth1] |= 1 << (_idDepth2 & 255);
        _tree[0][0] |= 1 << _idDepth1;
    }

    function removeFromTree(mapping(uint256 => uint256)[3] storage _tree, uint256 _id) internal {
        unchecked {
            // removes 1 at the right indices
            uint256 _idDepth2 = _id >> 8;
            uint256 _newLeafValue = _tree[2][_idDepth2] & (type(uint256).max ^ (1 << (_id & 255)));
            _tree[2][_idDepth2] = _newLeafValue;
            if (_newLeafValue == 0) {
                uint256 _idDepth1 = _id >> 16;
                _newLeafValue = _tree[1][_idDepth1] & (type(uint256).max ^ (1 << (_idDepth2 & 255)));
                _tree[1][_idDepth1] = _newLeafValue;
                if (_newLeafValue == 0) {
                    _tree[0][0] &= type(uint256).max ^ (1 << _idDepth1);
                }
            }
        }
    }
}
