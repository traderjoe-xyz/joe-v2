// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "test/helpers/TestHelper.sol";

/*
* Test scenarios:
* 2. Receive
* 3. Create LBPair
* 4. Add Liquidity
* 5. Add liquidity AVAX
* 6. Remove liquidity
* 7. Remove liquidity AVAX
* 8. Sweep ERC20s
* 9. Sweep LBToken*/
contract LiquidityBinRouterTest is TestHelper {
    function setUp() public override {
        super.setUp();

        factory.setFactoryLockedState(false);

        // Create necessary pairs
        router.createLBPair(usdt, usdc, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(wavax, usdc, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(taxToken, usdc, ID_ONE, DEFAULT_BIN_STEP);
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

    function testFuzz_AddLiquidityNoSlippage(uint256 amountYIn, uint24 binNumber, uint24 gap) public {
        amountYIn = bound(amountYIn, 5_000, type(uint112).max);
        binNumber = uint24(bound(binNumber, 0, 400));
        binNumber = binNumber * 2 + 1;
        gap = uint24(bound(gap, 0, 20));

        ILBRouter.LiquidityParameters memory liquidityParameters =
            getLiquidityParameters(usdt, usdc, amountYIn, ID_ONE, binNumber, gap);

        deal(address(usdt), DEV, liquidityParameters.amountX);
        deal(address(usdc), DEV, liquidityParameters.amountY);

        // Add liquidity
        router.addLiquidity(liquidityParameters);
    }
}
