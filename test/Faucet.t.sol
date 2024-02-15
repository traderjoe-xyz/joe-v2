// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "test/mocks/ERC20.sol";
import "test/mocks/Faucet.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FaucetTest is Test {
    Faucet private faucet;

    address internal immutable DEV = address(this);
    address internal constant ALICE = address(bytes20(bytes32(keccak256(bytes("ALICE")))));
    address internal constant BOB = address(bytes20(bytes32(keccak256(bytes("BOB")))));
    address internal constant OPERATOR = address(bytes20(bytes32(keccak256(bytes("OPERATOR")))));

    ERC20Mock token6;
    ERC20Mock token12;

    IERC20 NATIVE = IERC20(address(0));

    uint96 constant TOKEN6_PER_REQUEST = 1_000e6;
    uint96 constant TOKEN12_PER_REQUEST = 1_000e12;
    uint96 constant NATIVE_PER_REQUEST = 1e18;
    uint256 constant REQUEST_COOLDOWN = 24 hours;

    function setUp() public {
        token6 = new ERC20Mock(6);
        token12 = new ERC20Mock(12);

        faucet = new Faucet{value: 10 * NATIVE_PER_REQUEST}(address(this), NATIVE_PER_REQUEST, REQUEST_COOLDOWN);

        token6.mint(address(faucet), 10 * TOKEN6_PER_REQUEST);
        token12.mint(address(faucet), 10 * TOKEN12_PER_REQUEST);

        faucet.addFaucetToken(IERC20(token6), TOKEN6_PER_REQUEST);
        faucet.addFaucetToken(IERC20(token12), TOKEN12_PER_REQUEST);

        faucet.setUnlockedRequest(true);

        // We increase timestamp so current timestamp is not 0
        vm.warp(365 days);
    }

    function testRevertOnNonEOA() external {
        vm.startPrank(address(faucet));
        vm.expectRevert("Only EOA");
        faucet.request();
        vm.stopPrank();
    }

    function testLockRequest() external {
        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        faucet.setUnlockedRequest(false);
        vm.stopPrank();

        faucet.setUnlockedRequest(false);

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert("Direct request is locked");
        faucet.request();
        vm.stopPrank();

        faucet.setUnlockedRequest(true);

        vm.startPrank(ALICE, ALICE);
        faucet.request();
        vm.stopPrank();
    }

    function testAddToken() external {
        ERC20Mock newToken = new ERC20Mock(18);
        newToken.mint(address(faucet), 1_000e18);

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        faucet.addFaucetToken(IERC20(newToken), 1e18);
        vm.stopPrank();

        faucet.addFaucetToken(IERC20(newToken), 1e18);

        vm.expectRevert("Already a faucet token");
        faucet.addFaucetToken(IERC20(newToken), 1e18);
    }

    function testRemoveToken() external {
        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        faucet.removeFaucetToken(IERC20(address(1)));
        vm.stopPrank();

        vm.expectRevert("Not a faucet token");
        faucet.removeFaucetToken(NATIVE);

        faucet.removeFaucetToken(IERC20(token6));

        IERC20 faucetToken;
        (faucetToken,) = faucet.faucetTokens(0);
        assertEq(address(faucetToken), address(NATIVE), "testRemoveToken::1");

        (faucetToken,) = faucet.faucetTokens(1);
        assertEq(address(faucetToken), address(token12), "testRemoveToken::2");

        assertEq(faucet.owner(), DEV, "testRemoveToken::3");

        vm.expectRevert("Not a faucet token");
        faucet.removeFaucetToken(IERC20(token6));
    }

    function testRequestFaucetTokens() external {
        vm.startPrank(ALICE, ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), TOKEN6_PER_REQUEST, "testRequestFaucetTokens::1");
        assertEq(token12.balanceOf(ALICE), TOKEN12_PER_REQUEST, "testRequestFaucetTokens::2");
        assertEq(ALICE.balance, NATIVE_PER_REQUEST, "testRequestFaucetTokens::3");

        vm.startPrank(BOB, BOB);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(BOB), TOKEN6_PER_REQUEST, "testRequestFaucetTokens::4");
        assertEq(token12.balanceOf(BOB), TOKEN12_PER_REQUEST, "testRequestFaucetTokens::5");
        assertEq(BOB.balance, NATIVE_PER_REQUEST, "testRequestFaucetTokens::6");
    }

    function testRequestFaucetTokensByOperator() external {
        vm.startPrank(ALICE, ALICE);
        vm.expectRevert("Only operator");
        faucet.request(ALICE);
        vm.stopPrank();

        faucet.setOperator(OPERATOR);

        vm.startPrank(DEV);
        vm.expectRevert("Only operator");
        faucet.request(DEV);
        vm.stopPrank();

        vm.startPrank(OPERATOR);
        faucet.request(ALICE);
        faucet.request(BOB);
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), TOKEN6_PER_REQUEST, "testRequestFaucetTokensByOperator::1");
        assertEq(token12.balanceOf(ALICE), TOKEN12_PER_REQUEST, "testRequestFaucetTokensByOperator::2");
        assertEq(ALICE.balance, NATIVE_PER_REQUEST, "testRequestFaucetTokensByOperator::3");

        assertEq(token6.balanceOf(BOB), TOKEN6_PER_REQUEST, "testRequestFaucetTokensByOperator::4");
        assertEq(token12.balanceOf(BOB), TOKEN12_PER_REQUEST, "testRequestFaucetTokensByOperator::5");
        assertEq(BOB.balance, NATIVE_PER_REQUEST, "testRequestFaucetTokensByOperator::6");

        vm.startPrank(BOB, BOB);
        vm.expectRevert("Too many requests");
        faucet.request();
        vm.stopPrank();
    }

    function testSetRequestAmount() external {
        uint96 newRequestToken6Amount = 100e6;
        uint96 newRequestToken12Amount = 100e12;
        uint96 newRequestNativeAmount = 2e18;

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        faucet.setAmountPerRequest(NATIVE, newRequestToken6Amount);
        vm.stopPrank();

        faucet.setAmountPerRequest(IERC20(token6), newRequestToken6Amount);
        faucet.setAmountPerRequest(IERC20(token12), newRequestToken12Amount);
        faucet.setAmountPerRequest(NATIVE, newRequestNativeAmount);

        vm.startPrank(ALICE, ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), newRequestToken6Amount, "testSetRequestAmount::1");
        assertEq(token12.balanceOf(ALICE), newRequestToken12Amount, "testSetRequestAmount::2");
        assertEq(ALICE.balance, newRequestNativeAmount, "testSetRequestAmount::3");
    }

    function testWithdrawNative() external {
        assertEq(ALICE.balance, 0, "testWithdrawNative::1");
        faucet.withdrawToken(NATIVE, ALICE, 1e18);
        assertEq(ALICE.balance, 1e18, "testWithdrawNative::2");

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        faucet.withdrawToken(NATIVE, ALICE, 1e18);
        vm.stopPrank();

        // Leave 0.99...9 NATIVE in the contract
        faucet.withdrawToken(NATIVE, ALICE, address(faucet).balance - (NATIVE_PER_REQUEST - 1));
        assertEq(address(faucet).balance, NATIVE_PER_REQUEST - 1, "testWithdrawNative::3");

        vm.startPrank(BOB, BOB);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(BOB), TOKEN6_PER_REQUEST, "testWithdrawNative::4");
        assertEq(token12.balanceOf(BOB), TOKEN12_PER_REQUEST, "testWithdrawNative::5");
        assertEq(BOB.balance, 0, "testWithdrawNative::6");
    }

    function testWithdrawToken() external {
        // Tries to withdraw
        assertEq(token12.balanceOf(ALICE), 0, "testWithdrawToken::1");
        faucet.withdrawToken(IERC20(token12), ALICE, 2 * TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(ALICE), 2 * TOKEN6_PER_REQUEST, "testWithdrawToken::2");

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        faucet.withdrawToken(IERC20(token6), ALICE, 1e18);
        vm.stopPrank();

        // Leave 0.99...9 TOKEN6 in the contract
        faucet.withdrawToken(IERC20(token6), ALICE, token6.balanceOf(address(faucet)) - (TOKEN6_PER_REQUEST - 1));
        assertEq(token6.balanceOf(address(faucet)), TOKEN6_PER_REQUEST - 1, "testWithdrawToken::3");

        vm.startPrank(BOB, BOB);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(BOB), 0, "testWithdrawToken::4");
        assertEq(token12.balanceOf(BOB), TOKEN12_PER_REQUEST, "testWithdrawToken::5");
        assertEq(BOB.balance, NATIVE_PER_REQUEST, "testWithdrawToken::6");
    }

    function testSetRequestCooldown() external {
        uint256 timestamp = block.timestamp;

        vm.startPrank(ALICE, ALICE);
        faucet.request();

        // increase time
        vm.warp(timestamp + 1 hours);

        vm.expectRevert("Too many requests");
        faucet.request();
        vm.stopPrank();

        faucet.setRequestCooldown(1 hours);

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        faucet.setRequestCooldown(10 hours);
        vm.stopPrank();

        vm.startPrank(ALICE, ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), 2 * TOKEN6_PER_REQUEST, "testSetRequestCooldown::1");
        assertEq(token12.balanceOf(ALICE), 2 * TOKEN12_PER_REQUEST, "testSetRequestCooldown::2");
        assertEq(ALICE.balance, 2 * NATIVE_PER_REQUEST, "testSetRequestCooldown::3");
    }
}
