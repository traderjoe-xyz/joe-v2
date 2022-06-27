// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./MathS40x36.sol";

error BinHelper__PriceUnderflow();
error BinHelper__WrongLog2Value(int256 log2Value);
error BinHelper__IdOverflows(int256 id);
error BinHelper__PriceOverflows(uint256 _price);

library BinHelper {
    using MathS40x36 for int256;

    int256 private constant INT24_SHIFT = 2**23;

    /// @notice Returns the id corresponding to the given price
    /// @dev The id may be inaccurate due to rounding issues, always trust getPriceFromId rather than
    /// getIdFromPrice
    /// @param _price The price of y per x (with 36 decimals)
    /// @param _log2Value The value of log2(1 + binStep) of the pair (with 36 decimals)
    /// @return The id corresponding to this price
    function getIdFromPrice(uint256 _price, int256 _log2Value)
        internal
        pure
        returns (uint24)
    { 
        unchecked {
            if (_price > uint256(type(int256).max))
                revert BinHelper__PriceOverflows(_price);
            if (_log2Value <= 0 || _log2Value > 2e36)
                revert BinHelper__WrongLog2Value(_log2Value);

            int256 _id = INT24_SHIFT + int256(_price).log2() / _log2Value;

            if (_id < 0 || uint256(_id) > type(uint24).max)
                revert BinHelper__IdOverflows(_id);
            return uint24(uint256(_id));
        }
    }

    /// @notice Returns the price corresponding to the given ID (with 36 decimals)
    /// @dev This is the trusted function to link id to price, the other way may be inaccurate
    /// @param _id The id as a uint24
    /// @param _log2Value The value of log2(1 + binStep) of the pair (with 36 decimals)
    /// @return price The price corresponding to this id (with 36 decimals)
    function getPriceFromId(uint24 _id, int256 _log2Value)
        internal
        pure
        returns (uint256 price)
    {
        unchecked {
            if (_log2Value <= 0 || _log2Value > 2e36)
                revert BinHelper__WrongLog2Value(_log2Value);
            price = uint256(
                ((int256(uint256(_id)) - INT24_SHIFT) * _log2Value).exp2()
            );
            if (price == 0) revert BinHelper__PriceUnderflow();
        }
    }
}
