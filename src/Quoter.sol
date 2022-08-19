// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./interfaces/IJoeFactory.sol";
import "./interfaces/ILBFactory.sol";
import "./interfaces/ILBRouter.sol";
import "./libraries/JoeLibrary.sol";
import "./libraries/BinHelper.sol";

contract Quoter {
    address public immutable routerV2;

    address public immutable factoryV1;
    address public immutable factoryV2;

    address public immutable wavax;

    struct Quote {
        address[] route;
        address[] pairs;
        uint256[] binSteps;
        uint256[] amounts;
        uint256[] midPrice;
        uint256 tradeValueAVAX;
    }

    constructor(
        address _routerV2,
        address _factoryV1,
        address _factoryV2,
        address _wavax
    ) {
        routerV2 = _routerV2;
        factoryV1 = _factoryV1;
        factoryV2 = _factoryV2;
        wavax = _wavax;
    }

    function findBestPathAmountIn(address[] memory _route, uint256 _amountIn) public view returns (Quote memory quote) {
        quote.route = _route;

        uint256 routeLength = _route.length;
        quote.pairs = new address[](routeLength - 1);
        quote.binSteps = new uint256[](routeLength - 1);
        quote.midPrice = new uint256[](routeLength - 1);
        quote.amounts = new uint256[](routeLength);

        quote.amounts[0] = _amountIn;
        if (_route[0] == wavax) {
            quote.tradeValueAVAX = _amountIn;
        }

        for (uint256 i; i < routeLength - 1; i++) {
            // Fetch swap for V1
            quote.pairs[i] = IJoeFactory(factoryV1).getPair(_route[i], _route[i + 1]);
            quote.binSteps[i] = 0;
            if (quote.pairs[i] != address(0)) {
                (uint256 reserveIn, uint256 reserveOut) = JoeLibrary.getReserves(factoryV1, _route[i], _route[i + 1]);

                quote.amounts[i + 1] = JoeLibrary.getAmountOut(quote.amounts[i], reserveIn, reserveOut);

                quote.midPrice[i] = JoeLibrary.quote(1e18, reserveIn, reserveOut);
            }

            // Fetch swaps for V2
            ILBFactory.LBPairAvailable[] memory LBPairsAvailable = ILBFactory(factoryV2).getAvailableLBPairsBinStep(
                IERC20(_route[i]),
                IERC20(_route[i + 1])
            );

            if (LBPairsAvailable.length > 0) {
                for (uint256 j; j < LBPairsAvailable.length; j++) {
                    uint256 swapAmountOut = ILBRouter(routerV2).getSwapOut(
                        LBPairsAvailable[j].LBPair,
                        quote.amounts[i],
                        address(LBPairsAvailable[j].LBPair.tokenY()) == _route[i + 1]
                    );

                    if (swapAmountOut > quote.amounts[i + 1]) {
                        quote.amounts[i + 1] = swapAmountOut;
                        quote.pairs[i] = address(LBPairsAvailable[j].LBPair);
                        quote.binSteps[i] = LBPairsAvailable[j].LBPair.feeParameters().binStep;

                        // Getting current price
                        (, , uint256 activeId) = LBPairsAvailable[j].LBPair.getReservesAndId();
                        quote.midPrice[i] = (BinHelper.getPriceFromId(activeId, quote.binSteps[i]) * 1e18) / 2**128;
                    }
                }
            }

            if (_route[i + 1] == wavax) {
                quote.tradeValueAVAX = quote.amounts[i + 1];
            }
        }

        // If we don't go trough an AVAX pair directly, check all tokens against AVAX
        if (quote.tradeValueAVAX == 0) {
            for (uint256 i; i < routeLength - 1; i++) {
                address avaxPair = IJoeFactory(factoryV1).getPair(_route[i], wavax);
                if (avaxPair != address(0)) {
                    (uint256 reserveIn, uint256 reserveOut) = JoeLibrary.getReserves(factoryV1, _route[i], wavax);
                    quote.tradeValueAVAX = JoeLibrary.getAmountIn(quote.amounts[i], reserveIn, reserveOut);
                }

                // Fetch swaps for V2
                ILBFactory.LBPairAvailable[] memory LBPairsAvailable = ILBFactory(factoryV2).getAvailableLBPairsBinStep(
                    IERC20(_route[i]),
                    IERC20(wavax)
                );

                if (LBPairsAvailable.length > 0) {
                    uint256 swapOut;
                    for (uint256 j; j < LBPairsAvailable.length; j++) {
                        swapOut = ILBRouter(routerV2).getSwapOut(
                            LBPairsAvailable[j].LBPair,
                            quote.amounts[i],
                            address(LBPairsAvailable[j].LBPair.tokenY()) == wavax
                        );

                        // We keep the biggest amount to be the most accurate
                        if (swapOut > quote.tradeValueAVAX) {
                            quote.tradeValueAVAX = swapOut;
                        }
                    }
                }
            }
        }
    }

    function findBestPathAmountOut(address[] memory _route, uint256 _amountOut)
        public
        view
        returns (Quote memory quote)
    {
        quote.route = _route;

        uint256 routeLength = _route.length;
        quote.pairs = new address[](routeLength - 1);
        quote.binSteps = new uint256[](routeLength - 1);
        quote.midPrice = new uint256[](routeLength - 1);
        quote.amounts = new uint256[](routeLength);

        quote.amounts[routeLength - 1] = _amountOut;
        if (_route[routeLength - 1] == wavax) {
            quote.tradeValueAVAX = _amountOut;
        }

        for (uint256 i = routeLength - 1; i > 0; i--) {
            // Fetch swap for V1
            quote.pairs[i - 1] = IJoeFactory(factoryV1).getPair(_route[i - 1], _route[i]);
            quote.binSteps[i - 1] = 0;
            quote.amounts[i - 1] = type(uint256).max;
            if (quote.pairs[i - 1] != address(0)) {
                (uint256 reserveIn, uint256 reserveOut) = JoeLibrary.getReserves(factoryV1, _route[i - 1], _route[i]);
                quote.amounts[i - 1] = JoeLibrary.getAmountIn(quote.amounts[i], reserveIn, reserveOut);

                quote.midPrice[i - 1] = JoeLibrary.quote(1e18, reserveIn, reserveOut);
            }

            // Fetch swaps for V2
            ILBFactory.LBPairAvailable[] memory LBPairsAvailable = ILBFactory(factoryV2).getAvailableLBPairsBinStep(
                IERC20(_route[i - 1]),
                IERC20(_route[i])
            );

            if (LBPairsAvailable.length > 0 && quote.amounts[i] > 0) {
                for (uint256 j; j < LBPairsAvailable.length; j++) {
                    uint256 swapAmountIn = ILBRouter(routerV2).getSwapIn(
                        LBPairsAvailable[j].LBPair,
                        quote.amounts[i],
                        address(LBPairsAvailable[j].LBPair.tokenY()) == _route[i]
                    );
                    if (swapAmountIn != 0 && swapAmountIn < quote.amounts[i - 1]) {
                        quote.amounts[i - 1] = swapAmountIn;
                        quote.pairs[i - 1] = address(LBPairsAvailable[j].LBPair);
                        quote.binSteps[i - 1] = LBPairsAvailable[j].LBPair.feeParameters().binStep;

                        // Getting current price
                        (, , uint256 activeId) = LBPairsAvailable[j].LBPair.getReservesAndId();
                        quote.midPrice[i - 1] =
                            (BinHelper.getPriceFromId(activeId, quote.binSteps[i - 1]) * 1e18) /
                            2**128;
                    }
                }
            }

            if (_route[i - 1] == wavax) {
                quote.tradeValueAVAX = quote.amounts[i - 1];
            }
        }

        // If we don't go trough an AVAX pair directly, check all tokens against AVAX
        if (quote.tradeValueAVAX == 0) {
            for (uint256 i; i < routeLength - 1; i++) {
                address avaxPair = IJoeFactory(factoryV1).getPair(_route[i], wavax);
                if (avaxPair != address(0)) {
                    (uint256 reserveIn, uint256 reserveOut) = JoeLibrary.getReserves(factoryV1, _route[i], wavax);
                    quote.tradeValueAVAX = JoeLibrary.getAmountIn(quote.amounts[i], reserveIn, reserveOut);
                }

                // Fetch swaps for V2
                ILBFactory.LBPairAvailable[] memory LBPairsAvailable = ILBFactory(factoryV2).getAvailableLBPairsBinStep(
                    IERC20(_route[i]),
                    IERC20(wavax)
                );

                if (LBPairsAvailable.length > 0) {
                    uint256 swapOut;
                    for (uint256 j; j < LBPairsAvailable.length; j++) {
                        swapOut = ILBRouter(routerV2).getSwapOut(
                            LBPairsAvailable[j].LBPair,
                            quote.amounts[i],
                            address(LBPairsAvailable[j].LBPair.tokenY()) == wavax
                        );

                        // We keep the biggest amount to be the most accurate
                        if (swapOut > quote.tradeValueAVAX) {
                            quote.tradeValueAVAX = swapOut;
                        }
                    }
                }
            }
        }
    }
}
