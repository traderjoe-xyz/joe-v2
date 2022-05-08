// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./JLBPToken.sol";
import "./libraries/Math.sol";

/// @title Liquidity Bin Exchange
/// @author Trader Joe
/// @notice DexV2 POC
contract LiquidityBinPair is JLBPToken, ReentrancyGuard {
    using Math for uint256;
    using SafeERC20 for IERC20Metadata;

    /// @dev Structure to store the information of a bin such as:
    /// - l: The constant sum liquidity, l, is defined as `p * reserve0 + reserve1`
    /// - reserve0: Amounts of token0 allocated to that bin
    /// - reserve1: Amounts of token1 allocated to that bin
    // @note linked list ? previous bin - next bin etc..., not sure there is a good way to make it work
    struct Bin {
        uint256 l; /// l = p * x + y
        uint112 reserve0; // x
        uint112 reserve1; // y
    }

    /// @dev Structure to store the global information of the pair such as:
    /// - reserve0: The sum of amounts of token0 across all bins
    /// - reserve1: The sum of amounts of token1 across all bins
    /// - currentId: The currentId of the pair, this is also linked with the price
    struct GlobalInfo {
        uint128 reserve0;
        uint128 reserve1;
        uint256 currentId;
    }

    IERC20Metadata public token0;
    IERC20Metadata public token1;

    /// @notice The fee added to each swap
    uint256 public fee;
    /// @notice The bin precision, this defined the change of price between two successive bins
    /// @dev The upper bounds of bins will thus be:
    /// (10 + 9 * (ceil(decimalsOf(max(uint112))) + decimalsOf(PRICE_PRECISION) - BIN_PRECISION_DECIMALS)) * BIN_PRECISION
    /// = (10 + 9 * (34 + 36 - BIN_PRECISION_DECIMALS)) * 10**BIN_PRECISION_DECIMALS
    uint256 public constant BIN_PRECISION = 10**BIN_PRECISION_DECIMALS;
    uint256 public constant PRICE_PRECISION = 1e36;
    uint256 public constant BASIS_POINT_MAX = 10_000;

    GlobalInfo public global;

    // uint256 private immutable fee_helper;

    /// @dev If set to more than 4, then the binEmpty mapping and the findFirstBin function
    /// needs to be updated to make sure all the bins fits in our representation.
    /// The upper bound needs to be lower than 2**(8*binEmptyDepth)
    /// When set to 4, the upper bound is 6040000 and is lower than 2**(3*8)
    uint256 private constant BIN_PRECISION_DECIMALS = 3;

    /// @dev Mapping from an id to a bin
    mapping(uint256 => Bin) private bins;
    /// @dev Tree to know if a bin has liquidity or not
    mapping(uint256 => uint256)[3] private binEmpty;

    /// @notice Constructor of pair (will soon become an init as this contract needs to be a ClonableProxy)
    /// @param _token0 The address of the token0
    /// @param _token1 The address of the token1
    /// @param _fee The fee added to every swap
    constructor(
        IERC20Metadata _token0,
        IERC20Metadata _token1,
        uint256 _fee
    ) {
        require(fee < BASIS_POINT_MAX / 10, "LBP: Fee too big");
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
        uint112 _amount0Out,
        uint112 _amount1Out,
        address _to,
        bytes calldata _data
    ) external nonReentrant {
        GlobalInfo memory _global = global;
        uint256 _amount0in = token0.balanceOf(address(this)) - _global.reserve0;
        uint256 _amount1In = token1.balanceOf(address(this)) - _global.reserve1;
        require(
            _amount0in != 0 || _amount1In != 0,
            "LBP: Insufficient amounts"
        );

        if (_amount0Out != 0) {
            token0.safeTransfer(_to, _amount0Out); // sends tokens
            if (_amount0in != 0) {
                // if some token0 are stuck, we take them in account here
                if ((_amount0in * fee) / BASIS_POINT_MAX < _amount0Out) {
                    _amount0Out -= ((_amount0in * fee) / BASIS_POINT_MAX)
                        .safe112();
                } else {
                    _amount0Out = 0;
                }
            }
        }
        if (_amount1Out != 0) {
            token1.safeTransfer(_to, _amount1Out);
            if (_amount1In != 0) {
                // if some token1 are stuck, we take them in account here
                if ((_amount1In * fee) / BASIS_POINT_MAX < _amount1Out) {
                    _amount1Out -= ((_amount1In * fee) / BASIS_POINT_MAX)
                        .safe112();
                } else {
                    _amount1Out = 0;
                }
            }
        }

        require(_amount0Out == 0 || _amount1Out == 0, "LBP: Wrong amounts"); // If this is wrong, then we're sure the amounts sent are wrong

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (_amount0Out != 0 || _amount1Out != 0) {
            Bin memory _bin = bins[_global.currentId];
            if (_bin.reserve0 != 0 || _bin.reserve1 != 0) {
                if (_amount0Out != 0) {
                    uint112 _amount0OutOfBin = _amount0Out > _bin.reserve0
                        ? _bin.reserve0
                        : _amount0Out;

                    _bin.reserve0 -= _amount0OutOfBin;
                    _global.reserve0 -= _amount0OutOfBin;
                    _amount0Out -= _amount0OutOfBin;

                    uint256 _amount1InToBin = _getPriceFromId(_global.currentId)
                        .mulDivRoundUp(
                            _amount0OutOfBin * BASIS_POINT_MAX,
                            PRICE_PRECISION * fee
                        );
                    _amount1In -= _amount1InToBin;
                    _bin.reserve1 += _amount1InToBin.safe112();
                    _global.reserve1 += _amount1InToBin.safe112();
                }
                if (_amount1Out != 0) {
                    uint112 _amount1OutOfBin = _amount1Out > _bin.reserve1
                        ? _bin.reserve1
                        : _amount1Out;

                    _bin.reserve1 -= _amount1OutOfBin;
                    _global.reserve1 -= _amount1OutOfBin;
                    _amount1Out -= _amount1OutOfBin;

                    uint256 _amount0inToBin = PRICE_PRECISION.mulDivRoundUp(
                        _amount1OutOfBin * BASIS_POINT_MAX,
                        _getPriceFromId(_global.currentId) * fee
                    );
                    _amount0in -= _amount0inToBin;
                    _bin.reserve0 += _amount0inToBin.safe112();
                    _global.reserve0 += _amount0inToBin.safe112();
                }
                _bin.l =
                    _getPriceFromId(_global.currentId).mulDivRoundUp(
                        _bin.reserve0,
                        PRICE_PRECISION
                    ) +
                    _bin.reserve1;
                // We do not need to check that _bin.l >= bins[_global.currentId].l
                // because this is ensured by the rounding up and the fee added

                bins[_global.currentId] = _bin;
            }

            if (_amount0Out != 0 || _amount1Out != 0) {
                _global.currentId = _findFirstBin(
                    _global.currentId,
                    _amount0Out == 0
                );
            }
        }
        global = _global;
        require(
            _amount0Out == 0 && _amount1Out == 0,
            "LBP: Broken safety check"
        ); // Safety check, but should never be false as it would have reverted on transfer
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
        require(
            _startPrice <= _endPrice && _startPrice != 0,
            "LBP: Wrong prices"
        );
        uint256 _startId = _getIdFromPrice(_startPrice);
        uint256 _endId = _getIdFromPrice(_endPrice);

        require(
            _len == _amounts1.length && _endId - _startId + 1 == _len,
            "LBP: Wrong lengths"
        );
        GlobalInfo memory _global = global;
        uint256 _maxAmount0 = token0.balanceOf(address(this)) -
            _global.reserve0;
        uint256 _maxAmount1 = token1.balanceOf(address(this)) -
            _global.reserve1;

        // seeding liquidity
        if (_global.currentId == 0) {
            _global.currentId =
                _startId +
                _binarySearchMiddle(0, _len - 1, _amounts0);
        }

        uint256 id = _startId;
        for (; id <= _endId; id++) {
            uint112 amount0 = _amounts0[id - _startId];
            uint112 amount1 = _amounts1[id - _startId];
            if (amount0 != 0 || amount1 != 0) {
                Bin storage bin = bins[id];

                uint112 _reserve0 = bin.reserve0;
                uint112 _reserve1 = bin.reserve1;

                if (_reserve0 == 0 && _reserve1 == 0) {
                    // add 1 at the right indices if the pair was empty
                    binEmpty[2][id / 256] |= 2**(id % 256);
                    binEmpty[1][id / 65_536] |= 2**((id / 256) % 256);
                    binEmpty[0][0] |= 2**(id / 65_536);
                }
                if (id < _global.currentId) {
                    require(
                        amount1 != 0 && amount0 == 0,
                        "LBP: Forbidden fill factor"
                    );
                    _maxAmount1 -= amount1; // revert if too much
                    _reserve1 += amount1;
                    bin.reserve1 = _reserve1;
                    _global.reserve1 += amount1;
                } else if (id > _global.currentId) {
                    require(
                        amount0 != 0 && amount1 == 0,
                        "LBP: Forbidden fill factor"
                    );
                    _maxAmount0 -= amount0; // revert if too much
                    _reserve0 += amount0;
                    bin.reserve0 = _reserve0;
                    _global.reserve0 += amount0;
                } else {
                    // @note for slippage adds, do this first and modulate the amounts
                    if (_reserve1 != 0) {
                        require(
                            (amount1 * bin.reserve0) / _reserve1 == amount0,
                            "LBP: Forbidden"
                        ); // @note question -> how add liquidity as price moves, hard to add to the exact f
                    } else {
                        require(
                            amount1 == 0 || bin.reserve0 == 0,
                            "LBP: Forbidden"
                        ); // @note question -> how add liquidity as price moves, hard to add to the exact f
                    }
                    _maxAmount0 -= amount0; // revert if too much
                    _maxAmount1 -= amount1; // revert if too much

                    _reserve0 += amount0;
                    _reserve1 += amount1;

                    bin.reserve0 = _reserve0;
                    bin.reserve1 = _reserve1;

                    _global.reserve0 += amount0;
                    _global.reserve1 += amount1;
                }
                uint256 _newL = _getPriceFromId(id).mulDivRoundUp(
                    _reserve0,
                    PRICE_PRECISION
                ) + _reserve1;
                uint256 _pastL = bin.l;
                bin.l = _newL;
                if (_pastL == 0) {
                    _newL -= 1000;
                    _mint(address(0), id, 1000); // lock the first 1000 liquidity to avoid rounding down precision
                } else {
                    _newL = (_newL - _pastL).mulDivRoundUp(
                        _totalSupplies[id],
                        _pastL
                    );
                }
                require(_newL != 0, "LPB: insufficient liquidity minted");
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
        uint112[] calldata _ids,
        uint256[] calldata _amounts,
        address _to
    ) external nonReentrant {
        uint256 _len = _ids.length;
        require(_len == _amounts.length, "LBP: Wrong lengths");

        GlobalInfo memory _global = global;

        uint256 _amounts0;
        uint256 _amounts1;

        for (uint256 i; i <= _len; i++) {
            uint256 _amount = _amounts[i];
            require(_amount != 0, "LBP: insufficient liquidity burned");

            uint256 _id = _ids[i];
            Bin storage bin = bins[_id];
            uint112 _reserve0 = bin.reserve0;
            uint112 _reserve1 = bin.reserve1;

            uint256 totalSupply = _totalSupplies[_id];

            /// Calculates the amounts
            uint112 _amount0 = ((_amount * _reserve0) / totalSupply).safe112();
            uint112 _amount1 = ((_amount * _reserve1) / totalSupply).safe112();

            if (_id <= _global.currentId) {
                _amounts1 += _amount1;
                bin.reserve1 = _reserve1 - _amount1;
            }
            if (_id >= _global.currentId) {
                _amounts0 += _amount0;
                bin.reserve0 = _reserve0 - _amount0;
            }

            if (_reserve0 == _amount0 && _reserve1 == _amount1) {
                // removes 1 at the right indices
                binEmpty[2][_id / 256] -= 2**(_id % 256);
                if (binEmpty[2][_id / 256] == 0) {
                    binEmpty[1][_id / 65_536] -= 2**((_id / 256) % 256);
                    if (binEmpty[1][_id / 65_536] == 0) {
                        binEmpty[0][0] -= 2**(_id / 65_536);
                    }
                }
            }

            _global.reserve0 -= _amount0;
            _global.reserve1 -= _amount1;

            bin.l -= _amount;
            _burn(address(this), _id, _amount);
        }
        if (_global.reserve0 == 0 && _global.reserve1 == 0) {
            _global.currentId = 0; // back to seeding liquidity
        }
        global = _global;
        token0.safeTransfer(_to, _amounts0);
        token1.safeTransfer(_to, _amounts1);
    }

    /// @notice View function to get the bin at price `price`
    /// @param price The exchange price of y per x (multiplied by 1e36)
    /// @return The bin corresponding to the inputted price
    function getBin(uint256 price) external view returns (Bin memory) {
        return bins[_getIdFromPrice(price)];
    }

    /// @notice Returns the first id that is non zero, corresponding to a bin with
    /// liquidity in it
    /// @param _binId the binId to start searching
    /// @param _isSearchingRight The boolean value to decide if the algorithm will look
    /// for the closest non zero bit on the right or the left
    /// @return The closest non zero bit on the right side
    function findFirstBin(uint256 _binId, bool _isSearchingRight)
        external
        view
        returns (uint256)
    {
        return _findFirstBin(_binId, _isSearchingRight);
    }

    /// @notice Returns the id corresponding to the inputted price
    /// @param _price The price of y per x (multiplied by 1e36)
    /// @return The id corresponding to this price
    function getIdFromPrice(uint256 _price) external pure returns (uint256) {
        return _getIdFromPrice(_price);
    }

    /// @notice Returns the price corresponding to the inputted id
    /// @param _id The id
    /// @return The price corresponding to this id
    function getPriceFromId(uint256 _id) external pure returns (uint256) {
        return _getPriceFromId(_id);
    }

    /** Private functions **/

    /// @notice Returns the id corresponding to the inputted price
    /// @param _price The price of y per x (multiplied by 1e36)
    /// @return The id corresponding to this price
    function _getIdFromPrice(uint256 _price) private pure returns (uint256) {
        if (_price <= 10 * BIN_PRECISION) {
            return _price;
        }
        uint256 alpha = _price.getDecimals() - BIN_PRECISION_DECIMALS;
        return _price / 10**alpha + 9 * BIN_PRECISION * alpha;
    }

    /// @notice Returns the price corresponding to the inputted id
    /// @param _id The id
    /// @return The price corresponding to this id
    function _getPriceFromId(uint256 _id) private pure returns (uint256) {
        if (_id <= 10 * BIN_PRECISION) {
            return _id;
        }
        uint256 alpha = (_id - BIN_PRECISION) / (9 * BIN_PRECISION);
        return (_id - 9 * BIN_PRECISION * alpha) * 10**alpha; // cant simplify as rounding down is necessary
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
        uint256 current;
        uint256 nextBit;
        bool found;

        uint256 bit = _binId % 256;
        _binId /= 256;
        if (_isSearchingRight) {
            // Search in depth 2
            if (bit != 0) {
                current = binEmpty[2][_binId];
                (nextBit, found) = current.closestBitRight(bit - 1);
                if (found) {
                    return _binId * 256 + nextBit;
                }
            }

            uint256 binIdDepth1 = _binId / 256;
            uint256 nextBinId;

            require(binIdDepth1 != 0, "LBP: Error depth search");

            // Search in depth 1
            if (_binId % 256 != 0) {
                current = binEmpty[1][binIdDepth1];
                (nextBinId, found) = current.closestBitRight(
                    (_binId % 256) - 1
                );
                if (found) {
                    nextBinId = 256 * binIdDepth1 + nextBinId;
                    current = binEmpty[2][nextBinId];
                    nextBit = current.mostSignificantBit();
                    return nextBinId * 256 + nextBit;
                }
            }

            // Search in depth 0
            current = binEmpty[0][0];
            (nextBinId, found) = current.closestBitRight(binIdDepth1 - 1);
            require(found, "LBP: Error depth search");
            current = binEmpty[1][nextBinId];
            nextBinId = 256 * nextBinId + current.mostSignificantBit();
            current = binEmpty[2][nextBinId];
            nextBit = current.mostSignificantBit();
            return nextBinId * 256 + nextBit;
        } else {
            // Search in depth 2
            if (bit < 255) {
                current = binEmpty[2][_binId];
                (nextBit, found) = current.closestBitLeft(bit + 1);
                if (found) {
                    return _binId * 256 + nextBit;
                }
            }

            uint256 binIdDepth1 = _binId / 256;
            uint256 nextBinId;

            require(binIdDepth1 != 255, "LBP: Error depth search");

            // Search in depth 1
            if (_binId % 256 != 255) {
                current = binEmpty[1][binIdDepth1];
                (nextBinId, found) = current.closestBitLeft((_binId % 256) + 1);
                if (found) {
                    nextBinId = 256 * binIdDepth1 + nextBinId;
                    current = binEmpty[2][nextBinId];
                    nextBit = current.leastSignificantBit();
                    return nextBinId * 256 + nextBit;
                }
            }

            // Search in depth 0
            current = binEmpty[0][0];
            (nextBinId, found) = current.closestBitLeft(binIdDepth1 + 1);
            require(found, "LBP: Error depth search");
            current = binEmpty[1][nextBinId];
            nextBinId = 256 * nextBinId + current.leastSignificantBit();
            current = binEmpty[2][nextBinId];
            nextBit = current.leastSignificantBit();
            return nextBinId * 256 + nextBit;
        }
    }

    /// @notice Returns the first index of the array that is non zero, The
    /// array need to be ordered so that zeros and non zeros aren't together
    /// (no cross over), e.g. [0,1,2,1], [1,1,1,0,0], [0,0,0], [1,2,1]
    /// @param _start The index where the search will start
    /// @param _end The index where the search will end
    /// @param _array The uint112 array
    /// @return The first index of the array that is non zero
    function _binarySearchMiddle(
        uint256 _start,
        uint256 _end,
        uint112[] memory _array
    ) private pure returns (uint256) {
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
