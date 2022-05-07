// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./JLBPToken.sol";
import "./libraries/Math.sol";

import "hardhat/console.sol";

/// @title Liquidity Bin Exchange
/// @author Trader Joe
/// @notice DexV2 POC
contract LiquidityBinExchange is JLBPToken, ReentrancyGuard {
    using Math for uint256;

    // @note linked list ? previous bin - next bin etc..., not sure there is a good way to make it work
    struct Bin {
        /// l = p * reserve0 + reserve1
        uint256 l;
        uint112 reserve0; // x
        uint112 reserve1; // y
    }

    struct GlobalInfo {
        /// Total reserve of token0 inside the bins
        uint128 reserve0; // sum of all bins' reserve0
        /// Total reserve of token1 inside the bins
        uint128 reserve1; // sum of all bins' reserve1
        /// The current id
        uint256 currentId;
        /// The last bin id
        uint256 lastId; // @note useless ?
        /// The first bin id
        uint256 firstId; // @note useless ?
    }

    IERC20Metadata public token0;
    IERC20Metadata public token1;

    uint256 public fee;
    uint256 private constant BIN_PRECISION_DECIMALS = 3;
    uint256 public constant BIN_PRECISION = 10**BIN_PRECISION_DECIMALS; // @note there will be (9 * BIN_PRECISION) number of bins with the same binStep
    // @note thus, the total number of bin will be lower than 65 * 90_000 + 100_000 = 5_950_000
    uint256 public constant PRICE_PRECISION = 1e36;
    uint256 public constant BASE_POINT_MAX = 10_000;

    GlobalInfo public global;

    // uint256 private immutable fee_helper;

    mapping(uint256 => Bin) private bins;
    mapping(uint256 => uint256)[3] private binEmpty;

    constructor(
        IERC20Metadata _token0,
        IERC20Metadata _token1,
        uint256 _fee
    ) {
        token0 = _token0;
        token1 = _token1;

        fee = BASE_POINT_MAX - _fee;
        global.firstId = ~uint256(0);
        // uint256 _fee_helper;
        // if (BASE_POINT_MAX + (_fee % BASE_POINT_MAX) == 0) {
        //     _fee_helper = (BASE_POINT_MAX * BASE_POINT_MAX) / (BASE_POINT_MAX + _fee);
        // } else {
        //     _fee_helper = (BASE_POINT_MAX * BASE_POINT_MAX) / (BASE_POINT_MAX + _fee) + 1;
        // }
        // fee_helper = _fee_helper; // @note do we do this ? (if not, if fee is 50%, people will have to pay for 2 times more in fact, not 1.5 as expected)
    }

    function swap(
        uint112 _amount0Out,
        uint112 _amount1Out,
        address _to,
        bytes calldata _data
    ) external nonReentrant {
        // @note change to `uint amount0Out, uint amount1Out, address to, bytes calldata data` for compatibility
        GlobalInfo memory _global = global;
        uint256 _amount0in = token0.balanceOf(address(this)) - _global.reserve0;
        uint256 _amount1In = token1.balanceOf(address(this)) - _global.reserve1;
        require(
            _amount0in != 0 || _amount1In != 0,
            "LBE: Insufficient amounts"
        );

        if (_amount0Out != 0) {
            token0.transfer(_to, _amount0Out); // sends tokens
            if (_amount0in != 0) {
                // if some token0 are stuck, we take them in account here
                if ((_amount0in * fee) / BASE_POINT_MAX < _amount0Out) {
                    _amount0Out -= ((_amount0in * fee) / BASE_POINT_MAX)
                        .safe112();
                } else {
                    _amount0Out = 0;
                }
            }
        }
        if (_amount1Out != 0) {
            token1.transfer(_to, _amount1Out);
            if (_amount1In != 0) {
                // if some token1 are stuck, we take them in account here
                if ((_amount1In * fee) / BASE_POINT_MAX < _amount1Out) {
                    _amount1Out -= ((_amount1In * fee) / BASE_POINT_MAX)
                        .safe112();
                } else {
                    _amount1Out = 0;
                }
            }
        }
        require(_amount0Out == 0 || _amount1Out == 0, "LBE: Wrong amounts"); // If this is wrong, then we're sure the amounts sent are wrong

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
                            _amount0OutOfBin * BASE_POINT_MAX,
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
                        _amount1OutOfBin * BASE_POINT_MAX,
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
                    _bin.reserve1; // doesn't need to check that _bin.l >= previousL because this is ensured by the if statements.
                assert(_bin.l >= bins[_global.currentId].l);

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
            "LBE: Broken safety check"
        ); // @note safety check, but should never be false (would revert on transfer)
    }

    function addLiquidity(
        uint256 _startPrice,
        uint256 _endPrice, // endPrice is included
        uint112[] calldata _amounts0, // [1 2 5 20 0 0 0]
        uint112[] calldata _amounts1 //  [0 0 0 20 5 2 1]
    ) external nonReentrant {
        uint256 _len = _amounts0.length;
        require(
            _startPrice <= _endPrice && _startPrice != 0,
            "LBE: Wrong prices"
        );
        uint256 _startId = _getIdFromPrice(_startPrice);
        uint256 _endId = _getIdFromPrice(_endPrice);

        require(
            _len == _amounts1.length && _endId - _startId + 1 == _len,
            "LBE: Wrong lengths"
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
                if (_global.lastId < id) {
                    _global.lastId = id;
                }
                if (_global.firstId > id) {
                    _global.firstId = id;
                }
                Bin storage bin = bins[id];

                uint112 _reserve0 = bin.reserve0;
                uint112 _reserve1 = bin.reserve1;

                if (_reserve0 == 0 && _reserve1 == 0) {
                    binEmpty[2][id / 256] |= 2**(id % 256); // add 1 at the right index
                    binEmpty[1][id / 65_536] |= 2**((id / 256) % 256); // add 1 at the right index
                    binEmpty[0][0] |= 2**(id / 65_536); // add 1 at the right index
                }
                if (id < _global.currentId) {
                    require(
                        amount1 != 0 && amount0 == 0,
                        "LBE: Forbidden fill factor"
                    );
                    _maxAmount1 -= amount1; // revert if too much
                    bin.reserve1 = _reserve1 + amount1;
                    _global.reserve1 += amount1;
                } else if (id > _global.currentId) {
                    require(
                        amount0 != 0 && amount1 == 0,
                        "LBE: Forbidden fill factor"
                    );
                    _maxAmount0 -= amount0; // revert if too much
                    bin.reserve0 = _reserve0 + amount0;
                    _global.reserve0 += amount0;
                } else {
                    // @note for slippage adds, do this first and modulate the amounts
                    if (_reserve1 != 0) {
                        require(
                            (amount1 * bin.reserve0) / _reserve1 == amount0,
                            "LBE: Forbidden"
                        ); // @note question -> how add liquidity as price moves, hard to add to the exact f
                    } else {
                        require(
                            amount1 == 0 || bin.reserve0 == 0,
                            "LBE: Forbidden"
                        ); // @note question -> how add liquidity as price moves, hard to add to the exact f
                    }
                    _maxAmount0 -= amount0; // revert if too much
                    _maxAmount1 -= amount1; // revert if too much

                    bin.reserve0 = _reserve0 + amount0;
                    bin.reserve1 = _reserve1 + amount1;

                    _global.reserve0 += amount0;
                    _global.reserve1 += amount1;
                }
                uint256 deltaL = _getPriceFromId(id).mulDivRoundUp(
                    amount0,
                    PRICE_PRECISION
                ) + amount1;
                bin.l += deltaL;
                _mint(msg.sender, id, deltaL);
            }
        }
        global = _global;
    }

    function removeLiquidity(uint112[] calldata ids, uint256[] calldata amounts)
        external
        nonReentrant
    {
        uint256 _len = ids.length;
        require(_len == amounts.length, "LBE: Wrong lengths");

        GlobalInfo memory _global = global;

        uint256 _amounts0;
        uint256 _amounts1;

        for (uint256 i; i <= _len; i++) {
            uint256 _amount = amounts[i];
            require(_amount != 0, "LBE: amounts too low");

            uint256 _id = ids[i];
            Bin storage bin = bins[_id];
            uint112 _reserve0 = bin.reserve0;
            uint112 _reserve1 = bin.reserve1;

            uint256 totalSupply = _totalSupply[_id];
            _burn(msg.sender, _id, _amount);

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
            bin.l =
                _getPriceFromId(_id).mulDivRoundUp(_reserve0, PRICE_PRECISION) +
                _reserve1;

            if (_reserve0 == _amount0 && _reserve1 == _amount1) {
                binEmpty[2][_id / 256] -= 2**(_id % 256); // remove 1 at the right index
                if (binEmpty[2][_id / 256] == 0) {
                    binEmpty[1][_id / 65_536] -= 2**((_id / 256) % 256); // remove 1 at the right index
                    if (binEmpty[1][_id / 65_536] == 0) {
                        binEmpty[0][0] -= 2**(_id / 65_536); // remove 1 at the right index
                    }
                }
            }

            _global.reserve0 -= _amount0;
            _global.reserve1 -= _amount1;
        }
        if (_global.reserve0 == 0 && _global.reserve1 == 0) {
            _global.currentId = 0; // back to seeding liquidity
        }
        global = _global;
    }

    function getBin(uint256 price) external view returns (Bin memory) {
        return bins[_getIdFromPrice(price)];
    }

    function findFirstBin(uint256 binId, bool isSearchRight)
        external
        view
        returns (uint256)
    {
        return _findFirstBin(binId, isSearchRight);
    }

    function getIdFromPrice(uint256 price) external pure returns (uint256) {
        return _getIdFromPrice(price);
    }

    function getPriceFromId(uint256 id) external pure returns (uint256) {
        return _getPriceFromId(id);
    }

    /** Private functions **/

    function _getIdFromPrice(uint256 price) private pure returns (uint256) {
        if (price <= 10 * BIN_PRECISION) {
            return price;
        }
        uint256 alpha = price.getDecimals() - BIN_PRECISION_DECIMALS;
        return price / 10**alpha + 9 * BIN_PRECISION * alpha;
    }

    function _getPriceFromId(uint256 id) private pure returns (uint256) {
        if (id <= 10 * BIN_PRECISION) {
            return id;
        }
        uint256 alpha = (id - BIN_PRECISION) / (9 * BIN_PRECISION);
        return (id - 9 * BIN_PRECISION * alpha) * 10**alpha; // cant simplify as rounding down is necessary
    }

    function _findFirstBin(uint256 binId, bool isSearchingRight)
        private
        view
        returns (uint256)
    {
        uint256 current;
        uint256 nextBit;
        bool found;

        uint256 bit = binId % 256;
        binId /= 256;
        if (isSearchingRight) {
            // Search in depth 2
            if (bit != 0) {
                current = binEmpty[2][binId];
                (nextBit, found) = current.closestBitRight(bit - 1);
                if (found) {
                    return binId * 256 + nextBit;
                }
            }

            uint256 binIdDepth1 = binId / 256;
            uint256 nextBinId;

            require(binIdDepth1 != 0, "LBE: Error depth search");

            // Search in depth 1
            if (binId % 256 != 0) {
                current = binEmpty[1][binIdDepth1];
                (nextBinId, found) = current.closestBitRight((binId % 256) - 1);
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
            require(found, "LBE: Error depth search");
            current = binEmpty[1][nextBinId];
            nextBinId = 256 * nextBinId + current.mostSignificantBit();
            current = binEmpty[2][nextBinId];
            nextBit = current.mostSignificantBit();
            return nextBinId * 256 + nextBit;
        } else {
            // Search in depth 2
            if (bit < 255) {
                current = binEmpty[2][binId];
                (nextBit, found) = current.closestBitLeft(bit + 1);
                if (found) {
                    return binId * 256 + nextBit;
                }
            }

            uint256 binIdDepth1 = binId / 256;
            uint256 nextBinId;

            require(binIdDepth1 != 255, "LBE: Error depth search");

            // Search in depth 1
            if (binId % 256 != 255) {
                current = binEmpty[1][binIdDepth1];
                (nextBinId, found) = current.closestBitLeft((binId % 256) + 1);
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
            require(found, "LBE: Error depth search");
            current = binEmpty[1][nextBinId];
            nextBinId = 256 * nextBinId + current.leastSignificantBit();
            current = binEmpty[2][nextBinId];
            nextBit = current.leastSignificantBit();
            return nextBinId * 256 + nextBit;
        }
    }

    function _binarySearchMiddle(
        uint256 start,
        uint256 end,
        uint112[] memory array
    ) private pure returns (uint256) {
        uint256 middle;
        if (array[end] == 0) {
            return end;
        }
        while (end > start) {
            middle = (start + end) / 2;
            if (array[middle] == 0) {
                start = middle + 1;
            } else {
                end = middle;
            }
        }
        if (array[middle] == 0) {
            return middle + 1;
        }
        return middle;
    }
}
