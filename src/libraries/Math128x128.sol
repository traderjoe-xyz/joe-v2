// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "../LBErrors.sol";
import "./Math512Bits.sol";
import "./BitMath.sol";
import "./Constants.sol";

library Math128x128 {
    using Math512Bits for uint256;
    using BitMath for uint256;

    /// @notice Calculates the binary logarithm of x.
    ///
    /// @dev Based on the iterative approximation algorithm.
    /// https://en.wikipedia.org/wiki/Binary_logarithm#Iterative_approximation
    ///
    /// Requirements:
    /// - x must be greater than zero.
    ///
    /// Caveats:
    /// - The results are not perfectly accurate to the last decimal, due to the lossy precision of the iterative approximation.
    ///
    /// @param x The unsigned 128.128-binary fixed-point number for which to calculate the binary logarithm.
    /// @return result The binary logarithm as a signed 128.128-binary fixed-point number.
    function log2(uint256 x) internal pure returns (int256 result) {
        if (x == 0) revert Math128x128__LogUnderflow();

        unchecked {
            // This works because log2(x) = -log2(1/x).
            int256 sign;
            if (x >= Constants.SCALE) {
                sign = 1;
            } else {
                sign = -1;
                // Do the fixed-point inversion inline to save gas. The numerator is Constants.SCALE * Constants.S_SCALE.
                x = type(uint256).max / x;
            }

            // Calculate the integer part of the logarithm and add it to the result and finally calculate y = x * 2^(-n).
            uint256 n = (x >> Constants.SCALE_OFFSET).mostSignificantBit();

            // The integer part of the logarithm as a signed 128.128-binary fixed-point number. The operation can't overflow
            // because n is maximum 255, Constants.SCALE is 2^128 and sign is either 1 or -1.
            result = int256(n) << Constants.SCALE_OFFSET;

            // This is y = x * 2^(-n).
            uint256 y = x >> n;

            // If y = 1, the fractional part is zero.
            if (y == Constants.SCALE) {
                return result * sign;
            }

            // Calculate the fractional part via the iterative approximation.
            // The "delta >>= 1" part is equivalent to "delta /= 2", but shifting bits is faster.
            for (int256 delta = int256(1 << (Constants.SCALE_OFFSET - 1)); delta > 0; delta >>= 1) {
                y = y.mulShiftRoundDown(y, Constants.SCALE_OFFSET);

                // Is y^2 > 2 and so in the range [2,4)?
                if (y >= 1 << (Constants.SCALE_OFFSET + 1)) {
                    // Add the 2^(-m) factor to the logarithm.
                    result += delta;

                    // Corresponds to z/2 on Wikipedia.
                    y >>= 1;
                }
            }
            result *= sign;
        }
    }

    /// @notice Returns the value of x^y It's calculated using `1 / x^(-y)` to have the same precision
    /// whether `y` is negative or positive.
    /// @param x The unsigned 128.128-binary fixed-point number for which to calculate the power
    /// @param y A relative number without any decimals
    /// @return The result of `x^y`
    function power(uint256 x, int256 y) internal pure returns (uint256) {
        unchecked {
            uint256 result = Constants.SCALE;

            uint256 absY;
            uint256 pow;
            bool invert;

            if (y < 0) {
                invert = !invert;
                absY = uint256(-y);
            } else {
                absY = uint256(y);
            }

            if (x > type(uint128).max) {
                pow = type(uint256).max / x;
                invert = !invert;
            } else pow = x;

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

            if (result == 0 || absY > 0xfffff) revert Math128x128__PowerUnderflow(x, y);

            return invert ? type(uint256).max / result : result;
        }
    }
}
