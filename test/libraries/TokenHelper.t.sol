// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../../src/libraries/TokenHelper.sol";

contract TokenHelperTest is Test {
    using TokenHelper for IERC20;

    Vault vault;

    function setUp() public {
        vault = new Vault();
    }

    function test_transferFrom() public {
        IERC20 goodToken = IERC20(address(new ERC20ReturnTrue()));

        vault.deposit(goodToken, 1);

        vault.withdraw(goodToken, 1);
    }

    function test_transferFromEmpty() public {
        IERC20 goodToken = IERC20(address(new ERC20ReturnsEmpty()));

        vault.deposit(goodToken, 1);

        vault.withdraw(goodToken, 1);
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

        vm.expectRevert(TokenHelper.TokenHelper__TransferFailed.selector);
        vault.deposit(badToken, 1);

        vm.expectRevert(TokenHelper.TokenHelper__TransferFailed.selector);
        vault.withdraw(badToken, 1);
    }

    function test_revert_TransferOnRevertWithMessage() public {
        IERC20 badToken = IERC20(address(new ERC20RevertsWithMessage()));

        vm.expectRevert(bytes("fail"));
        vault.deposit(badToken, 1);

        vm.expectRevert(bytes("fail"));
        vault.withdraw(badToken, 1);
    }

    function test_revert_TransferOnRevertWithoutMessage() public {
        IERC20 badToken = IERC20(address(new ERC20RevertsWithoutMessage()));

        vm.expectRevert(TokenHelper.TokenHelper__TransferFailed.selector);
        vault.deposit(badToken, 1);

        vm.expectRevert(TokenHelper.TokenHelper__TransferFailed.selector);
        vault.withdraw(badToken, 1);
    }

    function test_revert_TransferOnNoCode() public {
        IERC20 badToken = IERC20(makeAddr("Token"));

        vm.expectRevert(TokenHelper.TokenHelper__TransferFailed.selector);
        vault.deposit(badToken, 1);

        vm.expectRevert(TokenHelper.TokenHelper__TransferFailed.selector);
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

contract ERC20ReturnTrue {
    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }
}

contract ERC20ReturnsEmpty {
    function transfer(address, uint256) external pure {}

    function transferFrom(address, address, uint256) external pure {}
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

contract ERC20RevertsWithMessage {
    function transfer(address, uint256) external pure {
        revert("fail");
    }

    function transferFrom(address, address, uint256) external pure {
        revert("fail");
    }
}

contract ERC20RevertsWithoutMessage {
    function transfer(address, uint256) external pure {
        revert();
    }

    function transferFrom(address, address, uint256) external pure {
        revert();
    }
}
