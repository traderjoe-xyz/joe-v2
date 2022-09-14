// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./interfaces/IJoeFactory.sol";
import "./interfaces/ILBFactory.sol";
import "./interfaces/ILBRouter.sol";
import "./libraries/JoeLibrary.sol";
import "./libraries/BinHelper.sol";

contract LBQuoter {
    /// @notice Dex V2 router address
    address public immutable routerV2;
    /// @notice Dex V1 factory address
    address public immutable factoryV1;
    /// @notice Dex V2 factory address
    address public immutable factoryV2;

    struct Quote {
        address[] route;
        address[] pairs;
        uint256[] binSteps;
        uint256[] amounts;
        uint256[] midPrice;
    }

    /// @notice Constructor
    /// @param _routerV2 Dex V2 router address
    /// @param _factoryV1 Dex V1 factory address
    /// @param _factoryV2 Dex V2 factory address
    constructor(
        address _routerV2,
        address _factoryV1,
        address _factoryV2
    ) {
        routerV2 = _routerV2;
        factoryV1 = _factoryV1;
        factoryV2 = _factoryV2;
    }

    /// @notice Finds the best path given a list of tokens and the input amount wanted from the swap
    /// @param _route List of the tokens to go through
    /// @param _amountIn Swap amount in
    function findBestPathAmountIn(address[] memory _route, uint256 _amountIn) public view returns (Quote memory quote) {
        quote.route = _route;

        uint256 swapLength = _route.length - 1;
        quote.pairs = new address[](swapLength);
        quote.binSteps = new uint256[](swapLength);
        quote.midPrice = new uint256[](swapLength);
        quote.amounts = new uint256[](_route.length);

        quote.amounts[0] = _amountIn;

        for (uint256 i; i < swapLength; i++) {
            // Fetch swap for V1
            quote.pairs[i] = IJoeFactory(factoryV1).getPair(_route[i], _route[i + 1]);

            if (quote.pairs[i] != address(0) && quote.amounts[i] > 0) {
                (uint256 reserveIn, uint256 reserveOut) = _getReserves(quote.pairs[i], _route[i], _route[i + 1]);

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

        uint256 swapLength = _route.length - 1;
        quote.pairs = new address[](swapLength);
        quote.binSteps = new uint256[](swapLength);
        quote.midPrice = new uint256[](swapLength);
        quote.amounts = new uint256[](_route.length);

        quote.amounts[swapLength] = _amountOut;

        for (uint256 i = swapLength; i > 0; i--) {
            // Fetch swap for V1
            quote.pairs[i - 1] = IJoeFactory(factoryV1).getPair(_route[i - 1], _route[i]);
            quote.amounts[i - 1] = type(uint256).max;
            if (quote.pairs[i - 1] != address(0) && quote.amounts[i] > 0) {
                (uint256 reserveIn, uint256 reserveOut) = _getReserves(quote.pairs[i - 1], _route[i - 1], _route[i]);
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
        }
    }

    // Forked from JoeLibrary
    // Doesn't rely on the init code hash of the factory
    function _getReserves(
        address pair,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = JoeLibrary.sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IJoePair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }
}
