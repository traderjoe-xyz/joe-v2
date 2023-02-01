// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../src/libraries/PriceHelper.sol";

contract PriceHelperTest is Test {
    using Uint256x256Math for uint256;

    Math immutable math = new Math();

    function testFuzz_GetBase(uint8 binStep) external {
        uint256 base128x128 = PriceHelper.getBase(binStep);
        uint256 expectedBase128x128 = (1 << 128) + (uint256(binStep) << 128) / 20_000;

        assertEq(base128x128, expectedBase128x128, "test_GetBase::1");
    }

    function testFuzz_GetExponent(uint24 id) external {
        int256 exponent128x128 = PriceHelper.getExponent(id);
        int256 expectedExponent128x128 = int256(uint256(id)) - (1 << 23);

        assertEq(exponent128x128, expectedExponent128x128, "test_GetExponent::1");
    }

    function testFuzz_ConvertDecimalPriceTo128x128(uint256 price) external {
        // result of `type(uint256).max * 1e18 >> 128`, this is the largest number before the result overflows
        vm.assume(price <= 340282366920938463463374607431768211455999999999999999999);
        uint256 price128x128 = PriceHelper.convertDecimalPriceTo128x128(price);
        uint256 expectedPrice128x128 = price.shiftDivRoundDown(128, 1e18);

        assertEq(price128x128, expectedPrice128x128, "test_ConvertDecimalPriceTo128x128::1");
    }

    function testFuzz_revert_ConvertDecimalPriceTo128x128(uint256 price) external {
        // result of `type(uint256).max * 1e18 >> 128`, this is the largest number before the result overflows
        vm.assume(price > 340282366920938463463374607431768211455999999999999999999);

        vm.expectRevert(Uint256x256Math.Uint256x256Math__MulDivOverflow.selector);
        PriceHelper.convertDecimalPriceTo128x128(price);
    }

    function testFuzz_Convert128x128PriceToDecimal(uint256 price128x128) external {
        uint256 priceDecimal = PriceHelper.convert128x128PriceToDecimal(price128x128);
        uint256 expectedPriceDecimal = price128x128.mulShiftRoundDown(1e18, 128);

        assertEq(priceDecimal, expectedPriceDecimal, "test_Convert128x128PriceToDecimal::1");
    }

    function testFuzz_Price(uint256 price, uint8 binStep) external {
        // test that all prices from 1e64 to 1e192 are valid, includes 1e-18 to 1e18 in decimal.
        vm.assume(price > 1 << 64 && price < 1 << 192 && binStep > 0 && binStep < 200);

        (bool s, bytes memory data) =
            address(math).staticcall(abi.encodeWithSelector(math.idFromPrice.selector, price, binStep));

        if (s) {
            uint24 id = abi.decode(data, (uint24));
            uint256 calculatedPrice = PriceHelper.getPriceFromId(id, binStep);

            // Can't use `assertApproxEqRel` as it overflow when multiplying by 1e18
            // Assert that price is at most `binStep`% away from the calculated price
            assertLe(
                price * (Constants.TWO_BASIS_POINT_MAX - binStep) / Constants.TWO_BASIS_POINT_MAX,
                calculatedPrice,
                "test_Price::1"
            );
            assertGe(
                price * (Constants.TWO_BASIS_POINT_MAX + binStep) / Constants.TWO_BASIS_POINT_MAX,
                calculatedPrice,
                "test_Price::2"
            );
        }
    }

    function test_Price() external {
        uint24 id = 8761245; // result of `log2(123456789) / log2(1.00005) + 2**23`
        uint256 expectedPrice = PriceHelper.convertDecimalPriceTo128x128(123456789e18);
        assertLe(PriceHelper.getPriceFromId(id - 1, 1), expectedPrice, "test_Price::1");
        assertGe(PriceHelper.getPriceFromId(id + 1, 1), expectedPrice, "test_Price::2");

        id = 8116506; // result of `log2(0.00000123456789) / log2(1.00005) + 2**23`
        expectedPrice = PriceHelper.convertDecimalPriceTo128x128(0.00000123456789e18);
        assertLe(PriceHelper.getPriceFromId(id - 1, 1), expectedPrice, "test_Price::3");
        assertGe(PriceHelper.getPriceFromId(id + 1, 1), expectedPrice, "test_Price::4");

        id = 8392773; // result of `log2(10**18)/log2(1.01) + 2**23`
        expectedPrice = PriceHelper.convertDecimalPriceTo128x128(1e36);
        assertLe(PriceHelper.getPriceFromId(id - 1, 200), expectedPrice, "test_Price::5");
        assertGe(PriceHelper.getPriceFromId(id + 1, 200), expectedPrice, "test_Price::6");
    }
}

contract Math {
    function priceFromId(uint24 id, uint8 binStep) external pure returns (uint256) {
        return PriceHelper.getPriceFromId(id, binStep);
    }

    function idFromPrice(uint256 price, uint8 binStep) external pure returns (uint24) {
        return PriceHelper.getIdFromPrice(price, binStep);
    }
}
