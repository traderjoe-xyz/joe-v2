// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./TestHelper.sol";

contract LiquidityBinTokenTest is TestHelper {
    event TransferBatch(
        address indexed sender,
        address indexed from,
        address indexed to,
        ILBToken.LiquidityAmount[] liquidityAmounts
    );

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV, 8e14);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
        new LBFactoryHelper(factory);
        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testSafeBatchTransferFrom() public {
        uint256 amountIn = 1e18;

        (ILBPair.LiquidityDeposit[] memory deposits, ) = addLiquidity(amountIn, ID_ONE, 5, 0);

        ILBToken.LiquidityAmount[] memory liquidityAmounts = new ILBToken.LiquidityAmount[](5);
        for (uint256 i; i < 5; i++) {
            assertEq(pair.userPositionAt(DEV, i), deposits[i].id);
            liquidityAmounts[i].id = deposits[i].id;
            liquidityAmounts[i].amount = pair.balanceOf(DEV, deposits[i].id);
        }

        assertEq(pair.userPositionNb(DEV), 5);

        assertEq(pair.balanceOf(DEV, ID_ONE - 1), amountIn / 3);
        vm.expectEmit(true, true, true, true);
        emit TransferBatch(DEV, DEV, ALICE, liquidityAmounts);
        pair.safeBatchTransferFrom(DEV, ALICE, liquidityAmounts);
        assertEq(pair.balanceOf(DEV, ID_ONE - 1), 0);
        assertEq(pair.balanceOf(ALICE, ID_ONE - 1), amountIn / 3);

        vm.prank(ALICE);
        pair.setApprovalForAll(BOB, true);
        assertTrue(pair.isApprovedForAll(ALICE, BOB));
        assertFalse(pair.isApprovedForAll(BOB, ALICE));

        vm.prank(BOB);
        vm.expectEmit(true, true, true, true);
        emit TransferBatch(BOB, ALICE, BOB, liquidityAmounts);
        pair.safeBatchTransferFrom(ALICE, BOB, liquidityAmounts);
        assertEq(pair.balanceOf(DEV, ID_ONE - 1), 0); // DEV
        assertEq(pair.balanceOf(ALICE, ID_ONE - 1), 0);
        assertEq(pair.balanceOf(BOB, ID_ONE - 1), amountIn / 3);
    }

    function testTransferNotApprovedReverts() public {
        uint256 amountIn = 1e18;
        (ILBPair.LiquidityDeposit[] memory deposits, ) = addLiquidity(amountIn, ID_ONE, 5, 0);

        ILBToken.LiquidityAmount[] memory liquidityAmounts = new ILBToken.LiquidityAmount[](5);
        for (uint256 i; i < 5; i++) {
            assertEq(pair.userPositionAt(DEV, i), deposits[i].id);
            liquidityAmounts[i].id = deposits[i].id;
            liquidityAmounts[i].amount = pair.balanceOf(DEV, deposits[i].id);
        }

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(LBToken__SpenderNotApproved.selector, DEV, BOB));
        pair.safeBatchTransferFrom(DEV, BOB, liquidityAmounts);
    }

    function testSafeBatchTransferFromReverts() public {
        uint24 binAmount = 11;
        uint256 amountIn = 1e18;
        (ILBPair.LiquidityDeposit[] memory deposits, ) = addLiquidity(amountIn, ID_ONE, binAmount, 0);

        ILBToken.LiquidityAmount[] memory liquidityAmounts = new ILBToken.LiquidityAmount[](binAmount);
        for (uint256 i; i < binAmount; i++) {
            assertEq(pair.userPositionAt(DEV, i), deposits[i].id);
            liquidityAmounts[i].id = deposits[i].id;
            liquidityAmounts[i].amount = pair.balanceOf(DEV, deposits[i].id);
        }

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(LBToken__SpenderNotApproved.selector, DEV, BOB));
        pair.safeBatchTransferFrom(DEV, BOB, liquidityAmounts);

        vm.prank(address(0));
        vm.expectRevert(LBToken__TransferFromOrToAddress0.selector);
        pair.safeBatchTransferFrom(address(0), BOB, liquidityAmounts);

        vm.prank(DEV);
        vm.expectRevert(LBToken__TransferFromOrToAddress0.selector);
        pair.safeBatchTransferFrom(DEV, address(0), liquidityAmounts);

        liquidityAmounts[0].amount += 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                LBToken__TransferExceedsBalance.selector,
                DEV,
                liquidityAmounts[0].id,
                liquidityAmounts[0].amount
            )
        );
        pair.safeBatchTransferFrom(DEV, ALICE, liquidityAmounts);

        liquidityAmounts[0].amount -= 1; //revert back to proper amount
        liquidityAmounts[1].id = ID_ONE + binAmount;
        vm.expectRevert(
            abi.encodeWithSelector(
                LBToken__TransferExceedsBalance.selector,
                DEV,
                liquidityAmounts[1].id,
                liquidityAmounts[1].amount
            )
        );
        pair.safeBatchTransferFrom(DEV, ALICE, liquidityAmounts);
    }

    function testSelfApprovalReverts() public {
        vm.expectRevert(abi.encodeWithSelector(LBToken__SelfApproval.selector, DEV));
        pair.setApprovalForAll(DEV, true);
    }

    function testPrivateViewFunctions() public {
        assertEq(pair.name(), "Liquidity Book Token");
        assertEq(pair.symbol(), "LBT");
        assertEq(pair.decimals(), 18);
    }
}
