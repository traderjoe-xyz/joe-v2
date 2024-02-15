// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "../src/LBPair.sol";
import "../src/libraries/ImmutableClone.sol";

contract LBPairImplementationTest is Test {
    address factory;
    address implementation;

    function setUp() public {
        factory = makeAddr("factory");
        implementation = address(new LBPair(ILBFactory(factory)));
    }

    function testFuzz_Getters(address tokenX, address tokenY, uint16 binStep) public {
        bytes32 salt = keccak256(abi.encodePacked(tokenX, tokenY, binStep));
        bytes memory data = abi.encodePacked(tokenX, tokenY, binStep);

        LBPair pair = LBPair(ImmutableClone.cloneDeterministic(implementation, data, salt));

        assertEq(address(pair.getTokenX()), tokenX, "testFuzz_Getters::1");
        assertEq(address(pair.getTokenY()), tokenY, "testFuzz_Getters::2");
        assertEq(pair.getBinStep(), binStep, "testFuzz_Getters::3");
    }

    function testFuzz_revert_InitializeImplementation() public {
        vm.expectRevert(ILBPair.LBPair__OnlyFactory.selector);
        LBPair(implementation).initialize(1, 1, 1, 1, 1, 1, 1, 1);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vm.prank(address(factory));
        LBPair(implementation).initialize(1, 1, 1, 1, 1, 1, 1, 1);
    }
}
