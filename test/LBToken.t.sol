// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import "../src/LBToken.sol";

contract LBTokenTest is Test {
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    LBTokenCoverage public lbToken;

    mapping(uint256 => uint256) public idToAmount0;
    mapping(uint256 => uint256) public idToAmount1;

    EnumerableMap.AddressToUintMap private accountToBalance;

    struct MintCase {
        uint256 id;
        uint256 mintAmount;
    }

    struct BurnCase {
        uint256 id;
        uint256 mintAmount;
        uint256 burnAmount;
    }

    struct BalanceCase {
        address account;
        uint256 id;
        uint256 mintAmount;
    }

    function setUp() external {
        lbToken = new LBTokenCoverage();
    }

    function test_Name() external view {
        assertEq(lbToken.name(), "Liquidity Book Token", "test_Name::1");
    }

    function test_Symbol() external view {
        assertEq(lbToken.symbol(), "LBT", "test_Symbol::1");
    }

    function testFuzz_BatchMint(address to, MintCase[] memory mints) external {
        vm.assume(to != address(0) && to != address(lbToken) && mints.length > 0);

        uint256[] memory ids = new uint256[](mints.length);
        uint256[] memory amounts = new uint256[](mints.length);

        for (uint256 i = 0; i < mints.length; i++) {
            _updateMintAmount(mints[i]);

            amounts[i] = mints[i].mintAmount;
            ids[i] = mints[i].id;

            idToAmount0[mints[i].id] += mints[i].mintAmount;
        }

        lbToken.mintBatch(to, ids, amounts);

        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(lbToken.balanceOf(to, ids[i]), idToAmount0[ids[i]], "testFuzz_BatchMint::1");
            assertEq(lbToken.totalSupply(ids[i]), idToAmount0[ids[i]], "testFuzz_BatchMint::2");
        }
    }

    function testFuzz_BatchBurn(address from, BurnCase[] memory burns) external {
        vm.assume(from != address(0) && from != address(lbToken) && burns.length > 0);

        uint256[] memory ids = new uint256[](burns.length);
        uint256[] memory mintAmounts = new uint256[](burns.length);
        uint256[] memory burnAmounts = new uint256[](burns.length);

        for (uint256 i = 0; i < burns.length; i++) {
            MintCase memory mint = MintCase(burns[i].id, burns[i].mintAmount);
            _updateMintAmount(mint);
            _updateBurnAmount(burns[i]);

            idToAmount0[mint.id] += mint.mintAmount;
            idToAmount1[mint.id] += burns[i].burnAmount;

            ids[i] = mint.id;
            mintAmounts[i] = mint.mintAmount;
            burnAmounts[i] = burns[i].burnAmount;
        }

        lbToken.mintBatch(from, ids, mintAmounts);
        lbToken.batchBurnFrom(from, ids, burnAmounts);

        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(
                lbToken.balanceOf(from, ids[i]), idToAmount0[ids[i]] - idToAmount1[ids[i]], "testFuzz_BatchBurn::1"
            );
            assertEq(lbToken.totalSupply(ids[i]), idToAmount0[ids[i]] - idToAmount1[ids[i]], "testFuzz_BatchBurn::2");
        }
    }

    function testFuzz_BatchTransfer(address from, address to, MintCase[] memory mints) external {
        vm.assume(
            from != address(0) && from != address(lbToken) && to != address(0) && to != address(lbToken) && from != to
                && mints.length > 0
        );

        uint256[] memory ids = new uint256[](mints.length);
        uint256[] memory amounts = new uint256[](mints.length);

        for (uint256 i = 0; i < mints.length; i++) {
            uint256 id = mints[i].id;
            uint256 mintAmount = mints[i].mintAmount;

            uint256 minted = idToAmount0[id];

            if (mintAmount > type(uint256).max - minted) {
                mintAmount = type(uint256).max - minted;
            }

            minted += mintAmount;
            idToAmount0[id] = minted;

            ids[i] = id;
            amounts[i] = mintAmount;
        }

        vm.startPrank(from);
        lbToken.mintBatch(from, ids, amounts);
        lbToken.batchTransferFrom(from, to, ids, amounts);
        vm.stopPrank();

        for (uint256 i = 0; i < ids.length; i++) {
            assertEq(lbToken.balanceOf(from, ids[i]), 0, "testFuzz_BatchTransfer::1");
            assertEq(lbToken.balanceOf(to, ids[i]), idToAmount0[ids[i]], "testFuzz_BatchTransfer::2");
            assertEq(lbToken.totalSupply(ids[i]), idToAmount0[ids[i]], "testFuzz_BatchTransfer::3");
        }
    }

    function testFuzz_BatchTransferFromPartial(address from, address to, MintCase[] memory mints) external {
        vm.assume(
            from != address(0) && from != address(lbToken) && to != address(0) && to != address(lbToken) && from != to
                && mints.length > 0
        );

        uint256[] memory ids = new uint256[](mints.length);
        uint256[] memory amounts = new uint256[](mints.length);
        uint256[] memory transferAmounts = new uint256[](mints.length);

        for (uint256 i = 0; i < mints.length; i++) {
            uint256 id = mints[i].id;
            uint256 mintAmount = mints[i].mintAmount;

            uint256 minted = idToAmount0[id];

            if (mintAmount > type(uint256).max - minted) {
                mintAmount = type(uint256).max - minted;
            }

            idToAmount0[id] += mintAmount;
            idToAmount1[id] += mintAmount / 2;

            ids[i] = id;
            amounts[i] = mintAmount;
            transferAmounts[i] = mintAmount / 2;
        }

        vm.startPrank(from);
        lbToken.mintBatch(from, ids, amounts);
        lbToken.batchTransferFrom(from, to, ids, transferAmounts);
        vm.stopPrank();

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];

            uint256 transferAmount = idToAmount1[id];
            uint256 remainingAmount = idToAmount0[id] - transferAmount;

            assertEq(lbToken.balanceOf(from, id), remainingAmount, "testFuzz_BatchTransferFromPartial::1");
            assertEq(lbToken.balanceOf(to, id), transferAmount, "testFuzz_BatchTransferFromPartial::2");
            assertEq(lbToken.totalSupply(id), idToAmount0[id], "testFuzz_BatchTransferFromPartial::3");
        }
    }

    function testFuzz_BalanceOfBatch(BalanceCase[] memory cases) external {
        vm.assume(cases.length > 0);

        uint256[] memory sIds = new uint256[](1);
        uint256[] memory sAmounts = new uint256[](1);

        uint256[] memory ids = new uint256[](cases.length);
        address[] memory accounts = new address[](cases.length);

        for (uint256 i = 0; i < cases.length; i++) {
            vm.assume(cases[i].account != address(0) && cases[i].account != address(lbToken));

            MintCase memory mint = MintCase(cases[i].id, cases[i].mintAmount);
            _updateMintAmount(mint);

            idToAmount0[mint.id] += mint.mintAmount;

            sIds[0] = mint.id;
            sAmounts[0] = mint.mintAmount;

            lbToken.mintBatch(cases[i].account, sIds, sAmounts);

            ids[i] = mint.id;
            accounts[i] = cases[i].account;
        }

        uint256[] memory balances = lbToken.balanceOfBatch(accounts, ids);

        for (uint256 i = 0; i < cases.length; i++) {
            assertEq(balances[i], lbToken.balanceOf(cases[i].account, cases[i].id), "testFuzz_BalanceOfBatch::1");
        }
    }

    function testFuzz_ApprovedForAll(address from, address to, uint256 id, uint256 amount) external {
        vm.assume(
            from != address(lbToken) && from != address(0) && to != address(lbToken) && to != address(0)
                && to != address(lbToken) && from != to
        );

        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        ids[0] = id;
        amounts[0] = amount;

        lbToken.mintBatch(from, ids, amounts);

        vm.startPrank(to);
        vm.expectRevert(abi.encodeWithSelector(ILBToken.LBToken__SpenderNotApproved.selector, from, to));
        lbToken.batchTransferFrom(from, to, ids, amounts);
        vm.stopPrank();

        vm.startPrank(from);
        lbToken.approveForAll(to, true);
        vm.stopPrank();

        assertEq(lbToken.isApprovedForAll(from, to), true, "testFuzz_ApprovedForAll::1");

        vm.startPrank(to);
        lbToken.batchTransferFrom(from, to, ids, amounts);
        vm.stopPrank();

        assertEq(lbToken.balanceOf(from, id), 0, "testFuzz_ApprovedForAll::2");
        assertEq(lbToken.balanceOf(to, id), amount, "testFuzz_ApprovedForAll::3");

        vm.startPrank(from);
        lbToken.approveForAll(to, false);
        vm.stopPrank();

        assertEq(lbToken.isApprovedForAll(from, to), false, "testFuzz_ApprovedForAll::4");

        vm.startPrank(to);
        vm.expectRevert(abi.encodeWithSelector(ILBToken.LBToken__SpenderNotApproved.selector, from, to));
        lbToken.batchTransferFrom(from, to, ids, amounts);
        vm.stopPrank();
    }

    function test_RevertForAddressZeroOrThis() external {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        vm.expectRevert(abi.encodeWithSelector(ILBToken.LBToken__AddressThisOrZero.selector));
        vm.prank(address(1));
        lbToken.batchTransferFrom(address(1), address(0), ids, amounts);

        vm.expectRevert(abi.encodeWithSelector(ILBToken.LBToken__AddressThisOrZero.selector));
        vm.prank(address(1));
        lbToken.batchTransferFrom(address(1), address(lbToken), ids, amounts);
    }

    function testFuzz_SetApprovalOnSelf(address account) external {
        vm.assume(account != address(0) && account != address(lbToken));

        vm.startPrank(account);
        vm.expectRevert(abi.encodeWithSelector(ILBToken.LBToken__SelfApproval.selector, account));
        lbToken.approveForAll(account, true);
        vm.stopPrank();

        assertEq(lbToken.isApprovedForAll(account, account), true, "testFuzz_SetApprovalOnSelf::1");
    }

    function testFuzz_RevertOnInvalidLength(uint256[] memory ids, uint256[] memory amounts) external {
        vm.assume(ids.length != amounts.length && ids.length != 0);

        vm.expectRevert(abi.encodeWithSelector(ILBToken.LBToken__InvalidLength.selector));
        vm.prank(address(1));
        lbToken.batchTransferFrom(address(1), address(2), ids, amounts);
    }

    function testFuzz_RevertFromBalanceExceeded(uint256 id, uint256 amount) external {
        vm.assume(amount != type(uint256).max);

        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);

        ids[0] = id;
        amounts[0] = amount;

        lbToken.mintBatch(address(1), ids, amounts);

        amounts[0] = amount + 1;
        vm.expectRevert(
            abi.encodeWithSelector(ILBToken.LBToken__TransferExceedsBalance.selector, address(1), id, amount + 1)
        );
        vm.prank(address(1));
        lbToken.batchTransferFrom(address(1), address(2), ids, amounts);

        vm.expectRevert(
            abi.encodeWithSelector(ILBToken.LBToken__BurnExceedsBalance.selector, address(1), id, amount + 1)
        );
        vm.prank(address(1));
        lbToken.batchBurnFrom(address(1), ids, amounts);
    }

    // Helper Functions

    function _updateMintAmount(MintCase memory mint) internal view {
        uint256 id = mint.id;
        uint256 mintAmount = mint.mintAmount;

        uint256 minted = idToAmount0[id];

        if (mintAmount > type(uint256).max - minted) {
            mint.mintAmount = type(uint256).max - minted;
        }
    }

    function _updateBurnAmount(BurnCase memory burn) internal view {
        uint256 id = burn.id;
        uint256 burnAmount = burn.burnAmount;

        uint256 burned = idToAmount0[id] - idToAmount1[id];

        if (burnAmount > burned) {
            burn.burnAmount = burned;
        }
    }
}

contract LBTokenCoverage is LBToken {
    function mintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts) external {
        // _mintBatch(to, ids, amounts);
        for (uint256 i = 0; i < ids.length; i++) {
            _mint(to, ids[i], amounts[i]);
        }
    }

    function batchBurnFrom(address from, uint256[] calldata ids, uint256[] calldata amounts) external {
        // _batchBurnFrom(from, ids, amounts);
        for (uint256 i = 0; i < ids.length; i++) {
            _burn(from, ids[i], amounts[i]);
        }
    }
}
