// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ILBPair.sol";
import "./interfaces/ILBFactory.sol";
import "./interfaces/IWAVAX.sol";
import "./interfaces/ILBRouter.sol";
import "./libraries/BinHelper.sol";
import "./libraries/FeeHelper.sol";
import "./libraries/Math512Bits.sol";
import "./libraries/SwapHelper.sol";
import "./libraries/Constants.sol";

error LBRouter__SenderIsNotWavax();
error LBRouter__PairIsNotCreated(IERC20 tokenX, IERC20 tokenY);
error LBRouter__WrongAmounts(uint256 amount, uint256 reserve);
error LBRouter__SwapOverflows(uint256 id);
error LBRouter__BrokenSwapSafetyCheck();
error LBRouter__NotFactoryOwner();
error LBRouter__TooMuchTokensIn(uint256 excess);
error LBRouter__BinReserveOverflows(uint256 id);

contract LBRouter is ILBRouter {
    using SafeERC20 for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;
    using Math512Bits for uint256;
    using SwapHelper for ILBPair.PairInformation;

    ILBFactory public immutable factory;
    IWAVAX public immutable wavax;

    modifier onlyFactoryOwner() {
        if (msg.sender != factory.owner()) revert LBRouter__NotFactoryOwner();
        _;
    }

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
        return
            BinHelper.getIdFromPrice(_price, _LBPair.feeParameters().binStep);
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
        return BinHelper.getPriceFromId(_id, _LBPair.feeParameters().binStep);
    }

    /// @notice Simulate a swap in
    /// @param _LBPair The address of the LBPair
    /// @param _amountOut The amount of token to receive
    /// @param _swapForY Wether you swap X for Y (true), or Y for X (false)
    /// @return amountIn The amount of token to send in order to receive _amountOut token
    function getSwapIn(
        ILBPair _LBPair,
        uint256 _amountOut,
        bool _swapForY
    ) external view override returns (uint256 amountIn) {
        ILBPair.PairInformation memory _pair = _LBPair.pairInformation();

        if (
            _amountOut == 0 ||
            (
                _swapForY
                    ? _amountOut > _pair.reserveY
                    : _amountOut > _pair.reserveX
            )
        )
            revert LBRouter__WrongAmounts(
                _amountOut,
                _swapForY ? _pair.reserveY : _pair.reserveX
            ); // If this is wrong, then we're sure the amounts sent are wrong

        FeeHelper.FeeParameters memory _fp = _LBPair.feeParameters();
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.id;

        uint256 _amountOutOfBin;
        uint256 _amountInWithFees;
        uint256 _reserve;
        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            {
                (uint256 _reserveX, uint256 _reserveY) = _LBPair.getBin(
                    _pair.id
                );
                _reserve = _swapForY ? _reserveY : _reserveX;
            }
            uint256 _price = BinHelper.getPriceFromId(_pair.id, _fp.binStep);
            if (_reserve != 0) {
                _amountOutOfBin = _amountOut > _reserve ? _reserve : _amountOut;

                uint256 _amountInToBin = _swapForY
                    ? Constants.PRICE_PRECISION.mulDivRoundUp(
                        _amountOutOfBin,
                        _price
                    )
                    : _price.mulDivRoundUp(
                        _amountOutOfBin,
                        Constants.PRICE_PRECISION
                    );

                _amountInWithFees =
                    _amountInToBin +
                    _fp.getFees(
                        _amountInToBin,
                        _startId > _pair.id
                            ? _startId - _pair.id
                            : _pair.id - _startId
                    );

                if (_amountInWithFees + _reserve > type(uint112).max)
                    revert LBRouter__SwapOverflows(_pair.id);
                amountIn += _amountInWithFees;
                _amountOut -= _amountOutOfBin;
            }

            if (_amountOut != 0) {
                _pair.id = uint24(_LBPair.findFirstBin(_pair.id, _swapForY));
            } else {
                break;
            }
        }
        if (_amountOut != 0) revert LBRouter__BrokenSwapSafetyCheck(); // Safety check, but should never be false as it would have reverted on transfer
    }

    /// @notice Simulate a swap out
    /// @param _LBPair The address of the LBPair
    /// @param _amountIn The amount of token sent
    /// @param _swapForY Wether you swap X for Y (true), or Y for X (false)
    /// @return _amountOut The amount of token received if _amountIn tokenX are sent
    function getSwapOut(
        ILBPair _LBPair,
        uint256 _amountIn,
        bool _swapForY
    ) external view override returns (uint256 _amountOut) {
        ILBPair.PairInformation memory _pair = _LBPair.pairInformation();

        FeeHelper.FeeParameters memory _fp = _LBPair.feeParameters();
        _fp.updateAccumulatorValue();
        ILBPair.Bin memory _bin;

        uint256 _startId = _pair.id;

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            {
                (uint256 _reserveX, uint256 _reserveY) = _LBPair.getBin(
                    _pair.id
                );
                _bin = ILBPair.Bin(
                    uint112(_reserveX),
                    uint112(_reserveY),
                    0,
                    0
                );
            }
            if (_bin.reserveX != 0 || _bin.reserveY != 0) {
                (
                    uint256 _amountInToBin,
                    uint256 _amountOutOfBin,
                    FeeHelper.FeesDistribution memory _fees
                ) = _pair.getAmounts(
                        _bin,
                        _fp,
                        !_swapForY,
                        _startId,
                        _amountIn
                    );

                if (_amountInToBin > type(uint112).max)
                    revert LBRouter__BinReserveOverflows(_pair.id);

                _amountIn -= _amountInToBin + _fees.total;
                _amountOut += _amountOutOfBin;
            }

            if (_amountIn != 0) {
                _pair.id = uint24(_LBPair.findFirstBin(_pair.id, _swapForY));
            } else {
                break;
            }
        }
        if (_amountIn != 0) revert LBRouter__TooMuchTokensIn(_amountIn);
    }

    function sweep(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyFactoryOwner {
        if (_amount == type(uint256).max)
            _amount = _token.balanceOf(address(this));
        _token.safeTransfer(_to, _amount);
    }
}
