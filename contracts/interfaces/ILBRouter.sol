// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./ILBPair.sol";

interface ILBRouter {
    function getIdFromPrice(ILBPair LBPair, uint256 price)
        external
        view
        returns (uint24);

    function getPriceFromId(ILBPair LBPair, uint24 id)
        external
        view
        returns (uint256);

    function getSwapIn(
        ILBPair LBPair,
        uint256 amount0Out,
        uint256 amount1Out
    ) external view returns (uint256 amount0In, uint256 amount1In);

    function getSwapOut(
        ILBPair LBPair,
        uint256 amount0In,
        uint256 amount1In
    ) external view returns (uint256 amount0Out, uint256 amount1Out);
}
