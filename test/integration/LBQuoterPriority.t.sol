// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "../helpers/TestHelper.sol";

/**
 * Market deployed:
 * - USDT/USDC, V1 with low liquidity, V2 with high liquidity
 * - WNATIVE/USDC, V1 with high liquidity, V2 with low liquidity
 * - WETH/USDC, V1 with low liquidity, V2.1 with high liquidity
 * - BNB/USDC, V2 with high liquidity, V2.1 with low liquidity
 *
 * Every market with low liquidity has a slighly higher price.
 * It should be picked with small amounts but not with large amounts.
 * All tokens are considered 18 decimals for simplification purposes.
 */

contract LiquidityBinQuoterPriorityTest is Test {
    address internal constant factory = 0x8e42f2F4101563bF679975178e880FD87d3eFd4e;
    address internal constant router = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;
    address internal constant routerV1 = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    address internal constant factoryV1 = 0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10;
    address internal constant legacyRouterV2 = 0xE3Ffc583dC176575eEA7FD9dF2A7c65F7E23f4C3;
    address internal constant legacyFactoryV2 = 0x6E77932A92582f504FF6c4BdbCef7Da6c198aEEf;

    address internal constant usdc = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
    address internal constant usdt = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;

    address internal constant legacyUsdcUsdtPair = 0x1D7A1a79e2b4Ef88D2323f3845246D24a3c20F1d;
    address internal constant newUsdcUsdtPair = 0x9B2Cc8E6a2Bbb56d6bE4682891a91B0e48633c72;

    LBQuoter internal newQuoter;
    LBQuoter internal oldQuoter = LBQuoter(0x64b57F4249aA99a812212cee7DAEFEDC40B203cD);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 33313442);

        newQuoter = new LBQuoter(factoryV1, legacyFactoryV2, factory, legacyRouterV2, router);
    }

    function test_QuoteFromAmountIn() public {
        address[] memory route = new address[](2);
        route[0] = address(usdt);
        route[1] = address(usdc);

        uint128 amountIn = 1e6;

        LBQuoter.Quote memory newQuote = newQuoter.findBestPathFromAmountIn(route, amountIn);
        LBQuoter.Quote memory oldQuote = oldQuoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(newQuote.route[0], oldQuote.route[0], "test_QuoteFromAmountIn::1");
        assertEq(newQuote.route[1], oldQuote.route[1], "test_QuoteFromAmountIn::2");

        assertEq(newQuote.pairs[0], newUsdcUsdtPair, "test_QuoteFromAmountIn::3");
        assertEq(oldQuote.pairs[0], legacyUsdcUsdtPair, "test_QuoteFromAmountIn::4");

        assertEq(newQuote.binSteps[0], oldQuote.binSteps[0], "test_QuoteFromAmountIn::5");

        assertEq(uint8(newQuote.versions[0]), uint8(ILBRouter.Version.V2_1), "test_QuoteFromAmountIn::6");
        assertEq(uint8(oldQuote.versions[0]), uint8(ILBRouter.Version.V2), "test_QuoteFromAmountIn::7");

        assertEq(newQuote.amounts[0], oldQuote.amounts[0], "test_QuoteFromAmountIn::8");
        assertEq(newQuote.amounts[1], oldQuote.amounts[1], "test_QuoteFromAmountIn::9");

        assertEq(
            newQuote.virtualAmountsWithoutSlippage[0],
            oldQuote.virtualAmountsWithoutSlippage[0],
            "test_QuoteFromAmountIn::10"
        );
        assertEq(
            newQuote.virtualAmountsWithoutSlippage[1],
            oldQuote.virtualAmountsWithoutSlippage[1],
            "test_QuoteFromAmountIn::11"
        );

        assertEq(newQuote.fees[0], oldQuote.fees[0], "test_QuoteFromAmountIn::12");

        route[0] = address(usdc);
        route[1] = address(usdt);

        newQuote = newQuoter.findBestPathFromAmountIn(route, amountIn);
        oldQuote = oldQuoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(newQuote.route[0], oldQuote.route[0], "test_QuoteFromAmountIn::13");
        assertEq(newQuote.route[1], oldQuote.route[1], "test_QuoteFromAmountIn::14");

        assertEq(newQuote.pairs[0], newUsdcUsdtPair, "test_QuoteFromAmountIn::15");
        assertEq(oldQuote.pairs[0], legacyUsdcUsdtPair, "test_QuoteFromAmountIn::16");

        assertEq(newQuote.binSteps[0], oldQuote.binSteps[0], "test_QuoteFromAmountIn::17");

        assertEq(uint8(newQuote.versions[0]), uint8(ILBRouter.Version.V2_1), "test_QuoteFromAmountIn::18");
        assertEq(uint8(oldQuote.versions[0]), uint8(ILBRouter.Version.V2), "test_QuoteFromAmountIn::19");

        assertEq(newQuote.amounts[0], oldQuote.amounts[0], "test_QuoteFromAmountIn::20");
        assertEq(newQuote.amounts[1], oldQuote.amounts[1], "test_QuoteFromAmountIn::21");

        assertEq(
            newQuote.virtualAmountsWithoutSlippage[0],
            oldQuote.virtualAmountsWithoutSlippage[0],
            "test_QuoteFromAmountIn::22"
        );
        assertEq(
            newQuote.virtualAmountsWithoutSlippage[1],
            oldQuote.virtualAmountsWithoutSlippage[1],
            "test_QuoteFromAmountIn::23"
        );

        assertEq(newQuote.fees[0], oldQuote.fees[0], "test_QuoteFromAmountIn::24");
    }

    function test_QuoteFromAmounOut() public {
        address[] memory route = new address[](2);
        route[0] = address(usdc);
        route[1] = address(usdt);

        uint128 amountOut = 1e6;

        LBQuoter.Quote memory newQuote = newQuoter.findBestPathFromAmountOut(route, amountOut);
        LBQuoter.Quote memory oldQuote = oldQuoter.findBestPathFromAmountOut(route, amountOut);

        assertEq(newQuote.route[0], oldQuote.route[0], "test_QuoteFromAmounOut::1");
        assertEq(newQuote.route[1], oldQuote.route[1], "test_QuoteFromAmounOut::2");

        assertEq(newQuote.pairs[0], newUsdcUsdtPair, "test_QuoteFromAmounOut::3");
        assertEq(oldQuote.pairs[0], legacyUsdcUsdtPair, "test_QuoteFromAmounOut::4");

        assertEq(newQuote.binSteps[0], oldQuote.binSteps[0], "test_QuoteFromAmounOut::5");

        assertEq(uint8(newQuote.versions[0]), uint8(ILBRouter.Version.V2_1), "test_QuoteFromAmounOut::6");
        assertEq(uint8(oldQuote.versions[0]), uint8(ILBRouter.Version.V2), "test_QuoteFromAmounOut::7");

        assertEq(newQuote.amounts[0], oldQuote.amounts[0], "test_QuoteFromAmounOut::8");
        assertEq(newQuote.amounts[1], oldQuote.amounts[1], "test_QuoteFromAmounOut::9");

        assertEq(
            newQuote.virtualAmountsWithoutSlippage[0],
            oldQuote.virtualAmountsWithoutSlippage[0],
            "test_QuoteFromAmounOut::10"
        );
        assertEq(
            newQuote.virtualAmountsWithoutSlippage[1],
            oldQuote.virtualAmountsWithoutSlippage[1],
            "test_QuoteFromAmounOut::11"
        );

        assertEq(newQuote.fees[0], oldQuote.fees[0], "test_QuoteFromAmounOut::12");

        route[0] = address(usdt);
        route[1] = address(usdc);

        newQuote = newQuoter.findBestPathFromAmountOut(route, amountOut);
        oldQuote = oldQuoter.findBestPathFromAmountOut(route, amountOut);

        assertEq(newQuote.route[0], oldQuote.route[0], "test_QuoteFromAmounOut::13");
        assertEq(newQuote.route[1], oldQuote.route[1], "test_QuoteFromAmounOut::14");

        assertEq(newQuote.pairs[0], newUsdcUsdtPair, "test_QuoteFromAmounOut::15");
        assertEq(oldQuote.pairs[0], legacyUsdcUsdtPair, "test_QuoteFromAmounOut::16");

        assertEq(newQuote.binSteps[0], oldQuote.binSteps[0], "test_QuoteFromAmounOut::17");

        assertEq(uint8(newQuote.versions[0]), uint8(ILBRouter.Version.V2_1), "test_QuoteFromAmounOut::18");
        assertEq(uint8(oldQuote.versions[0]), uint8(ILBRouter.Version.V2), "test_QuoteFromAmounOut::19");

        assertEq(newQuote.amounts[0], oldQuote.amounts[0], "test_QuoteFromAmounOut::20");
        assertEq(newQuote.amounts[1], oldQuote.amounts[1], "test_QuoteFromAmounOut::21");

        assertEq(
            newQuote.virtualAmountsWithoutSlippage[0],
            oldQuote.virtualAmountsWithoutSlippage[0],
            "test_QuoteFromAmounOut::22"
        );
        assertEq(
            newQuote.virtualAmountsWithoutSlippage[1],
            oldQuote.virtualAmountsWithoutSlippage[1],
            "test_QuoteFromAmounOut::23"
        );

        assertEq(newQuote.fees[0], oldQuote.fees[0], "test_QuoteFromAmounOut::24");
    }
}
