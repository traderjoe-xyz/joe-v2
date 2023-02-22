// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../../src/libraries/math/Encoded.sol";

contract EncodedTest is Test {
    using Encoded for bytes32;

    function testFuzz_Set(bytes32 x, uint256 v, uint256 mask, uint256 offset) external {
        bytes32 y = x.set(v, mask, offset);

        bytes32 expected = x;
        expected &= bytes32(~(mask << offset));
        expected |= bytes32((v & mask) << offset);

        assertEq(y, expected, "test_Set::1");
    }

    function testFuzz_Decode(bytes32 x, uint256 mask, uint256 offset) external {
        uint256 v = x.decode(mask, offset);
        assertEq(v, (uint256(x) >> offset) & mask, "test_Decode::1");
    }

    function testFuzz_SetAndDecode(bytes32 x, uint256 v, uint256 mask, uint256 offset) external {
        bytes32 y = x.set(v, mask, offset);
        uint256 v2 = y.decode(mask, offset);

        assertEq(v2, ((v << offset) >> offset) & mask, "test_SetAndDecode::1");
    }

    function testFuzz_decodeBool(bytes32 x, uint256 offset) external {
        bool v = x.decodeBool(offset);
        assertEq(v ? 1 : 0, (uint256(x) >> offset) & 1, "test_decodeUint1::1");
    }

    function testFuzz_decodeUint8(bytes32 x, uint256 offset) external {
        uint256 v = x.decodeUint8(offset);
        assertEq(v, (uint256(x) >> offset) & 0xff, "test_decodeUint8::1");
    }

    function testFuzz_decodeUint12(bytes32 x, uint256 offset) external {
        uint256 v = x.decodeUint12(offset);
        assertEq(v, (uint256(x) >> offset) & 0xfff, "test_decodeUint12::1");
    }

    function testFuzz_decodeUint14(bytes32 x, uint256 offset) external {
        uint256 v = x.decodeUint14(offset);
        assertEq(v, (uint256(x) >> offset) & 0x3fff, "test_decodeUint14::1");
    }

    function testFuzz_decodeUint16(bytes32 x, uint256 offset) external {
        uint256 v = x.decodeUint16(offset);
        assertEq(v, (uint256(x) >> offset) & 0xffff, "test_decodeUint16::1");
    }

    function testFuzz_decodeUint20(bytes32 x, uint256 offset) external {
        uint256 v = x.decodeUint20(offset);
        assertEq(v, (uint256(x) >> offset) & 0xfffff, "test_decodeUint20::1");
    }

    function testFuzz_decodeUint24(bytes32 x, uint256 offset) external {
        uint256 v = x.decodeUint24(offset);
        assertEq(v, (uint256(x) >> offset) & 0xffffff, "test_decodeUint24::1");
    }

    function testFuzz_decodeUint40(bytes32 x, uint256 offset) external {
        uint256 v = x.decodeUint40(offset);
        assertEq(v, (uint256(x) >> offset) & 0xffffffffff, "test_decodeUint40::1");
    }

    function testFuzz_decodeUint64(bytes32 x, uint256 offset) external {
        uint256 v = x.decodeUint64(offset);
        assertEq(v, (uint256(x) >> offset) & 0xffffffffffffffff, "test_decodeUint64::1");
    }

    function testFuzz_decodeUint128(bytes32 x, uint256 offset) external {
        uint256 v = x.decodeUint128(offset);
        assertEq(v, (uint256(x) >> offset) & 0xffffffffffffffffffffffffffffffff, "test_decodeUint128::1");
    }
}
