// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "prb-math/contracts/PRBMath.sol";

import "hardhat/console.sol";

contract LiquidityBinExchange is ReentrancyGuard {
    using PRBMath for uint256;

    // @note linked list ? previous bin - next bin etc..., not sure there is a good way to make it work
    struct Bin {
        /// l = p * reserve0 + reserve1
        uint256 l;
        uint112 reserve0;
        uint112 reserve1;
    }

    struct GlobalInfo {
        /// Total reserve of token0 inside the bins
        uint128 reserve0;
        /// Total reserve of token1 inside the bins
        uint128 reserve1;
        /// The current id or price (y / x)
        uint256 currentId;
        /// The last bin id
        uint256 lastId;
        /// The first bin id
        uint256 firstId;
    }

    IERC20Metadata public immutable token0;
    IERC20Metadata public immutable token1;
    uint256 public immutable fee;
    uint256 private constant BIN_PRECISION_DECIMALS = 4;
    uint256 public constant BIN_PRECISION = 10**BIN_PRECISION_DECIMALS; // @note there will be (9 * BIN_PRECISION) number of bins with the same binStep
    // @note thus, the total number of bin will be lower than 65 * 90_000 + 100_000 = 5_950_000
    uint256 public constant PRICE_PRECISION = 1e36;
    uint256 public constant BP_PRECISION = 10_000;

    GlobalInfo public global;

    // uint256 private immutable fee_helper;

    mapping(uint256 => Bin) private bins;
    mapping(uint256 => uint256) private ids;

    mapping(uint256 => uint256)[3] private binEmpty;

    constructor(
        IERC20Metadata _token0,
        IERC20Metadata _token1,
        uint256 _fee,
        uint256 _price
    ) {
        token0 = _token0;
        token1 = _token1;

        fee = BP_PRECISION - _fee;
        uint256 price = _getBinPrice(_price);
        global.currentId = price;
        global.firstId = price;
        global.lastId = price;
        // uint256 _fee_helper;
        // if (BP_PRECISION + (_fee % BP_PRECISION) == 0) {
        //     _fee_helper = (BP_PRECISION * BP_PRECISION) / (BP_PRECISION + _fee);
        // } else {
        //     _fee_helper = (BP_PRECISION * BP_PRECISION) / (BP_PRECISION + _fee) + 1;
        // }
        // fee_helper = _fee_helper; // @note do we do this ? (if not, if fee is 50%, people will have to pay for 2 times more in fact, not 1.5 as expected)
    }

    function swap(
        uint112 _amount0Out,
        uint112 _amount1Out,
        address to,
        bytes calldata data
    ) external nonReentrant {
        // @note change to `uint amount0Out, uint amount1Out, address to, bytes calldata data` for compatibility
        GlobalInfo memory _global = global;
        uint256 sent0 = token0.balanceOf(address(this)) - _global.reserve0;
        uint256 sent1 = token1.balanceOf(address(this)) - _global.reserve1;
        require(sent0 != 0 || sent1 != 0, "LBE: Insufficient amounts");
        if (_amount0Out != 0) {
            token0.transfer(to, _amount0Out); // sends tokens
            if (sent0 != 0) {
                // if some token0 are stuck, we take them in account here
                if ((sent0 * fee) / BP_PRECISION < _amount0Out) {
                    _amount0Out =
                        _amount0Out -
                        _safe112((sent0 * fee) / BP_PRECISION);
                } else {
                    _amount0Out = 0;
                }
            }
        }
        if (_amount1Out != 0) {
            token1.transfer(to, _amount1Out);
            if (sent1 != 0) {
                // if some token1 are stuck, we take them in account here
                if ((sent1 * fee) / BP_PRECISION < _amount0Out) {
                    _amount1Out =
                        _amount1Out -
                        _safe112((sent1 * fee) / BP_PRECISION);
                } else {
                    _amount1Out = 0;
                }
            }
        }
        require(_amount0Out == 0 || _amount1Out == 0, "LBE: Wrong amounts"); // If this is wrong, then we're sure the amounts sent are wrong

        while (
            _global.firstId <= _global.currentId &&
            _global.currentId <= _global.lastId // to make sure this loop stops
        ) {
            Bin memory _bin = bins[_global.currentId];
            if (_bin.reserve0 != 0 || _bin.reserve1 != 0) {
                if (_amount0Out != 0) {
                    if (_amount0Out <= _bin.reserve0) {
                        // the bin can cover the swap
                        _bin.reserve0 -= _amount0Out;
                        _global.reserve0 -= _amount0Out;
                        uint256 sent1ToBin = _getPriceFromId(_global.currentId)
                            .mulDiv(
                                _amount0Out * BP_PRECISION,
                                PRICE_PRECISION * fee
                            );
                        sent1 -= sent1ToBin;
                        _bin.reserve1 += _safe112(sent1ToBin);
                        _global.reserve1 += _safe112(sent1ToBin);

                        _amount0Out = 0;
                    } else {
                        // the swap will empty current bin
                        uint256 sent1ToBin = _getPriceFromId(_global.currentId)
                            .mulDiv(
                                _bin.reserve0 * BP_PRECISION,
                                PRICE_PRECISION * fee
                            );
                        sent1 -= sent1ToBin;
                        _bin.reserve1 += _safe112(sent1ToBin);
                        _global.reserve1 += _safe112(sent1ToBin);

                        _amount0Out -= _bin.reserve0;
                        _global.reserve0 -= _bin.reserve0;
                        _bin.reserve0 = 0;
                    }
                }
                if (_amount1Out != 0) {
                    if (_amount1Out <= _bin.reserve1) {
                        // the bin can cover the swap
                        _bin.reserve1 -= _amount1Out;
                        _global.reserve1 -= _amount1Out;
                        uint256 sent0ToBin = PRICE_PRECISION.mulDiv(
                            _amount1Out * BP_PRECISION,
                            _getPriceFromId(_global.currentId) * fee
                        );
                        sent0 -= sent0ToBin;
                        _bin.reserve0 += _safe112(sent0ToBin);
                        _global.reserve0 += _safe112(sent0ToBin);

                        _amount1Out = 0;
                    } else {
                        // the swap will empty current bin
                        uint256 sent0ToBin = _safe112(
                            PRICE_PRECISION.mulDiv(
                                _bin.reserve1 * BP_PRECISION,
                                _getPriceFromId(_global.currentId) * fee
                            )
                        );
                        sent0 -= sent0ToBin;
                        _bin.reserve0 += _safe112(sent0ToBin);
                        _global.reserve0 += _safe112(sent0ToBin);

                        _amount1Out -= _bin.reserve1;
                        _global.reserve1 -= _bin.reserve1;
                        _bin.reserve1 = 0;
                    }
                }
                uint256 l = _getPriceFromId(_global.currentId).mulDiv(
                    _bin.reserve0,
                    PRICE_PRECISION
                ) + _bin.reserve1;
                require(_bin.l <= l, "LBE: Constant liquidity not respected"); // not sure this is even needed as this checks is forced thanks to the fees added
                _bin.l = l;

                bins[_global.currentId] = _bin;
            }

            if (_amount0Out == 0 && _amount1Out == 0) {
                break;
            } else {
                _global.currentId = _findFirstBin(
                    _global.currentId,
                    _amount0Out != 0
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
        uint112[] calldata _amounts0,
        uint112[] calldata _amounts1
    ) external nonReentrant {
        uint256 _len = _amounts0.length;
        require(_len == _amounts1.length, "LBE: Wrong lengths");
        require(
            _startPrice <= _endPrice && _startPrice != 0,
            "LBE: Wrong prices"
        );
        GlobalInfo memory _global = global;
        uint256 _maxAmount0 = token0.balanceOf(address(this)) -
            _global.reserve0;
        uint256 _maxAmount1 = token1.balanceOf(address(this)) -
            _global.reserve1;

        uint256 _startId = _getIdFromPrice(_startPrice);
        uint256 _endId = _getIdFromPrice(_endPrice);
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
                ids[id / 256] |= 2**(id % 256); // add 1 at the right index
                if (id < _global.currentId) {
                    require(amount0 != 0 && amount1 == 0, "LBE: Forbidden");
                    _maxAmount0 -= amount0; // revert if too much
                    bin.reserve0 += amount0;
                    _global.reserve0 += amount0;
                } else if (id > _global.currentId) {
                    require(amount1 != 0 && amount0 == 0, "LBE: Forbidden");
                    _maxAmount1 -= amount1; // revert if too much
                    bin.reserve1 += amount1;
                    _global.reserve1 += amount1;
                } else {
                    // @note for slippage adds, do this first and modulate the amounts
                    uint112 _reserve1 = bin.reserve1;
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

                    bin.reserve0 += amount0;
                    bin.reserve1 += amount1;

                    _global.reserve0 += amount0;
                    _global.reserve1 += amount1;
                }
                bin.l +=
                    (_getPriceFromId(id) * amount0) /
                    PRICE_PRECISION +
                    amount1;
            }
        }
        global = _global;
    }

    function getBin(uint256 price) external view returns (Bin memory) {
        return bins[_getIdFromPrice(price)];
    }

    function getBinStep(uint256 price) external pure returns (uint256) {
        return _getBinStep(price);
    }

    function getBinPrice(uint256 price) external pure returns (uint256) {
        return _getBinPrice(price);
    }

    function getDecimals(uint256 x) external pure returns (uint256) {
        return _getDecimals(x);
    }

    function findFirstBin(uint256 binId, bool isRight)
        external
        view
        returns (uint256)
    {
        return _findFirstBin(binId, isRight);
    }

    function getIdFromPrice(uint256 price) external pure returns (uint256) {
        return _getIdFromPrice(price);
    }

    function getPriceFromId(uint256 id) external pure returns (uint256) {
        return _getPriceFromId(id);
    }

    function _getIdFromPrice(uint256 price) private pure returns (uint256) {
        if (price <= 10 * BIN_PRECISION) {
            return price;
        }
        uint256 alpha = _getDecimals(price) - BIN_PRECISION_DECIMALS;
        return price / 10**alpha + 9 * BIN_PRECISION * alpha;
    }

    function _getPriceFromId(uint256 id) private pure returns (uint256) {
        if (id <= 10 * BIN_PRECISION) {
            return id;
        }
        uint256 alpha = (id - BIN_PRECISION) / (9 * BIN_PRECISION);
        return (id - 9 * BIN_PRECISION * alpha) * 10**alpha; // cant simplify as rounding down is necessary
    }

    function _getBinPrice(uint256 price) private pure returns (uint256) {
        /// 1e36 / 2**112 = 192.59..
        require(price >= 192, "LBE: Price too low");
        /// 2 ** 112 * 1e36 = 5192296858534827628530496329220096000000000000000000000000000000000000
        require(
            price <
                5192296858534827628530496329220096000000000000000000000000000000000000,
            "LBE: Price too high"
        );
        if (price < BIN_PRECISION) {
            return price;
        }
        uint256 binStep = _getBinStep(price);
        return (price / binStep) * binStep;
    }

    function _getBinStep(uint256 price) private pure returns (uint256) {
        uint256 decimals = _getDecimals(price);
        return 10**decimals / BIN_PRECISION;
    } // 1.00000000 -> [1.0001 - 1.0002[

    function _getDecimals(uint256 x) private pure returns (uint256 decimals) {
        unchecked {
            if (x >= 1e38) {
                x /= 1e38;
                decimals += 38;
            }

            if (x >= 1e19) {
                x /= 1e19;
                decimals += 19;
            }

            if (x >= 1e10) {
                x /= 1e10;
                decimals += 10;
            }

            if (x >= 1e5) {
                x /= 1e5;
                decimals += 5;
            }

            if (x >= 1e3) {
                x /= 1e3;
                decimals += 3;
            }

            if (x >= 1e2) {
                x /= 1e2;
                decimals += 2;
            }

            if (x >= 1e1) {
                decimals += 1;
            }
        }
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
            if (bit < 255) {
                current = binEmpty[2][binId];
                (nextBit, found) = _closestBitLeft(current, bit + 1);
                if (found) {
                    return binId * 256 + nextBit;
                }
            }

            uint256 binIdDepth1 = binId / 256;
            uint256 nextBinId;

            require(binIdDepth1 != 255, "LBE: Error depth search");

            if (binId % 256 != 255) {
                current = binEmpty[1][binIdDepth1];
                (nextBinId, found) = _closestBitLeft(
                    current,
                    (binId % 256) + 1
                );
                if (found) {
                    nextBinId = 256 * binIdDepth1 + nextBinId;
                    current = binEmpty[2][nextBinId];
                    nextBit = _leastSignificantBit(current);
                    return nextBinId * 256 + nextBit;
                }
            }

            current = binEmpty[0][0];
            (nextBinId, found) = _closestBitLeft(current, binIdDepth1 + 1);
            require(found, "LBE: Error depth search");
            current = binEmpty[1][nextBinId];
            nextBinId = 256 * nextBinId + _leastSignificantBit(current);
            current = binEmpty[2][nextBinId];
            nextBit = _leastSignificantBit(current);
            return nextBinId * 256 + nextBit;
        } else {
            // Search in depth 2
            if (bit != 0) {
                current = binEmpty[2][binId];
                (nextBit, found) = _closestBitRight(current, bit - 1);
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
                (nextBinId, found) = _closestBitRight(
                    current,
                    (binId % 256) - 1
                );
                if (found) {
                    nextBinId = 256 * binIdDepth1 + nextBinId;
                    current = binEmpty[2][nextBinId];
                    nextBit = _mostSignificantBit(current);
                    return nextBinId * 256 + nextBit;
                }
            }

            // Search in depth 0
            current = binEmpty[0][0];
            (nextBinId, found) = _closestBitRight(current, binIdDepth1 - 1);
            require(found, "LBE: Error depth search");
            current = binEmpty[1][nextBinId];
            nextBinId = 256 * nextBinId + _mostSignificantBit(current);
            current = binEmpty[2][nextBinId];
            nextBit = _mostSignificantBit(current);
            return nextBinId * 256 + nextBit;
        }
    }

    function _closestBitRight(uint256 x, uint256 bit)
        public
        pure
        returns (uint256 id, bool found)
    {
        unchecked {
            x <<= 255 - bit;

            if (x == 0) {
                return (0, false);
            }

            return (_mostSignificantBit(x) - (255 - bit), true);
        }
    }

    function _closestBitLeft(uint256 x, uint256 bit)
        public
        pure
        returns (uint256 id, bool found)
    {
        unchecked {
            x >>= bit;

            if (x == 0) {
                return (0, false);
            }

            return (_leastSignificantBit(x) + bit, true);
        }
    }

    function _mostSignificantBit(uint256 x)
        internal
        pure
        returns (uint256 msb)
    {
        unchecked {
            if (x >= 1 << 128) {
                x >>= 128;
                msb += 128;
            }
            if (x >= 1 << 64) {
                x >>= 64;
                msb += 64;
            }
            if (x >= 1 << 32) {
                x >>= 32;
                msb += 32;
            }
            if (x >= 1 << 16) {
                x >>= 16;
                msb += 16;
            }
            if (x >= 1 << 8) {
                x >>= 8;
                msb += 8;
            }
            if (x >= 1 << 4) {
                x >>= 4;
                msb += 4;
            }
            if (x >= 1 << 2) {
                x >>= 2;
                msb += 2;
            }
            if (x >= 1 << 1) {
                msb += 1;
            }
        }
    }

    function _leastSignificantBit(uint256 x)
        internal
        pure
        returns (uint256 lsb)
    {
        unchecked {
            if (x << 128 != 0) {
                x <<= 128;
                lsb += 128;
            }
            if (x << 64 != 0) {
                x <<= 64;
                lsb += 64;
            }
            if (x << 32 != 0) {
                x <<= 32;
                lsb += 32;
            }
            if (x << 16 != 0) {
                x <<= 16;
                lsb += 16;
            }
            if (x << 8 != 0) {
                x <<= 8;
                lsb += 8;
            }
            if (x << 4 != 0) {
                x <<= 4;
                lsb += 4;
            }
            if (x << 2 != 0) {
                x <<= 2;
                lsb += 2;
            }
            if (x << 1 != 0) {
                lsb += 1;
            }

            return 255 - lsb;
        }
    }

    function _safe112(uint256 x) private pure returns (uint112) {
        require(x < 2**112, "LBE: Exceeds 112 bits");
        return uint112(x);
    }

    function _safe128(uint256 x) private pure returns (uint128) {
        require(x < 2**128, "LBE: Exceeds 128 bits");
        return uint128(x);
    }

    function _max(uint256 x, uint256 y) private pure returns (uint256) {
        return x > y ? x : y;
    }
}
