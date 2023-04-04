// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../src/libraries/ReentrancyGuard.sol";
import "../../src/libraries/AddressHelper.sol";

contract ReentrancyGuardTest is Test {
    Foo foo;

    function setUp() public {
        foo = new Foo();
    }

    function testReentrancyGuard() public {
        vm.expectRevert(ReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        foo.callSelf(abi.encodeWithSignature("reentrancyGuarded()"));
    }

    function testNoReentrancyGuard() public {
        foo.callSelf(abi.encodeWithSignature("noReentrancyGuard()"));
    }
}

contract Foo is ReentrancyGuard {
    using AddressHelper for address;

    constructor() {
        __ReentrancyGuard_init();
    }

    function callSelf(bytes memory data) external nonReentrant {
        address(this).callAndCatch(data);
    }

    function reentrancyGuarded() external nonReentrant {}

    function noReentrancyGuard() external pure {}
}
