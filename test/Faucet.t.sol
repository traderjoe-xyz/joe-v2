// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "test/mocks/ERC20MockDecimalsOwnable.sol";
import "test/mocks/Faucet.sol";

contract FaucetTest is Test {
    Faucet private faucet;

    address internal immutable DEV = address(this);
    address internal constant ALICE = address(bytes20(bytes32(keccak256(bytes("ALICE")))));
    address internal constant BOB = address(bytes20(bytes32(keccak256(bytes("BOB")))));

    ERC20MockDecimalsOwnable token6;
    ERC20MockDecimalsOwnable token12;

    address AVAX = address(0);

    uint96 constant TOKEN6_PER_REQUEST = 1_000e6;
    uint96 constant TOKEN12_PER_REQUEST = 1_000e12;
    uint96 constant AVAX_PER_REQUEST = 1e18;
    uint256 constant REQUEST_COOLDOWN = 24 hours;

    function setUp() public {
        token6 = new ERC20MockDecimalsOwnable("Mock Token 6 decimals", "TOKEN6", 6);
        token12 = new ERC20MockDecimalsOwnable("Mock Token 12 decimals", "TOKEN12", 12);

        faucet = new Faucet{value: 1000e18}(AVAX_PER_REQUEST, REQUEST_COOLDOWN);

        token6.transferOwnership(address(faucet));
        token12.transferOwnership(address(faucet));

        faucet.addFaucetToken(address(token6), TOKEN6_PER_REQUEST);
        faucet.addFaucetToken(address(token12), TOKEN12_PER_REQUEST);

        // We increase timestamp so current timestamp is not 0
        vm.warp(365 days);
    }

    function testAddToken() external {
        vm.startPrank(address(faucet));
        ERC20MockDecimalsOwnable newToken = new ERC20MockDecimalsOwnable("New Token", "NEW_TOKEN", 18);
        newToken.transferOwnership(address(faucet));
        vm.stopPrank();

        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.addFaucetToken(address(newToken), 1e18);
        vm.stopPrank();

        faucet.addFaucetToken(address(newToken), 1e18);

        vm.expectRevert("Already a faucet token");
        faucet.addFaucetToken(address(newToken), 1e18);
    }

    function testRevertWhenAddingNonOwnableContract() external {
        vm.expectRevert();
        faucet.addFaucetToken(address(1), 1e18);
    }

    function testRemoveToken() external {
        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.removeFaucetToken(address(1));
        vm.stopPrank();

        vm.expectRevert("Not a faucet token");
        faucet.removeFaucetToken(address(0));

        faucet.removeFaucetToken(address(token6));

        assertEq(faucet.owner(), DEV);

        vm.expectRevert("Not a faucet token");
        faucet.removeFaucetToken(address(token6));
    }

    function testMintOnlyOwner() external {
        vm.expectRevert("Ownable: caller is not the owner");
        token6.mint(DEV, 1e18);

        vm.startPrank(ALICE);
        vm.expectRevert("Ownable: caller is not the owner");
        token6.mint(ALICE, 1e18);
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), 0);
        faucet.mint(address(token6), ALICE, 1e18);
        assertEq(token6.balanceOf(ALICE), 1e18);
    }

    function testRequestFaucetTokens() external {
        vm.startPrank(ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(ALICE), TOKEN12_PER_REQUEST);
        assertEq(ALICE.balance, AVAX_PER_REQUEST);

        vm.startPrank(BOB);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(BOB), TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(BOB), TOKEN12_PER_REQUEST);
        assertEq(BOB.balance, AVAX_PER_REQUEST);
    }

    function testSetRequestAmount() external {
        uint96 newRequestToken6Amount = 100e6;
        uint96 newRequestToken12Amount = 100e12;
        uint96 newRequestAvaxAmount = 2e18;

        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.setAmountPerRequest(AVAX, newRequestToken6Amount);
        vm.stopPrank();

        faucet.setAmountPerRequest(address(token6), newRequestToken6Amount);
        faucet.setAmountPerRequest(address(token12), newRequestToken12Amount);
        faucet.setAmountPerRequest(AVAX, newRequestAvaxAmount);

        vm.startPrank(ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), newRequestToken6Amount);
        assertEq(token12.balanceOf(ALICE), newRequestToken12Amount);
        assertEq(ALICE.balance, newRequestAvaxAmount);
    }

    function testWithdrawAvax() external {
        assertEq(ALICE.balance, 0);
        faucet.withdrawAVAX(ALICE, 1e18);
        assertEq(ALICE.balance, 1e18);

        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.withdrawAVAX(ALICE, 1e18);
        vm.stopPrank();

        // Leave 0.99...9 AVAX in the contract
        faucet.withdrawAVAX(ALICE, address(faucet).balance - (1e18 - 1));
        assertEq(address(faucet).balance, 1e18 - 1);

        vm.startPrank(BOB);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(BOB), TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(BOB), TOKEN12_PER_REQUEST);
        assertEq(BOB.balance, 0);
    }

    function testSetRequestCooldown() external {
        uint256 timestamp = block.timestamp;

        vm.startPrank(ALICE);
        faucet.request();
        console.log(
            token6.balanceOf(ALICE),
            token6.balanceOf(DEV),
            block.timestamp + faucet.requestCooldown(),
            faucet.lastRequest(ALICE)
        );

        // increase time
        vm.warp(timestamp + 1 hours);

        vm.expectRevert("Too many request");
        faucet.request();
        vm.stopPrank();
        console.log(
            token6.balanceOf(ALICE),
            token6.balanceOf(DEV),
            block.timestamp + faucet.requestCooldown(),
            faucet.lastRequest(ALICE)
        );

        faucet.setRequestCooldown(1 hours);

        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.setRequestCooldown(10 hours);
        vm.stopPrank();

        vm.startPrank(ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), 2 * TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(ALICE), 2 * TOKEN12_PER_REQUEST);
        assertEq(ALICE.balance, 2 * AVAX_PER_REQUEST);
    }
}
