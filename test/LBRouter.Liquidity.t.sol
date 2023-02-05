// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "test/helpers/TestHelper.sol";

/**
 * Test scenarios:
 * 2. Receive
 * 3. Create LBPair
 * 4. Add Liquidity
 * 5. Add liquidity AVAX
 * 6. Remove liquidity
 * 7. Remove liquidity AVAX
 * 8. Sweep ERC20s
 * 9. Sweep LBToken
 */
contract LiquidityBinRouterTest is TestHelper {
    bool blockReceive;

    function setUp() public override {
        super.setUp();

        factory.setOpenPreset(DEFAULT_BIN_STEP, true);

        // Create necessary pairs
        router.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(wavax, usdc, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(taxToken, usdc, ID_ONE, DEFAULT_BIN_STEP);

        uint256 startingBalance = type(uint112).max;
        deal(address(usdc), address(this), startingBalance);
        deal(address(usdt), address(this), startingBalance);
        deal(address(bnb), address(this), startingBalance);
        deal(address(weth), address(this), startingBalance);
    }

    function test_ReceiveAVAX() public {
        // Users can't send AVAX to the router
        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__SenderIsNotWAVAX.selector));
        (bool success,) = address(router).call{value: 1e18}("");

        // WAVAX can
        deal(address(wavax), 1e18);
        vm.prank(address(wavax));
        (success,) = address(router).call{value: 1e18}("");

        assertTrue(success);
    }

    function test_CreatePair() public {
        router.createLBPair(weth, usdc, ID_ONE, DEFAULT_BIN_STEP);

        factory.setOpenPreset(DEFAULT_BIN_STEP, false);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBFactory.LBFactory__FunctionIsLockedForUsers.selector, address(router), DEFAULT_BIN_STEP
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
        assertEq(amountXAdded, liquidityParameters.amountX, "amountXAdded");
        assertEq(amountYAdded, liquidityParameters.amountY, "amountYAdded");
        assertLt(amountXLeft, amountXAdded, "amountXLeft");
        assertLt(amountYLeft, amountYAdded, "amountYLeft");

        assertEq(usdt.balanceOf(BOB), amountXLeft, "usdt balance");
        assertEq(usdc.balanceOf(BOB), amountYLeft, "usdc balance");

        // Check liquidity minted
        assertEq(liquidityMinted.length, binNumber);
        assertEq(depositIds.length, binNumber);
    }

    function test_reverts_AddLiquidity() public {
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

        // Revert is slippage is too high
        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);
        liquidityParameters.amountXMin = liquidityParameters.amountX + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__AmountSlippageCaught.selector,
                liquidityParameters.amountXMin,
                liquidityParameters.amountX,
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
                liquidityParameters.amountX,
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

    function test_AddLiquidityAVAX() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(wavax, usdc, amountYIn, ID_ONE, binNumber, gap);

        // Add liquidity
        (
            uint256 amountXAdded,
            uint256 amountYAdded,
            uint256 amountXLeft,
            uint256 amountYLeft,
            uint256[] memory depositIds,
            uint256[] memory liquidityMinted
        ) = router.addLiquidityAVAX{value: liquidityParameters.amountX}(liquidityParameters);

        // Check amounts
        assertEq(amountXAdded, liquidityParameters.amountX, "amountXAdded");
        assertEq(amountYAdded, liquidityParameters.amountY, "amountYAdded");
        assertLt(amountXLeft, amountXAdded, "amountXLeft");
        assertLt(amountYLeft, amountYAdded, "amountYLeft");

        // Check liquidity minted
        assertEq(liquidityMinted.length, binNumber);
        assertEq(depositIds.length, binNumber);

        // Test with AVAX as token Y
        router.createLBPair(bnb, wavax, ID_ONE, DEFAULT_BIN_STEP);

        liquidityParameters = getLiquidityParameters(bnb, wavax, amountYIn, ID_ONE, binNumber, gap);

        router.addLiquidityAVAX{value: liquidityParameters.amountY}(liquidityParameters);
    }

    function test_reverts_AddLiquidityAVAX() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        // Revert if tokens are in the wrong order
        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdc, wavax, amountYIn, ID_ONE, binNumber, gap);

        vm.expectRevert(abi.encodeWithSelector(ILBRouter.LBRouter__WrongTokenOrder.selector));
        router.addLiquidityAVAX{value: liquidityParameters.amountY}(liquidityParameters);

        // Revert if for non WAVAX pairs
        liquidityParameters = getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__WrongAvaxLiquidityParameters.selector,
                address(liquidityParameters.tokenX),
                address(liquidityParameters.tokenY),
                liquidityParameters.amountX,
                liquidityParameters.amountY,
                liquidityParameters.amountY
            )
        );
        router.addLiquidityAVAX{value: liquidityParameters.amountY}(liquidityParameters);

        // Revert if the amount of AVAX isn't correct
        liquidityParameters = getLiquidityParameters(wavax, usdc, amountYIn, ID_ONE, binNumber, gap);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBRouter.LBRouter__WrongAvaxLiquidityParameters.selector,
                address(liquidityParameters.tokenX),
                address(liquidityParameters.tokenY),
                liquidityParameters.amountX,
                liquidityParameters.amountY,
                liquidityParameters.amountY
            )
        );
        // liquidityParameters.amountX should be sent as message value
        router.addLiquidityAVAX{value: liquidityParameters.amountY}(liquidityParameters);
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

        pair.setApprovalForAll(address(router), true);

        (uint256 amountXOut, uint256 amountYOut) = router.removeLiquidity(
            usdt, usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, address(this), block.timestamp
        );

        assertApproxEqAbs(amountXOut, amountXAdded, 10, "amountXOut");
        assertApproxEqAbs(amountYOut, amountYAdded, 10, "amountYOut");

        assertLe(amountXOut, amountXAdded, "amountXOut");
        assertLe(amountYOut, amountYAdded, "amountYOut");

        for (uint256 i = 0; i < depositIds.length; i++) {
            assertEq(pair.balanceOf(address(this), depositIds[i]), 0, "depositId");
        }

        // Try with the token inversed
        (amountXAdded, amountYAdded,,, depositIds, liquidityMinted) = router.addLiquidity(liquidityParameters);

        (amountYOut, amountXOut) = router.removeLiquidity(
            usdc, usdt, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, address(this), block.timestamp
        );

        assertApproxEqAbs(amountXOut, amountXAdded, 10, "amountXOut");
        assertApproxEqAbs(amountYOut, amountYAdded, 10, "amountYOut");

        // Try removing half of the liquidity
        (amountXAdded, amountYAdded,,, depositIds, liquidityMinted) = router.addLiquidity(liquidityParameters);

        for (uint256 i = 0; i < depositIds.length; i++) {
            liquidityMinted[i] = liquidityMinted[i] / 2;
        }

        (amountXOut, amountYOut) = router.removeLiquidity(
            usdt, usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, address(this), block.timestamp
        );

        assertApproxEqAbs(amountXOut, amountXAdded / 2, 10, "amountXOut");
        assertApproxEqAbs(amountYOut, amountYAdded / 2, 10, "amountYOut");
    }

    function test_reverts_RemoveLiquidity() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);

        // Add liquidity
        (uint256 amountXAdded, uint256 amountYAdded,,, uint256[] memory depositIds, uint256[] memory liquidityMinted) =
            router.addLiquidity(liquidityParameters);

        ILBPair pair = factory.getLBPairInformation(usdt, usdc, DEFAULT_BIN_STEP).LBPair;
        pair.setApprovalForAll(address(router), true);

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
                ILBRouter.LBRouter__AmountSlippageCaught.selector, amountXAdded + 1, amountXAdded - 2, 0, amountYAdded
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
                ILBRouter.LBRouter__AmountSlippageCaught.selector, 0, amountXAdded - 2, amountYAdded + 1, amountYAdded
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

    function test_RemoveLiquidityAVAX() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(wavax, usdc, amountYIn, ID_ONE, binNumber, gap);

        // Add liquidity
        (uint256 amountXAdded, uint256 amountYAdded,,, uint256[] memory depositIds, uint256[] memory liquidityMinted) =
            router.addLiquidityAVAX{value: liquidityParameters.amountX}(liquidityParameters);

        ILBPair pair = factory.getLBPairInformation(wavax, usdc, DEFAULT_BIN_STEP).LBPair;
        pair.setApprovalForAll(address(router), true);

        uint256 balanceAVAXBefore = address(this).balance;
        uint256 balanceUSDCBefore = usdc.balanceOf(address(this));

        (uint256 amountToken, uint256 amountAVAX) = router.removeLiquidityAVAX(
            usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, payable(address(this)), block.timestamp
        );

        assertApproxEqAbs(amountAVAX, amountXAdded, 10, "amountXOut");
        assertApproxEqAbs(amountToken, amountYAdded, 10, "amountYOut");

        assertEq(address(this).balance, balanceAVAXBefore + amountAVAX, "balanceAVAXAfter");
        assertEq(usdc.balanceOf(address(this)), balanceUSDCBefore + amountToken, "balanceUSDCAfter");
    }

    function test_reverts_RemoveLiquidityAVAX() public {
        uint256 amountYIn = 1e18;
        uint24 binNumber = 7;
        uint24 gap = 2;

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(wavax, usdc, amountYIn, ID_ONE, binNumber, gap);

        // Add liquidity
        (uint256 amountXAdded,,,, uint256[] memory depositIds, uint256[] memory liquidityMinted) =
            router.addLiquidityAVAX{value: liquidityParameters.amountX}(liquidityParameters);

        ILBPair pair = factory.getLBPairInformation(wavax, usdc, DEFAULT_BIN_STEP).LBPair;
        pair.setApprovalForAll(address(router), true);

        // Revert if the deadline is passed
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__DeadlineExceeded.selector, block.timestamp - 1, block.timestamp)
        );
        router.removeLiquidityAVAX(
            usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, payable(address(this)), block.timestamp - 1
        );

        // Revert if the contract does not have a receive function
        blockReceive = true;
        vm.expectRevert(
            abi.encodeWithSelector(ILBRouter.LBRouter__FailedToSendAVAX.selector, address(this), amountXAdded - 2)
        );
        router.removeLiquidityAVAX(
            usdc, DEFAULT_BIN_STEP, 0, 0, depositIds, liquidityMinted, payable(address(this)), block.timestamp
        );
    }

    function test_SweepERC20() public {
        uint256 amount = 1e18;
        usdc.mint(address(router), amount);

        uint256 balanceBefore = usdc.balanceOf(address(this));
        router.sweep(usdc, address(this), amount);
        assertEq(usdc.balanceOf(address(this)), balanceBefore + amount, "balanceAfter");

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
            assertEq(pair.balanceOf(DEV, depositIds[i]), balancesBefore[i] + liquidityMinted[i], "balanceAfter");
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
