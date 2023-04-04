// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../src/libraries/AddressHelper.sol";

contract AddressHelperTest is Test {
    using AddressHelper for address;

    RandomContract immutable randomContract = new RandomContract();

    function test_IsContract() public {
        assertTrue(address(randomContract).isContract(), "isContract::1");
        assertTrue(!address(0).isContract(), "isContract::2");
    }

    function test_CallAndCatchSuccessfull() public {
        bytes memory data = abi.encodeWithSignature("return1()");
        bytes memory returnData = address(randomContract).callAndCatch(data);
        assertEq(returnData.length, 32, "callAndCatch::1");
        assertEq(uint256(abi.decode(returnData, (uint256))), 1, "callAndCatch::2");

        data = abi.encodeWithSignature("returnNothing()");
        returnData = address(randomContract).callAndCatch(data);
        assertEq(returnData.length, 0, "callAndCatch::2");
    }

    function test_CallAndCatchFail() public {
        vm.expectRevert("AddressHelperTest: fail");
        address(randomContract).callAndCatch(abi.encodeWithSignature("revertWithString()"));

        vm.expectRevert(AddressHelper.AddressHelper__CallFailed.selector);
        // can't call the library directly orelse foundry expect the revert to be the first revert (L23)
        randomContract.callAndCatch(address(this), abi.encodeWithSignature("UndefindedFunction()"));
    }

    function testFuzz_CallAndCatchNonContract(bytes memory data) public {
        vm.expectRevert(AddressHelper.AddressHelper__NonContract.selector);
        // same reason as above
        randomContract.callAndCatch(address(0), data);
    }
}

contract RandomContract {
    using AddressHelper for address;

    function return1() public pure returns (uint256) {
        return 1;
    }

    function returnNothing() public pure {}

    function revertWithString() public pure {
        revert("AddressHelperTest: fail");
    }

    function callAndCatch(address target, bytes memory data) public returns (bytes memory) {
        return target.callAndCatch(data);
    }
}
