// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./Math512Bits.sol";
import "./BitMath.sol";
import "./Constants.sol";

/// @notice Emitted when the input is less than or equal to zero.
error Math__LogInputTooSmall(int256 x);

library MathS40x36 {
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
    /// @param x The signed 40.36-decimal fixed-point number for which to calculate the binary logarithm.
    /// @return result The binary logarithm as a signed 40.36-decimal fixed-point number.
    function log2(int256 x) internal pure returns (int256 result) {
        if (x <= 0) {
            revert Math__LogInputTooSmall(x);
        }
        unchecked {
            // This works because log2(x) = -log2(1/x).
            int256 sign;
            if (x >= Constants.S_PRICE_PRECISION) {
                sign = 1;
            } else {
                sign = -1;
                // Do the fixed-point inversion inline to save gas. The numerator is Constants.S_PRICE_PRECISION * Constants.S_PRICE_PRECISION.
                assembly {
                    x := div(
                        1000000000000000000000000000000000000000000000000000000000000000000000000,
                        x
                    )
                }
            }

            // Calculate the integer part of the logarithm and add it to the result and finally calculate y = x * 2^(-n).
            uint256 n = uint256(x / Constants.S_PRICE_PRECISION)
                .mostSignificantBit();

            // The integer part of the logarithm as a signed 40.36-decimal fixed-point number. The operation can't overflow
            // because n is maximum 255, Constants.S_PRICE_PRECISION is 1e36 and sign is either 1 or -1.
            result = int256(n) * Constants.S_PRICE_PRECISION;

            // This is y = x * 2^(-n).
            int256 y = x >> n;

            // If y = 1, the fractional part is zero.
            if (y == Constants.S_PRICE_PRECISION) {
                return result * sign;
            }

            // Calculate the fractional part via the iterative approximation.
            // The "delta >>= 1" part is equivalent to "delta /= 2", but shifting bits is faster.
            for (
                int256 delta = int256(Constants.S_HALF_PRICE_PRECISION);
                delta > 0;
                delta >>= 1
            ) {
                y = int256(
                    uint256(y).mulDivRoundDown(
                        uint256(y),
                        uint256(Constants.S_PRICE_PRECISION)
                    )
                );

                // Is y^2 > 2 and so in the range [2,4)?
                if (y >= 2 * Constants.S_PRICE_PRECISION) {
                    // Add the 2^(-m) factor to the logarithm.
                    result += delta;

                    // Corresponds to z/2 on Wikipedia.
                    y >>= 1;
                }
            }
            result *= sign;
        }
    }
}
