// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "../helpers/TestHelper.sol";

/**
 * Makes sure that the new quoter picks the version 2.1 over the version 2 if both outputs are exactly the same
 */
contract LiquidityBinQuoterPriorityTest is Test {
    address internal constant factory = 0x8e42f2F4101563bF679975178e880FD87d3eFd4e;
    address internal constant router = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;

    address internal constant legacyUsdcUsdtPair = 0x1D7A1a79e2b4Ef88D2323f3845246D24a3c20F1d;
    address internal constant newUsdcUsdtPair = 0x9B2Cc8E6a2Bbb56d6bE4682891a91B0e48633c72;

    LBQuoter internal newQuoter;
    LBQuoter internal oldQuoter = LBQuoter(0x64b57F4249aA99a812212cee7DAEFEDC40B203cD);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 33313442);

        newQuoter = new LBQuoter(
            AvalancheAddresses.JOE_V1_FACTORY,
            AvalancheAddresses.JOE_V2_FACTORY,
            AvalancheAddresses.JOE_V2_1_FACTORY,
            factory,
            AvalancheAddresses.JOE_V2_ROUTER,
            AvalancheAddresses.JOE_V2_1_ROUTER,
            router
        );
    }

    function test_QuoteFromAmountIn() public view {
        address[] memory route = new address[](2);
        route[0] = address(AvalancheAddresses.USDT);
        route[1] = address(AvalancheAddresses.USDC);

        uint128 amountIn = 1e6;

        LBQuoter.Quote memory newQuote = newQuoter.findBestPathFromAmountIn(route, amountIn);
        LBQuoter.Quote memory oldQuote = oldQuoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(newQuote.route[0], oldQuote.route[0], "test_QuoteFromAmountIn::1");
        assertEq(newQuote.route[1], oldQuote.route[1], "test_QuoteFromAmountIn::2");

        assertEq(newQuote.pairs[0], newUsdcUsdtPair, "test_QuoteFromAmountIn::3");
        assertEq(oldQuote.pairs[0], legacyUsdcUsdtPair, "test_QuoteFromAmountIn::4");

        assertEq(newQuote.binSteps[0], oldQuote.binSteps[0], "test_QuoteFromAmountIn::5");

        assertEq(uint8(newQuote.versions[0]), uint8(ILBRouter.Version.V2_2), "test_QuoteFromAmountIn::6");
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

        route[0] = address(AvalancheAddresses.USDC);
        route[1] = address(AvalancheAddresses.USDT);

        newQuote = newQuoter.findBestPathFromAmountIn(route, amountIn);
        oldQuote = oldQuoter.findBestPathFromAmountIn(route, amountIn);

        assertEq(newQuote.route[0], oldQuote.route[0], "test_QuoteFromAmountIn::13");
        assertEq(newQuote.route[1], oldQuote.route[1], "test_QuoteFromAmountIn::14");

        assertEq(newQuote.pairs[0], newUsdcUsdtPair, "test_QuoteFromAmountIn::15");
        assertEq(oldQuote.pairs[0], legacyUsdcUsdtPair, "test_QuoteFromAmountIn::16");

        assertEq(newQuote.binSteps[0], oldQuote.binSteps[0], "test_QuoteFromAmountIn::17");

        assertEq(uint8(newQuote.versions[0]), uint8(ILBRouter.Version.V2_2), "test_QuoteFromAmountIn::18");
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

    function test_QuoteFromAmounOut() public view {
        address[] memory route = new address[](2);
        route[0] = address(AvalancheAddresses.USDC);
        route[1] = address(AvalancheAddresses.USDT);

        uint128 amountOut = 1e6;

        LBQuoter.Quote memory newQuote = newQuoter.findBestPathFromAmountOut(route, amountOut);
        LBQuoter.Quote memory oldQuote = oldQuoter.findBestPathFromAmountOut(route, amountOut);

        assertEq(newQuote.route[0], oldQuote.route[0], "test_QuoteFromAmounOut::1");
        assertEq(newQuote.route[1], oldQuote.route[1], "test_QuoteFromAmounOut::2");

        assertEq(newQuote.pairs[0], newUsdcUsdtPair, "test_QuoteFromAmounOut::3");
        assertEq(oldQuote.pairs[0], legacyUsdcUsdtPair, "test_QuoteFromAmounOut::4");

        assertEq(newQuote.binSteps[0], oldQuote.binSteps[0], "test_QuoteFromAmounOut::5");

        assertEq(uint8(newQuote.versions[0]), uint8(ILBRouter.Version.V2_2), "test_QuoteFromAmounOut::6");
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

        route[0] = address(AvalancheAddresses.USDT);
        route[1] = address(AvalancheAddresses.USDC);

        newQuote = newQuoter.findBestPathFromAmountOut(route, amountOut);
        oldQuote = oldQuoter.findBestPathFromAmountOut(route, amountOut);

        assertEq(newQuote.route[0], oldQuote.route[0], "test_QuoteFromAmounOut::13");
        assertEq(newQuote.route[1], oldQuote.route[1], "test_QuoteFromAmounOut::14");

        assertEq(newQuote.pairs[0], newUsdcUsdtPair, "test_QuoteFromAmounOut::15");
        assertEq(oldQuote.pairs[0], legacyUsdcUsdtPair, "test_QuoteFromAmounOut::16");

        assertEq(newQuote.binSteps[0], oldQuote.binSteps[0], "test_QuoteFromAmounOut::17");

        assertEq(uint8(newQuote.versions[0]), uint8(ILBRouter.Version.V2_2), "test_QuoteFromAmounOut::18");
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
