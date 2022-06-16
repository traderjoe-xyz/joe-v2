// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "forge-std/Test.sol";
import "src/LBPair.sol";
import "src/LBFactory.sol";
import "src/mocks/ERC20MockDecimals.sol";
import {console} from "forge-std/console.sol";

contract LiquidityBinPairTest is Test {
    address private constant DEV = 0x1119fbb02F38764CD90F2d9fB35FeDcd8378ac2A;
    LBPair private lbPair;
    ERC20MockDecimals private token6D;
    ERC20MockDecimals private token12D;

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token12D = new ERC20MockDecimals(12);
        lbPair = new LBPair(
            LBFactory(DEV),
            token6D,
            token12D,
            int256(0xb19a9e77af6827457b6619208c48),
            bytes32(
                abi.encodePacked(
                    uint8(0),
                    uint16(5_000),
                    uint16(1_000),
                    uint16(25),
                    uint16(100),
                    uint16(10),
                    uint168(50 * 10_000)
                )
            )
        );
    }

    function testConstructorParameters() public {
        assertEq(address(lbPair.factory()), DEV);
        assertEq(address(lbPair.tokenX()), address(token6D));
        assertEq(address(lbPair.tokenY()), address(token12D));

        FeeHelper.FeeParameters memory feeParameters = lbPair.feeParameters();
        assertEq(feeParameters.accumulator, 0);
        assertEq(feeParameters.time, 0);
        assertEq(feeParameters.maxAccumulator, 50 * 10_000);
        assertEq(feeParameters.filterPeriod, 10);
        assertEq(feeParameters.decayPeriod, 100);
        assertEq(feeParameters.binStep, 25);
        assertEq(feeParameters.baseFactor, 1_000);
        assertEq(feeParameters.protocolShare, 5_000);
        assertEq(feeParameters.variableFeeDisabled, 0);
    }
}
