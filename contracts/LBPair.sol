// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./LBToken.sol";
import "./libraries/Math.sol";
import "./libraries/MathS40x36.sol";

error LBPair__BaseFeeTooBig(uint256 baseFee);
error LBPair__InsufficientAmounts();
error LBPair__WrongAmounts(uint256 amount0Out, uint256 amount1Out);
error LBPair__BrokenSafetyCheck();
error LBPair__ForbiddenFillFactor();
error LBPair__InsufficientLiquidityMinted();
error LBPair__InsufficientLiquidityBurned();
error LBPair__WrongLengths();
error LBPair__ZeroAddress();
error LBPair__AlreadyInitialized();
error LBPair__TransferFailed(address token, address to, uint256 value);
error LBPair__ErrorDepthSearch();
error LBPair__WrongId();
error LBPair__BasisPointTooBig();
error LBPair__SwapExceedsAmountIn();

// TODO add oracle price, add baseFee distributed to protocol
/// @title Liquidity Bin Exchange
/// @author Trader Joe
/// @notice DexV2 POC
contract LBPair is LBToken, ReentrancyGuardUpgradeable {
    using Math for uint256;
    using MathS40x36 for int256;

    /// @dev Structure to store the globalInfo information of the pair such as:
    /// - currentId: The currentId of the pair, this is also linked with the price
    /// - reserve0: The sum of amounts of token0 across all bins
    /// - reserve1: The sum of amounts of token1 across all bins
    /// - currentReserve0: The amount of token0 in the bins[currentId]
    struct GlobalInfo {
        uint24 currentId;
        uint136 reserve0;
        uint136 reserve1;
        uint112 currentReserve0;
    }

    uint256 public constant PRICE_PRECISION = 1e36;
    uint256 private constant BASIS_POINT_MAX = 10_000;
    uint256 private constant INT24_SHIFT = 2**23;
    /// @dev Hardcoded value of bytes4(keccak256(bytes('transfer(address,uint256)')))
    bytes4 private constant SELECTOR = 0xa9059cbb;

    IERC20Upgradeable public immutable token0;
    IERC20Upgradeable public immutable token1;

    /// @notice The baseFee added to each swap
    uint256 public immutable baseFee;
    /// @notice The `log2(1 + α bp)` value as a signed 39.36-decimal fixed-point number
    int256 public immutable log2Value;

    GlobalInfo private globalInfo;
    bool private initialized;

    // uint256 private immutable fee_helper;

    /// @dev the reserves of tokens for every bin. This is the amount
    /// of token1 if `id < globalInfo.id`; of token0 if `id > globalInfo.id`
    /// and a mix of both if `id == globalInfo.id`
    mapping(uint256 => uint112) private _reserves;

    /// @dev Tree to find bins with non zero liquidity
    mapping(uint256 => uint256)[3] private _tree;

    /// @notice Initialize the parameters
    /// @param _token0 The address of the token0. Can't be address 0
    /// @param _token1 The address of the token1. Can't be address 0
    /// @param _baseFee The baseFee added to every swap. Max is 100 (1%)
    /// @param _bp The basis point, used to calculate log(1 + _bp). Max is 100 (1%)
    constructor(
        IERC20Upgradeable _token0,
        IERC20Upgradeable _token1,
        uint256 _baseFee,
        uint256 _bp
    ) LBToken("Liquidity Unified Bin Exchange", "LUBE") {
        if (initialized) revert LBPair__AlreadyInitialized();
        if (_isAddress0(_token0) || _isAddress0(_token1))
            revert LBPair__ZeroAddress();
        if (_baseFee > BASIS_POINT_MAX / 100)
            revert LBPair__BaseFeeTooBig(_baseFee);
        if (_bp > BASIS_POINT_MAX / 100) revert LBPair__BasisPointTooBig();
        initialized = true;

        token0 = _token0;
        token1 = _token1;
        baseFee = _baseFee;
        log2Value = int256(
            PRICE_PRECISION + (_bp * PRICE_PRECISION) / BASIS_POINT_MAX
        ).log2();
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
        GlobalInfo memory _global = globalInfo;
        uint256 _amount0In;
        uint256 _amount1In;

        if (_amount0Out != 0) {
            _amount1In = token1.balanceOf(address(this)) - _global.reserve1;
            _safeTransfer(address(token0), _to, _amount0Out);
            _amount0Out = _getAmountOut(_amount0In, _amount0Out);
        }
        if (_amount1Out != 0) {
            _amount0In = token0.balanceOf(address(this)) - _global.reserve0;
            _safeTransfer(address(token1), _to, _amount1Out);
            _amount1Out = _getAmountOut(_amount1In, _amount1Out);
        }
        if (_amount0In == 0 && _amount1In == 0)
            revert LBPair__InsufficientAmounts();

        if (_amount0Out != 0 && _amount1Out != 0)
            revert LBPair__WrongAmounts(_amount0Out, _amount1Out); // If this is wrong, then we're sure the amounts sent are wrong

        uint256 _currentId = _global.currentId;
        uint256 _fee = _getFee();

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (_amount0Out != 0 || _amount1Out != 0) {
            uint256 _reserve = _reserves[_global.currentId];
            if (_reserve != 0 || _global.currentReserve0 != 0) {
                uint256 _price = _getPriceFromId(_global.currentId);
                if (_amount0Out != 0) {
                    uint256 _reserve0 = _getReserve(
                        _currentId,
                        _global.currentId,
                        _global.currentReserve0,
                        _reserve
                    );

                    (
                        uint256 _amount0OutOfBin,
                        uint256 _amount1InToBin
                    ) = _getAmountsOut(
                            _amount0Out,
                            _reserve0,
                            _price,
                            PRICE_PRECISION,
                            _fee
                        );

                    _reserve = _reserve + _amount1InToBin;
                    if (_amount1In < _amount1InToBin)
                        revert LBPair__SwapExceedsAmountIn();

                    unchecked {
                        _global.currentReserve0 = uint112(
                            _reserve0 - _amount0OutOfBin
                        );
                        _amount0Out -= _amount0OutOfBin;
                        _global.reserve0 -= uint112(_amount0OutOfBin);

                        _amount1In -= _amount1InToBin;
                        _global.reserve1 += uint112(_amount1InToBin);
                    }
                } else {
                    (
                        uint256 _amount1OutOfBin,
                        uint256 _amount0InToBin
                    ) = _getAmountsOut(
                            _amount1Out,
                            _reserve,
                            PRICE_PRECISION,
                            _price,
                            _fee
                        );

                    if (_amount0In < _amount0InToBin)
                        revert LBPair__SwapExceedsAmountIn();

                    unchecked {
                        if (_amount1OutOfBin == _amount1Out) {
                            // this is the final bin, so this bin is a mix of x and y
                            _reserve -= _amount1OutOfBin;
                            _global.currentReserve0 = (_global.currentReserve0 +
                                _amount0InToBin).safe112();
                        } else {
                            // This is not the final bin, so this bin becomes only x
                            _reserve =
                                _amount0InToBin +
                                _global.currentReserve0;
                            _global.currentReserve0 = 0;
                        }

                        _amount1Out -= _amount1OutOfBin;
                        _global.reserve1 -= uint112(_amount1OutOfBin);

                        _amount0In -= _amount0InToBin;
                        _global.reserve0 += uint112(_amount0InToBin);
                    }
                }
                _reserves[_global.currentId] = _reserve.safe112();
            }

            if (_amount0Out != 0 || _amount1Out != 0) {
                _global.currentId = _findFirstBin(
                    _global.currentId,
                    _amount0Out == 0
                ).safe24();
            }
        }
        globalInfo = _global;
        if (_amount0Out != 0 || _amount1Out != 0)
            revert LBPair__BrokenSafetyCheck(); // Safety check, but should never be false as it would have reverted on transfer
    }

    function _getReserve(
        uint256 _currentId,
        uint256 _id,
        uint256 _reserve0,
        uint256 _reserve
    ) internal pure returns (uint256 reserve) {
        reserve = _currentId == _id ? _reserve0 : _reserve;
    }

    function _getAmountsOut(
        uint256 _amountOut,
        uint256 _reserve,
        uint256 _numerator,
        uint256 _denominator,
        uint256 _fee
    ) internal pure returns (uint256 amountOut, uint256 amountIn) {
        amountOut = _amountOut > _reserve ? _reserve : _amountOut;
        amountIn = _numerator
            .mulDivRoundUp(amountOut * BASIS_POINT_MAX, _denominator * _fee)
            .safe112();
    }

    function _getAmountsIn(
        uint256 _amountIn,
        uint256 _reserve,
        uint256 _numerator,
        uint256 _denominator,
        uint256 _fee,
        uint256 _amountOut
    ) internal pure returns (uint256, uint256) {
        uint256 _maxAmountIn = _numerator.mulDivRoundUp(
            _reserve * BASIS_POINT_MAX,
            _denominator * _fee
        );
        uint256 _amountInToBin = _amountIn > _maxAmountIn
            ? _maxAmountIn
            : _amountIn;

        unchecked {
            return (
                _amountIn - _amountInToBin,
                _amountOut + (_amountInToBin * _reserve) / _maxAmountIn
            );
        }
    }

    /// @notice Simulate a swap in
    /// @param _amount0Out The amount of token0 to receive
    /// @param _amount1Out The amount of token1 to receive
    /// @return amount0In The amount of token0 to send in order to receive _amount1Out token1
    /// @return amount1In The amount of token1 to send in order to receive _amount0Out token0
    function getSwapIn(uint256 _amount0Out, uint256 _amount1Out)
        external
        view
        returns (uint256 amount0In, uint256 amount1In)
    {
        GlobalInfo memory _global = globalInfo;

        if (
            (_amount0Out != 0 && _amount1Out != 0) ||
            _amount0Out > _global.reserve0 ||
            _amount1Out > _global.reserve1
        ) revert LBPair__WrongAmounts(_amount0Out, _amount1Out); // If this is wrong, then we're sure the amounts sent are wrong

        uint256 _currentId = _global.currentId;
        uint256 _fee = _getFee();

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (_amount0Out != 0 || _amount1Out != 0) {
            uint256 _reserve = _reserves[_currentId];
            if (_reserve != 0 || _global.currentReserve0 != 0) {
                uint256 _price = _getPriceFromId(uint24(_currentId));
                if (_amount0Out != 0) {
                    uint256 _reserve0 = _getReserve(
                        _currentId,
                        _global.currentId,
                        _global.currentReserve0,
                        _reserve
                    );

                    (
                        uint256 _amount0OutOfBin,
                        uint256 _amount1InToBin
                    ) = _getAmountsOut(
                            _amount0Out,
                            _reserve0,
                            _price,
                            PRICE_PRECISION,
                            _fee
                        );
                    unchecked {
                        _amount0Out -= _amount0OutOfBin;
                        amount1In += _amount1InToBin;
                    }
                } else {
                    (
                        uint256 _amount1OutOfBin,
                        uint256 _amount0InToBin
                    ) = _getAmountsOut(
                            _amount1Out,
                            _reserve,
                            PRICE_PRECISION,
                            _price,
                            _fee
                        );
                    unchecked {
                        _amount1Out -= _amount1OutOfBin;
                        amount0In += _amount0InToBin;
                    }
                }
            }

            if (_amount0Out != 0 || _amount1Out != 0) {
                _currentId = _findFirstBin(_currentId, _amount0Out == 0)
                    .safe24();
            }
        }
        if (_amount0Out != 0 || _amount1Out != 0)
            revert LBPair__BrokenSafetyCheck(); // Safety check, but should never be false as it would have reverted on transfer
    }

    /// @notice Simulate a swap out
    /// @param _amount0In The amount of token0 sent
    /// @param _amount1In The amount of token1 sent
    /// @return amount0Out The amount of token0 received if _amount0In token0 are sent
    /// @return amount1Out The amount of token1 received if _amount1In token1 are sent
    function getSwapOut(uint256 _amount0In, uint256 _amount1In)
        external
        view
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        GlobalInfo memory _global = globalInfo;

        if (_amount0In != 0 && _amount1In != 0)
            revert LBPair__WrongAmounts(amount0Out, amount1Out); // If this is wrong, then we're sure the amounts sent are wrong

        uint256 _currentId = _global.currentId;
        uint256 _fee = _getFee();

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (_amount0In != 0 || _amount1In != 0) {
            uint256 _reserve = _reserves[_currentId];
            if (_reserve != 0 || _global.currentReserve0 != 0) {
                uint256 _price = _getPriceFromId(uint24(_currentId));
                if (_amount1In != 0) {
                    uint256 _reserve0 = _getReserve(
                        _currentId,
                        _global.currentId,
                        _global.currentReserve0,
                        _reserve
                    );
                    (_amount1In, amount0Out) = _getAmountsIn(
                        _amount1In,
                        _reserve0,
                        _price,
                        PRICE_PRECISION,
                        _fee,
                        amount0Out
                    );
                } else {
                    (_amount0In, amount1Out) = _getAmountsIn(
                        _amount0In,
                        _reserve,
                        PRICE_PRECISION,
                        _price,
                        _fee,
                        amount1Out
                    );
                }
            }

            if (_amount0In != 0 || _amount1In != 0) {
                _currentId = _findFirstBin(_currentId, _amount1In == 0).safe24();
            }
        }
        if (_amount0In != 0 || _amount1In != 0)
            revert LBPair__BrokenSafetyCheck(); // Safety check, but should never be false as it would have reverted on transfer
    }

    /// @notice Performs a low level add, this needs to be called from a contract which performs important safety checks
    /// @param _startId The first id user wants like to add liquidity to
    /// @param _amounts0 The amounts of token0
    /// @param _amounts1 The amounts of token1
    /// @param _to The address of the recipient
    function mint(
        uint24 _startId,
        uint112[] calldata _amounts0, // [1 2 5 20 0 0 0]
        uint112[] calldata _amounts1, // [0 0 0 20 5 2 1]
        address _to
    ) external nonReentrant {
        uint256 _len = _amounts0.length;
        if (_len != _amounts1.length && _len != 0)
            revert LBPair__WrongLengths();

        GlobalInfo memory _global = globalInfo;
        uint256 _amount0In = token0.balanceOf(address(this)) - _global.reserve0;
        uint256 _amount1In = token1.balanceOf(address(this)) - _global.reserve1;

        uint256 id = _startId;

        // seeding liquidity
        if (_global.currentId == 0) {
            _global.currentId = (id +
                _binarySearchMiddle(_amounts0, 0, _len - 1)).safe24();
        }

        for (uint256 i; i < _len; ++i) {
            uint256 _amount0 = _amounts0[i];
            uint256 _amount1 = _amounts1[i];
            if (_amount0 != 0 || _amount1 != 0) {
                uint256 _reserve = _reserves[id];

                uint256 _pastL;
                uint256 _newL;

                if (
                    _reserve == 0 ||
                    (id == _global.currentId && _global.currentReserve0 == 0)
                ) {
                    // add 1 at the right indices if the pair was empty
                    _tree[2][id / 256] |= 1 << (id % 256);
                    _tree[1][id / 65_536] |= 1 << ((id / 256) % 256);
                    _tree[0][0] |= 1 << (id / 65_536);
                }
                if (id < _global.currentId) {
                    if (_amount0 != 0) revert LBPair__ForbiddenFillFactor();
                    _pastL = _reserve;

                    _amount1In -= _amount1; // revert if too much
                    _reserve += _amount1;
                    _global.reserve1 = (_global.reserve1 + _amount1).safe112();

                    _newL = _amount1;
                } else if (id > _global.currentId) {
                    if (_amount1 != 0) revert LBPair__ForbiddenFillFactor();

                    uint256 _price = _getPriceFromId(uint24(id));
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
                            _amount1 != 0 && // @note can't add 0 ?
                            _global.currentReserve0 != 0)
                    ) revert LBPair__ForbiddenFillFactor();

                    uint256 _price = _getPriceFromId(uint24(id));
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

                    _global.reserve0 += _amount0.safe128();
                    _global.reserve1 += _amount1.safe128();

                    _newL =
                        _price.mulDivRoundUp(_amount0, PRICE_PRECISION) +
                        _amount1;
                }
                _reserves[id] = _reserve.safe112();
                if (_pastL != 0) {
                    _newL = _newL.mulDivRoundUp(totalSupply(id), _pastL);
                }
                if (_newL == 0) revert LBPair__InsufficientLiquidityMinted();

                _mint(_to, id, _newL);
                ++id;
            }
        }
        globalInfo = _global;
    }

    /// @notice Performs a low level remove, this needs to be called from a contract which performs important safety checks
    /// @param _ids The ids the user want to remove its liquidity
    /// @param _to The address of the recipient
    function burn(uint24[] calldata _ids, address _to) external nonReentrant {
        uint256 _len = _ids.length;

        GlobalInfo memory _global = globalInfo;

        uint256 _amounts0;
        uint256 _amounts1;

        for (uint256 i; i < _len; ++i) {
            uint256 _id = _ids[i];
            uint256 _amount = balanceOf(address(this), _id);

            if (_amount == 0) revert LBPair__InsufficientLiquidityBurned();

            uint256 _reserve = _reserves[_id];

            uint256 totalSupply = totalSupply(_id);

            if (_id <= _global.currentId) {
                uint256 _amount1 = _amount.mulDivRoundDown(
                    _reserve,
                    totalSupply
                );

                _amounts1 += _amount1;
                _reserve -= _amount1;
                _global.reserve1 -= _amount1.safe128();
            }
            if (_id >= _global.currentId) {
                uint256 _amount0;
                if (_id == _global.currentId) {
                    _amount0 = _amount.mulDivRoundDown(
                        _global.currentReserve0,
                        totalSupply
                    );
                    _global.currentReserve0 -= uint112(_amount0);
                } else {
                    _amount0 = _amount.mulDivRoundDown(_reserve, totalSupply);
                    _reserve -= _amount0;
                }

                _amounts0 += _amount0;
                _global.reserve0 -= _amount0.safe128();
            }

            if (
                _reserve == 0 &&
                (_id != _global.currentId || _global.currentReserve0 == 0)
            ) {
                // removes 1 at the right indices
                uint256 memId2 = _id / 256;
                _tree[2][memId2] -= 1 << (_id % 256);
                if (_tree[2][memId2] == 0) {
                    uint256 memId1 = _id / 65_536;
                    _tree[1][memId1] -= 1 << (memId2 % 256);
                    if (_tree[1][memId1] == 0) {
                        _tree[0][0] -= 1 << memId1;
                    }
                }
            }

            _reserves[_id] = uint112(_reserve);

            _burn(address(this), _id, _amount);
        }
        globalInfo = _global;
        _safeTransfer(address(token0), _to, _amounts0);
        _safeTransfer(address(token1), _to, _amounts1);
    }

    /// @notice View function to get the bin at `id`
    /// @param _id The bin id
    /// @return price The exchange price of y per x inside this bin (multiplied by 1e36)
    /// @return reserve0 The reserve of token0 of the bin
    /// @return reserve1 The reserve of token1 of the bin
    function getBin(uint24 _id)
        external
        view
        returns (
            uint256 price,
            uint112 reserve0,
            uint112 reserve1
        )
    {
        uint256 _price = _getPriceFromId(_id);
        uint256 _currentId = globalInfo.currentId;
        if (_id < _currentId) return (_price, 0, _reserves[_id]);
        if (_id > _currentId) return (_price, _reserves[_id], 0);
        return (_price, globalInfo.currentReserve0, _reserves[_id]);
    }

    /// @notice Returns the approximate id corresponding to the inputted price.
    /// Warning, the returned id may be inaccurate close to the start price of a bin
    /// @param _price The price of y per x (multiplied by 1e36)
    /// @return The id corresponding to this price
    function getIdFromPrice(uint256 _price) external view returns (uint24) {
        return _getIdFromPrice(_price);
    }

    /// @notice Returns the price corresponding to the inputted id
    /// @param _id The id
    /// @return The price corresponding to this id
    function getPriceFromId(uint24 _id) external view returns (uint256) {
        return _getPriceFromId(_id);
    }

    /// @notice View function to return the global data
    /// @return reserve0 The total amount of token0 inside all bins
    /// @return reserve1 The total amount of token1 inside all bins
    /// @return currentId The public current id
    /// @return currentReserve0 The reserve of token0 inside the current bin
    /// @return currentReserve1 The reserve of token1 inside the current bin
    function global()
        external
        view
        returns (
            uint136 reserve0,
            uint136 reserve1,
            uint24 currentId,
            uint112 currentReserve0,
            uint112 currentReserve1
        )
    {
        GlobalInfo memory _global = globalInfo;
        return (
            _global.reserve0,
            _global.reserve1,
            _global.currentId,
            _global.currentReserve0,
            _reserves[_global.currentId]
        );
    }

    /** Private functions **/

    /// @notice Returns the id corresponding to the inputted price
    /// @param _price The price of y per x (multiplied by 1e36)
    /// @return The id corresponding to this price
    function _getIdFromPrice(uint256 _price) private view returns (uint24) {
        /// don't need to check if it overflows as log2(max_s40x36) < 136e36
        /// and log2Value > 1e32, thus the result is lower than 136e36 / 1e32 = 136e4 < 2**24
        return
            uint24(
                uint256(int256(INT24_SHIFT) + int256(_price).log2() / log2Value)
            );
    }

    /// @notice Returns the price corresponding to the inputted id
    /// @param _id The id
    /// @return price The price corresponding to this id
    function _getPriceFromId(uint24 _id) private view returns (uint256 price) {
        unchecked {
            price = uint256((int256(_id - INT24_SHIFT) * log2Value).exp2());
            if (price == 0) revert LBPair__WrongId();
        }
    }

    /// @notice Returns the fee added to a swap
    /// @return The fee
    function _getFee() private view returns (uint256) {
        return BASIS_POINT_MAX - baseFee;
    }

    /// @notice Returns the amount that needs to be swapped
    /// @param _amountIn The amount sent to the pair
    /// @param _amountOut The amount that will be sent to user
    /// @return The amount that still needs to be swapped
    function _getAmountOut(uint256 _amountIn, uint256 _amountOut)
        private
        pure
        returns (uint256)
    {
        // if some tokens are stuck, we take them in account here
        if (_amountOut > _amountIn) {
            return _amountOut - _amountIn;
        }
        return 0;
    }

    /// @notice Returns the first id that is non zero, corresponding to a bin with
    /// liquidity in it
    /// @param _binId the binId to start searching
    /// @param _isSearchingRight The boolean value to decide if the algorithm will look
    /// for the closest non zero bit on the right or the left
    /// @return The closest non zero bit on the right side
    function _findFirstBin(uint256 _binId, bool _isSearchingRight)
        private
        view
        returns (uint256)
    {
        unchecked {
            uint256 current;
            bool found;

            uint256 bit = _binId % 256;
            _binId /= 256;

            // Search in depth 2
            if (
                (_isSearchingRight && bit != 0) ||
                (!_isSearchingRight && bit < 255)
            ) {
                current = _tree[2][_binId];
                (bit, found) = _closestBit(current, bit, _isSearchingRight);
                if (found) {
                    return _binId * 256 + bit;
                }
            }

            bit = _binId % 256;
            _binId /= 256;

            // Search in depth 1
            if (
                (_isSearchingRight && _binId % 256 != 0) ||
                (!_isSearchingRight && _binId % 256 != 255)
            ) {
                current = _tree[1][_binId];
                (bit, found) = _closestBit(current, bit, _isSearchingRight);
                if (found) {
                    _binId = 256 * _binId + bit;
                    current = _tree[2][_binId];
                    bit = current.mostSignificantBit();
                    return _binId * 256 + bit;
                }
            }

            // Search in depth 0
            current = _tree[0][0];
            (_binId, found) = _closestBit(current, _binId, _isSearchingRight);
            if (!found) revert LBPair__ErrorDepthSearch();
            current = _tree[1][_binId];
            _binId = 256 * _binId + _significantBit(current, _isSearchingRight);
            current = _tree[2][_binId];
            bit = _significantBit(current, _isSearchingRight);
            return _binId * 256 + bit;
        }
    }

    /// @notice Returns the first index of the array that is non zero, The
    /// array need to be ordered so that zeros and non zeros aren't together
    /// (no cross over), e.g. [0,1,2,1], [1,1,1,0,0], [0,0,0], [1,2,1]
    /// @param _array The uint112 array
    /// @param _start The index where the search will start
    /// @param _end The index where the search will end
    /// @return The first index of the array that is non zero
    function _binarySearchMiddle(
        uint112[] memory _array,
        uint256 _start,
        uint256 _end
    ) private pure returns (uint256) {
        unchecked {
            uint256 middle;
            if (_array[_end] == 0) {
                return _end;
            }
            while (_end > _start) {
                middle = (_start + _end) / 2;
                if (_array[middle] == 0) {
                    _start = middle + 1;
                } else {
                    _end = middle;
                }
            }
            if (_array[middle] == 0) {
                return middle + 1;
            }
            return middle;
        }
    }

    /// @notice Return the closest non zero bit of `_integer` to the right (or left) of the `bit` index
    /// @param _integer The integer
    /// @param _bit The bit
    /// @param _isSearchingRight If we're searching to the right (true) or left (false)
    /// @return The index of the closest non zero bit
    /// @return Wether it was found (true), or not (false)
    function _closestBit(
        uint256 _integer,
        uint256 _bit,
        bool _isSearchingRight
    ) private pure returns (uint256, bool) {
        unchecked {
            if (_isSearchingRight) {
                return _integer.closestBitRight(_bit - 1);
            }
            return _integer.closestBitLeft(_bit + 1);
        }
    }

    /// @notice Return the most (or least) significant bit of `_integer`
    /// @param _integer The integer
    /// @param _isMostSignificant Wether we want the most (true) or the least (false) significant bit
    /// @return The index of the most (or least) significant bit
    function _significantBit(uint256 _integer, bool _isMostSignificant)
        private
        pure
        returns (uint256)
    {
        if (_isMostSignificant) {
            return _integer.mostSignificantBit();
        }
        return _integer.leastSignificantBit();
    }

    /// @notice Return if the address is the zero address
    /// @param _token The token address
    /// @return True if `_address` is zero address
    function _isAddress0(IERC20Upgradeable _token) private pure returns (bool) {
        return address(_token) == address(0);
    }

    /// @notice Helper function to transfer tokens, similar to safeTransfer, but lighter
    /// @param _token The address of the token
    /// @param _to The address to send tokens to
    /// @param _amount The amount to transfer
    function _safeTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) private {
        (bool _success, bytes memory _data) = _token.call(
            abi.encodeWithSelector(SELECTOR, _to, _amount)
        );
        if (!_success || (_data.length == 0 && !abi.decode(_data, (bool))))
            revert LBPair__TransferFailed(_token, _to, _amount);
    }
}
