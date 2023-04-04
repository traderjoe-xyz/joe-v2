// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "../../src/libraries/TokenHelper.sol";

contract TokenHelperTest is Test {
    using TokenHelper for IERC20;

    Vault vault;

    function setUp() public {
        vault = new Vault();
    }

    function test_revert_TransferOnFalse() public {
        IERC20 badToken = IERC20(address(new ERC20ReturnsFalse()));

        vm.expectRevert(TokenHelper.TokenHelper__TransferFailed.selector);
        vault.deposit(badToken, 1);

        vm.expectRevert(TokenHelper.TokenHelper__TransferFailed.selector);
        vault.withdraw(badToken, 1);
    }

    function test_revert_TransferOnCustom() public {
        IERC20 badToken = IERC20(address(new ERC20ReturnsCustom()));

        vm.expectRevert();
        vault.deposit(badToken, 1);

        vm.expectRevert();
        vault.withdraw(badToken, 1);
    }
}

contract Vault {
    using TokenHelper for IERC20;

    function deposit(IERC20 token, uint256 amount) external {
        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(IERC20 token, uint256 amount) external {
        token.safeTransfer(msg.sender, amount);
    }
}

contract ERC20ReturnsFalse {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract ERC20ReturnsCustom {
    function transfer(address, uint256) external pure returns (bytes32) {
        return keccak256("fail");
    }

    function transferFrom(address, address, uint256) external pure returns (bytes32) {
        return keccak256("fail");
    }
}
