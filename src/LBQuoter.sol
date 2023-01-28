// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {Constants} from "./libraries/Constants.sol";
import {JoeLibrary} from "./libraries/JoeLibrary.sol";
import {PriceHelper} from "./libraries/PriceHelper.sol";
import {Uint256x256Math} from "./libraries/math/Uint256x256Math.sol";

import {IJoeFactory} from "./interfaces/IJoeFactory.sol";
import {ILBFactory} from "./interfaces/ILBFactory.sol";
import {ILBLegacyFactory} from "./interfaces/ILBLegacyFactory.sol";
import {IJoePair} from "./interfaces/IJoePair.sol";
import {ILBPair} from "./interfaces/ILBPair.sol";
import {ILBRouter} from "./interfaces/ILBRouter.sol";

/// @title Liquidity Book Quoter
/// @author Trader Joe
/// @notice Helper contract to determine best path through multiple markets
contract LBQuoter {
    using Uint256x256Math for uint256;

    error LBQuoter_InvalidLength();

    /// @notice Dex V2 router address
    address public immutable routerV2;
    /// @notice Dex V1 factory address
    address public immutable factoryV1;
    /// @notice Dex V2 factory address
    address public immutable legacyFactoryV2;
    /// @notice Dex V2.1 factory address
    address public immutable factoryV2;

    struct Quote {
        address[] route;
        address[] pairs;
        uint256[] binSteps;
        uint256[] revisions;
        uint128[] amounts;
        uint128[] virtualAmountsWithoutSlippage;
        uint128[] fees;
    }

    /// @notice Constructor
    /// @param routerV2_ Dex V2 router address
    /// @param factoryV1_ Dex V1 factory address
    /// @param legacyFactoryV2_ Dex V2 factory address
    /// @param factoryV2_ Dex V2.1 factory address
    constructor(address factoryV1_, address legacyFactoryV2_, address factoryV2_, address routerV2_) {
        factoryV1 = factoryV1_;
        legacyFactoryV2 = legacyFactoryV2_;
        factoryV2 = factoryV2_;
        routerV2 = routerV2_;
    }

    /// @notice Finds the best path given a list of tokens and the input amount wanted from the swap
    /// @param route List of the tokens to go through
    /// @param amountIn Swap amount in
    /// @return quote The Quote structure containing the necessary element to perform the swap
    function findBestPathFromAmountIn(address[] calldata route, uint128 amountIn)
        public
        view
        returns (Quote memory quote)
    {
        if (route.length < 2) {
            revert LBQuoter_InvalidLength();
        }

        quote.route = route;

        uint256 swapLength = route.length - 1;
        quote.pairs = new address[](swapLength);
        quote.binSteps = new uint256[](swapLength);
        quote.revisions = new uint256[](swapLength);
        quote.fees = new uint128[](swapLength);
        quote.amounts = new uint128[](route.length);
        quote.virtualAmountsWithoutSlippage = new uint128[](route.length);

        quote.amounts[0] = amountIn;
        quote.virtualAmountsWithoutSlippage[0] = amountIn;

        for (uint256 i; i < swapLength; i++) {
            // Fetch swap for V1
            quote.pairs[i] = IJoeFactory(factoryV1).getPair(route[i], route[i + 1]);

            if (quote.pairs[i] != address(0) && quote.amounts[i] > 0) {
                (uint256 reserveIn, uint256 reserveOut) = _getReserves(quote.pairs[i], route[i], route[i + 1]);

                if (reserveIn > 0 && reserveOut > 0) {
                    quote.amounts[i + 1] = uint128(JoeLibrary.getAmountOut(quote.amounts[i], reserveIn, reserveOut));
                    quote.virtualAmountsWithoutSlippage[i + 1] = uint128(
                        JoeLibrary.quote(quote.virtualAmountsWithoutSlippage[i] * 997, reserveIn * 1000, reserveOut)
                    );
                    quote.fees[i] = 0.003e18; // 0.3%
                }
            }

            // Fetch swaps for V2
            ILBFactory.LBPairInformation[] memory LBPairsAvailable;

            for (uint256 k = 0; k < 2; k++) {
                if (k == 0) {
                    LBPairsAvailable = ILBFactory(factoryV2).getAllLBPairs(IERC20(route[i]), IERC20(route[i + 1]));
                } else {
                    ILBLegacyFactory.LBPairInformation[] memory LBPairsAvailableLegacy =
                        ILBLegacyFactory(legacyFactoryV2).getAllLBPairs(IERC20(route[i]), IERC20(route[i + 1]));

                    LBPairsAvailable = new ILBFactory.LBPairInformation[](LBPairsAvailableLegacy.length);
                    for (uint256 l = 0; l < LBPairsAvailableLegacy.length; l++) {
                        LBPairsAvailable[l] = ILBFactory.LBPairInformation(
                            uint8(LBPairsAvailableLegacy[l].binStep),
                            ILBPair(address(LBPairsAvailableLegacy[l].LBPair)),
                            LBPairsAvailableLegacy[l].createdByOwner,
                            LBPairsAvailableLegacy[l].ignoredForRouting,
                            0,
                            address(0)
                        );
                    }
                }

                if (LBPairsAvailable.length > 0 && quote.amounts[i] > 0) {
                    for (uint256 j; j < LBPairsAvailable.length; j++) {
                        if (!LBPairsAvailable[j].ignoredForRouting) {
                            bool swapForY = address(LBPairsAvailable[j].LBPair.getTokenY()) == route[i + 1];

                            try ILBRouter(routerV2).getSwapOut(LBPairsAvailable[j].LBPair, quote.amounts[i], swapForY)
                            returns (uint128, uint128 swapAmountOut, uint128 fees) {
                                if (swapAmountOut > quote.amounts[i + 1]) {
                                    quote.amounts[i + 1] = swapAmountOut;
                                    quote.pairs[i] = address(LBPairsAvailable[j].LBPair);
                                    quote.binSteps[i] = uint8(LBPairsAvailable[j].binStep);
                                    quote.revisions[i] = LBPairsAvailable[j].revisionIndex;

                                    // Getting current price
                                    uint24 activeId = LBPairsAvailable[j].LBPair.getActiveId();
                                    quote.virtualAmountsWithoutSlippage[i + 1] = uint128(
                                        _getV2Quote(
                                            quote.virtualAmountsWithoutSlippage[i] - fees,
                                            activeId,
                                            quote.binSteps[i],
                                            swapForY
                                        )
                                    );

                                    quote.fees[i] = (fees * 1e18) / quote.amounts[i]; // fee percentage in amountIn
                                }
                            } catch {}
                        }
                    }
                }
            }
        }
    }

    /// @notice Finds the best path given a list of tokens and the output amount wanted from the swap
    /// @param route List of the tokens to go through
    /// @param amountOut Swap amount out
    /// @return quote The Quote structure containing the necessary element to perform the swap
    function findBestPathFromAmountOut(address[] calldata route, uint128 amountOut)
        public
        view
        returns (Quote memory quote)
    {
        if (route.length < 2) {
            revert LBQuoter_InvalidLength();
        }
        quote.route = route;

        uint256 swapLength = route.length - 1;
        quote.pairs = new address[](swapLength);
        quote.binSteps = new uint256[](swapLength);
        quote.revisions = new uint256[](swapLength);
        quote.fees = new uint128[](swapLength);
        quote.amounts = new uint128[](route.length);
        quote.virtualAmountsWithoutSlippage = new uint128[](route.length);

        quote.amounts[swapLength] = amountOut;
        quote.virtualAmountsWithoutSlippage[swapLength] = amountOut;

        for (uint256 i = swapLength; i > 0; i--) {
            // Fetch swap for V1
            quote.pairs[i - 1] = IJoeFactory(factoryV1).getPair(route[i - 1], route[i]);
            if (quote.pairs[i - 1] != address(0) && quote.amounts[i] > 0) {
                (uint256 reserveIn, uint256 reserveOut) = _getReserves(quote.pairs[i - 1], route[i - 1], route[i]);

                if (reserveIn > 0 && reserveOut > quote.amounts[i]) {
                    quote.amounts[i - 1] = uint128(JoeLibrary.getAmountIn(quote.amounts[i], reserveIn, reserveOut));
                    quote.virtualAmountsWithoutSlippage[i - 1] = uint128(
                        JoeLibrary.quote(quote.virtualAmountsWithoutSlippage[i] * 1000, reserveOut * 997, reserveIn) + 1
                    );

                    quote.fees[i - 1] = 0.003e18; // 0.3%
                }
            }

            // Fetch swaps for V2
            ILBFactory.LBPairInformation[] memory LBPairsAvailable;

            for (uint256 k = 0; k < 2; k++) {
                if (k == 0) {
                    LBPairsAvailable = ILBFactory(factoryV2).getAllLBPairs(IERC20(route[i - 1]), IERC20(route[i]));
                } else {
                    LBPairsAvailable = ILBFactory(legacyFactoryV2).getAllLBPairs(IERC20(route[i - 1]), IERC20(route[i]));
                }

                if (LBPairsAvailable.length > 0 && quote.amounts[i] > 0) {
                    for (uint256 j; j < LBPairsAvailable.length; j++) {
                        if (!LBPairsAvailable[j].ignoredForRouting) {
                            bool swapForY = address(LBPairsAvailable[j].LBPair.getTokenY()) == route[i];
                            try ILBRouter(routerV2).getSwapIn(LBPairsAvailable[j].LBPair, quote.amounts[i], swapForY)
                            returns (uint128 swapAmountIn, uint128, uint128 fees) {
                                if (
                                    swapAmountIn != 0
                                        && (swapAmountIn < quote.amounts[i - 1] || quote.amounts[i - 1] == 0)
                                ) {
                                    quote.amounts[i - 1] = swapAmountIn;
                                    quote.pairs[i - 1] = address(LBPairsAvailable[j].LBPair);
                                    quote.binSteps[i - 1] = uint8(LBPairsAvailable[j].binStep);
                                    quote.revisions[i - 1] = LBPairsAvailable[j].revisionIndex;

                                    // Getting current price
                                    uint24 activeId = LBPairsAvailable[j].LBPair.getActiveId();
                                    quote.virtualAmountsWithoutSlippage[i - 1] = uint128(
                                        _getV2Quote(
                                            quote.virtualAmountsWithoutSlippage[i],
                                            activeId,
                                            quote.binSteps[i - 1],
                                            !swapForY
                                        )
                                    ) + fees;

                                    quote.fees[i - 1] = (fees * 1e18) / quote.amounts[i - 1]; // fee percentage in amountIn
                                }
                            } catch {}
                        }
                    }
                }
            }
        }
    }

    /// @dev Forked from JoeLibrary
    /// @dev Doesn't rely on the init code hash of the factory
    /// @param pair Address of the pair
    /// @param tokenA Address of token A
    /// @param tokenB Address of token B
    /// @return reserveA Reserve of token A in the pair
    /// @return reserveB Reserve of token B in the pair
    function _getReserves(address pair, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = JoeLibrary.sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IJoePair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @dev Calculates a quote for a V2 pair
    /// @param amount Amount in to consider
    /// @param activeId Current active Id of the considred pair
    /// @param binStep Bin step of the considered pair
    /// @param swapForY Boolean describing if we are swapping from X to Y or the opposite
    /// @return quote Amount Out if _amount was swapped with no slippage and no fees
    function _getV2Quote(uint256 amount, uint24 activeId, uint256 binStep, bool swapForY)
        internal
        pure
        returns (uint256 quote)
    {
        if (swapForY) {
            quote =
                PriceHelper.getPriceFromId(activeId, uint8(binStep)).mulShiftRoundDown(amount, Constants.SCALE_OFFSET);
        } else {
            quote =
                amount.shiftDivRoundDown(Constants.SCALE_OFFSET, PriceHelper.getPriceFromId(activeId, uint8(binStep)));
        }
    }
}
