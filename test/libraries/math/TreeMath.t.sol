// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

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

    function test_FindFirst() external {
        _tree.add(0);
        _tree.add(1);
        _tree.add(2);

        assertEq(_tree.findFirstRight(2), 1, "testFuzz_FindFirst::1");
        assertEq(_tree.findFirstRight(1), 0, "testFuzz_FindFirst::2");

        assertEq(_tree.findFirstLeft(0), 1, "testFuzz_FindFirst::3");
        assertEq(_tree.findFirstLeft(1), 2, "testFuzz_FindFirst::4");

        assertEq(_tree.findFirstRight(0), type(uint24).max, "testFuzz_FindFirst::5");
        assertEq(_tree.findFirstLeft(2), 0, "testFuzz_FindFirst::6");
    }

    function test_FindFirstFar() external {
        _tree.add(0);
        _tree.add(type(uint24).max);

        assertEq(_tree.findFirstRight(type(uint24).max), 0, "testFuzz_FindFirstFar::1");

        assertEq(_tree.findFirstLeft(0), type(uint24).max, "testFuzz_FindFirstFar::2");
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
