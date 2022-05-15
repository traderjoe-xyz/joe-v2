// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./JLBPToken.sol";
import "./libraries/Search.sol";
import "./libraries/Math.sol";
import "./libraries/MathS40x36.sol";

error LBP__FeeTooBig(uint256 fee);
error LBP__InsufficientAmounts(uint256 amount0In, uint256 amount1In);
error LBP__WrongAmounts(uint256 amount0Out, uint256 amount1Out);
error LBP__BrokenSafetyCheck();
error LBP__WrongInputs(int256 startId, int256 endId, uint256 len);
error LBP__ForbiddenFillFactor();
error LBP__InsufficientLiquidityMinted();
error LBP__InsufficientLiquidityBurned();
error LBP__WrongLengths();
error LBP__TransferFailed(address token, address to, uint256 value);

/// @title Liquidity Bin Exchange
/// @author Trader Joe
/// @notice DexV2 POC
contract LiquidityBinPair is JLBPToken, ReentrancyGuard, ILiquidityBinPair {
    using Math for uint256;
    using MathS40x36 for int256;

    /// @dev Structure to store the global information of the pair such as:
    /// - reserve0: The sum of amounts of token0 across all bins
    /// - reserve1: The sum of amounts of token1 across all bins
    /// - currentId: The currentId of the pair, this is also linked with the price
    /// - currentReserve0: The amount of token0 in the bins[currentId]
    struct GlobalInfo {
        uint128 reserve0;
        uint128 reserve1;
        int256 currentId;
        uint112 currentReserve0;
    }

    IERC20 public token0;
    IERC20 public token1;

    /// @notice The fee added to each swap
    uint256 public fee;
    uint256 public constant PRICE_PRECISION = 1e36;
    uint256 private constant BASIS_POINT_MAX = 10_000;
    /// @notice The `log2(1 + 1bp)` value hard codded as a signed 39.36-decimal fixed-point number
    int256 public constant LOG2_1BP = 0x71cd89a50de980ef9634c417572;
    /// Hardcoded value of bytes4(keccak256(bytes('transfer(address,uint256)')))
    bytes4 private constant SELECTOR = 0xa9059cbb;

    GlobalInfo public global;

    // uint256 private immutable fee_helper;

    Bins private bins;

    /// @notice Constructor of pair (will soon become an init as this contract needs to be a ClonableProxy)
    /// @param _token0 The address of the token0
    /// @param _token1 The address of the token1
    /// @param _fee The fee added to every swap
    constructor(
        IERC20 _token0,
        IERC20 _token1,
        uint256 _fee
    ) {
        if (_fee > BASIS_POINT_MAX / 10) {
            revert LBP__FeeTooBig(_fee);
        }
        unchecked {
            fee = BASIS_POINT_MAX - _fee;
        }

        token0 = _token0;
        token1 = _token1;

        // uint256 _fee_helper;
        // if (BASIS_POINT_MAX + (_fee % BASIS_POINT_MAX) == 0) {
        //     _fee_helper = (BASIS_POINT_MAX * BASIS_POINT_MAX) / (BASIS_POINT_MAX + _fee);
        // } else {
        //     _fee_helper = (BASIS_POINT_MAX * BASIS_POINT_MAX) / (BASIS_POINT_MAX + _fee) + 1;
        // }
        // fee_helper = _fee_helper; // @note do we do this ? (if not, if fee is 50%, people will have to pay for 2 times more in fact, not 1.5 as expected)
    }

    /// @notice Performs a low level swap, this needs to be called from a contract which performs important safety checks
    /// @param _amount0Out The amount of token0
    /// @param _amount1Out The amount of token1
    /// @param _to The address of the recipient
    /// @param _data Unused for now
    function swap(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to,
        bytes calldata _data
    ) external nonReentrant {
        GlobalInfo memory _global = global;
        uint256 _amount0In = token0.balanceOf(address(this)) - _global.reserve0;
        uint256 _amount1In = token1.balanceOf(address(this)) - _global.reserve1;
        if (_amount0In == 0 && _amount1In == 0)
            revert LBP__InsufficientAmounts(_amount0In, _amount1In);

        if (_amount0Out != 0) {
            _safeTransfer(address(token0), _to, _amount0Out);
            _amount0Out = _getAmountOut(_amount0In, _amount0Out);
        }
        if (_amount1Out != 0) {
            _safeTransfer(address(token1), _to, _amount1Out);
            _amount1Out = _getAmountOut(_amount1In, _amount1Out);
        }

        if (_amount0Out != 0 && _amount1Out != 0)
            revert LBP__WrongAmounts(_amount0Out, _amount1Out); // If this is wrong, then we're sure the amounts sent are wrong

        int256 _currentId = _global.currentId;

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (_amount0Out != 0 || _amount1Out != 0) {
            uint256 _reserve = bins.reserves[_global.currentId];
            if (_reserve != 0 || _global.currentReserve0 != 0) {
                // TODO only 1 reserve data for all bins except current one, if swap > reserve -> bin is wiped, else its current
                if (_amount0Out != 0) {
                    uint256 _reserve0 = _currentId == _global.currentId
                        ? _global.currentReserve0
                        : _reserve;
                    uint256 _amount0OutOfBin = _amount0Out > _reserve0
                        ? _reserve0
                        : _amount0Out;
                    uint256 _amount1InToBin = _getPriceFromId(_global.currentId)
                        .mulDivRoundUp(
                            _amount0OutOfBin * BASIS_POINT_MAX,
                            PRICE_PRECISION * fee
                        );
                    _reserve += _amount1InToBin;
                    _global.currentReserve0 = (_reserve0 - _amount0OutOfBin)
                        .safe112();

                    _amount0Out -= _amount0OutOfBin;
                    _global.reserve0 -= _amount0OutOfBin.safe112(); // check that this can't underflow

                    _amount1In -= _amount1InToBin; // check that these can't overflow
                    _global.reserve1 += _amount1InToBin.safe112();
                } else {
                    uint256 _amount1OutOfBin = _amount1Out > _reserve
                        ? _reserve
                        : _amount1Out;
                    uint256 _amount0InToBin = PRICE_PRECISION.mulDivRoundUp(
                        _amount1OutOfBin * BASIS_POINT_MAX,
                        _getPriceFromId(_global.currentId) * fee
                    );

                    if (_amount1OutOfBin == _amount1Out) {
                        // this is the final bin, so this bin is a mix of x and y
                        _reserve -= _amount1OutOfBin;
                        _global.currentReserve0 = (_global.currentReserve0 +
                            _amount0InToBin).safe112();
                    } else {
                        // This is not the final bin, so this bin becomes only x
                        _reserve = _amount0InToBin + _global.currentReserve0;
                        _global.currentReserve0 = 0;
                    }

                    _amount1Out -= _amount1OutOfBin;
                    _global.reserve1 -= _amount1OutOfBin.safe112(); // check that this can't underflow

                    _amount0In -= _amount0InToBin; // check that these can't overflow
                    _global.reserve0 += _amount0InToBin.safe112();
                }

                bins.reserves[_global.currentId] = _reserve.safe112();
            }

            if (_amount0Out != 0 || _amount1Out != 0) {
                _global.currentId = Search._findFirstBin(
                    bins,
                    _global.currentId,
                    _amount0Out == 0
                );
            }
        }
        global = _global;
        if (_amount0Out != 0 || _amount1Out != 0)
            revert LBP__BrokenSafetyCheck(); // Safety check, but should never be false as it would have reverted on transfer
    }

    /// @notice Performs a low level add, this needs to be called from a contract which performs important safety checks
    /// @param _startPrice The first price user wants like to add liquidity to
    /// @param _endPrice The last price user wants to add liquidity to
    /// @param _amounts0 The amounts of token0
    /// @param _amounts1 The amounts of token1
    /// @param _to The address of the recipient
    function addLiquidity(
        uint256 _startPrice,
        uint256 _endPrice, // endPrice is included
        uint112[] calldata _amounts0, // [1 2 5 20 0 0 0]
        uint112[] calldata _amounts1, // [0 0 0 20 5 2 1]
        address _to
    ) external nonReentrant {
        uint256 _len = _amounts0.length;
        int256 _startId = _getIdFromPrice(_startPrice);
        int256 _endId = _getIdFromPrice(_endPrice);

        if (
            _startPrice == 0 ||
            _startPrice > _endPrice ||
            _len != _amounts1.length ||
            _endId - _startId + 1 != int256(_len)
        ) revert LBP__WrongInputs(_startId, _endId, _len);

        GlobalInfo memory _global = global;
        uint256 _amount0In = token0.balanceOf(address(this)) - _global.reserve0;
        uint256 _amount1In = token1.balanceOf(address(this)) - _global.reserve1;

        // seeding liquidity
        if (_global.currentId == 0) {
            _global.currentId =
                _startId +
                int256(Search.binarySearchMiddle(_amounts0, 0, _len - 1));
        }

        int256 id = _startId;
        for (; id <= _endId; id++) {
            uint256 _amount0 = _amounts0[uint256(id - _startId)];
            uint256 _amount1 = _amounts1[uint256(id - _startId)];
            if (_amount0 != 0 || _amount1 != 0) {
                uint256 _reserve = bins.reserves[id];

                uint256 _pastL;
                uint256 _newL;

                if (
                    _reserve == 0 ||
                    (id == _global.currentId && _global.currentReserve0 == 0)
                ) {
                    // add 1 at the right indices if the pair was empty
                    uint256 absId = id.abs();
                    bins.tree[2][id / 256] |= 1 << (absId % 256);
                    bins.tree[1][id / 65_536] |= 1 << ((absId / 256) % 256);
                    bins.tree[0][0] |= 1 << (absId / 65_536);
                }
                if (id < _global.currentId) {
                    if (_amount0 != 0) revert LBP__ForbiddenFillFactor();
                    _pastL = _reserve;

                    _amount1In -= _amount1; // revert if too much
                    _reserve += _amount1;
                    _global.reserve1 = (_global.reserve1 + _amount1).safe112();

                    _newL = _amount1;
                } else if (id > _global.currentId) {
                    if (_amount1 != 0) revert LBP__ForbiddenFillFactor();
                    uint256 _price = _getPriceFromId(id);
                    _pastL = _price.mulDivRoundUp(_reserve, PRICE_PRECISION);

                    _amount0In -= _amount0; // revert if too much
                    _reserve += _amount0;
                    _global.reserve0 = (_global.reserve0 + _amount0).safe112();

                    _newL = _price.mulDivRoundUp(_amount0, PRICE_PRECISION);
                } else {
                    // @note for slippage adds, do this first and modulate the amounts
                    if (
                        (_reserve != 0 &&
                            uint256(_amount1).mulDivRoundDown(
                                _global.currentReserve0,
                                _reserve
                            ) !=
                            _amount0) ||
                        (_reserve == 0 &&
                            _amount1 != 0 &&
                            _global.currentReserve0 != 0)
                    ) revert LBP__ForbiddenFillFactor();

                    uint256 _price = _getPriceFromId(id);
                    _pastL =
                        _price.mulDivRoundUp(
                            _global.currentReserve0,
                            PRICE_PRECISION
                        ) +
                        _reserve;

                    _amount0In -= _amount0; // revert if too much
                    _amount1In -= _amount1; // revert if too much

                    _global.currentReserve0 = (_global.currentReserve0 +
                        _amount0).safe112();
                    _reserve += _amount1;

                    _global.reserve0 += uint128(_amount0);
                    _global.reserve1 += uint128(_amount1);

                    _newL =
                        _price.mulDivRoundUp(_amount0, PRICE_PRECISION) +
                        _amount1;
                }
                bins.reserves[id] = uint112(_reserve);
                if (_pastL != 0) {
                    _newL = _newL.mulDivRoundUp(_totalSupplies[id], _pastL);
                }
                if (_newL == 0) revert LBP__InsufficientLiquidityMinted();

                _mint(_to, id, _newL);
            }
        }
        global = _global;
    }

    /// @notice Performs a low level remove, this needs to be called from a contract which performs important safety checks
    /// @param _ids The ids the user want to remove its liquidity
    /// @param _amounts The amounts he wants to remove
    /// @param _to The address of the recipient
    function removeLiquidity(
        int112[] calldata _ids,
        uint256[] calldata _amounts,
        address _to
    ) external nonReentrant {
        uint256 _len = _ids.length;
        if (_len != _amounts.length) revert LBP__WrongLengths();

        GlobalInfo memory _global = global;

        uint256 _amounts0;
        uint256 _amounts1;

        for (uint256 i; i <= _len; i++) {
            uint256 _amount = _amounts[i];

            if (_amount == 0) revert LBP__InsufficientLiquidityBurned();

            int256 _id = _ids[i];
            uint256 _reserve = bins.reserves[_id];

            uint256 totalSupply = _totalSupplies[_id];

            if (_id <= _global.currentId) {
                uint112 _amount1 = _amount
                    .mulDivRoundDown(_reserve, totalSupply)
                    .safe112();

                _amounts1 += _amount1;
                _reserve -= _amount1;
                _global.reserve1 -= _amount1;
            }
            if (_id >= _global.currentId) {
                uint256 _amount0;
                if (_id == _global.currentId) {
                    _amount0 = _amount
                        .mulDivRoundDown(_global.currentReserve0, totalSupply)
                        .safe112();
                    _global.currentReserve0 -= uint112(_amount0);
                } else {
                    _amount0 = _amount
                        .mulDivRoundDown(_reserve, totalSupply)
                        .safe112();
                    _reserve -= _amount0;
                }

                _amounts0 += _amount0;
                _global.reserve0 -= _amount0.safe112();
            }

            if (
                _reserve == 0 &&
                (_id != _global.currentId || _global.currentReserve0 == 0)
            ) {
                // removes 1 at the right indices
                uint256 absId = _id.abs();
                bins.tree[2][_id / 256] -= 1 << (absId % 256);
                if (bins.tree[2][_id / 256] == 0) {
                    bins.tree[1][_id / 65_536] -= 1 << ((absId / 256) % 256);
                    if (bins.tree[1][_id / 65_536] == 0) {
                        bins.tree[0][0] -= 1 << (absId / 65_536);
                    }
                }
            }

            bins.reserves[_id] = uint112(_reserve);

            _burn(address(this), _id, _amount);
        }
        global = _global;
        _safeTransfer(address(token0), _to, _amounts0);
        _safeTransfer(address(token1), _to, _amounts1);
    }

    /// @notice View function to get the bin at price `price`
    /// @param _price The exchange price of y per x (multiplied by 1e36)
    /// @return reserve0 The reserve0 of the bin corresponding to the inputted price
    /// @return reserve1 The reserve1 of the bin corresponding to the inputted price
    function getBin(uint256 _price)
        external
        view
        returns (uint112 reserve0, uint112 reserve1)
    {
        int256 _id = _getIdFromPrice(_price);
        int256 _currentId = global.currentId;
        if (_id < _currentId) return (bins.reserves[_id], 0);
        if (_id > _currentId) return (0, bins.reserves[_id]);
        return (global.currentReserve0, bins.reserves[_id]);
    }

    /// @notice Returns the first id that is non zero, corresponding to a bin with
    /// liquidity in it
    /// @param _binId the binId to start searching
    /// @param _isSearchingRight The boolean value to decide if the algorithm will look
    /// for the closest non zero bit on the right or the left
    /// @return The closest non zero bit on the right side
    function findFirstBin(int256 _binId, bool _isSearchingRight)
        external
        view
        returns (int256)
    {
        return Search._findFirstBin(bins, _binId, _isSearchingRight);
    }

    /// @notice Returns the id corresponding to the inputted price
    /// @param _price The price of y per x (multiplied by 1e36)
    /// @return The id corresponding to this price
    function getIdFromPrice(uint256 _price) external pure returns (int256) {
        return _getIdFromPrice(_price);
    }

    /// @notice Returns the price corresponding to the inputted id
    /// @param _id The id
    /// @return The price corresponding to this id
    function getPriceFromId(int256 _id) external pure returns (uint256) {
        return _getPriceFromId(_id);
    }

    /** Private functions **/

    /// @notice Returns the id corresponding to the inputted price
    /// @param _price The price of y per x (multiplied by 1e36)
    /// @return The id corresponding to this price
    function _getIdFromPrice(uint256 _price) private pure returns (int256) {
        if (_price > PRICE_PRECISION) {
            return (int256(_price).log2() - 1) / LOG2_1BP + 1;
        } else {
            return int256(_price).log2() / LOG2_1BP;
        }
    }

    /// @notice Returns the price corresponding to the inputted id
    /// @param _id The id
    /// @return The price corresponding to this id
    function _getPriceFromId(int256 _id) private pure returns (uint256) {
        return uint256((_id * LOG2_1BP).exp2());
    }

    function _getAmountOut(uint256 _amountIn, uint256 _amountOut)
        private
        view
        returns (uint112)
    {
        // if some token0 are stuck, we take them in account here
        uint256 _amount = (_amountIn * fee) / BASIS_POINT_MAX;
        if (_amountOut > _amount) {
            return (_amountOut - _amount).safe112();
        }
        return 0;
    }

    function _safeTransfer(
        address _token,
        address _to,
        uint256 _value
    ) private {
        (bool _success, bytes memory _data) = _token.call(
            abi.encodeWithSelector(SELECTOR, _to, _value)
        );
        if (!_success || (_data.length != 0 && abi.decode(_data, (bool))))
            revert LBP__TransferFailed(_token, _to, _value);
    }
}
