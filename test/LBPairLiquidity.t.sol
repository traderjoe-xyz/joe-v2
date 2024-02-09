// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./helpers/TestHelper.sol";

contract LBPairLiquidityTest is TestHelper {
    using SafeCast for uint256;

    uint256 constant PRECISION = 1e18;

    uint24 immutable activeId = ID_ONE - 24647; // id where 1 NATIVE = 20 USDC

    function setUp() public override {
        super.setUp();

        pairWnative = createLBPairFromStartId(wnative, usdc, activeId);
    }

    function test_SimpleMint() external {
        uint256 amountX = 100 * 10 ** 18;
        uint256 amountY = 2_000 * 10 ** 6;
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWnative, activeId, amountX, amountY, nbBinX, nbBinY);

        assertEq(
            wnative.balanceOf(ALICE), amountX - amountX * (PRECISION / nbBinX) / 1e18 * nbBinX, "test_SimpleMint::1"
        );
        assertEq(usdc.balanceOf(ALICE), amountY - amountY * (PRECISION / nbBinY) / 1e18 * nbBinY, "test_SimpleMint::2");

        uint256 total = getTotalBins(nbBinX, nbBinY);
        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            (uint128 binReserveX, uint128 binReserveY) = pairWnative.getBin(id);

            if (id < activeId) {
                assertEq(binReserveX, 0, "test_SimpleMint::3");
                assertEq(binReserveY, amountY * (PRECISION / nbBinY) / 1e18, "test_SimpleMint::4");
            } else if (id == activeId) {
                assertApproxEqRel(binReserveX, amountX * (PRECISION / nbBinX) / 1e18, 1e15, "test_SimpleMint::5");
                assertApproxEqRel(binReserveY, amountY * (PRECISION / nbBinY) / 1e18, 1e15, "test_SimpleMint::6");
            } else {
                assertEq(binReserveX, amountX * (PRECISION / nbBinX) / 1e18, "test_SimpleMint::7");
                assertEq(binReserveY, 0, "test_SimpleMint::8");
            }

            assertGt(pairWnative.balanceOf(BOB, id), 0, "test_SimpleMint::9");
            assertEq(pairWnative.balanceOf(ALICE, id), 0, "test_SimpleMint::10");
        }
    }

    function test_MintTwice() external {
        uint256 amountX = 100 * 10 ** 18;
        uint256 amountY = 2_000 * 10 ** 6;
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWnative, activeId, amountX, amountY, nbBinX, nbBinY);

        uint256 total = getTotalBins(nbBinX, nbBinY);
        uint256[] memory balances = new uint256[](total);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            balances[i] = pairWnative.balanceOf(BOB, id);
        }

        addLiquidity(ALICE, BOB, pairWnative, activeId, amountX, amountY, nbBinX, nbBinY);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            (uint128 binReserveX, uint128 binReserveY) = pairWnative.getBin(id);

            if (id < activeId) {
                assertEq(binReserveX, 0, "test_MintTwice::1");
                assertEq(binReserveY, 2 * (amountY * (PRECISION / nbBinY) / 1e18), "test_MintTwice::2");
            } else if (id == activeId) {
                assertApproxEqRel(binReserveX, 2 * (amountX * (PRECISION / nbBinX) / 1e18), 1e15, "test_MintTwice::3");
                assertApproxEqRel(binReserveY, 2 * (amountY * (PRECISION / nbBinY) / 1e18), 1e15, "test_MintTwice::4");
            } else {
                assertEq(binReserveX, 2 * (amountX * (PRECISION / nbBinX) / 1e18), "test_MintTwice::5");
                assertEq(binReserveY, 0, "test_MintTwice::6");
            }

            assertEq(pairWnative.balanceOf(BOB, id), 2 * balances[i], "test_MintTwice::7");
        }
    }

    function test_MintWithDifferentBins() external {
        uint256 amountX = 100 * 10 ** 18;
        uint256 amountY = 2_000 * 10 ** 6;
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWnative, activeId, amountX, amountY, nbBinX, nbBinY);

        uint256 total = getTotalBins(nbBinX, nbBinY);
        uint256[] memory balances = new uint256[](total);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            balances[i] = pairWnative.balanceOf(BOB, id);
        }

        addLiquidity(ALICE, BOB, pairWnative, activeId, amountX, amountY, nbBinX, 0);
        addLiquidity(ALICE, BOB, pairWnative, activeId, amountX, amountY, 0, nbBinY);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            if (id == activeId) {
                assertApproxEqRel(
                    pairWnative.balanceOf(BOB, id), 2 * balances[i], 1e15, "test_MintWithDifferentBins::1"
                ); // composition fee
            } else {
                assertEq(pairWnative.balanceOf(BOB, id), 2 * balances[i], "test_MintWithDifferentBins::2");
            }
        }
    }

    function test_SimpleBurn() external {
        uint256 amountX = 100 * 10 ** 18;
        uint256 amountY = 2_000 * 10 ** 6;
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWnative, activeId, amountX, amountY, nbBinX, nbBinY);

        uint256 total = getTotalBins(nbBinX, nbBinY);

        uint256[] memory balances = new uint256[](total);
        uint256[] memory ids = new uint256[](total);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            ids[i] = id;
            balances[i] = pairWnative.balanceOf(BOB, id);
        }

        (uint128 reserveX, uint128 reserveY) = pairWnative.getReserves();

        vm.prank(BOB);
        pairWnative.burn(BOB, BOB, ids, balances);

        assertEq(wnative.balanceOf(BOB), reserveX, "test_SimpleBurn::1");
        assertEq(usdc.balanceOf(BOB), reserveY, "test_SimpleBurn::2");
        (reserveX, reserveY) = pairWnative.getReserves();

        assertEq(reserveX, 0, "test_SimpleBurn::3");
        assertEq(reserveY, 0, "test_SimpleBurn::4");
    }

    function test_BurnHalfTwice() external {
        uint256 amountX = 100 * 10 ** 18;
        uint256 amountY = 2_000 * 10 ** 6;
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWnative, activeId, amountX, amountY, nbBinX, nbBinY);

        uint256 total = getTotalBins(nbBinX, nbBinY);

        uint256[] memory halfbalances = new uint256[](total);
        uint256[] memory balances = new uint256[](total);
        uint256[] memory ids = new uint256[](total);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            ids[i] = id;
            uint256 balance = pairWnative.balanceOf(BOB, id);

            halfbalances[i] = balance / 2;
            balances[i] = balance - balance / 2;
        }

        (uint128 reserveX, uint128 reserveY) = pairWnative.getReserves();

        vm.prank(BOB);
        pairWnative.burn(BOB, BOB, ids, halfbalances);

        assertApproxEqRel(wnative.balanceOf(BOB), reserveX / 2, 1e10, "test_BurnHalfTwice::1");
        assertApproxEqRel(usdc.balanceOf(BOB), reserveY / 2, 1e10, "test_BurnHalfTwice::2");

        vm.prank(BOB);
        pairWnative.burn(BOB, BOB, ids, balances);

        assertEq(wnative.balanceOf(BOB), reserveX, "test_BurnHalfTwice::3");
        assertEq(usdc.balanceOf(BOB), reserveY, "test_BurnHalfTwice::4");

        (reserveX, reserveY) = pairWnative.getReserves();

        assertEq(reserveX, 0, "test_BurnHalfTwice::5");
        assertEq(reserveY, 0, "test_BurnHalfTwice::6");
    }

    function test_GetNextNonEmptyBin() external {
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWnative, activeId, 100 * 10 ** 18, 2_000 * 10 ** 6, nbBinX, nbBinY);

        uint24 lowId = activeId - nbBinY + 1;
        uint24 upperId = activeId + nbBinX - 1;

        uint24 id = pairWnative.getNextNonEmptyBin(false, 0);

        assertEq(id, lowId, "test_GetNextNonEmptyBin::1");

        uint256 total = getTotalBins(nbBinX, nbBinY);

        for (uint256 i; i < total - 1; ++i) {
            id = pairWnative.getNextNonEmptyBin(false, id);

            assertEq(id, lowId + i + 1, "test_GetNextNonEmptyBin::2");
        }

        id = pairWnative.getNextNonEmptyBin(true, type(uint24).max);

        assertEq(id, upperId, "test_GetNextNonEmptyBin::3");

        uint256[] memory ids = new uint256[](1);
        uint256[] memory balances = new uint256[](1);

        ids[0] = activeId;
        balances[0] = pairWnative.balanceOf(BOB, activeId);

        vm.prank(BOB);
        pairWnative.burn(BOB, BOB, ids, balances);

        id = pairWnative.getNextNonEmptyBin(false, activeId - 1);

        assertEq(id, activeId + 1, "test_GetNextNonEmptyBin::4");

        id = pairWnative.getNextNonEmptyBin(true, activeId + 1);

        assertEq(id, activeId - 1, "test_GetNextNonEmptyBin::5");
    }

    function test_revert_MintEmptyConfig() external {
        bytes32[] memory data = new bytes32[](0);
        vm.expectRevert(ILBPair.LBPair__EmptyMarketConfigs.selector);
        pairWnative.mint(BOB, data, BOB);
    }

    function test_revert_MintZeroShares() external {
        bytes32[] memory data = new bytes32[](1);
        data[0] = LiquidityConfigurations.encodeParams(1e18, 1e18, activeId);
        vm.expectRevert(abi.encodeWithSelector(ILBPair.LBPair__ZeroShares.selector, activeId));
        pairWnative.mint(BOB, data, BOB);
    }

    function test_revert_MintMoreThanAmountSent() external {
        deal(address(wnative), address(pairWnative), 1e18);
        deal(address(usdc), address(pairWnative), 1e18);

        bytes32[] memory data = new bytes32[](2);
        data[0] = LiquidityConfigurations.encodeParams(0, 0.5e18, activeId - 1);
        data[1] = LiquidityConfigurations.encodeParams(0, 0.5e18 + 1, activeId);
        vm.expectRevert(PackedUint128Math.PackedUint128Math__SubUnderflow.selector);
        pairWnative.mint(BOB, data, BOB);

        data[1] = LiquidityConfigurations.encodeParams(0.5e18, 0, activeId);
        data[0] = LiquidityConfigurations.encodeParams(0.5e18 + 1, 0, activeId + 1);
        vm.expectRevert(PackedUint128Math.PackedUint128Math__SubUnderflow.selector);
        pairWnative.mint(BOB, data, BOB);
    }

    function test_revert_BurnEmptyArraysOrDifferent() external {
        uint256[] memory ids = new uint256[](0);
        uint256[] memory balances = new uint256[](1);

        vm.expectRevert(ILBPair.LBPair__InvalidInput.selector);
        pairWnative.burn(DEV, DEV, ids, balances);

        ids = new uint256[](1);
        balances = new uint256[](0);

        vm.expectRevert(ILBPair.LBPair__InvalidInput.selector);
        pairWnative.burn(DEV, DEV, ids, balances);

        ids = new uint256[](0);
        balances = new uint256[](0);

        vm.expectRevert(ILBPair.LBPair__InvalidInput.selector);
        pairWnative.burn(DEV, DEV, ids, balances);

        ids = new uint256[](1);
        balances = new uint256[](2);

        vm.expectRevert(ILBPair.LBPair__InvalidInput.selector);
        pairWnative.burn(DEV, DEV, ids, balances);
    }

    function test_revert_BurnMoreThanBalance() external {
        addLiquidity(ALICE, ALICE, pairWnative, activeId, 1e18, 1e18, 1, 0);
        addLiquidity(DEV, DEV, pairWnative, activeId, 1e18, 1e18, 1, 0);

        uint256[] memory ids = new uint256[](1);
        uint256[] memory balances = new uint256[](1);

        ids[0] = activeId;
        balances[0] = pairWnative.balanceOf(DEV, activeId) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(ILBToken.LBToken__BurnExceedsBalance.selector, DEV, activeId, balances[0])
        );
        pairWnative.burn(DEV, DEV, ids, balances);
    }

    function test_revert_BurnZeroShares() external {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory balances = new uint256[](1);

        ids[0] = activeId;
        balances[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(ILBPair.LBPair__ZeroAmount.selector, activeId));
        pairWnative.burn(DEV, DEV, ids, balances);
    }

    function test_revert_BurnForZeroAmounts() external {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory balances = new uint256[](1);

        ids[0] = activeId;
        balances[0] = 1;

        addLiquidity(DEV, DEV, pairWnative, activeId, 1e18, 1e18, 1, 1);

        vm.expectRevert(abi.encodeWithSelector(ILBPair.LBPair__ZeroAmountsOut.selector, activeId));
        pairWnative.burn(DEV, DEV, ids, balances);
    }
}
