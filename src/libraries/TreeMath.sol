// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./BitMath.sol";

error TreeMath__ErrorDepthSearch();

library TreeMath {
    using BitMath for uint256;

    /// @notice Returns the first id that is non zero, corresponding to a bin with
    /// liquidity in it
    /// @param _binId the binId to start searching
    /// @param _isSearchingRight The boolean value to decide if the algorithm will look
    /// for the closest non zero bit on the right or the left
    /// @return The closest non zero bit on the right side
    function findFirstBin(
        mapping(uint256 => uint256)[3] storage _tree,
        uint256 _binId,
        bool _isSearchingRight
    ) internal view returns (uint256) {
        unchecked {
            uint256 current;
            bool found;

            uint256 bit = _binId % 256;
            _binId /= 256;

            // Search in depth 2
            if ((_isSearchingRight && bit != 0) || (!_isSearchingRight && bit < 255)) {
                current = _tree[2][_binId];
                (bit, found) = current.closestBit(bit, _isSearchingRight);
                if (found) {
                    return _binId * 256 + bit;
                }
            }

            bit = _binId % 256;
            _binId /= 256;

            // Search in depth 1
            if ((_isSearchingRight && _binId % 256 != 0) || (!_isSearchingRight && _binId % 256 != 255)) {
                current = _tree[1][_binId];
                (bit, found) = current.closestBit(bit, _isSearchingRight);
                if (found) {
                    _binId = 256 * _binId + bit;
                    current = _tree[2][_binId];
                    bit = current.mostSignificantBit();
                    return _binId * 256 + bit;
                }
            }

            // Search in depth 0
            current = _tree[0][0];
            (_binId, found) = current.closestBit(_binId, _isSearchingRight);
            if (!found) revert TreeMath__ErrorDepthSearch();
            current = _tree[1][_binId];
            _binId = 256 * _binId + current.significantBit(_isSearchingRight);
            current = _tree[2][_binId];
            bit = current.significantBit(_isSearchingRight);
            return _binId * 256 + bit;
        }
    }
}
