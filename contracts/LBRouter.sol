// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ILBPair.sol";
import "./interfaces/ILBFactory.sol";
import "./interfaces/IWAVAX.sol";

error LBRouter__SenderIsNotWavax();

contract LBRouter {
    using SafeERC20 for IERC20;

    ILBFactory public immutable factory;
    IWAVAX public immutable wavax;

    constructor(ILBFactory _factory, IWAVAX _wavax) {
        factory = _factory;
        wavax = _wavax;
    }

    receive() external payable {
        if (msg.sender != address(wavax)) revert LBRouter__SenderIsNotWavax(); // only accept AVAX via fallback from the WAVAX contract
    }

    function _addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _startId,
        uint256 _endId,
        uint256 _amountA,
        uint256 _amountB
    ) private {
        address pair = factory.getLBPair(_tokenA, _tokenB);
        if (pair == address(0)) {
            // pair = factory.createLBPair(_tokenA, _tokenB, ?fee?);
        }

    }
}
