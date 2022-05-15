// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ILiquidityBinPair {
    struct Bins {
        mapping(int256 => uint112) reserves;
        mapping(int256 => uint256)[3] tree;
    }
}
