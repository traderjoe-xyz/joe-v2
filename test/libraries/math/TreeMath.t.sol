// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../../src/libraries/math/TreeMath.sol";

contract TreeMathTest is Test {
    using TreeMath for TreeMath.TreeUint24;

    TreeMath.TreeUint24 private _tree;

    function testFuzz_AddToTree(uint24[] calldata ids) external {
        for (uint256 i = 0; i < ids.length; i++) {
            bool contains = _tree.contains(ids[i]);
            assertEq(_tree.add(ids[i]), !contains, "testFuzz_AddToTree::1");
            assertEq(_tree.contains(ids[i]), true, "testFuzz_AddToTree::2");
        }
    }

    function testFuzz_RemoveFromTree(uint24[] calldata ids) external {
        for (uint256 i = 0; i < ids.length; i++) {
            _tree.add(ids[i]);
        }

        for (uint256 i = 0; i < ids.length; i++) {
            bool contains = _tree.contains(ids[i]);
            assertEq(_tree.remove(ids[i]), contains, "testFuzz_RemoveFromTree::1");
            assertEq(_tree.contains(ids[i]), false, "testFuzz_RemoveFromTree::2");
        }
    }

    function testFuzz_AddAndRemove(uint24 id) external {
        _tree.add(id);

        assertEq(_tree.contains(id), true, "testFuzz_AddAndRemove::1");

        assertGt(uint256(_tree.level0), 0, "testFuzz_AddAndRemove::2");
        assertGt(uint256(_tree.level1[bytes32(uint256(id >> 16))]), 0, "testFuzz_AddAndRemove::3");
        assertGt(uint256(_tree.level2[bytes32(uint256(id >> 8))]), 0, "testFuzz_AddAndRemove::4");

        _tree.remove(id);

        assertEq(_tree.contains(id), false, "testFuzz_AddAndRemove::5");

        assertEq(uint256(_tree.level0), 0, "testFuzz_AddAndRemove::6");
        assertEq(uint256(_tree.level1[bytes32(uint256(id >> 16))]), 0, "testFuzz_AddAndRemove::7");
        assertEq(uint256(_tree.level2[bytes32(uint256(id >> 8))]), 0, "testFuzz_AddAndRemove::8");
    }

    function testFuzz_RemoveLogicAndSearchRight(uint24 id) external {
        vm.assume(id > 0);

        _tree.add(id);
        _tree.add(id - 1);

        assertEq(_tree.findFirstRight(id), id - 1, "testFuzz_RemoveLogicAndSearchRight::1");

        _tree.remove(id - 1);
        assertEq(_tree.findFirstRight(id), type(uint24).max, "testFuzz_RemoveLogicAndSearchRight::2");
    }

    function testFuzz_RemoveLogicAndSearchLeft(uint24 id) external {
        vm.assume(id < type(uint24).max);

        _tree.add(id);
        _tree.add(id + 1);
        assertEq(_tree.findFirstLeft(id), id + 1, "testFuzz_RemoveLogicAndSearchLeft::1");

        _tree.remove(id + 1);
        assertEq(_tree.findFirstLeft(id), 0, "testFuzz_RemoveLogicAndSearchLeft::2");
    }

    function test_FindFirst() external {
        _tree.add(0);
        _tree.add(1);
        _tree.add(2);

        assertEq(_tree.findFirstRight(2), 1, "test_FindFirst::1");
        assertEq(_tree.findFirstRight(1), 0, "test_FindFirst::2");

        assertEq(_tree.findFirstLeft(0), 1, "test_FindFirst::3");
        assertEq(_tree.findFirstLeft(1), 2, "test_FindFirst::4");

        assertEq(_tree.findFirstRight(0), type(uint24).max, "test_FindFirst::5");
        assertEq(_tree.findFirstLeft(2), 0, "test_FindFirst::6");
    }

    function test_FindFirstFar() external {
        _tree.add(0);
        _tree.add(type(uint24).max);

        assertEq(_tree.findFirstRight(type(uint24).max), 0, "test_FindFirstFar::1");

        assertEq(_tree.findFirstLeft(0), type(uint24).max, "test_FindFirstFar::2");
    }

    function testFuzz_FindFirst(uint24[] calldata ids) external {
        vm.assume(ids.length > 0);

        for (uint256 i = 0; i < ids.length; i++) {
            _tree.add(ids[i]);
        }

        for (uint256 i = 0; i < ids.length; i++) {
            uint24 id = ids[i];

            uint24 firstRight = _tree.findFirstRight(id);
            uint24 firstLeft = _tree.findFirstLeft(id);

            if (firstRight != type(uint24).max) {
                assertEq(_tree.contains(firstRight), true, "testFuzz_FindFirst::1");
                assertEq(firstRight < id, true, "testFuzz_FindFirst::2");
            }

            if (firstLeft != 0) {
                assertEq(_tree.contains(firstLeft), true, "testFuzz_FindFirst::3");
                assertEq(firstLeft > id, true, "testFuzz_FindFirst::4");
            }
        }
    }
}
