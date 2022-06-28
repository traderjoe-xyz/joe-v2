// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract BinHelperTest is TestHelper {
    function testInversePriceForOppositeBins() public {
        assertApproxEqRel(
            (getPriceFromId(ID_ONE + 10) * getPriceFromId(ID_ONE - 10)) / 1e36,
            1e36,
            1
        );

        assertApproxEqRel(
            (getPriceFromId(ID_ONE + 1_000) * getPriceFromId(ID_ONE - 1_000)) /
                1e36,
            1e36,
            1
        );

        assertApproxEqRel(
            (getPriceFromId(ID_ONE + 10_000) *
                getPriceFromId(ID_ONE - 10_000)) / 1e36,
            1e36,
            1
        );
    }
}
