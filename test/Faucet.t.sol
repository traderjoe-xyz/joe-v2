// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";
import "test/mocks/ERC20MockDecimalsOwnable.sol";
import "test/mocks/Faucet.sol";

contract FaucetTest is Test {
    Faucet private faucet;

    address internal immutable DEV = address(this);
    address internal constant ALICE = address(bytes20(bytes32(keccak256(bytes("ALICE")))));
    address internal constant BOB = address(bytes20(bytes32(keccak256(bytes("BOB")))));
    address internal constant OPERATOR = address(bytes20(bytes32(keccak256(bytes("OPERATOR")))));

    ERC20MockDecimalsOwnable token6;
    ERC20MockDecimalsOwnable token12;

    IERC20 AVAX = IERC20(address(0));

    uint96 constant TOKEN6_PER_REQUEST = 1_000e6;
    uint96 constant TOKEN12_PER_REQUEST = 1_000e12;
    uint96 constant AVAX_PER_REQUEST = 1e18;
    uint256 constant REQUEST_COOLDOWN = 24 hours;

    function setUp() public {
        token6 = new ERC20MockDecimalsOwnable("Mock Token 6 decimals", "TOKEN6", 6);
        token12 = new ERC20MockDecimalsOwnable("Mock Token 12 decimals", "TOKEN12", 12);

        faucet = new Faucet{value: 10 * AVAX_PER_REQUEST}(AVAX_PER_REQUEST, REQUEST_COOLDOWN);

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
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
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
        ERC20MockDecimalsOwnable newToken = new ERC20MockDecimalsOwnable("New Token", "NEW_TOKEN", 18);
        newToken.mint(address(faucet), 1_000e18);

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.addFaucetToken(IERC20(newToken), 1e18);
        vm.stopPrank();

        faucet.addFaucetToken(IERC20(newToken), 1e18);

        vm.expectRevert("Already a faucet token");
        faucet.addFaucetToken(IERC20(newToken), 1e18);
    }

    function testRemoveToken() external {
        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.removeFaucetToken(IERC20(address(1)));
        vm.stopPrank();

        vm.expectRevert("Not a faucet token");
        faucet.removeFaucetToken(AVAX);

        faucet.removeFaucetToken(IERC20(token6));

        IERC20 faucetToken;
        (faucetToken, ) = faucet.faucetTokens(0);
        assertEq(address(faucetToken), address(AVAX));

        (faucetToken, ) = faucet.faucetTokens(1);
        assertEq(address(faucetToken), address(token12));

        assertEq(faucet.owner(), DEV);

        vm.expectRevert("Not a faucet token");
        faucet.removeFaucetToken(IERC20(token6));
    }

    function testRequestFaucetTokens() external {
        vm.startPrank(ALICE, ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(ALICE), TOKEN12_PER_REQUEST);
        assertEq(ALICE.balance, AVAX_PER_REQUEST);

        vm.startPrank(BOB, BOB);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(BOB), TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(BOB), TOKEN12_PER_REQUEST);
        assertEq(BOB.balance, AVAX_PER_REQUEST);
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

        assertEq(token6.balanceOf(ALICE), TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(ALICE), TOKEN12_PER_REQUEST);
        assertEq(ALICE.balance, AVAX_PER_REQUEST);

        assertEq(token6.balanceOf(BOB), TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(BOB), TOKEN12_PER_REQUEST);
        assertEq(BOB.balance, AVAX_PER_REQUEST);

        vm.startPrank(BOB, BOB);
        vm.expectRevert("Too many requests");
        faucet.request();
        vm.stopPrank();
    }

    function testSetRequestAmount() external {
        uint96 newRequestToken6Amount = 100e6;
        uint96 newRequestToken12Amount = 100e12;
        uint96 newRequestAvaxAmount = 2e18;

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.setAmountPerRequest(AVAX, newRequestToken6Amount);
        vm.stopPrank();

        faucet.setAmountPerRequest(IERC20(token6), newRequestToken6Amount);
        faucet.setAmountPerRequest(IERC20(token12), newRequestToken12Amount);
        faucet.setAmountPerRequest(AVAX, newRequestAvaxAmount);

        vm.startPrank(ALICE, ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), newRequestToken6Amount);
        assertEq(token12.balanceOf(ALICE), newRequestToken12Amount);
        assertEq(ALICE.balance, newRequestAvaxAmount);
    }

    function testWithdrawAvax() external {
        assertEq(ALICE.balance, 0);
        faucet.withdrawToken(AVAX, ALICE, 1e18);
        assertEq(ALICE.balance, 1e18);

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.withdrawToken(AVAX, ALICE, 1e18);
        vm.stopPrank();

        // Leave 0.99...9 AVAX in the contract
        faucet.withdrawToken(AVAX, ALICE, address(faucet).balance - (AVAX_PER_REQUEST - 1));
        assertEq(address(faucet).balance, AVAX_PER_REQUEST - 1);

        vm.startPrank(BOB, BOB);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(BOB), TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(BOB), TOKEN12_PER_REQUEST);
        assertEq(BOB.balance, 0);
    }

    function testWithdrawToken() external {
        // Tries to withdraw
        assertEq(token12.balanceOf(ALICE), 0);
        faucet.withdrawToken(IERC20(token12), ALICE, 2 * TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(ALICE), 2 * TOKEN6_PER_REQUEST);

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.withdrawToken(IERC20(token6), ALICE, 1e18);
        vm.stopPrank();

        // Leave 0.99...9 TOKEN6 in the contract
        faucet.withdrawToken(IERC20(token6), ALICE, token6.balanceOf(address(faucet)) - (TOKEN6_PER_REQUEST - 1));
        assertEq(token6.balanceOf(address(faucet)), TOKEN6_PER_REQUEST - 1);

        vm.startPrank(BOB, BOB);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(BOB), 0);
        assertEq(token12.balanceOf(BOB), TOKEN12_PER_REQUEST);
        assertEq(BOB.balance, AVAX_PER_REQUEST);
    }

    function testSetRequestCooldown() external {
        uint256 timestamp = block.timestamp;

        vm.startPrank(ALICE, ALICE);
        faucet.request();
        console.log(
            token6.balanceOf(ALICE),
            token6.balanceOf(DEV),
            block.timestamp + faucet.requestCooldown(),
            faucet.lastRequest(ALICE)
        );

        // increase time
        vm.warp(timestamp + 1 hours);

        vm.expectRevert("Too many requests");
        faucet.request();
        vm.stopPrank();
        console.log(
            token6.balanceOf(ALICE),
            token6.balanceOf(DEV),
            block.timestamp + faucet.requestCooldown(),
            faucet.lastRequest(ALICE)
        );

        faucet.setRequestCooldown(1 hours);

        vm.startPrank(ALICE, ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.setRequestCooldown(10 hours);
        vm.stopPrank();

        vm.startPrank(ALICE, ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), 2 * TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(ALICE), 2 * TOKEN12_PER_REQUEST);
        assertEq(ALICE.balance, 2 * AVAX_PER_REQUEST);
    }
}
