// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./Math128x128.sol";

error BinHelper__WrongBPValue(uint256 bp);
error BinHelper__IdOverflows(int256 _id);

library BinHelper {
    using Math128x128 for uint256;

    int256 private constant INT24_SHIFT = 2**23;

    /// @notice Returns the id corresponding to the given price
    /// @dev The id may be inaccurate due to rounding issues, always trust getPriceFromId rather than
    /// getIdFromPrice
    /// @param _price The price of y per x (with 36 decimals)
    /// @param _bp The bin step
    /// @return The id corresponding to this price
    function getIdFromPrice(uint256 _price, uint256 _bp) internal pure returns (uint24) {
        unchecked {
            uint256 _bpValue = _getBPValue(_bp);

            int256 _id = INT24_SHIFT + _price.log2() / _bpValue.log2();

            if (_id < 0 || uint256(_id) > type(uint24).max) revert BinHelper__IdOverflows(_id);
            return uint24(uint256(_id));
        }
    }

    /// @notice Returns the price corresponding to the given ID (with 36 decimals)
    /// @dev This is the trusted function to link id to price, the other way may be inaccurate
    /// @param _id The id
    /// @param _bp The bin step
    /// @return The price corresponding to this id (with 36 decimals)
    function getPriceFromId(uint256 _id, uint256 _bp) internal pure returns (uint256) {
        unchecked {
            int256 _realId = int256(uint256(_id)) - INT24_SHIFT;

            return _getBPValue(_bp).power(_realId);
        }
    }

    /// @notice Returns the (1 + bp) value as a 128.128-decimal fixed-point number
    /// @param _bp The bp value in [1; 100] (referring to 0.01% to 1%)
    /// @return The (1+bp) value as a 128.128-decimal fixed-point number
    function _getBPValue(uint256 _bp) internal pure returns (uint256) {
        unchecked {
            return Constants.SCALE + (_bp << Constants.SCALE_OFFSET) / Constants.BASIS_POINT_MAX;
        }
    }
}
