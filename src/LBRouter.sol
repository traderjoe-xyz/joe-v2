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
import "./libraries/Constants.sol";

error LBRouter__SenderIsNotWavax();
error LBRouter__PairIsNotCreated(IERC20 tokenX, IERC20 tokenY);
error LBRouter__WrongAmounts(uint256 amountX, uint256 amountY);
error LBRouter__SwapOverflows(uint256 id);
error LBRouter__BrokenSwapSafetyCheck();
error LBRouter__NotFactoryOwner();
error LBRouter__TooMuchTokensIn(uint256 excessX, uint256 excessY);

contract LBRouter is ILBRouter {
    using SafeERC20 for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;
    using Math512Bits for uint256;

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
    /// @param _amountXOut The amount of tokenX to receive
    /// @param _amountYOut The amount of tokenY to receive
    /// @return amountXIn The amount of tokenX to send in order to receive _amountYOut tokenY
    /// @return amountYIn The amount of tokenY to send in order to receive _amountXOut tokenX
    function getSwapIn(
        ILBPair _LBPair,
        uint256 _amountXOut,
        uint256 _amountYOut
    ) external view override returns (uint256 amountXIn, uint256 amountYIn) {
        ILBPair.PairInformation memory _pair = _LBPair.pairInformation();

        if (
            (_amountXOut != 0 && _amountYOut != 0) ||
            _amountXOut > _pair.reserveX ||
            _amountYOut > _pair.reserveY
        ) revert LBRouter__WrongAmounts(_amountXOut, _amountYOut); // If this is wrong, then we're sure the amounts sent are wrong

        FeeHelper.FeeParameters memory _fp = _LBPair.feeParameters();
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.id;

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            (uint256 _price, uint256 _reserveX, uint256 _reserveY) = _LBPair
                .getBin(_pair.id);
            if (_reserveX != 0 || _reserveY != 0) {
                if (_amountXOut != 0) {
                    uint256 _amountXOutOfBin = _amountXOut > _reserveX
                        ? _reserveX
                        : _amountXOut;
                    uint256 _amountYInToBin = _price.mulDivRoundUp(
                        _amountXOutOfBin,
                        Constants.PRICE_PRECISION
                    );
                    uint256 _amountYInWithFees = _amountYInToBin +
                        _fp.getFees(_amountYInToBin, _pair.id - _startId);

                    unchecked {
                        if (_amountYInWithFees > type(uint112).max)
                            revert LBRouter__SwapOverflows(_pair.id);

                        _amountXOut -= _amountXOutOfBin;
                        amountYIn += _amountYInWithFees;
                    }
                } else {
                    uint256 _amountYOutOfBin = _amountYOut > _reserveY
                        ? _reserveY
                        : _amountYOut;
                    uint256 _amountXInToBin = Constants
                        .PRICE_PRECISION
                        .mulDivRoundUp(_amountYOutOfBin, _price);
                    uint256 _amountXInWithFees = _amountXInToBin +
                        _fp.getFees(_amountXInToBin, _startId - _pair.id);

                    unchecked {
                        if (_amountXInWithFees > type(uint112).max)
                            revert LBRouter__SwapOverflows(_pair.id);

                        amountXIn += _amountXInWithFees;
                        _amountYOut -= _amountYOutOfBin;
                    }
                }
            }

            if (_amountXOut != 0 || _amountYOut != 0) {
                _pair.id = uint24(
                    _LBPair.findFirstBin(_pair.id, _amountXOut == 0)
                );
            } else {
                break;
            }
        }
        if (_amountXOut != 0 || _amountYOut != 0)
            revert LBRouter__BrokenSwapSafetyCheck(); // Safety check, but should never be false as it would have reverted on transfer
    }

    /// @notice Simulate a swap out
    /// @param _LBPair The address of the LBPair
    /// @param _amountXIn The amount of tokenX sent
    /// @param _amountYIn The amount of tokenY sent
    /// @return amountXOut The amount of tokenX received if _amountXIn tokenX are sent
    /// @return amountYOut The amount of tokenY received if _amountYIn tokenY are sent
    function getSwapOut(
        ILBPair _LBPair,
        uint256 _amountXIn,
        uint256 _amountYIn
    ) external view override returns (uint256 amountXOut, uint256 amountYOut) {
        ILBPair.PairInformation memory _pair = _LBPair.pairInformation();

        if (_amountXIn != 0 && _amountYIn != 0)
            revert LBRouter__WrongAmounts(amountXOut, amountYOut); // If this is wrong, then we're sure the amounts sent are wrong

        FeeHelper.FeeParameters memory _fp = _LBPair.feeParameters();
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.id;

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            (uint256 _price, uint256 _reserveX, uint256 _reserveY) = _LBPair
                .getBin(_pair.id);
            if (_reserveX != 0 || _reserveY != 0) {
                if (_amountYIn != 0) {
                    uint256 _maxAmountYIn = _price.mulDivRoundUp(
                        _reserveX,
                        Constants.PRICE_PRECISION
                    );

                    uint256 _maxAmountYInWithFees = _maxAmountYIn +
                        _fp.getFees(_maxAmountYIn, _pair.id - _startId);

                    uint256 _amountYInWithFees = _amountYIn >
                        _maxAmountYInWithFees
                        ? _maxAmountYInWithFees
                        : _amountYIn; // TODO doesnt take fee

                    if (_amountYInWithFees > type(uint112).max)
                        revert LBRouter__SwapOverflows(_pair.id);

                    unchecked {
                        uint256 _amountXOutOfBin = _amountYInWithFees != 0
                            ? ((_amountYInWithFees - 1) * _reserveX) /
                                _maxAmountYInWithFees
                            : 0; // Forces round down to match the round up during a swap

                        _amountYIn -= _amountYInWithFees;
                        amountXOut += _amountXOutOfBin;
                    }
                } else {
                    uint256 _maxAmountXIn = Constants
                        .PRICE_PRECISION
                        .mulDivRoundUp(_reserveY, _price);

                    uint256 _maxAmountXInWithFees = _maxAmountXIn +
                        _fp.getFees(_maxAmountXIn, _startId - _pair.id);

                    uint256 _amountXInWithFees = _amountXIn >
                        _maxAmountXInWithFees
                        ? _maxAmountXInWithFees
                        : _amountXIn;

                    if (_amountXInWithFees > type(uint112).max)
                        revert LBRouter__SwapOverflows(_pair.id);

                    unchecked {
                        uint256 _amountYOutOfBin = _amountXInWithFees != 0
                            ? ((_amountXInWithFees - 1) * _reserveY) /
                                _maxAmountXInWithFees
                            : 0; // Forces round down to match the round up during a swap

                        _amountXIn -= _amountXInWithFees;
                        amountYOut += _amountYOutOfBin;
                    }
                }
            }

            if (_amountXIn != 0 || _amountYIn != 0) {
                _pair.id = uint24(
                    _LBPair.findFirstBin(_pair.id, _amountYIn == 0)
                );
            } else {
                break;
            }
        }
        if (_amountXIn != 0 || _amountYIn != 0)
            revert LBRouter__TooMuchTokensIn(_amountXIn, _amountYIn);
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
