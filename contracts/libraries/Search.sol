// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../interfaces/ILiquidityBinPair.sol";
import "./MathS40x36.sol";
import "./Math.sol";

error Search__ErrorDepthSearch();

library Search {
    using Math for uint256;
    using MathS40x36 for int256;

    /// @notice Returns the first index of the array that is non zero, The
    /// array need to be ordered so that zeros and non zeros aren't together
    /// (no cross over), e.g. [0,1,2,1], [1,1,1,0,0], [0,0,0], [1,2,1]
    /// @param _array The uint112 array
    /// @param _start The index where the search will start
    /// @param _end The index where the search will end
    /// @return The first index of the array that is non zero
    function binarySearchMiddle(
        uint112[] memory _array,
        uint256 _start,
        uint256 _end
    ) internal pure returns (uint256) {
        uint256 middle;
        if (_array[_end] == 0) {
            return _end;
        }
        while (_end > _start) {
            middle = (_start + _end) / 2;
            if (_array[middle] == 0) {
                _start = middle + 1;
            } else {
                _end = middle;
            }
        }
        if (_array[middle] == 0) {
            return middle + 1;
        }
        return middle;
    }

    /// @notice Returns the first id that is non zero, corresponding to a bin with
    /// liquidity in it
    /// @param _bins the bins as a LiquidityBinPair.Bins
    /// @param _binId the binId to start searching
    /// @param _isSearchingRight The boolean value to decide if the algorithm will look
    /// for the closest non zero bit on the right or the left
    /// @return The closest non zero bit on the right side
    function _findFirstBin(
        ILiquidityBinPair.Bins storage _bins,
        int256 _binId,
        bool _isSearchingRight
    ) internal view returns (int256) {
        uint256 current;
        bool found;

        uint256 bit = _binId > 0
            ? uint256(_binId) % 256
            : uint256(-_binId) % 256; // bit is always >= 0
        _binId /= 256;
        // if (_isSearchingRight) {
        // Search in depth 2
        if (
            (_isSearchingRight && bit != 0) || (!_isSearchingRight && bit < 255)
        ) {
            current = _bins.tree[2][_binId];
            (bit, found) = _closestBit(current, bit, _isSearchingRight);
            if (found) {
                return _binId * 256 + int256(bit);
            }
        }

        int256 binIdDepth1 = _binId / 256;
        int256 nextBinId;

        // Search in depth 1
        if (
            (_isSearchingRight && _binId % 256 != 0) ||
            (!_isSearchingRight && _binId % 256 != 255)
        ) {
            current = _bins.tree[1][binIdDepth1];
            (bit, found) = _closestBit(
                current,
                _binId.abs() % 256,
                _isSearchingRight
            );
            if (found) {
                nextBinId = 256 * binIdDepth1 + int256(bit);
                current = _bins.tree[2][nextBinId];
                bit = current.mostSignificantBit();
                return nextBinId * 256 + int256(bit);
            }
        }

        // Search in depth 0
        current = _bins.tree[0][0];
        (bit, found) = _closestBit(
            current,
            binIdDepth1.abs(),
            _isSearchingRight
        );
        if (!found) revert Search__ErrorDepthSearch();
        nextBinId = int256(bit) - 128;
        current = _bins.tree[1][nextBinId];
        nextBinId =
            256 *
            nextBinId +
            int256(_significantBit(current, _isSearchingRight));
        current = _bins.tree[2][nextBinId];
        bit = _significantBit(current, _isSearchingRight);
        return nextBinId * 256 + int256(bit);
    }

    function _closestBit(
        uint256 integer,
        uint256 _bit,
        bool _isSearchingRight
    ) private view returns (uint256, bool) {
        if (_isSearchingRight) {
            return integer.closestBitRight(_bit - 1);
        }
        return integer.closestBitLeft(_bit + 1);
    }

    function _significantBit(uint256 integer, bool _isSearchingRight)
        private
        view
        returns (uint256)
    {
        if (_isSearchingRight) {
            return integer.mostSignificantBit();
        }
        return integer.leastSignificantBit();
    }
}
