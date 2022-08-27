// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

import "./TestHelper.sol";

contract LiquidityBinTokenTest is TestHelper {
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

        (uint256[] memory _ids, , , ) = addLiquidity(amountIn, ID_ONE, 5, 0);

        uint256[] memory amounts = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            assertEq(pair.userPositionAt(DEV, i), _ids[i]);
            amounts[i] = pair.balanceOf(DEV, _ids[i]);
        }
        assertEq(pair.userPositionNb(DEV), 5);

        assertEq(pair.balanceOf(DEV, ID_ONE - 1), amountIn / 3);

        pair.safeBatchTransferFrom(DEV, ALICE, _ids, amounts);
        assertEq(pair.balanceOf(DEV, ID_ONE - 1), 0);
        assertEq(pair.balanceOf(ALICE, ID_ONE - 1), amountIn / 3);

        vm.prank(ALICE);
        pair.setApprovalForAll(BOB, true);
        assertTrue(pair.isApprovedForAll(ALICE, BOB));
        assertFalse(pair.isApprovedForAll(BOB, ALICE));

        vm.prank(BOB);
        pair.safeBatchTransferFrom(ALICE, BOB, _ids, amounts);
        assertEq(pair.balanceOf(DEV, ID_ONE - 1), 0); // DEV
        assertEq(pair.balanceOf(ALICE, ID_ONE - 1), 0);
        assertEq(pair.balanceOf(BOB, ID_ONE - 1), amountIn / 3);
    }

    function testFailTransferNotApproved() public {
        uint256 amountIn = 1e18;
        token18D.mint(address(pair), amountIn);

        uint256[] memory ids = new uint256[](2);
        ids[0] = ID_ONE;
        ids[1] = ID_ONE - 1;
        uint256[] memory liquidities = new uint256[](2);
        liquidities[0] = 0;
        liquidities[1] = amountIn;

        pair.mint(ids, liquidities, new uint256[](2), DEV);

        pair.safeBatchTransferFrom(DEV, ALICE, ids, liquidities);

        vm.prank(BOB);
        pair.safeBatchTransferFrom(ALICE, BOB, ids, liquidities);
    }

    function testFailWrongIdTransfer() public {
        uint256 amountIn = 1e18;
        token18D.mint(address(pair), amountIn);

        uint256[] memory ids = new uint256[](2);
        ids[0] = ID_ONE;
        ids[1] = ID_ONE - 1;
        uint256[] memory liquidities = new uint256[](2);
        liquidities[0] = 0;
        liquidities[1] = amountIn;

        pair.mint(ids, liquidities, new uint256[](2), DEV);

        ids[1] = ID_ONE - 2;
        pair.safeBatchTransferFrom(DEV, ALICE, ids, liquidities);
    }
}
