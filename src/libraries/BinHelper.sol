// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./MathS40x36.sol";

error BinHelper__PowerUnderflow();
error BinHelper__PriceOverflows(uint256 _price);
error BinHelper__WrongBPValue(uint256 bp);
error BinHelper__IdOverflows(int256 _id);

library BinHelper {
    using MathS40x36 for int256;

    int256 private constant INT24_SHIFT = 2**23;

    /// @notice Returns the _id corresponding to the given price
    /// @dev The _id may be inaccurate due to rounding issues, always trust getPriceFromId rather than
    /// getIdFromPrice
    /// @param _price The price of y per x (with 36 decimals)
    /// @param _bp The bin step
    /// @return The _id corresponding to this price
    function getIdFromPrice(uint256 _price, uint256 _bp)
        internal
        pure
        returns (uint24)
    {
        unchecked {
            if (_price > uint256(type(int256).max))
                revert BinHelper__PriceOverflows(_price);

            int256 _bpValue = int256(_getBPValue(_bp));

            int256 _id = INT24_SHIFT + int256(_price).log2() / _bpValue.log2();

            if (_id < 0 || uint256(_id) > type(uint24).max)
                revert BinHelper__IdOverflows(_id);
            return uint24(uint256(_id));
        }
    }

    /// @notice Returns the price corresponding to the given ID (with 36 decimals)
    /// @dev This is the trusted function to link _id to price, the other way may be inaccurate
    /// @param _id The _id.
    /// @param _bp The bin step
    /// @return The price corresponding to this _id (with 36 decimals)
    function getPriceFromId(uint256 _id, uint256 _bp)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            int256 _realId = int256(uint256(_id)) - INT24_SHIFT;
            return _getPrice(_realId, _bp);
        }
    }

    /// @notice Returns the value of (1+bp)^i. It's calculated using 1 / (1+bp)^-i to have the same precision
    /// when i is negative or positive.
    /// @param _id The _id.
    /// @param _bp The bin step
    /// @return The price corresponding to this _id (with 36 decimals)
    function _getPrice(int256 _id, uint256 _bp)
        internal
        pure
        returns (uint256)
    {
        unchecked {
            uint256 pow = Constants.DOUBLE_SCALE / _getBPValue(_bp);
            uint256 absId = _id >= 0 ? uint256(_id) : uint256(-_id);

            if (absId > 0xca62c) revert BinHelper__IdOverflows(_id);

            uint256 result = Constants.SCALE;

            if (absId & 0x1 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x2 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x4 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x8 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x10 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x20 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x40 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x80 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x100 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x200 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x400 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x800 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x1000 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x2000 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x4000 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x8000 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x10000 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x20000 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x40000 != 0) result = (result * pow) / Constants.SCALE;
            pow = (pow**2) / Constants.SCALE;
            if (absId & 0x80000 != 0) result = (result * pow) / Constants.SCALE;

            if (result == 0) revert BinHelper__PowerUnderflow();

            return _id <= 0 ? result : Constants.DOUBLE_SCALE / result;
        }
    }

    /// @notice Returns the (1 + bp) value
    /// @param _bp The bp value [1; 10_000]
    /// @return The (1+bp) value
    function _getBPValue(uint256 _bp) internal pure returns (uint256) {
        if (_bp == 0 || _bp > Constants.BASIS_POINT_MAX)
            revert BinHelper__WrongBPValue(_bp);
        return Constants.SCALE + _bp * 1e32;
    }
}
