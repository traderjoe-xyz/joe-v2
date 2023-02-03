// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./helpers/TestHelper.sol";

contract LBPairLiquidityTest is TestHelper {
    using SafeCast for uint256;

    uint256 constant PRECISION = 1e18;

    uint24 immutable activeId = ID_ONE - 24647; // id where 1 AVAX = 20 USDC

    function setUp() public override {
        super.setUp();

        pairWavax = createLBPairFromStartId(wavax, usdc, activeId);
    }

    function test_SimpleMint() external {
        uint256 amountX = 100 * 10 ** 18;
        uint256 amountY = 2_000 * 10 ** 6;
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWavax, activeId, amountX, amountY, nbBinX, nbBinY);

        assertEq(wavax.balanceOf(ALICE), amountX - amountX * (PRECISION / nbBinX) / 1e18 * nbBinX, "test_SimpleMint::1");
        assertEq(usdc.balanceOf(ALICE), amountY - amountY * (PRECISION / nbBinY) / 1e18 * nbBinY, "test_SimpleMint::2");

        uint256 total = getTotalBins(nbBinX, nbBinY);
        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            (uint128 binReserveX, uint128 binReserveY) = pairWavax.getBin(id);

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

            assertGt(pairWavax.balanceOf(BOB, id), 0, "test_SimpleMint::9");
            assertEq(pairWavax.balanceOf(ALICE, id), 0, "test_SimpleMint::10");
        }
    }

    function test_MintTwice() external {
        uint256 amountX = 100 * 10 ** 18;
        uint256 amountY = 2_000 * 10 ** 6;
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWavax, activeId, amountX, amountY, nbBinX, nbBinY);

        uint256 total = getTotalBins(nbBinX, nbBinY);
        uint256[] memory balances = new uint256[](total);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            balances[i] = pairWavax.balanceOf(BOB, id);
        }

        addLiquidity(ALICE, BOB, pairWavax, activeId, amountX, amountY, nbBinX, nbBinY);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            (uint128 binReserveX, uint128 binReserveY) = pairWavax.getBin(id);

            if (id < activeId) {
                assertEq(binReserveX, 0, "test_SimpleMint::1");
                assertEq(binReserveY, 2 * (amountY * (PRECISION / nbBinY) / 1e18), "test_SimpleMint::2");
            } else if (id == activeId) {
                assertApproxEqRel(binReserveX, 2 * (amountX * (PRECISION / nbBinX) / 1e18), 1e15, "test_SimpleMint::3");
                assertApproxEqRel(binReserveY, 2 * (amountY * (PRECISION / nbBinY) / 1e18), 1e15, "test_SimpleMint::4");
            } else {
                assertEq(binReserveX, 2 * (amountX * (PRECISION / nbBinX) / 1e18), "test_SimpleMint::5");
                assertEq(binReserveY, 0, "test_SimpleMint::6");
            }

            assertEq(pairWavax.balanceOf(BOB, id), 2 * balances[i], "test_DoubleMint::7");
        }
    }

    function test_MintWithDifferentBins() external {
        uint256 amountX = 100 * 10 ** 18;
        uint256 amountY = 2_000 * 10 ** 6;
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWavax, activeId, amountX, amountY, nbBinX, nbBinY);

        uint256 total = getTotalBins(nbBinX, nbBinY);
        uint256[] memory balances = new uint256[](total);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            balances[i] = pairWavax.balanceOf(BOB, id);
        }

        addLiquidity(ALICE, BOB, pairWavax, activeId, amountX, amountY, nbBinX, 0);
        addLiquidity(ALICE, BOB, pairWavax, activeId, amountX, amountY, 0, nbBinY);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            if (id == activeId) {
                assertApproxEqRel(pairWavax.balanceOf(BOB, id), 2 * balances[i], 1e15, "test_MintWithDifferentBins::1"); // composition fee
            } else {
                assertEq(pairWavax.balanceOf(BOB, id), 2 * balances[i], "test_MintWithDifferentBins::2");
            }
        }
    }

    function test_SimpleBurn() external {
        uint256 amountX = 100 * 10 ** 18;
        uint256 amountY = 2_000 * 10 ** 6;
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWavax, activeId, amountX, amountY, nbBinX, nbBinY);

        uint256 total = getTotalBins(nbBinX, nbBinY);

        uint256[] memory balances = new uint256[](total);
        uint256[] memory ids = new uint256[](total);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            ids[i] = id;
            balances[i] = pairWavax.balanceOf(BOB, id);
        }

        (uint128 reserveX, uint128 reserveY) = pairWavax.getReserves();

        vm.prank(BOB);
        pairWavax.burn(BOB, BOB, ids, balances);

        assertEq(wavax.balanceOf(BOB), reserveX, "test_SimpleBurn::1");
        assertEq(usdc.balanceOf(BOB), reserveY, "test_SimpleBurn::2");
        (reserveX, reserveY) = pairWavax.getReserves();

        assertEq(reserveX, 0, "test_BurnPartial::3");
        assertEq(reserveY, 0, "test_BurnPartial::4");
    }

    function test_BurnHalfTwice() external {
        uint256 amountX = 100 * 10 ** 18;
        uint256 amountY = 2_000 * 10 ** 6;
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWavax, activeId, amountX, amountY, nbBinX, nbBinY);

        uint256 total = getTotalBins(nbBinX, nbBinY);

        uint256[] memory halfbalances = new uint256[](total);
        uint256[] memory balances = new uint256[](total);
        uint256[] memory ids = new uint256[](total);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            ids[i] = id;
            uint256 balance = pairWavax.balanceOf(BOB, id);

            halfbalances[i] = balance / 2;
            balances[i] = balance - balance / 2;
        }

        (uint128 reserveX, uint128 reserveY) = pairWavax.getReserves();

        vm.prank(BOB);
        pairWavax.burn(BOB, BOB, ids, halfbalances);

        assertApproxEqRel(wavax.balanceOf(BOB), reserveX / 2, 1e10, "test_BurnPartial::1");
        assertApproxEqRel(usdc.balanceOf(BOB), reserveY / 2, 1e10, "test_BurnPartial::2");

        vm.prank(BOB);
        pairWavax.burn(BOB, BOB, ids, balances);

        assertEq(wavax.balanceOf(BOB), reserveX, "test_BurnPartial::3");
        assertEq(usdc.balanceOf(BOB), reserveY, "test_BurnPartial::4");

        (reserveX, reserveY) = pairWavax.getReserves();

        assertEq(reserveX, 0, "test_BurnPartial::5");
        assertEq(reserveY, 0, "test_BurnPartial::6");
    }

    function test_GetNextNonEmptyBin() external {
        uint8 nbBinX = 6;
        uint8 nbBinY = 6;

        addLiquidity(ALICE, BOB, pairWavax, activeId, 100 * 10 ** 18, 2_000 * 10 ** 6, nbBinX, nbBinY);

        uint24 lowId = activeId - nbBinY + 1;
        uint24 upperId = activeId + nbBinX - 1;

        uint24 id = pairWavax.getNextNonEmptyBin(false, 0);

        assertEq(id, lowId, "test_GetNextNonEmptyBin::1");

        uint256 total = getTotalBins(nbBinX, nbBinY);

        for (uint256 i; i < total - 1; ++i) {
            id = pairWavax.getNextNonEmptyBin(false, id);

            assertEq(id, lowId + i + 1, "test_GetNextNonEmptyBin::2");
        }

        id = pairWavax.getNextNonEmptyBin(true, type(uint24).max);

        assertEq(id, upperId, "test_GetNextNonEmptyBin::3");

        uint256[] memory ids = new uint256[](1);
        uint256[] memory balances = new uint256[](1);

        ids[0] = activeId;
        balances[0] = pairWavax.balanceOf(BOB, activeId);

        vm.prank(BOB);
        pairWavax.burn(BOB, BOB, ids, balances);

        id = pairWavax.getNextNonEmptyBin(false, activeId - 1);

        assertEq(id, activeId + 1, "test_GetNextNonEmptyBin::4");

        id = pairWavax.getNextNonEmptyBin(true, activeId + 1);

        assertEq(id, activeId - 1, "test_GetNextNonEmptyBin::5");
    }

    function test_revert_MintEmptyConfig() external {
        bytes32[] memory data = new bytes32[](0);
        vm.expectRevert(ILBPair.LBPair__EmptyMarketConfigs.selector);
        pairWavax.mint(BOB, data, BOB);
    }

    function test_revert_MintZeroShares() external {
        bytes32[] memory data = new bytes32[](1);
        data[0] = LiquidityConfigurations.encodeParams(1e18, 1e18, activeId);
        vm.expectRevert(abi.encodeWithSelector(ILBPair.LBPair__ZeroShares.selector, activeId));
        pairWavax.mint(BOB, data, BOB);
    }

    function test_revert_MintMoreThanAmountSent() external {
        deal(address(wavax), address(pairWavax), 1e18);
        deal(address(usdc), address(pairWavax), 1e18);

        bytes32[] memory data = new bytes32[](2);
        data[0] = LiquidityConfigurations.encodeParams(0, 0.5e18, activeId - 1);
        data[1] = LiquidityConfigurations.encodeParams(0, 0.5e18 + 1, activeId);
        vm.expectRevert(PackedUint128Math.PackedUint128Math__SubUnderflow.selector);
        pairWavax.mint(BOB, data, BOB);

        data[1] = LiquidityConfigurations.encodeParams(0.5e18, 0, activeId);
        data[0] = LiquidityConfigurations.encodeParams(0.5e18 + 1, 0, activeId + 1);
        vm.expectRevert(PackedUint128Math.PackedUint128Math__SubUnderflow.selector);
        pairWavax.mint(BOB, data, BOB);
    }

    function test_revert_BurnEmptyArraysOrDifferent() external {
        uint256[] memory ids = new uint256[](0);
        uint256[] memory balances = new uint256[](1);

        vm.expectRevert(ILBPair.LBPair__InvalidInput.selector);
        pairWavax.burn(DEV, DEV, ids, balances);

        ids = new uint256[](1);
        balances = new uint256[](0);

        vm.expectRevert(ILBPair.LBPair__InvalidInput.selector);
        pairWavax.burn(DEV, DEV, ids, balances);

        ids = new uint256[](0);
        balances = new uint256[](0);

        vm.expectRevert(ILBPair.LBPair__InvalidInput.selector);
        pairWavax.burn(DEV, DEV, ids, balances);

        ids = new uint256[](1);
        balances = new uint256[](2);

        vm.expectRevert(ILBPair.LBPair__InvalidInput.selector);
        pairWavax.burn(DEV, DEV, ids, balances);
    }

    function test_revert_BurnMoreThanBalance() external {
        addLiquidity(ALICE, ALICE, pairWavax, activeId, 1e18, 1e18, 1, 0);
        addLiquidity(DEV, DEV, pairWavax, activeId, 1e18, 1e18, 1, 0);

        uint256[] memory ids = new uint256[](1);
        uint256[] memory balances = new uint256[](1);

        ids[0] = activeId;
        balances[0] = pairWavax.balanceOf(DEV, activeId) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(ILBToken.LBToken__BurnExceedsBalance.selector, DEV, activeId, balances[0])
        );
        pairWavax.burn(DEV, DEV, ids, balances);
    }

    function test_revert_BurnZeroShares() external {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory balances = new uint256[](1);

        ids[0] = activeId;
        balances[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(ILBPair.LBPair__ZeroAmount.selector, activeId));
        pairWavax.burn(DEV, DEV, ids, balances);
    }

    function test_revert_BurnForZeroAmounts() external {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory balances = new uint256[](1);

        ids[0] = activeId;
        balances[0] = 1;

        vm.expectRevert(abi.encodeWithSelector(ILBPair.LBPair__ZeroAmountsOut.selector, activeId));
        pairWavax.burn(DEV, DEV, ids, balances);
    }
}
