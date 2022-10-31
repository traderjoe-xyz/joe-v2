// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract BinHelperTest is TestHelper {
    function testInversePriceForOppositeBins() public {
        assertApproxEqAbs(
            (getPriceFromId(ID_ONE + 10) * getPriceFromId(ID_ONE - 10)) / Constants.SCALE,
            Constants.SCALE,
            1
        );

        assertApproxEqAbs(
            (getPriceFromId(ID_ONE + 1_000) * getPriceFromId(ID_ONE - 1_000)) / Constants.SCALE,
            Constants.SCALE,
            1
        );

        assertApproxEqAbs(
            (getPriceFromId(ID_ONE + 10_000) * getPriceFromId(ID_ONE - 10_000)) / Constants.SCALE,
            Constants.SCALE,
            1
        );
    }
}
