// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./interfaces/IJoeFactory.sol";
import "./interfaces/ILBFactory.sol";
import "./interfaces/ILBRouter.sol";
import "./libraries/JoeLibrary.sol";
import "./libraries/BinHelper.sol";

contract Quoter {
    /// @notice Dex V2 router address
    address public immutable routerV2;
    /// @notice Dex V1 factory address
    address public immutable factoryV1;
    /// @notice Dex V2 factory address
    address public immutable factoryV2;
    /// @notice Wrapped avax address
    address public immutable wavax;

    struct Quote {
        address[] route;
        address[] pairs;
        uint256[] binSteps;
        uint256[] amounts;
        uint256[] midPrice;
        uint256 tradeValueAVAX;
    }

    /// @notice Constructor
    /// @param _routerV2 Dex V2 router address
    /// @param _factoryV1 Dex V1 factory address
    /// @param _factoryV2 Dex V2 factory address
    /// @param _wavax Wrapped avax address
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

    /// @notice Finds the best path given a list of tokens and the input amount wanted from the swap
    /// @param _route List of the tokens to go through
    /// @param _amountIn Swap amount in
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

            if (quote.pairs[i] != address(0) && quote.amounts[i] > 0) {
                (uint256 reserveIn, uint256 reserveOut) = JoeLibrary.getReserves(factoryV1, _route[i], _route[i + 1]);

                quote.amounts[i + 1] = JoeLibrary.getAmountOut(quote.amounts[i], reserveIn, reserveOut);
                quote.midPrice[i] = JoeLibrary.quote(1e18, reserveIn, reserveOut);
            }

            // Fetch swaps for V2
            ILBFactory.LBPairAvailable[] memory LBPairsAvailable = ILBFactory(factoryV2).getAvailableLBPairsBinStep(
                IERC20(_route[i]),
                IERC20(_route[i + 1])
            );

            if (LBPairsAvailable.length > 0 && quote.amounts[i] > 0) {
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

        // If we don't go through an AVAX pair directly, check all tokens against AVAX
        if (quote.tradeValueAVAX == 0) {
            quote.tradeValueAVAX = _getPriceAgainstAVAX(quote);
        }
    }

    /// @notice Finds the best path given a list of tokens and the output amount wanted from the swap
    /// @param _route List of the tokens to go through
    /// @param _amountOut Swap amount out
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
            quote.amounts[i - 1] = type(uint256).max;
            if (quote.pairs[i - 1] != address(0) && quote.amounts[i] > 0) {
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
                    if (swapAmountIn != 0 && (swapAmountIn < quote.amounts[i - 1] || quote.amounts[i - 1] == 0)) {
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

        // If we don't go through an AVAX pair directly, check all tokens against AVAX
        if (quote.tradeValueAVAX == 0) {
            quote.tradeValueAVAX = _getPriceAgainstAVAX(quote);
        }
    }

    /// @notice Tries to fetch an equivalent to the swap amount in AVAX, by looping on all the tokens on the route
    /// @param _quote Current quote
    function _getPriceAgainstAVAX(Quote memory _quote) private view returns (uint256 tradeValueAVAX) {
        uint256 routeLength = _quote.route.length;
        for (uint256 i; i < routeLength - 1; i++) {
            address avaxPair = IJoeFactory(factoryV1).getPair(_quote.route[i], wavax);
            if (avaxPair != address(0) && _quote.amounts[i] > 0) {
                (uint256 reserveIn, uint256 reserveOut) = JoeLibrary.getReserves(factoryV1, _quote.route[i], wavax);
                tradeValueAVAX = JoeLibrary.getAmountOut(_quote.amounts[i], reserveIn, reserveOut);
            }

            // Fetch swaps for V2
            ILBFactory.LBPairAvailable[] memory LBPairsAvailable = ILBFactory(factoryV2).getAvailableLBPairsBinStep(
                IERC20(_quote.route[i]),
                IERC20(wavax)
            );

            if (LBPairsAvailable.length > 0 && _quote.amounts[i] > 0) {
                uint256 swapOut;
                for (uint256 j; j < LBPairsAvailable.length; j++) {
                    swapOut = ILBRouter(routerV2).getSwapOut(
                        LBPairsAvailable[j].LBPair,
                        _quote.amounts[i],
                        address(LBPairsAvailable[j].LBPair.tokenY()) == wavax
                    );

                    // We keep the biggest amount to be the most accurate
                    if (swapOut > tradeValueAVAX) {
                        tradeValueAVAX = swapOut;
                    }
                }
            }
        }
    }
}
