// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./MathS40x36.sol";

error BinHelper__WrongId(uint24 id);

library BinHelper {
    using MathS40x36 for int256;

    uint256 private constant INT24_SHIFT = 2**23;

    /// @notice Returns the id corresponding to the inputted price
    /// @param _price The price of y per x (multiplied by 1e36)
    /// @return The id corresponding to this price
    function getIdFromPrice(uint256 _price, int256 _log2Value)
        internal
        pure
        returns (uint24)
    {
        /// don't need to check if it overflows as log2(max_s40x36) < 136e36
        /// and log2Value > 1e32, thus the result is lower than 136e36 / 1e32 = 136e4 < 2**24
        return
            uint24(
                uint256(
                    int256(INT24_SHIFT) + int256(_price).log2() / _log2Value
                )
            );
    }

    /// @notice Returns the price corresponding to the inputted id
    /// @param _id The id
    /// @param _log2Value The log(1+binStep) value
    /// @return price The price corresponding to this id
    function getPriceFromId(uint24 _id, int256 _log2Value)
        internal
        pure
        returns (uint256 price)
    {
        unchecked {
            price = uint256((int256(_id - INT24_SHIFT) * _log2Value).exp2());
            if (price == 0) revert BinHelper__WrongId(_id);
        }
    }

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
        unchecked {
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
    }
}
