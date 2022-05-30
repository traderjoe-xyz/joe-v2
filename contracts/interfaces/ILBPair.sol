// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ILBPair {
    struct Bins {
        mapping(int256 => uint112) reserves;
        mapping(int256 => uint256)[3] tree;
    }

    function initialize(
        address _token0,
        address _token1,
        uint256 _fee
    ) external;
}
