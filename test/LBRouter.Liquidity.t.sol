// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "test/helpers/TestHelper.sol";

/**
 * Test scenarios:
 * 1. Receive
 * 2. Create LBPair
 * 3. Add Liquidity
 * 4. Add liquidity NATIVE
 * 5. Remove liquidity
 * 6. Remove liquidity NATIVE
 * 7. Sweep ERC20s
 * 8. Sweep LBToken
 */
contract LiquidityBinRouterTest is TestHelper {
    bool blockReceive;

    function setUp() public override {
        super.setUp();

        factory.setPresetOpenState(DEFAULT_BIN_STEP, true);

        // Create necessary pairs
        router.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(wnative, usdc, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(taxToken, usdc, ID_ONE, DEFAULT_BIN_STEP);

        uint256 startingBalance = type(uint112).max;
        deal(address(usdc), address(this), startingBalance);
        deal(address(usdt), address(this), startingBalance);
        deal(address(bnb), address(this), startingBalance);
        deal(address(weth), address(this), startingBalance);
    }

    function test_Constructor() public  view {
        assertEq(address(router.getFactory()), address(factory), "test_Constructor::1");
        assertEq(address(router.getLegacyFactory()), address(legacyFactoryV2), "test_Constructor::2");
        assertEq(address(router.getV1Factory()), address(factoryV1), "test_Constructor::3");
        assertEq(address(router.getLegacyRouter()), address(legacyRouterV2), "test_Constructor::4");
        assertEq(address(router.getWNATIVE()), address(wnative), "test_Constructor::5");
    }

    function test_AddLiquidityBadId() public {
        factory.setPreset(1, 10_000, 1, 10, 5_000, 1, 0, 1, false);

        uint24 id = 1 << 23;
        LBPair lbPair = createLBPairFromStartIdAndBinStep(usdt, usdc, id, 1);

        addLiquidity(DEV, DEV, lbPair, id - 1, 0, 1e18, 0, 1);
        addLiquidity(DEV, DEV, lbPair, id, 1e18, 1e18, 1, 1);

        removeLiquidity(DEV, DEV, lbPair, id - 1, 1e18, 1, 1);

        addLiquidity(DEV, DEV, lbPair, 8000000, 0, 1e18, 0, 1);

        deal(address(usdt), address(DEV), 2e18);

        vm.prank(DEV);
        usdt.transfer(address(lbPair), 2e18);

        lbPair.swap(true, DEV);
    }

    function test_ReceiveNATIVE() public {
        // Users can't send NATIVE to the router
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__SenderIsNotWNATIVE.selector));
        (bool success,) = address(router).call{value: 1e18}("");

        // WNATIVE can
        deal(address(wnative), 1e18);
        vm.prank(address(wnative));
        (success,) = address(router).call{value: 1e18}("");

        assertTrue(success, "test_ReceiveNATIVE::1");
    }

    function test_CreatePair() public {
        router.createLBPair(weth, usdc, ID_ONE, DEFAULT_BIN_STEP);

        factory.setPresetOpenState(DEFAULT_BIN_STEP, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBFactory.LBFactory__PresetIsLockedForUsers.selector, address(router), DEFAULT_BIN_STEP
            )
        );
        router.createLBPair(bnb, usdc, ID_ONE, DEFAULT_BIN_STEP);
    }

    function testFuzz_AddLiquidityNoSlippage(uint256 amountYIn, uint24 binNumber, uint24 gap) public {
        amountYIn = bound(amountYIn, 5_000, type(uint112).max);
        binNumber = uint24(bound(binNumber, 0, 400));
        binNumber = binNumber * 2 + 1;
        gap = uint24(bound(gap, 0, 20));

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.refundTo = BOB;

        // Add liquidity
        (
            uint256 amountXAdded,
            uint256 amountYAdded,
            uint256 amountXLeft,
            uint256 amountYLeft,
            uint256[] memory depositIds,
            uint256[] memory liquidityMinted
        ) = router.addLiquidity(liquidityParameters);

        // Check amounts
        assertEq(amountXAdded, liquidityParameters.amountX - amountXLeft, "testFuzz_AddLiquidityNoSlippage::1");
        assertEq(amountYAdded, liquidityParameters.amountY - amountYLeft, "testFuzz_AddLiquidityNoSlippage::2");
        assertLt(amountXLeft, amountXAdded, "testFuzz_AddLiquidityNoSlippage::3");
        assertLt(amountYLeft, amountYAdded, "testFuzz_AddLiquidityNoSlippage::4");

        assertEq(usdt.balanceOf(BOB), amountXLeft, "testFuzz_AddLiquidityNoSlippage::5");
        assertEq(usdc.balanceOf(BOB), amountYLeft, "testFuzz_AddLiquidityNoSlippage::6");

        // Check liquidity minted
        assertEq(liquidityMinted.length, binNumber, "testFuzz_AddLiquidityNoSlippage::7");
        assertEq(depositIds.length, binNumber, "testFuzz_AddLiquidityNoSlippage::8");
    }

    function test_revert_AddLiquidity() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        // Revert if tokens are in the wrong order
        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdc, usdt, amountYIn, ID_ONE, binNumber, gap);

        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__WrongTokenOrder.selector));
        router.addLiquidity(liquidityParameters);

        // Revert if the liquidity arrays are not the same length
        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.deltaIds = new int256[](binNumber - 1);

        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.addLiquidity(liquidityParameters);

        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.distributionY = new uint256[](binNumber - 1);

        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__LengthsMismatch.selector));
        router.addLiquidity(liquidityParameters);

        // Active Id required can't be greater than type(uint24).max
        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.activeIdDesired = uint256(type(uint24).max) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__IdDesiredOverflows.selector,
                liquidityParameters.activeIdDesired,
                liquidityParameters.idSlippage
            )
        );
        router.addLiquidity(liquidityParameters);

        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.idSlippage = uint256(type(uint24).max) + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__IdDesiredOverflows.selector,
                liquidityParameters.activeIdDesired,
                liquidityParameters.idSlippage
            )
        );
        router.addLiquidity(liquidityParameters);

        // Absolute IDs can't overflow
        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.deltaIds[0] = -int256(uint256(ID_ONE)) - 1;

        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__IdOverflows.selector, type(uint256).max));
        router.addLiquidity(liquidityParameters);

        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.deltaIds[0] = int256(uint256(ID_ONE));

        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__IdOverflows.selector, uint256(type(uint24).max) + 1));
        router.addLiquidity(liquidityParameters);

        // Revert if ID slippage is caught
        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.activeIdDesired = ID_ONE - 10;
        liquidityParameters.idSlippage = 5;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__IdSlippageCaught.selector,
                liquidityParameters.activeIdDesired,
                liquidityParameters.idSlippage,
                ID_ONE
            )
        );
        router.addLiquidity(liquidityParameters);

        liquidityParameters.activeIdDesired = ID_ONE + 10;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__IdSlippageCaught.selector,
                liquidityParameters.activeIdDesired,
                liquidityParameters.idSlippage,
                ID_ONE
            )
        );
        router.addLiquidity(liquidityParameters);

        // Revert if slippage is too high
        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.amountXMin = liquidityParameters.amountX + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__AmountSlippageCaught.selector,
                liquidityParameters.amountXMin,
                liquidityParameters.amountX - 2,
                liquidityParameters.amountYMin,
                liquidityParameters.amountY
            )
        );
        router.addLiquidity(liquidityParameters);

        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.amountYMin = liquidityParameters.amountY + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__AmountSlippageCaught.selector,
                liquidityParameters.amountXMin,
                liquidityParameters.amountX - 2,
                liquidityParameters.amountYMin,
                liquidityParameters.amountY
            )
        );
        router.addLiquidity(liquidityParameters);

        // Revert is the deadline passed
        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);

        skip(2_000);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__DeadlineExceeded.selector, liquidityParameters.deadline, block.timestamp
            )
        );
        router.addLiquidity(liquidityParameters);
    }

    function test_AddLiquidityNATIVE() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(wnative, usdc, amountYIn, ID_ONE, binNumber, gap);

        // Add liquidity
        (
            uint256 amountXAdded,
            uint256 amountYAdded,
            uint256 amountXLeft,
            uint256 amountYLeft,
            uint256[] memory depositIds,
            uint256[] memory liquidityMinted
        ) = router.addLiquidityNATIVE{value: liquidityParameters.amountX}(liquidityParameters);

        // Check amounts
        assertEq(amountXAdded, liquidityParameters.amountX - amountXLeft, "test_AddLiquidityNATIVE::1");
        assertEq(amountYAdded, liquidityParameters.amountY - amountYLeft, "test_AddLiquidityNATIVE::2");
        assertLt(amountXLeft, amountXAdded, "test_AddLiquidityNATIVE::3");
        assertLt(amountYLeft, amountYAdded, "test_AddLiquidityNATIVE::4");

        // Check liquidity minted
        assertEq(liquidityMinted.length, binNumber, "test_AddLiquidityNATIVE::5");
        assertEq(depositIds.length, binNumber, "test_AddLiquidityNATIVE::6");

        // Test with NATIVE as token Y
        router.createLBPair(bnb, wnative, ID_ONE, DEFAULT_BIN_STEP);

        liquidityParameters = getLiquidityParameters(bnb, wnative, amountYIn, ID_ONE, binNumber, gap);

        router.addLiquidityNATIVE{value: liquidityParameters.amountY}(liquidityParameters);
    }

    function test_revert_AddLiquidityNATIVE() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        // Revert if tokens are in the wrong order
        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdc, wnative, amountYIn, ID_ONE, binNumber, gap);

        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__WrongTokenOrder.selector));
        router.addLiquidityNATIVE{value: liquidityParameters.amountY}(liquidityParameters);

        // Revert if for non WNATIVE pairs
        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__WrongNativeLiquidityParameters.selector,
                address(liquidityParameters.tokenX),
                address(liquidityParameters.tokenY),
                liquidityParameters.amountX,
                liquidityParameters.amountY,
                liquidityParameters.amountY
            )
        );
        router.addLiquidityNATIVE{value: liquidityParameters.amountY}(liquidityParameters);

        // Revert if the amount of NATIVE isn't correct
        liquidityParameters = getLiquidityParameters(wnative, usdc, amountYIn, ID_ONE, binNumber, gap);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__WrongNativeLiquidityParameters.selector,
                address(liquidityParameters.tokenX),
                address(liquidityParameters.tokenY),
                liquidityParameters.amountX,
                liquidityParameters.amountY,
                liquidityParameters.amountY
            )
        );
        // liquidityParameters.amountX should be sent as message value
        router.addLiquidityNATIVE{value: liquidityParameters.amountY}(liquidityParameters);
    }

    function test_RemoveLiquidity() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);

        // Add liquidity
        (uint256 amountXAdded, uint256 amountYAdded,,, uint256[] memory depositIds, uint256[] memory liquidityMinted) =
            router.addLiquidity(liquidityParameters);

        ILBPair pair = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).LBPair;

        pair.approveForAll(address(router), true);

        (uint256 amountXOut, uint256 amountYOut) = router.removeLiquidity(
            usdt, usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, address(this), block.timestamp
        );

        assertApproxEqAbs(amountXOut, amountXAdded, 10, "test_RemoveLiquidity::1");
        assertApproxEqAbs(amountYOut, amountYAdded, 10, "test_RemoveLiquidity::2");

        assertLe(amountXOut, amountXAdded, "test_RemoveLiquidity::3");
        assertLe(amountYOut, amountYAdded, "test_RemoveLiquidity::4");

        for (uint256 i = 0; i < depositIds.length; i++) {
            assertEq(pair.balanceOf(address(this), depositIds[i]), 0, "test_RemoveLiquidity::5");
        }

        // Try with the token inversed
        (amountXAdded, amountYAdded,,, depositIds, liquidityMinted) = router.addLiquidity(liquidityParameters);

        (amountYOut, amountXOut) = router.removeLiquidity(
            usdc, usdt, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, address(this), block.timestamp
        );

        assertApproxEqAbs(amountXOut, amountXAdded, 10, "test_RemoveLiquidity::6");
        assertApproxEqAbs(amountYOut, amountYAdded, 10, "test_RemoveLiquidity::7");

        // Try removing half of the liquidity
        (amountXAdded, amountYAdded,,, depositIds, liquidityMinted) = router.addLiquidity(liquidityParameters);

        for (uint256 i = 0; i < depositIds.length; i++) {
            liquidityMinted[i] = liquidityMinted[i] / 2;
        }

        (amountXOut, amountYOut) = router.removeLiquidity(
            usdt, usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, address(this), block.timestamp
        );

        assertApproxEqAbs(amountXOut, amountXAdded / 2, 10, "test_RemoveLiquidity::8");
        assertApproxEqAbs(amountYOut, amountYAdded / 2, 10, "test_RemoveLiquidity::9");
    }

    function test_revert_RemoveLiquidity() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);

        // Add liquidity
        (uint256 amountXAdded, uint256 amountYAdded,,, uint256[] memory depositIds, uint256[] memory liquidityMinted) =
            router.addLiquidity(liquidityParameters);

        ILBPair pair = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).LBPair;
        pair.approveForAll(address(router), true);

        // Revert if the deadline is passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.removeLiquidity(
            usdt, usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, address(this), block.timestamp - 1
        );

        // Revert if the slippage is caught
        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__AmountSlippageCaught.selector, amountXAdded + 1, amountXAdded, 0, amountYAdded
            )
        );
        router.removeLiquidity(
            usdt,
            usdc,
            DEFAULT_BIN_STEP,
            amountXAdded + 1,
            0,
            depositIds,
            liquidityMinted,
            address(this),
            block.timestamp
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__AmountSlippageCaught.selector, 0, amountXAdded, amountYAdded + 1, amountYAdded
            )
        );
        router.removeLiquidity(
            usdt,
            usdc,
            DEFAULT_BIN_STEP,
            0,
            amountYAdded + 1,
            depositIds,
            liquidityMinted,
            address(this),
            block.timestamp
        );
    }

    function test_RemoveLiquidityNATIVE() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(wnative, usdc, amountYIn, ID_ONE, binNumber, gap);

        // Add liquidity
        (uint256 amountXAdded, uint256 amountYAdded,,, uint256[] memory depositIds, uint256[] memory liquidityMinted) =
            router.addLiquidityNATIVE{value: liquidityParameters.amountX}(liquidityParameters);

        ILBPair pair = factory.getLBPairInformation(wnative, usdc, DEFAULT_BIN_STEP).LBPair;
        pair.approveForAll(address(router), true);

        uint256 balanceNATIVEBefore = address(this).balance;
        uint256 balanceUSDCBefore = usdc.balanceOf(address(this));

        (uint256 amountToken, uint256 amountNATIVE) = router.removeLiquidityNATIVE(
            usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, payable(address(this)), block.timestamp
        );

        assertApproxEqAbs(amountNATIVE, amountXAdded, 10, "test_RemoveLiquidityNATIVE::1");
        assertApproxEqAbs(amountToken, amountYAdded, 10, "test_RemoveLiquidityNATIVE::2");

        assertEq(address(this).balance, balanceNATIVEBefore + amountNATIVE, "test_RemoveLiquidityNATIVE::3");
        assertEq(usdc.balanceOf(address(this)), balanceUSDCBefore + amountToken, "test_RemoveLiquidityNATIVE::4");
    }

    function test_revert_RemoveLiquidityNATIVE() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(wnative, usdc, amountYIn, ID_ONE, binNumber, gap);

        // Add liquidity
        (uint256 amountXAdded,,,, uint256[] memory depositIds, uint256[] memory liquidityMinted) =
            router.addLiquidityNATIVE{value: liquidityParameters.amountX}(liquidityParameters);

        ILBPair pair = factory.getLBPairInformation(wnative, usdc, DEFAULT_BIN_STEP).LBPair;
        pair.approveForAll(address(router), true);

        // Revert if the deadline is passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.removeLiquidityNATIVE(
            usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, payable(address(this)), block.timestamp - 1
        );

        // Revert if the contract does not have a receive function
        blockReceive = true;
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__FailedToSendNATIVE.selector, address(this), amountXAdded)
        );
        router.removeLiquidityNATIVE(
            usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, payable(address(this)), block.timestamp
        );
    }

    function test_SweepERC20() public {
        uint256 amount = 1e18;
        usdc.mint(address(router), amount);

        uint256 balanceBefore = usdc.balanceOf(address(this));
        router.sweep(usdc, address(this), amount);
        assertEq(usdc.balanceOf(address(this)), balanceBefore + amount, "test_SweepERC20::1");

        deal(address(router), amount);

        balanceBefore = address(this).balance;
        router.sweep(IERC20(address(0)), address(this), type(uint256).max);
        assertEq(address(this).balance, balanceBefore + amount, "test_SweepERC20::2");

        // Can't sweep if non owner
        usdc.mint(address(router), amount);
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__NotFactoryOwner.selector));
        vm.prank(ALICE);
        router.sweep(usdc, address(this), amount);
    }

    function test_SweepLBTokens() public {
        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdt, usdc, 1e18, ID_ONE, 1, 0);

        liquidityParameters.to = address(router);
        (,,,, uint256[] memory depositIds, uint256[] memory liquidityMinted) = router.addLiquidity(liquidityParameters);

        ILBPair pair = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).LBPair;

        uint256[] memory balancesBefore = new uint256[](depositIds.length);
        for (uint256 i = 0; i < depositIds.length; i++) {
            balancesBefore[i] = pair.balanceOf(DEV, depositIds[i]);
        }

        router.sweepLBToken(pair, DEV, depositIds, liquidityMinted);

        for (uint256 i = 0; i < depositIds.length; i++) {
            assertEq(
                pair.balanceOf(DEV, depositIds[i]), balancesBefore[i] + liquidityMinted[i], "test_SweepLBTokens::1"
            );
        }

        (,,,, depositIds, liquidityMinted) = router.addLiquidity(liquidityParameters);

        // Can't sweep if non owner
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__NotFactoryOwner.selector));
        vm.prank(ALICE);
        router.sweepLBToken(pair, DEV, depositIds, liquidityMinted);
    }

    receive() external payable {
        if (blockReceive) {
            revert("No receive function on the contract");
        }
    }
}
