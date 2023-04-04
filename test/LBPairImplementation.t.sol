// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

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

        assertEq(address(pair.getTokenX()), tokenX);
        assertEq(address(pair.getTokenY()), tokenY);
        assertEq(pair.getBinStep(), binStep);
    }

    function testFuzz_revert_InitializeImplementation() public {
        vm.expectRevert(ILBPair.LBPair__OnlyFactory.selector);
        LBPair(implementation).initialize(1, 1, 1, 1, 1, 1, 1, 1);

        vm.expectRevert(ILBPair.LBPair__AlreadyInitialized.selector);
        vm.prank(address(factory));
        LBPair(implementation).initialize(1, 1, 1, 1, 1, 1, 1, 1);
    }
}
