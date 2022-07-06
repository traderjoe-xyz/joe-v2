// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinTokenTest is TestHelper {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV);
        new LBFactoryHelper(factory);
        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testSafeBatchTransferFrom() public {
        uint256 amountIn = 1e18;
        token18D.mint(address(pair), amountIn);

        uint256[] memory ids = new uint256[](2);
        ids[0] = ID_ONE;
        ids[1] = ID_ONE - 1;
        uint256[] memory liquidities = new uint256[](2);
        liquidities[0] = 0;
        liquidities[1] = amountIn;

        pair.mint(ids, liquidities, new uint256[](2), DEV);

        assertEq(pair.balanceOf(DEV, ID_ONE - 1), amountIn);
        pair.safeBatchTransferFrom(DEV, ALICE, ids, liquidities);
        assertEq(pair.balanceOf(DEV, ID_ONE - 1), 0);
        assertEq(pair.balanceOf(ALICE, ID_ONE - 1), amountIn);

        vm.prank(ALICE);
        pair.setApprovalForAll(BOB, true);
        assertTrue(pair.isApprovedForAll(ALICE, BOB));
        assertFalse(pair.isApprovedForAll(BOB, ALICE));

        vm.prank(BOB);
        pair.safeBatchTransferFrom(ALICE, BOB, ids, liquidities);
        assertEq(pair.balanceOf(ALICE, ID_ONE - 1), 0);
        assertEq(pair.balanceOf(BOB, ID_ONE - 1), amountIn);

        address[] memory accounts = new address[](3);
        accounts[0] = DEV;
        accounts[1] = ALICE;
        accounts[2] = BOB;
        ids = new uint256[](3);
        ids[0] = ID_ONE - 1;
        ids[1] = ID_ONE - 1;
        ids[2] = ID_ONE - 1;
        uint256[] memory batchBalances = pair.balanceOfBatch(accounts, ids);
        assertEq(batchBalances[0], 0); // DEV
        assertEq(batchBalances[1], 0); // ALICE
        assertEq(batchBalances[2], amountIn); // BOB
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
