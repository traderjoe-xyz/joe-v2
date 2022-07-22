// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./Math128x128.sol";

error BinHelper__PowerUnderflow();
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

            uint256 _value = _getBPValue(_bp);

            return _powerOf(_value, _realId);
        }
    }

    /// @notice Returns the value of x^y It's calculated using `1 / x^(-y)` to have the same precision
    /// whether `y` is negative or positive.
    /// @param x A real number with Constants.SCALE_OFFSET bits of decimals
    /// @param y A relative number without any decimals
    /// @return The result of `x^y`
    function _powerOf(uint256 x, int256 y) internal pure returns (uint256) {
        unchecked {
            uint256 absY = y >= 0 ? uint256(y) : uint256(-y);

            uint256 pow = type(uint256).max / x;

            uint256 result = Constants.SCALE;

            if (absY & 0x1 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x2 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x4 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x8 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x10 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x20 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x40 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x80 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x100 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x200 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x400 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x800 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x1000 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x2000 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x4000 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x8000 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x10000 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x20000 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x40000 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;
            pow = (pow * pow) >> Constants.SCALE_OFFSET;
            if (absY & 0x80000 != 0) result = (result * pow) >> Constants.SCALE_OFFSET;

            if (result == 0 || absY > 0xfffff) revert BinHelper__PowerUnderflow();

            return y <= 0 ? result : type(uint256).max / result;
        }
    }

    /// @notice Returns the (1 + bp) value
    /// @param _bp The bp value in [1; 100]
    /// @return The (1+bp) value
    function _getBPValue(uint256 _bp) internal pure returns (uint256) {
        unchecked {
            return Constants.SCALE + (_bp << Constants.SCALE_OFFSET) / Constants.BASIS_POINT_MAX;
        }
    }
}
