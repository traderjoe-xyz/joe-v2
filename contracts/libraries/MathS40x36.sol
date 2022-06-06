// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./Math512Bits.sol";
import "./BitMath.sol";

/// @notice Emitted when the input is less than or equal to zero.
error Math__LogInputTooSmall(int256 x);

/// @notice Emitted when the input is greater than 192.
error Math__Exp2InputTooBig(int256 x);

library MathS40x36 {
    using Math512Bits for uint256;
    using BitMath for uint256;

    int256 internal constant SCALE = 1e36;
    int256 private constant HALF_SCALE = 5e35;

    /// @notice Calculates the binary exponent of x using the binary fraction method.
    ///
    /// @dev See https://ethereum.stackexchange.com/q/79903/24693.
    ///
    /// Requirements:
    /// - x must be 128 or less.
    /// - The result must fit within MAX_SD40x36.
    ///
    /// Caveats:
    /// - For any x less than -119_589411415945044523331499461618046331, the result is zero.
    ///
    /// @param x The exponent as a signed 40.36-decimal fixed-point number.
    /// @return result The result as a signed 40.36-decimal fixed-point number.
    function exp2(int256 x) internal pure returns (int256 result) {
        unchecked {
            // This works because 2^(-x) = 1/2^x.
            if (x < 0) {
                // 2^119.589411415945044523331499461618046331 is the maximum number whose inverse does not truncate down to zero.
                if (x < -119_589411415945044523331499461618046331) {
                    return 0;
                }

                // Do the fixed-point inversion inline to save gas. The numerator is SCALE * SCALE.

                result = 1e72 / exp2(-x);
            } else {
                // 2^128 doesn't fit within the 128.128-bit format used internally in this function.
                if (x >= 128e36) {
                    revert Math__Exp2InputTooBig(x);
                }

                // Convert x to the 128.128-bit fixed-point format.
                uint256 x128x128 = (uint256(x) << 128) / uint256(SCALE);

                // Safe to convert the result to int256 directly because the maximum input allowed is 128.
                result = int256(_exp2(x128x128));
            }
        }
    }

    /// @notice Calculates the binary exponent of x using the binary fraction method.
    /// @dev Has to use 128.128-bit fixed-point numbers.
    /// See https://ethereum.stackexchange.com/a/96594/24693.
    /// @param x The exponent as an unsigned 128.128-bit fixed-point number.
    /// @return result The result as an unsigned 41.36-decimal fixed-point number.
    function _exp2(uint256 x) private pure returns (uint256 result) {
        unchecked {
            // Start from 0.5 in the 128.128-bit fixed-point format.
            result = 0x80000000000000000000000000000000;

            // Multiply the result by root(2, 2^-i) when the bit at position i is 1. None of the intermediary results overflows
            // because the initial result is 2^127 and all magic factors are less than 2^129.
            if (x & 0x80000000000000000000000000000000 != 0) {
                result = (result * 0x16A09E667F3BCC908B2FB1366EA957D3E) >> 128;
            }
            if (x & 0x40000000000000000000000000000000 != 0) {
                result = (result * 0x1306FE0A31B7152DE8D5A46305C85EDED) >> 128;
            }
            if (x & 0x20000000000000000000000000000000 != 0) {
                result = (result * 0x1172B83C7D517ADCDF7C8C50EB14A7920) >> 128;
            }
            if (x & 0x10000000000000000000000000000000 != 0) {
                result = (result * 0x10B5586CF9890F6298B92B71842A98364) >> 128;
            }
            if (x & 0x8000000000000000000000000000000 != 0) {
                result = (result * 0x1059B0D31585743AE7C548EB68CA417FE) >> 128;
            }
            if (x & 0x4000000000000000000000000000000 != 0) {
                result = (result * 0x102C9A3E778060EE6F7CACA4F7A29BDE9) >> 128;
            }
            if (x & 0x2000000000000000000000000000000 != 0) {
                result = (result * 0x10163DA9FB33356D84A66AE336DCDFA40) >> 128;
            }
            if (x & 0x1000000000000000000000000000000 != 0) {
                result = (result * 0x100B1AFA5ABCBED6129AB13EC11DC9544) >> 128;
            }
            if (x & 0x800000000000000000000000000000 != 0) {
                result = (result * 0x10058C86DA1C09EA1FF19D294CF2F679C) >> 128;
            }
            if (x & 0x400000000000000000000000000000 != 0) {
                result = (result * 0x1002C605E2E8CEC506D21BFC89A23A010) >> 128;
            }
            if (x & 0x200000000000000000000000000000 != 0) {
                result = (result * 0x100162F3904051FA128BCA9C55C31E5E0) >> 128;
            }
            if (x & 0x100000000000000000000000000000 != 0) {
                result = (result * 0x1000B175EFFDC76BA38E31671CA939726) >> 128;
            }
            if (x & 0x80000000000000000000000000000 != 0) {
                result = (result * 0x100058BA01FB9F96D6CACD4B180917C3E) >> 128;
            }
            if (x & 0x40000000000000000000000000000 != 0) {
                result = (result * 0x10002C5CC37DA9491D0985C348C68E7B4) >> 128;
            }
            if (x & 0x20000000000000000000000000000 != 0) {
                result = (result * 0x1000162E525EE054754457D5995292027) >> 128;
            }
            if (x & 0x10000000000000000000000000000 != 0) {
                result = (result * 0x10000B17255775C040618BF4A4ADE83FD) >> 128;
            }
            if (x & 0x8000000000000000000000000000 != 0) {
                result = (result * 0x1000058B91B5BC9AE2EED81E9B7D4CFAC) >> 128;
            }
            if (x & 0x4000000000000000000000000000 != 0) {
                result = (result * 0x100002C5C89D5EC6CA4D7C8ACC017B7CA) >> 128;
            }
            if (x & 0x2000000000000000000000000000 != 0) {
                result = (result * 0x10000162E43F4F831060E02D839A9D16E) >> 128;
            }
            if (x & 0x1000000000000000000000000000 != 0) {
                result = (result * 0x100000B1721BCFC99D9F890EA06911764) >> 128;
            }
            if (x & 0x800000000000000000000000000 != 0) {
                result = (result * 0x10000058B90CF1E6D97F9CA14DBCC1629) >> 128;
            }
            if (x & 0x400000000000000000000000000 != 0) {
                result = (result * 0x1000002C5C863B73F016468F6BAC5CA2C) >> 128;
            }
            if (x & 0x200000000000000000000000000 != 0) {
                result = (result * 0x100000162E430E5A18F6119E3C02282A6) >> 128;
            }
            if (x & 0x100000000000000000000000000 != 0) {
                result = (result * 0x1000000B1721835514B86E6D96EFD1BFF) >> 128;
            }
            if (x & 0x80000000000000000000000000 != 0) {
                result = (result * 0x100000058B90C0B48C6BE5DF846C5B2F0) >> 128;
            }
            if (x & 0x40000000000000000000000000 != 0) {
                result = (result * 0x10000002C5C8601CC6B9E94213C72737B) >> 128;
            }
            if (x & 0x20000000000000000000000000 != 0) {
                result = (result * 0x1000000162E42FFF037DF38AA2B219F07) >> 128;
            }
            if (x & 0x10000000000000000000000000 != 0) {
                result = (result * 0x10000000B17217FBA9C739AA5819F44FA) >> 128;
            }
            if (x & 0x8000000000000000000000000 != 0) {
                result = (result * 0x1000000058B90BFCDEE5ACD3C1CEDC824) >> 128;
            }
            if (x & 0x4000000000000000000000000 != 0) {
                result = (result * 0x100000002C5C85FE31F35A6A30DA1BE51) >> 128;
            }
            if (x & 0x2000000000000000000000000 != 0) {
                result = (result * 0x10000000162E42FF0999CE3541B9FFFD0) >> 128;
            }
            if (x & 0x1000000000000000000000000 != 0) {
                result = (result * 0x100000000B17217F80F4EF5AADDA45555) >> 128;
            }
            if (x & 0x800000000000000000000000 != 0) {
                result = (result * 0x10000000058B90BFBF8479BD5A81B51AE) >> 128;
            }
            if (x & 0x400000000000000000000000 != 0) {
                result = (result * 0x1000000002C5C85FDF84BD62AE30A74CD) >> 128;
            }
            if (x & 0x200000000000000000000000 != 0) {
                result = (result * 0x100000000162E42FEFB2FED257559BDAB) >> 128;
            }
            if (x & 0x100000000000000000000000 != 0) {
                result = (result * 0x1000000000B17217F7D5A7716BBA4A9AF) >> 128;
            }
            if (x & 0x80000000000000000000000 != 0) {
                result = (result * 0x100000000058B90BFBE9DDBAC5E109CCF) >> 128;
            }
            if (x & 0x40000000000000000000000 != 0) {
                result = (result * 0x10000000002C5C85FDF4B15DE6F17EB0E) >> 128;
            }
            if (x & 0x20000000000000000000000 != 0) {
                result = (result * 0x1000000000162E42FEFA494F1478FDE06) >> 128;
            }
            if (x & 0x10000000000000000000000 != 0) {
                result = (result * 0x10000000000B17217F7D20CF927C8E94D) >> 128;
            }
            if (x & 0x8000000000000000000000 != 0) {
                result = (result * 0x1000000000058B90BFBE8F71CB4E4B33E) >> 128;
            }
            if (x & 0x4000000000000000000000 != 0) {
                result = (result * 0x100000000002C5C85FDF477B662B26946) >> 128;
            }
            if (x & 0x2000000000000000000000 != 0) {
                result = (result * 0x10000000000162E42FEFA3AE53369388D) >> 128;
            }
            if (x & 0x1000000000000000000000 != 0) {
                result = (result * 0x100000000000B17217F7D1D351A389D41) >> 128;
            }
            if (x & 0x800000000000000000000 != 0) {
                result = (result * 0x10000000000058B90BFBE8E8B2D3D4EDF) >> 128;
            }
            if (x & 0x400000000000000000000 != 0) {
                result = (result * 0x1000000000002C5C85FDF4741BEA6E77F) >> 128;
            }
            if (x & 0x200000000000000000000 != 0) {
                result = (result * 0x100000000000162E42FEFA39FE95583C3) >> 128;
            }
            if (x & 0x100000000000000000000 != 0) {
                result = (result * 0x1000000000000B17217F7D1CFB72B45E2) >> 128;
            }
            if (x & 0x80000000000000000000 != 0) {
                result = (result * 0x100000000000058B90BFBE8E7CC35C3F1) >> 128;
            }
            if (x & 0x40000000000000000000 != 0) {
                result = (result * 0x10000000000002C5C85FDF473E242EA39) >> 128;
            }
            if (x & 0x20000000000000000000 != 0) {
                result = (result * 0x1000000000000162E42FEFA39F02B772D) >> 128;
            }
            if (x & 0x10000000000000000000 != 0) {
                result = (result * 0x10000000000000B17217F7D1CF7D83C1B) >> 128;
            }
            if (x & 0x8000000000000000000 != 0) {
                result = (result * 0x1000000000000058B90BFBE8E7BDCBE2F) >> 128;
            }
            if (x & 0x4000000000000000000 != 0) {
                result = (result * 0x100000000000002C5C85FDF473DEA8720) >> 128;
            }
            if (x & 0x2000000000000000000 != 0) {
                result = (result * 0x10000000000000162E42FEFA39EF44D92) >> 128;
            }
            if (x & 0x1000000000000000000 != 0) {
                result = (result * 0x100000000000000B17217F7D1CF79E94A) >> 128;
            }
            if (x & 0x800000000000000000 != 0) {
                result = (result * 0x10000000000000058B90BFBE8E7BCE545) >> 128;
            }
            if (x & 0x400000000000000000 != 0) {
                result = (result * 0x1000000000000002C5C85FDF473DE6ECB) >> 128;
            }
            if (x & 0x200000000000000000 != 0) {
                result = (result * 0x100000000000000162E42FEFA39EF3670) >> 128;
            }
            if (x & 0x100000000000000000 != 0) {
                result = (result * 0x1000000000000000B17217F7D1CF79AFB) >> 128;
            }
            if (x & 0x80000000000000000 != 0) {
                result = (result * 0x100000000000000058B90BFBE8E7BCD6E) >> 128;
            }
            if (x & 0x40000000000000000 != 0) {
                result = (result * 0x10000000000000002C5C85FDF473DE6B3) >> 128;
            }
            if (x & 0x20000000000000000 != 0) {
                result = (result * 0x1000000000000000162E42FEFA39EF359) >> 128;
            }
            if (x & 0x10000000000000000 != 0) {
                result = (result * 0x10000000000000000B17217F7D1CF79AC) >> 128;
            }
            if (x & 0x8000000000000000 != 0) {
                result = (result * 0x1000000000000000058B90BFBE8E7BCD6) >> 128;
            }
            if (x & 0x4000000000000000 != 0) {
                result = (result * 0x100000000000000002C5C85FDF473DE6B) >> 128;
            }
            if (x & 0x2000000000000000 != 0) {
                result = (result * 0x10000000000000000162E42FEFA39EF35) >> 128;
            }
            if (x & 0x1000000000000000 != 0) {
                result = (result * 0x100000000000000000B17217F7D1CF79A) >> 128;
            }
            if (x & 0x800000000000000 != 0) {
                result = (result * 0x10000000000000000058B90BFBE8E7BCD) >> 128;
            }
            if (x & 0x400000000000000 != 0) {
                result = (result * 0x1000000000000000002C5C85FDF473DE6) >> 128;
            }
            if (x & 0x200000000000000 != 0) {
                result = (result * 0x100000000000000000162E42FEFA39EF3) >> 128;
            }
            if (x & 0x100000000000000 != 0) {
                result = (result * 0x1000000000000000000B17217F7D1CF79) >> 128;
            }
            if (x & 0x80000000000000 != 0) {
                result = (result * 0x100000000000000000058B90BFBE8E7BC) >> 128;
            }
            if (x & 0x40000000000000 != 0) {
                result = (result * 0x10000000000000000002C5C85FDF473DE) >> 128;
            }
            if (x & 0x20000000000000 != 0) {
                result = (result * 0x1000000000000000000162E42FEFA39EF) >> 128;
            }
            if (x & 0x10000000000000 != 0) {
                result = (result * 0x10000000000000000000B17217F7D1CF7) >> 128;
            }
            if (x & 0x8000000000000 != 0) {
                result = (result * 0x1000000000000000000058B90BFBE8E7B) >> 128;
            }
            if (x & 0x4000000000000 != 0) {
                result = (result * 0x100000000000000000002C5C85FDF473D) >> 128;
            }
            if (x & 0x2000000000000 != 0) {
                result = (result * 0x10000000000000000000162E42FEFA39E) >> 128;
            }
            if (x & 0x1000000000000 != 0) {
                result = (result * 0x100000000000000000000B17217F7D1CF) >> 128;
            }
            if (x & 0x800000000000 != 0) {
                result = (result * 0x10000000000000000000058B90BFBE8E7) >> 128;
            }
            if (x & 0x400000000000 != 0) {
                result = (result * 0x1000000000000000000002C5C85FDF473) >> 128;
            }
            if (x & 0x200000000000 != 0) {
                result = (result * 0x100000000000000000000162E42FEFA39) >> 128;
            }
            if (x & 0x100000000000 != 0) {
                result = (result * 0x1000000000000000000000B17217F7D1C) >> 128;
            }
            if (x & 0x80000000000 != 0) {
                result = (result * 0x100000000000000000000058B90BFBE8E) >> 128;
            }
            if (x & 0x40000000000 != 0) {
                result = (result * 0x10000000000000000000002C5C85FDF47) >> 128;
            }
            if (x & 0x20000000000 != 0) {
                result = (result * 0x1000000000000000000000162E42FEFA3) >> 128;
            }
            if (x & 0x10000000000 != 0) {
                result = (result * 0x10000000000000000000000B17217F7D1) >> 128;
            }
            if (x & 0x8000000000 != 0) {
                result = (result * 0x1000000000000000000000058B90BFBE8) >> 128;
            }
            if (x & 0x4000000000 != 0) {
                result = (result * 0x100000000000000000000002C5C85FDF4) >> 128;
            }
            if (x & 0x2000000000 != 0) {
                result = (result * 0x10000000000000000000000162E42FEFA) >> 128;
            }
            if (x & 0x1000000000 != 0) {
                result = (result * 0x100000000000000000000000B17217F7D) >> 128;
            }
            if (x & 0x800000000 != 0) {
                result = (result * 0x10000000000000000000000058B90BFBE) >> 128;
            }
            if (x & 0x400000000 != 0) {
                result = (result * 0x1000000000000000000000002C5C85FDF) >> 128;
            }
            if (x & 0x200000000 != 0) {
                result = (result * 0x100000000000000000000000162E42FEF) >> 128;
            }
            if (x & 0x100000000 != 0) {
                result = (result * 0x1000000000000000000000000B17217F7) >> 128;
            }
            if (x & 0x80000000 != 0) {
                result = (result * 0x100000000000000000000000058B90BFB) >> 128;
            }
            if (x & 0x40000000 != 0) {
                result = (result * 0x10000000000000000000000002C5C85FD) >> 128;
            }
            if (x & 0x20000000 != 0) {
                result = (result * 0x1000000000000000000000000162E42FE) >> 128;
            }
            if (x & 0x10000000 != 0) {
                result = (result * 0x10000000000000000000000000B17217F) >> 128;
            }
            if (x & 0x8000000 != 0) {
                result = (result * 0x1000000000000000000000000058B90BF) >> 128;
            }
            if (x & 0x4000000 != 0) {
                result = (result * 0x100000000000000000000000002C5C85F) >> 128;
            }
            if (x & 0x2000000 != 0) {
                result = (result * 0x10000000000000000000000000162E42F) >> 128;
            }
            if (x & 0x1000000 != 0) {
                result = (result * 0x100000000000000000000000000B17217) >> 128;
            }
            if (x & 0x800000 != 0) {
                result = (result * 0x10000000000000000000000000058B90B) >> 128;
            }
            if (x & 0x400000 != 0) {
                result = (result * 0x1000000000000000000000000002C5C85) >> 128;
            }
            if (x & 0x200000 != 0) {
                result = (result * 0x100000000000000000000000000162E42) >> 128;
            }
            if (x & 0x100000 != 0) {
                result = (result * 0x1000000000000000000000000000B1721) >> 128;
            }
            if (x & 0x80000 != 0) {
                result = (result * 0x100000000000000000000000000058B90) >> 128;
            }
            if (x & 0x40000 != 0) {
                result = (result * 0x10000000000000000000000000002C5C8) >> 128;
            }
            if (x & 0x20000 != 0) {
                result = (result * 0x1000000000000000000000000000162E4) >> 128;
            }
            if (x & 0x10000 != 0) {
                result = (result * 0x10000000000000000000000000000B172) >> 128;
            }
            if (x & 0x8000 != 0) {
                result = (result * 0x1000000000000000000000000000058B9) >> 128;
            }
            if (x & 0x4000 != 0) {
                result = (result * 0x100000000000000000000000000002C5C) >> 128;
            }
            if (x & 0x2000 != 0) {
                result = (result * 0x10000000000000000000000000000162E) >> 128;
            }
            if (x & 0x1000 != 0) {
                result = (result * 0x100000000000000000000000000000B17) >> 128;
            }
            if (x & 0x800 != 0) {
                result = (result * 0x10000000000000000000000000000058B) >> 128;
            }
            if (x & 0x400 != 0) {
                result = (result * 0x1000000000000000000000000000002C5) >> 128;
            }
            if (x & 0x200 != 0) {
                result = (result * 0x100000000000000000000000000000162) >> 128;
            }
            if (x & 0x100 != 0) {
                result = (result * 0x1000000000000000000000000000000B1) >> 128;
            }
            if (x & 0x80 != 0) {
                result = (result * 0x100000000000000000000000000000058) >> 128;
            }
            if (x & 0x40 != 0) {
                result = (result * 0x10000000000000000000000000000002C) >> 128;
            }
            if (x & 0x20 != 0) {
                result = (result * 0x100000000000000000000000000000016) >> 128;
            }
            if (x & 0x10 != 0) {
                result = (result * 0x10000000000000000000000000000000B) >> 128;
            }
            if (x & 0x8 != 0) {
                result = (result * 0x100000000000000000000000000000005) >> 128;
            }
            if (x & 0x4 != 0) {
                result = (result * 0x100000000000000000000000000000002) >> 128;
            }
            if (x & 0x2 != 0) {
                result = (result * 0x100000000000000000000000000000001) >> 128;
            }

            // We're doing two things at the same time:
            //
            //   1. Multiply the result by 2^n + 1, where "2^n" is the integer part and the one is added to account for
            //      the fact that we initially set the result to 0.5. This is accomplished by subtracting from 127
            //      rather than 128.
            //   2. Convert the result to the unsigned 41.36-decimal fixed-point format.
            //
            // This works because 2^(127-ip) = 2^ip / 2^127, where "ip" is the integer part "2^n".
            result *= uint256(SCALE);
            result >>= (127 - (x >> 128));
        }
    }

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
            if (x >= SCALE) {
                sign = 1;
            } else {
                sign = -1;
                // Do the fixed-point inversion inline to save gas. The numerator is SCALE * SCALE.
                assembly {
                    x := div(
                        1000000000000000000000000000000000000000000000000000000000000000000000000,
                        x
                    )
                }
            }

            // Calculate the integer part of the logarithm and add it to the result and finally calculate y = x * 2^(-n).
            uint256 n = uint256(x / SCALE).mostSignificantBit();

            // The integer part of the logarithm as a signed 40.36-decimal fixed-point number. The operation can't overflow
            // because n is maximum 255, SCALE is 1e18 and sign is either 1 or -1.
            result = int256(n) * SCALE;

            // This is y = x * 2^(-n).
            int256 y = x >> n;

            // If y = 1, the fractional part is zero.
            if (y == SCALE) {
                return result * sign;
            }

            // Calculate the fractional part via the iterative approximation.
            // The "delta >>= 1" part is equivalent to "delta /= 2", but shifting bits is faster.
            for (int256 delta = int256(HALF_SCALE); delta > 0; delta >>= 1) {
                y = int256(
                    uint256(y).mulDivRoundDown(uint256(y), uint256(SCALE))
                );

                // Is y^2 > 2 and so in the range [2,4)?
                if (y >= 2 * SCALE) {
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
