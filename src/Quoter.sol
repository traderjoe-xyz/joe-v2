// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./interfaces/IJoeFactory.sol";
import "./interfaces/ILBFactory.sol";
import "./interfaces/ILBRouter.sol";
import "./libraries/JoeLibrary.sol";

contract Quoter {
    address public immutable routerV2;

    address public immutable factoryV1;
    address public immutable factoryV2;

    address public immutable wavax;

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

    function findBestPathAmountIn(address[] memory _route, uint256 _amountIn)
        public
        view
        returns (
            address[] memory route,
            address[] memory pairs,
            uint256[] memory binSteps,
            uint256[] memory amounts,
            uint256 tradeValueAVAX
        )
    {
        route = _route;
        uint256 routeLength = _route.length;
        pairs = new address[](routeLength - 1);
        binSteps = new uint256[](routeLength - 1);
        amounts = new uint256[](routeLength);
        amounts[0] = _amountIn;
        if (_route[0] == wavax) {
            tradeValueAVAX = _amountIn;
        }

        for (uint256 i; i < routeLength - 1; i++) {
            // Fetch swap for V1
            pairs[i] = IJoeFactory(factoryV1).getPair(_route[i], _route[i + 1]);
            binSteps[i] = 0;
            if (pairs[i] != address(0)) {
                (uint256 reserveIn, uint256 reserveOut) = JoeLibrary.getReserves(factoryV1, _route[i], _route[i + 1]);
                amounts[i + 1] = JoeLibrary.getAmountOut(amounts[i], reserveIn, reserveOut);
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
                        amounts[i],
                        address(LBPairsAvailable[j].LBPair.tokenY()) == _route[i + 1]
                    );

                    if (swapAmountOut > amounts[i + 1]) {
                        amounts[i + 1] = swapAmountOut;
                        pairs[i] = address(LBPairsAvailable[j].LBPair);
                        binSteps[i] = LBPairsAvailable[j].LBPair.feeParameters().binStep;
                    }
                }
            }

            if (_route[i + 1] == wavax) {
                tradeValueAVAX = amounts[i + 1];
            }
        }

        // Find the AVAX value of the swap to compare against gas cost
        if (tradeValueAVAX == 0) {
            address avaxPair = IJoeFactory(factoryV1).getPair(_route[routeLength - 1], wavax);
            if (avaxPair != address(0)) {
                (uint256 reserveIn, uint256 reserveOut) = JoeLibrary.getReserves(
                    factoryV1,
                    _route[routeLength - 1],
                    wavax
                );
                tradeValueAVAX = JoeLibrary.getAmountOut(amounts[routeLength - 1], reserveIn, reserveOut);
            }

            if (tradeValueAVAX == 0) {
                // Fetch swaps for V2
                ILBFactory.LBPairAvailable[] memory LBPairsAvailable = ILBFactory(factoryV2).getAvailableLBPairsBinStep(
                    IERC20(_route[routeLength - 1]),
                    IERC20(wavax)
                );

                if (LBPairsAvailable.length > 0) {
                    uint256 swapOut;
                    for (uint256 j; j < LBPairsAvailable.length; j++) {
                        swapOut = ILBRouter(routerV2).getSwapOut(
                            LBPairsAvailable[j].LBPair,
                            amounts[routeLength - 1],
                            address(LBPairsAvailable[j].LBPair.tokenY()) == wavax
                        );

                        if (swapOut > 0) {
                            tradeValueAVAX = swapOut;
                            break;
                        }
                    }
                }
            }
        }
    }

    function findBestPathAmountOut(address[] memory _route, uint256 _amountOut)
        public
        view
        returns (
            address[] memory route,
            address[] memory pairs,
            uint256[] memory binSteps,
            uint256[] memory amounts,
            uint256 tradeValueAVAX
        )
    {
        route = _route;
        uint256 routeLength = _route.length;
        pairs = new address[](routeLength - 1);
        binSteps = new uint256[](routeLength - 1);
        amounts = new uint256[](routeLength);
        amounts[routeLength - 1] = _amountOut;
        if (_route[routeLength - 1] == wavax) {
            tradeValueAVAX = _amountOut;
        }

        for (uint256 i = routeLength - 1; i > 0; i--) {
            // Fetch swap for V1
            pairs[i - 1] = IJoeFactory(factoryV1).getPair(_route[i - 1], _route[i]);
            binSteps[i - 1] = 0;
            if (pairs[i - 1] != address(0)) {
                (uint256 reserveIn, uint256 reserveOut) = JoeLibrary.getReserves(factoryV1, _route[i - 1], _route[i]);
                amounts[i - 1] = JoeLibrary.getAmountIn(amounts[i], reserveIn, reserveOut);
            }

            // Fetch swaps for V2
            ILBFactory.LBPairAvailable[] memory LBPairsAvailable = ILBFactory(factoryV2).getAvailableLBPairsBinStep(
                IERC20(_route[i - 1]),
                IERC20(_route[i])
            );

            if (LBPairsAvailable.length > 0) {
                for (uint256 j; j < LBPairsAvailable.length; j++) {
                    uint256 swapAmountIn = ILBRouter(routerV2).getSwapIn(
                        LBPairsAvailable[j].LBPair,
                        amounts[i - 1],
                        address(LBPairsAvailable[j].LBPair.tokenY()) == _route[i]
                    );

                    if (swapAmountIn < amounts[i]) {
                        amounts[i] = swapAmountIn;
                        pairs[i - 1] = address(LBPairsAvailable[j].LBPair);
                        binSteps[i - 1] = LBPairsAvailable[j].LBPair.feeParameters().binStep;
                    }
                }
            }

            if (_route[i] == wavax) {
                tradeValueAVAX = amounts[i];
            }
        }

        // Find the AVAX value of the swap to compare against gas cost
        if (tradeValueAVAX == 0) {
            address avaxPair = IJoeFactory(factoryV1).getPair(_route[0], wavax);
            if (avaxPair != address(0)) {
                (uint256 reserveIn, uint256 reserveOut) = JoeLibrary.getReserves(factoryV1, _route[0], wavax);
                tradeValueAVAX = JoeLibrary.getAmountIn(amounts[0], reserveIn, reserveOut);
            }

            if (tradeValueAVAX == 0) {
                // Fetch swaps for V2
                ILBFactory.LBPairAvailable[] memory LBPairsAvailable = ILBFactory(factoryV2).getAvailableLBPairsBinStep(
                    IERC20(_route[0]),
                    IERC20(wavax)
                );

                if (LBPairsAvailable.length > 0) {
                    uint256 swapIn;
                    for (uint256 j; j < LBPairsAvailable.length; j++) {
                        swapIn = ILBRouter(routerV2).getSwapIn(
                            LBPairsAvailable[j].LBPair,
                            amounts[0],
                            address(LBPairsAvailable[j].LBPair.tokenY()) == wavax
                        );

                        if (swapIn > 0) {
                            tradeValueAVAX = swapIn;
                            break;
                        }
                    }
                }
            }
        }
    }
}
