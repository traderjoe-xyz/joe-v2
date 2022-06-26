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
        uint256 amountXOut,
        uint256 amountYOut
    ) external view returns (uint256 amountXIn, uint256 amountYIn);

    function getSwapOut(
        ILBPair LBPair,
        uint256 amountXIn,
        uint256 amountYIn
    ) external view returns (uint256 amountXOut, uint256 amountYOut);
}
