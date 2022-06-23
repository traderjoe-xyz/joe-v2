// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ILBPair.sol";
import "./interfaces/ILBFactory.sol";
import "./interfaces/IWAVAX.sol";
import "./interfaces/ILBRouter.sol";
import "./libraries/BinHelper.sol";
import "./libraries/FeeHelper.sol";
import "./libraries/Math512Bits.sol";

error LBRouter__SenderIsNotWavax();
error LBRouter__PairIsNotCreated(IERC20 token0, IERC20 token1);
error LBRouter__WrongAmounts(uint256 amount0, uint256 amount1);
error LBRouter__SwapOverflows(uint256 id);
error LBRouter__BrokenSwapSafetyCheck();
error LBRouter__TooMuchTokensIn(uint256 excess0, uint256 excess1);

contract LBRouter is ILBRouter {
    using SafeERC20 for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;
    using Math512Bits for uint256;

    ILBFactory public immutable factory;
    IWAVAX public immutable wavax;

    uint256 public constant PRICE_PRECISION = 1e36;

    constructor(ILBFactory _factory, IWAVAX _wavax) {
        factory = _factory;
        wavax = _wavax;
    }

    receive() external payable {
        if (msg.sender != address(wavax)) revert LBRouter__SenderIsNotWavax(); // only accept AVAX via fallback from the WAVAX contract
    }

    /// @notice Returns the approximate id corresponding to the inputted price.
    /// Warning, the returned id may be inaccurate close to the start price of a bin
    /// @param _LBPair The address of the LBPair
    /// @param _price The price of y per x (multiplied by 1e36)
    /// @return The id corresponding to this price
    function getIdFromPrice(ILBPair _LBPair, uint256 _price)
        external
        view
        override
        returns (uint24)
    {
        return BinHelper.getIdFromPrice(_price, _LBPair.log2Value());
    }

    /// @notice Returns the price corresponding to the inputted id
    /// @param _LBPair The address of the LBPair
    /// @param _id The id
    /// @return The price corresponding to this id
    function getPriceFromId(ILBPair _LBPair, uint24 _id)
        external
        view
        override
        returns (uint256)
    {
        return BinHelper.getPriceFromId(_id, _LBPair.log2Value());
    }

    /// @notice Simulate a swap in
    /// @param _LBPair The address of the LBPair
    /// @param _amount0Out The amount of token0 to receive
    /// @param _amount1Out The amount of token1 to receive
    /// @return amount0In The amount of token0 to send in order to receive _amount1Out token1
    /// @return amount1In The amount of token1 to send in order to receive _amount0Out token0
    function getSwapIn(
        ILBPair _LBPair,
        uint256 _amount0Out,
        uint256 _amount1Out
    ) external view override returns (uint256 amount0In, uint256 amount1In) {
        ILBPair.PairInformation memory _pair = _LBPair.pairInformation();

        if (
            (_amount0Out != 0 && _amount1Out != 0) ||
            _amount0Out > _pair.reserve0 ||
            _amount1Out > _pair.reserve1
        ) revert LBRouter__WrongAmounts(_amount0Out, _amount1Out); // If this is wrong, then we're sure the amounts sent are wrong

        FeeHelper.FeeParameters memory _fp = _LBPair.feeParameters();
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.id;
        int256 _log2Value = _LBPair.log2Value();

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            (uint256 _price, uint256 _reserve0, uint256 _reserve1) = _LBPair
                .getBin(_pair.id);
            if (_reserve0 != 0 || _reserve1 != 0) {
                if (_amount0Out != 0) {
                    uint256 _amount0OutOfBin = _amount0Out > _reserve0
                        ? _reserve0
                        : _amount0Out;
                    uint256 _amount1InToBin = _price.mulDivRoundUp(
                        _amount0OutOfBin,
                        PRICE_PRECISION
                    );
                    uint256 _amount1InWithFees = _amount1InToBin +
                        _fp.getFees(_amount1InToBin, _pair.id - _startId);

                    unchecked {
                        if (_amount1InWithFees > type(uint112).max)
                            revert LBRouter__SwapOverflows(_pair.id);

                        _amount0Out -= _amount0OutOfBin;
                        amount1In += _amount1InWithFees;
                    }
                } else {
                    uint256 _amount1OutOfBin = _amount1Out > _reserve1
                        ? _reserve1
                        : _amount1Out;
                    uint256 _amount0InToBin = PRICE_PRECISION.mulDivRoundUp(
                        _amount1OutOfBin,
                        _price
                    );
                    uint256 _amount0InWithFees = _amount0InToBin +
                        _fp.getFees(_amount0InToBin, _startId - _pair.id);

                    unchecked {
                        if (_amount0InWithFees > type(uint112).max)
                            revert LBRouter__SwapOverflows(_pair.id);

                        amount0In += _amount0InWithFees;
                        _amount1Out -= _amount1OutOfBin;
                    }
                }
            }

            if (_amount0Out != 0 || _amount1Out != 0) {
                _pair.id = uint24(
                    _LBPair.findFirstBin(_pair.id, _amount0Out == 0)
                );
            } else {
                break;
            }
        }
        if (_amount0Out != 0 || _amount1Out != 0)
            revert LBRouter__BrokenSwapSafetyCheck(); // Safety check, but should never be false as it would have reverted on transfer
    }

    /// @notice Simulate a swap out
    /// @param _LBPair The address of the LBPair
    /// @param _amount0In The amount of token0 sent
    /// @param _amount1In The amount of token1 sent
    /// @return amount0Out The amount of token0 received if _amount0In token0 are sent
    /// @return amount1Out The amount of token1 received if _amount1In token1 are sent
    function getSwapOut(
        ILBPair _LBPair,
        uint256 _amount0In,
        uint256 _amount1In
    ) external view override returns (uint256 amount0Out, uint256 amount1Out) {
        ILBPair.PairInformation memory _pair = _LBPair.pairInformation();

        if (_amount0In != 0 && _amount1In != 0)
            revert LBRouter__WrongAmounts(amount0Out, amount1Out); // If this is wrong, then we're sure the amounts sent are wrong

        FeeHelper.FeeParameters memory _fp = _LBPair.feeParameters();
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.id;

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            (uint256 _price, uint256 _reserve0, uint256 _reserve1) = _LBPair
                .getBin(_pair.id);
            if (_reserve0 != 0 || _reserve1 != 0) {
                if (_amount1In != 0) {
                    uint256 _maxAmount1In = _price.mulDivRoundUp(
                        _reserve0,
                        PRICE_PRECISION
                    );

                    uint256 _maxAmount1InWithFees = _maxAmount1In +
                        _fp.getFees(_maxAmount1In, _pair.id - _startId);

                    uint256 _amount1InWithFees = _amount1In >
                        _maxAmount1InWithFees
                        ? _maxAmount1InWithFees
                        : _amount1In;

                    if (_amount1InWithFees > type(uint112).max)
                        revert LBRouter__SwapOverflows(_pair.id);

                    unchecked {
                        uint256 _amount0OutOfBin = _amount1InWithFees != 0
                            ? ((_amount1InWithFees - 1) * _reserve0) /
                                _maxAmount1InWithFees
                            : 0; // Forces round down to match the round up during a swap

                        _amount1In -= _amount1InWithFees;
                        amount0Out += _amount0OutOfBin;
                    }
                } else {
                    uint256 _maxAmount0In = PRICE_PRECISION.mulDivRoundUp(
                        _reserve1,
                        _price
                    );

                    uint256 _maxAmount0InWithFees = _maxAmount0In +
                        _fp.getFees(_maxAmount0In, _startId - _pair.id);

                    uint256 _amount0InWithFees = _amount0In >
                        _maxAmount0InWithFees
                        ? _maxAmount0InWithFees
                        : _amount0In;

                    if (_amount0InWithFees > type(uint112).max)
                        revert LBRouter__SwapOverflows(_pair.id);

                    unchecked {
                        uint256 _amount1OutOfBin = _amount0InWithFees != 0
                            ? ((_amount0InWithFees - 1) * _reserve1) /
                                _maxAmount0InWithFees
                            : 0; // Forces round down to match the round up during a swap

                        _amount0In -= _amount0InWithFees;
                        amount1Out += _amount1OutOfBin;
                    }
                }
            }

            if (_amount0In != 0 || _amount1In != 0) {
                _pair.id = uint24(
                    _LBPair.findFirstBin(_pair.id, _amount1In == 0)
                );
            } else {
                break;
            }
        }
        if (_amount0In != 0 || _amount1In != 0)
            revert LBRouter__TooMuchTokensIn(_amount0In, _amount1In);
    }

    function _addLiquidity(
        IERC20 _token0,
        IERC20 _token1,
        uint256 _ids,
        uint256 _liquidities
    ) private {
        ILBPair pair = factory.getLBPair(_token0, _token1);
        if (address(pair) == address(0))
            revert LBRouter__PairIsNotCreated(_token0, _token1);
    }
}
