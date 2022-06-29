// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./ILBPair.sol";

interface ILBRouter {
    function getIdFromPrice(ILBPair LBPair, uint256 _price)
        external
        view
        returns (uint24);

    function getPriceFromId(ILBPair LBPair, uint24 _id)
        external
        view
        returns (uint256);

    function getSwapOut(
        ILBPair _LBPair,
        uint256 _amountIn,
        bool _swapForY
    ) external view returns (uint256 _amountOut);

    function getSwapIn(
        ILBPair _LBPair,
        uint256 _amountOut,
        bool _swapForY
    ) external view returns (uint256 _amountIn);
}
