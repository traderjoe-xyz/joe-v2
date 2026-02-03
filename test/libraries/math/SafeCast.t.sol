// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../src/libraries/math/SafeCast.sol";

contract SafeCastTest is Test {
    using SafeCast for uint256;

    ExternalSafeCast private helper;

    function setUp() external {
        helper = new ExternalSafeCast();
    }

    function testFuzz_SafeCast248(uint256 x) external {
        if (x > type(uint248).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds248Bits.selector);
            helper.safe248(x);
        } else {
            assertEq(x.safe248(), uint248(x), "testFuzz_SafeCast248::1");
        }
    }

    function testFuzz_SafeCast240(uint256 x) external {
        if (x > type(uint240).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds240Bits.selector);
            helper.safe240(x);
        } else {
            assertEq(x.safe240(), uint240(x), "testFuzz_SafeCast240::1");
        }
    }

    function testFuzz_SafeCast232(uint256 x) external {
        if (x > type(uint232).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds232Bits.selector);
            helper.safe232(x);
        } else {
            assertEq(x.safe232(), uint232(x), "testFuzz_SafeCast232::1");
        }
    }

    function testFuzz_SafeCast224(uint256 x) external {
        if (x > type(uint224).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds224Bits.selector);
            helper.safe224(x);
        } else {
            assertEq(x.safe224(), uint224(x), "testFuzz_SafeCast224::1");
        }
    }

    function testFuzz_SafeCast216(uint256 x) external {
        if (x > type(uint216).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds216Bits.selector);
            helper.safe216(x);
        } else {
            assertEq(x.safe216(), uint216(x), "testFuzz_SafeCast216::1");
        }
    }

    function testFuzz_SafeCast208(uint256 x) external {
        if (x > type(uint208).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds208Bits.selector);
            helper.safe208(x);
        } else {
            assertEq(x.safe208(), uint208(x), "testFuzz_SafeCast208::1");
        }
    }

    function testFuzz_SafeCast200(uint256 x) external {
        if (x > type(uint200).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds200Bits.selector);
            helper.safe200(x);
        } else {
            assertEq(x.safe200(), uint200(x), "testFuzz_SafeCast200::1");
        }
    }

    function testFuzz_SafeCast192(uint256 x) external {
        if (x > type(uint192).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds192Bits.selector);
            helper.safe192(x);
        } else {
            assertEq(x.safe192(), uint192(x), "testFuzz_SafeCast192::1");
        }
    }

    function testFuzz_SafeCast184(uint256 x) external {
        if (x > type(uint184).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds184Bits.selector);
            helper.safe184(x);
        } else {
            assertEq(x.safe184(), uint184(x), "testFuzz_SafeCast184::1");
        }
    }

    function testFuzz_SafeCast176(uint256 x) external {
        if (x > type(uint176).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds176Bits.selector);
            helper.safe176(x);
        } else {
            assertEq(x.safe176(), uint176(x), "testFuzz_SafeCast176::1");
        }
    }

    function testFuzz_SafeCast168(uint256 x) external {
        if (x > type(uint168).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds168Bits.selector);
            helper.safe168(x);
        } else {
            assertEq(x.safe168(), uint168(x), "testFuzz_SafeCast168::1");
        }
    }

    function testFuzz_SafeCast160(uint256 x) external {
        if (x > type(uint160).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds160Bits.selector);
            helper.safe160(x);
        } else {
            assertEq(x.safe160(), uint160(x), "testFuzz_SafeCast160::1");
        }
    }

    function testFuzz_SafeCast152(uint256 x) external {
        if (x > type(uint152).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds152Bits.selector);
            helper.safe152(x);
        } else {
            assertEq(x.safe152(), uint152(x), "testFuzz_SafeCast152::1");
        }
    }

    function testFuzz_SafeCast144(uint256 x) external {
        if (x > type(uint144).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds144Bits.selector);
            helper.safe144(x);
        } else {
            assertEq(x.safe144(), uint144(x), "testFuzz_SafeCast144::1");
        }
    }

    function testFuzz_SafeCast136(uint256 x) external {
        if (x > type(uint136).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds136Bits.selector);
            helper.safe136(x);
        } else {
            assertEq(x.safe136(), uint136(x), "testFuzz_SafeCast136::1");
        }
    }

    function testFuzz_SafeCast128(uint256 x) external {
        if (x > type(uint128).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds128Bits.selector);
            helper.safe128(x);
        } else {
            assertEq(x.safe128(), uint128(x), "testFuzz_SafeCast128::1");
        }
    }

    function testFuzz_SafeCast120(uint256 x) external {
        if (x > type(uint120).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds120Bits.selector);
            helper.safe120(x);
        } else {
            assertEq(x.safe120(), uint120(x), "testFuzz_SafeCast120::1");
        }
    }

    function testFuzz_SafeCast112(uint256 x) external {
        if (x > type(uint112).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds112Bits.selector);
            helper.safe112(x);
        } else {
            assertEq(x.safe112(), uint112(x), "testFuzz_SafeCast112::1");
        }
    }

    function testFuzz_SafeCast104(uint256 x) external {
        if (x > type(uint104).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds104Bits.selector);
            helper.safe104(x);
        } else {
            assertEq(x.safe104(), uint104(x), "testFuzz_SafeCast104::1");
        }
    }

    function testFuzz_SafeCast96(uint256 x) external {
        if (x > type(uint96).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds96Bits.selector);
            helper.safe96(x);
        } else {
            assertEq(x.safe96(), uint96(x), "testFuzz_SafeCast96::1");
        }
    }

    function testFuzz_SafeCast88(uint256 x) external {
        if (x > type(uint88).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds88Bits.selector);
            helper.safe88(x);
        } else {
            assertEq(x.safe88(), uint88(x), "testFuzz_SafeCast88::1");
        }
    }

    function testFuzz_SafeCast80(uint256 x) external {
        if (x > type(uint80).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds80Bits.selector);
            helper.safe80(x);
        } else {
            assertEq(x.safe80(), uint80(x), "testFuzz_SafeCast80::1");
        }
    }

    function testFuzz_SafeCast72(uint256 x) external {
        if (x > type(uint72).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds72Bits.selector);
            helper.safe72(x);
        } else {
            assertEq(x.safe72(), uint72(x), "testFuzz_SafeCast72::1");
        }
    }

    function testFuzz_SafeCast64(uint256 x) external {
        if (x > type(uint64).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds64Bits.selector);
            helper.safe64(x);
        } else {
            assertEq(x.safe64(), uint64(x), "testFuzz_SafeCast64::1");
        }
    }

    function testFuzz_SafeCast56(uint256 x) external {
        if (x > type(uint56).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds56Bits.selector);
            helper.safe56(x);
        } else {
            assertEq(x.safe56(), uint56(x), "testFuzz_SafeCast56::1");
        }
    }

    function testFuzz_SafeCast48(uint256 x) external {
        if (x > type(uint48).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds48Bits.selector);
            helper.safe48(x);
        } else {
            assertEq(x.safe48(), uint48(x), "testFuzz_SafeCast48::1");
        }
    }

    function testFuzz_SafeCast40(uint256 x) external {
        if (x > type(uint40).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds40Bits.selector);
            helper.safe40(x);
        } else {
            assertEq(x.safe40(), uint40(x), "testFuzz_SafeCast40::1");
        }
    }

    function testFuzz_SafeCast32(uint256 x) external {
        if (x > type(uint32).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds32Bits.selector);
            helper.safe32(x);
        } else {
            assertEq(x.safe32(), uint32(x), "testFuzz_SafeCast32::1");
        }
    }

    function testFuzz_SafeCast24(uint256 x) external {
        if (x > type(uint24).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds24Bits.selector);
            helper.safe24(x);
        } else {
            assertEq(x.safe24(), uint24(x), "testFuzz_SafeCast24::1");
        }
    }

    function testFuzz_SafeCast16(uint256 x) external {
        if (x > type(uint16).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds16Bits.selector);
            helper.safe16(x);
        } else {
            assertEq(x.safe16(), uint16(x), "testFuzz_SafeCast16::1");
        }
    }

    function testFuzz_SafeCast8(uint256 x) external {
        if (x > type(uint8).max) {
            vm.expectRevert(SafeCast.SafeCast__Exceeds8Bits.selector);
            helper.safe8(x);
        } else {
            assertEq(x.safe8(), uint8(x), "testFuzz_SafeCast8::1");
        }
    }
}

contract ExternalSafeCast {
    function safe248(uint256 x) external pure returns (uint248) { return SafeCast.safe248(x); }
    function safe240(uint256 x) external pure returns (uint240) { return SafeCast.safe240(x); }
    function safe232(uint256 x) external pure returns (uint232) { return SafeCast.safe232(x); }
    function safe224(uint256 x) external pure returns (uint224) { return SafeCast.safe224(x); }
    function safe216(uint256 x) external pure returns (uint216) { return SafeCast.safe216(x); }
    function safe208(uint256 x) external pure returns (uint208) { return SafeCast.safe208(x); }
    function safe200(uint256 x) external pure returns (uint200) { return SafeCast.safe200(x); }
    function safe192(uint256 x) external pure returns (uint192) { return SafeCast.safe192(x); }
    function safe184(uint256 x) external pure returns (uint184) { return SafeCast.safe184(x); }
    function safe176(uint256 x) external pure returns (uint176) { return SafeCast.safe176(x); }
    function safe168(uint256 x) external pure returns (uint168) { return SafeCast.safe168(x); }
    function safe160(uint256 x) external pure returns (uint160) { return SafeCast.safe160(x); }
    function safe152(uint256 x) external pure returns (uint152) { return SafeCast.safe152(x); }
    function safe144(uint256 x) external pure returns (uint144) { return SafeCast.safe144(x); }
    function safe136(uint256 x) external pure returns (uint136) { return SafeCast.safe136(x); }
    function safe128(uint256 x) external pure returns (uint128) { return SafeCast.safe128(x); }
    function safe120(uint256 x) external pure returns (uint120) { return SafeCast.safe120(x); }
    function safe112(uint256 x) external pure returns (uint112) { return SafeCast.safe112(x); }
    function safe104(uint256 x) external pure returns (uint104) { return SafeCast.safe104(x); }
    function safe96(uint256 x) external pure returns (uint96) { return SafeCast.safe96(x); }
    function safe88(uint256 x) external pure returns (uint88) { return SafeCast.safe88(x); }
    function safe80(uint256 x) external pure returns (uint80) { return SafeCast.safe80(x); }
    function safe72(uint256 x) external pure returns (uint72) { return SafeCast.safe72(x); }
    function safe64(uint256 x) external pure returns (uint64) { return SafeCast.safe64(x); }
    function safe56(uint256 x) external pure returns (uint56) { return SafeCast.safe56(x); }
    function safe48(uint256 x) external pure returns (uint48) { return SafeCast.safe48(x); }
    function safe40(uint256 x) external pure returns (uint40) { return SafeCast.safe40(x); }
    function safe32(uint256 x) external pure returns (uint32) { return SafeCast.safe32(x); }
    function safe24(uint256 x) external pure returns (uint24) { return SafeCast.safe24(x); }
    function safe16(uint256 x) external pure returns (uint16) { return SafeCast.safe16(x); }
    function safe8(uint256 x) external pure returns (uint8) { return SafeCast.safe8(x); }

    // Exclude from coverage
    function test() external pure {}
}
