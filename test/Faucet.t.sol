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

    uint96 constant TOKEN6_PER_REQUEST = 1_000e6;
    uint96 constant TOKEN12_PER_REQUEST = 1_000e12;
    uint96 constant AVAX_PER_REQUEST = 1e18;
    uint256 constant REQUEST_COOL_DOWN = 24 hours;

    function setUp() public {
        Faucet.FaucetTokenParameter[] memory tokens = new Faucet.FaucetTokenParameter[](2);
        tokens[0] = Faucet.FaucetTokenParameter({
            name: "Mock Token 6 decimals",
            symbol: "TOKEN6",
            decimals: 6,
            amountPerRequest: TOKEN6_PER_REQUEST
        });
        tokens[1] = Faucet.FaucetTokenParameter({
            name: "Mock Token 12 decimals",
            symbol: "TOKEN12",
            decimals: 12,
            amountPerRequest: TOKEN12_PER_REQUEST
        });

        faucet = new Faucet{value: 1000e18}(tokens, AVAX_PER_REQUEST, REQUEST_COOL_DOWN);

        (address token, ) = faucet.faucetTokens(1);
        token6 = ERC20MockDecimalsOwnable(token);

        (token, ) = faucet.faucetTokens(2);
        token12 = ERC20MockDecimalsOwnable(token);

        // We increase timestamp so current timestamp is not 0
        vm.warp(365 days);
    }

    function testMintOnlyOwner() external {
        vm.expectRevert("Function is restricted to owner");
        token6.mint(DEV, 1e18);

        vm.prank(ALICE);
        vm.expectRevert("Function is restricted to owner");
        token6.mint(ALICE, 1e18);
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), 0);
        faucet.mint("TOKEN6", ALICE, 1e18);
        assertEq(token6.balanceOf(ALICE), 1e18);
    }

    function testRequestFaucetTokens() external {
        vm.prank(ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(ALICE), TOKEN12_PER_REQUEST);
        assertEq(ALICE.balance, AVAX_PER_REQUEST);

        vm.prank(BOB);
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

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.setAmountPerRequest("AVAX", newRequestToken6Amount);
        vm.stopPrank();

        faucet.setAmountPerRequest("TOKEN6", newRequestToken6Amount);
        faucet.setAmountPerRequest("TOKEN12", newRequestToken12Amount);
        faucet.setAmountPerRequest("AVAX", newRequestAvaxAmount);

        vm.prank(ALICE);
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

    function testSetRequestCoolDown() external {
        uint256 timestamp = block.timestamp;

        vm.startPrank(ALICE);
        faucet.request();
        console.log(
            token6.balanceOf(ALICE),
            token6.balanceOf(DEV),
            block.timestamp + faucet.requestCoolDown(),
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
            block.timestamp + faucet.requestCoolDown(),
            faucet.lastRequest(ALICE)
        );

        faucet.setRequestCoolDown(1 hours);

        vm.startPrank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(PendingOwnable__NotOwner.selector));
        faucet.setRequestCoolDown(10 hours);
        vm.stopPrank();

        vm.prank(ALICE);
        faucet.request();
        vm.stopPrank();

        assertEq(token6.balanceOf(ALICE), 2 * TOKEN6_PER_REQUEST);
        assertEq(token12.balanceOf(ALICE), 2 * TOKEN12_PER_REQUEST);
        assertEq(ALICE.balance, 2 * AVAX_PER_REQUEST);
    }
}
