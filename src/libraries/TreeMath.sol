// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./BitMath.sol";

error TreeMath__ErrorDepthSearch();

library TreeMath {
    using BitMath for uint256;

    /// @notice Returns the first id that is non zero, corresponding to a bin with
    /// liquidity in it
    /// @param _tree The storage slot of the tree
    /// @param _binId the binId to start searching
    /// @param _leftSide Whether we're searching in the left side of the tree (true) or the right side (false)
    /// for the closest non zero bit on the right or the left
    /// @return The closest non zero bit on the right side
    function findFirstBin(
        mapping(uint256 => uint256)[3] storage _tree,
        uint256 _binId,
        bool _leftSide
    ) internal view returns (uint256) {
        unchecked {
            uint256 current;
            bool found;

            uint256 bit = _binId % 256;
            _binId /= 256;

            // Search in depth 2
            if ((_leftSide && bit < 255) || (!_leftSide && bit != 0)) {
                current = _tree[2][_binId];
                (bit, found) = current.closestBit(bit, _leftSide);
                if (found) {
                    return _binId * 256 + bit;
                }
            }

            bit = _binId % 256;
            _binId /= 256;

            // Search in depth 1
            if ((_leftSide && _binId % 256 != 255) || (!_leftSide && _binId % 256 != 0)) {
                current = _tree[1][_binId];
                (bit, found) = current.closestBit(bit, _leftSide);
                if (found) {
                    _binId = 256 * _binId + bit;
                    current = _tree[2][_binId];
                    bit = current.mostSignificantBit();
                    return _binId * 256 + bit;
                }
            }

            // Search in depth 0
            current = _tree[0][0];
            (_binId, found) = current.closestBit(_binId, _leftSide);
            if (!found) revert TreeMath__ErrorDepthSearch();
            current = _tree[1][_binId];
            _binId = 256 * _binId + current.significantBit(_leftSide);
            current = _tree[2][_binId];
            bit = current.significantBit(_leftSide);
            return _binId * 256 + bit;
        }
    }
}
