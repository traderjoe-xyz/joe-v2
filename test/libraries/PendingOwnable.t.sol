// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../src/libraries/PendingOwnable.sol";

contract PendingOwnableTest is Test {
    Foo foo;

    address owner = makeAddr("owner");
    address pendingOwner = makeAddr("pendingOwner");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.prank(owner);
        foo = new Foo();
    }

    function test_PendingOwner() public {
        assertEq(foo.owner(), owner, "test_PendingOwner::1");
        assertEq(foo.pendingOwner(), address(0), "test_PendingOwner::2");

        vm.prank(owner);
        foo.setPendingOwner(pendingOwner);

        assertEq(foo.owner(), owner, "test_PendingOwner::3");
        assertEq(foo.pendingOwner(), pendingOwner, "test_PendingOwner::4");

        vm.prank(pendingOwner);
        foo.becomeOwner();

        assertEq(foo.owner(), pendingOwner, "test_PendingOwner::5");
        assertEq(foo.pendingOwner(), address(0), "test_PendingOwner::6");
    }

    function test_RestrictedToOwner() public {
        vm.prank(owner);
        foo.restrictedToOwner();

        vm.expectRevert(IPendingOwnable.PendingOwnable__NotOwner.selector);
        vm.prank(pendingOwner);
        foo.restrictedToOwner();

        vm.startPrank(bob);

        vm.expectRevert(IPendingOwnable.PendingOwnable__NotOwner.selector);
        foo.setPendingOwner(pendingOwner);

        vm.expectRevert(IPendingOwnable.PendingOwnable__NotOwner.selector);
        foo.revokePendingOwner();

        vm.expectRevert(IPendingOwnable.PendingOwnable__NotOwner.selector);
        foo.renounceOwnership();

        vm.stopPrank();
    }

    function test_RestrictedToPendingOwner() public {
        vm.prank(owner);
        foo.setPendingOwner(pendingOwner);

        vm.expectRevert(IPendingOwnable.PendingOwnable__NotPendingOwner.selector);
        vm.prank(owner);
        foo.restrictedToPendingOwner();

        vm.prank(pendingOwner);
        foo.restrictedToPendingOwner();

        vm.expectRevert(IPendingOwnable.PendingOwnable__NotPendingOwner.selector);
        vm.prank(bob);
        foo.becomeOwner();
    }

    function test_RevokePendingOwner() public {
        vm.startPrank(owner);

        vm.expectRevert(IPendingOwnable.PendingOwnable__NoPendingOwner.selector);
        foo.revokePendingOwner();

        foo.setPendingOwner(pendingOwner);

        foo.revokePendingOwner();
        vm.stopPrank();

        assertEq(foo.owner(), owner, "test_RevokePendingOwner::1");
        assertEq(foo.pendingOwner(), address(0), "test_RevokePendingOwner::2");
    }

    function test_RenounceOwnership() public {
        vm.expectRevert(IPendingOwnable.PendingOwnable__NotOwner.selector);
        vm.prank(pendingOwner);
        foo.renounceOwnership();

        vm.prank(owner);
        foo.renounceOwnership();

        assertEq(foo.owner(), address(0), "test_RenounceOwnership::1");
        assertEq(foo.pendingOwner(), address(0), "test_RenounceOwnership::2");
    }

    function test_revert_BecomeOwnerForAddressZero() public {
        vm.startPrank(foo.pendingOwner());
        vm.expectRevert(IPendingOwnable.PendingOwnable__NotPendingOwner.selector);
        foo.becomeOwner();
        vm.stopPrank();
    }

    function test_revert_SetPendingOwnerForAddressZero() public {
        vm.expectRevert(IPendingOwnable.PendingOwnable__AddressZero.selector);
        vm.prank(owner);
        foo.setPendingOwner(address(0));
    }
}

contract Foo is PendingOwnable {
    function restrictedToOwner() public view onlyOwner {}

    function restrictedToPendingOwner() public view onlyPendingOwner {}
}
