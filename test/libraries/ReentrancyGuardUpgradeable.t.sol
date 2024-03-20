// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/Address.sol";

import "../../src/libraries/ReentrancyGuardUpgradeable.sol";

contract ReentrancyGuardUpgradeableTest is Test {
    Foo foo;

    function setUp() public {
        foo = new Foo();
    }

    function testReentrancyGuard() public {
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        foo.callSelf(abi.encodeWithSignature("reentrancyGuarded()"));
    }

    function testNoReentrancyGuard() public {
        foo.callSelf(abi.encodeWithSignature("noReentrancyGuard()"));
    }
}

contract Foo is ReentrancyGuardUpgradeable {
    using Address for address;

    constructor() initializer {
        __ReentrancyGuard_init();
    }

    function callSelf(bytes memory data) external nonReentrant {
        address(this).functionCall(data);
    }

    function reentrancyGuarded() external nonReentrant {}

    function noReentrancyGuard() external pure {}
}
