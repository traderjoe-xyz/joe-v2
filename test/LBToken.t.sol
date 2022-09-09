// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./TestHelper.sol";

contract LiquidityBinTokenTest is TestHelper {
    event TransferBatch(
        address indexed sender,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] amounts
    );

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(_LBPairImplementation);
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testSafeBatchTransferFrom() public {
        uint256 amountIn = 1e18;

        (uint256[] memory _ids, , , ) = addLiquidity(amountIn, ID_ONE, 5, 0);

        uint256[] memory amounts = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            assertEq(pair.userPositionAt(DEV, i), _ids[i]);
            amounts[i] = pair.balanceOf(DEV, _ids[i]);
        }
        assertEq(pair.userPositionNb(DEV), 5);

        assertEq(pair.balanceOf(DEV, ID_ONE - 1), amountIn / 3);
        vm.expectEmit(true, true, true, true);
        emit TransferBatch(DEV, DEV, ALICE, _ids, amounts);
        pair.safeBatchTransferFrom(DEV, ALICE, _ids, amounts);
        assertEq(pair.balanceOf(DEV, ID_ONE - 1), 0);
        assertEq(pair.balanceOf(ALICE, ID_ONE - 1), amountIn / 3);

        vm.prank(ALICE);
        pair.setApprovalForAll(BOB, true);
        assertTrue(pair.isApprovedForAll(ALICE, BOB));
        assertFalse(pair.isApprovedForAll(BOB, ALICE));

        vm.prank(BOB);
        vm.expectEmit(true, true, true, true);
        emit TransferBatch(BOB, ALICE, BOB, _ids, amounts);
        pair.safeBatchTransferFrom(ALICE, BOB, _ids, amounts);
        assertEq(pair.balanceOf(DEV, ID_ONE - 1), 0); // DEV
        assertEq(pair.balanceOf(ALICE, ID_ONE - 1), 0);
        assertEq(pair.balanceOf(BOB, ID_ONE - 1), amountIn / 3);
    }

    function testTransferNotApprovedReverts() public {
        uint256 amountIn = 1e18;
        (uint256[] memory _ids, , , ) = addLiquidity(amountIn, ID_ONE, 5, 0);

        uint256[] memory amounts = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            assertEq(pair.userPositionAt(DEV, i), _ids[i]);
            amounts[i] = pair.balanceOf(DEV, _ids[i]);
        }

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(LBToken__SpenderNotApproved.selector, DEV, BOB));
        pair.safeBatchTransferFrom(DEV, BOB, _ids, amounts);
    }

    function testSafeBatchTransferFromReverts() public {
        uint24 binAmount = 11;
        uint256 amountIn = 1e18;
        (uint256[] memory _ids, , , ) = addLiquidity(amountIn, ID_ONE, binAmount, 0);

        uint256[] memory amounts = new uint256[](binAmount);
        for (uint256 i; i < binAmount; i++) {
            assertEq(pair.userPositionAt(DEV, i), _ids[i]);
            amounts[i] = pair.balanceOf(DEV, _ids[i]);
        }

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(LBToken__SpenderNotApproved.selector, DEV, BOB));
        pair.safeBatchTransferFrom(DEV, BOB, _ids, amounts);

        vm.prank(address(0));
        vm.expectRevert(LBToken__TransferFromOrToAddress0.selector);
        pair.safeBatchTransferFrom(address(0), BOB, _ids, amounts);

        vm.prank(DEV);
        vm.expectRevert(LBToken__TransferFromOrToAddress0.selector);
        pair.safeBatchTransferFrom(DEV, address(0), _ids, amounts);

        amounts[0] += 1;
        vm.expectRevert(abi.encodeWithSelector(LBToken__TransferExceedsBalance.selector, DEV, _ids[0], amounts[0]));
        pair.safeBatchTransferFrom(DEV, ALICE, _ids, amounts);

        amounts[0] -= 1; //revert back to proper amount
        _ids[1] = ID_ONE + binAmount;
        vm.expectRevert(abi.encodeWithSelector(LBToken__TransferExceedsBalance.selector, DEV, _ids[1], amounts[1]));
        pair.safeBatchTransferFrom(DEV, ALICE, _ids, amounts);
    }

    function testIdLengthMismatch() public {
        uint24 binAmount = 11;
        uint256 amountIn = 1e18;
        (uint256[] memory _ids, , , ) = addLiquidity(amountIn, ID_ONE, binAmount, 0);

        uint256[] memory amounts = new uint256[](binAmount - 1);
        for (uint256 i; i < binAmount - 1; i++) {
            assertEq(pair.userPositionAt(DEV, i), _ids[i]);
            amounts[i] = pair.balanceOf(DEV, _ids[i]);
        }

        vm.expectRevert(abi.encodeWithSelector(LBToken__LengthMismatch.selector, _ids.length, amounts.length));
        pair.safeBatchTransferFrom(DEV, ALICE, _ids, amounts);
    }

    function testSelfApprovalReverts() public {
        vm.expectRevert(abi.encodeWithSelector(LBToken__SelfApproval.selector, DEV));
        pair.setApprovalForAll(DEV, true);
    }

    function testPrivateViewFunctions() public {
        assertEq(pair.name(), "Liquidity Book Token");
        assertEq(pair.symbol(), "LBT");
    }
}
