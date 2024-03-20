// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/libraries/Clone.sol";
import "../../src/libraries/ImmutableClone.sol";

contract TestImmutableClone is Test {
    function cloneDeterministic(address implementation, bytes memory data, bytes32 salt) public returns (address) {
        return ImmutableClone.cloneDeterministic(implementation, data, salt);
    }

    function testFuzz_CloneDeterministic(bytes32 salt) public {
        address clone = address(ImmutableClone.cloneDeterministic(address(1), "", salt));

        assertEq(
            clone,
            ImmutableClone.predictDeterministicAddress(address(1), "", salt, address(this)),
            "testFuzz_CloneDeterministic::1"
        );

        // Check that cloning twice with the same salt reverts, needs to call the contract for the error to be caught
        vm.expectRevert(ImmutableClone.DeploymentFailed.selector);
        this.cloneDeterministic(address(1), "", salt);
    }

    function testFuzz_Implementation(bytes memory data) public {
        vm.assume(data.length <= 0xffca);

        address implementation = address(new Implementation());
        bytes32 salt = keccak256("salt");

        address clone = address(ImmutableClone.cloneDeterministic(implementation, data, salt));

        Implementation implementationClone = Implementation(clone);

        assertEq(implementationClone.getBytes(data.length), data, "testFuzz_Implementation::1");
    }

    function testFuzz_Pair(address tokenX, address tokenY, uint16 binStep) public {
        address implementation = address(new Pair());
        bytes32 salt = keccak256("salt");

        address clone =
            address(ImmutableClone.cloneDeterministic(implementation, abi.encodePacked(tokenX, tokenY, binStep), salt));

        Pair pair = Pair(clone);

        assertEq(pair.getTokenX(), tokenX, "testFuzz_Pair::1");
        assertEq(pair.getTokenY(), tokenY, "testFuzz_Pair::2");
        assertEq(pair.getBinStep(), binStep, "testFuzz_Pair::3");
    }

    function test_CloneDeterministicMaxLength() public {
        bytes memory b = new bytes(0xffc8);

        assembly {
            mstore8(add(b, 0x20), 0xff)
            mstore8(add(b, mload(b)), 0xca)
        }

        address implementation = address(new Implementation());
        address clone = ImmutableClone.cloneDeterministic(implementation, b, bytes32(0));

        assertEq(Implementation(clone).getBytes(b.length), b, "test_CloneDeterministicMaxLength::1");
    }

    function test_CloneDeterministicTooBig() public {
        bytes memory b = new bytes(0xffc8 + 1);
        vm.expectRevert(ImmutableClone.PackedDataTooBig.selector);
        ImmutableClone.cloneDeterministic(address(1), b, bytes32(0));
    }
}

contract Pair is Clone {
    function getTokenX() public pure returns (address) {
        return _getArgAddress(0);
    }

    function getTokenY() public pure returns (address) {
        return _getArgAddress(20);
    }

    function getBinStep() public pure returns (uint16) {
        return _getArgUint16(40);
    }
}

contract Implementation is Clone {
    function getBytes(uint256 length) public pure returns (bytes memory) {
        return _getArgBytes(0, length);
    }
}
