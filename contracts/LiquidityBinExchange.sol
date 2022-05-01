// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "prb-math/contracts/PRBMath.sol";

import "hardhat/console.sol";

contract LiquidityBinExchange {
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
        uint256 currentPrice;
        /// The last bin id
        uint256 lastPrice;
        /// The first bin id
        uint256 firstPrice;
    }

    IERC20Metadata public immutable token0;
    IERC20Metadata public immutable token1;
    uint256 public immutable fee;
    uint256 private constant BIN_PRECISION_DECIMALS = 4; // @note there will be (9 * BIN_PRECISION) number of elt with the same binStep
    uint256 public constant BIN_PRECISION = 10**BIN_PRECISION_DECIMALS; // @note there will be (9 * BIN_PRECISION) number of elt with the same binStep
    // @note thus, the total number of bin will be lower than 65 * 90_000 + 100_000 = 5_950_000
    uint256 public constant PRICE_PRECISION = 1e36;
    uint256 public constant BP_PRECISION = 10_000;

    GlobalInfo public global;

    // uint256 private immutable fee_helper;

    mapping(uint256 => Bin) private bins;

    mapping(uint256 => uint256) private binEmpty;

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
        global.currentPrice = price;
        global.firstPrice = price;
        global.lastPrice = price;
        // uint256 _fee_helper;
        // if (BP_PRECISION + (_fee % BP_PRECISION) == 0) {
        //     _fee_helper = (BP_PRECISION * BP_PRECISION) / (BP_PRECISION + _fee);
        // } else {
        //     _fee_helper = (BP_PRECISION * BP_PRECISION) / (BP_PRECISION + _fee) + 1;
        // }
        // fee_helper = _fee_helper; // @note do we do this ? (if not, if fee is 50%, people will have to pay for 2 times more in fact, not 1.5 as expected)
    }

    function swap(uint112 _amount0, uint112 _amount1) external {
        // @note change to `uint amount0Out, uint amount1Out, address to, bytes calldata data` for compatibility
        GlobalInfo memory _global = global;
        uint256 sent0 = token0.balanceOf(address(this)) - _global.reserve0;
        uint256 sent1 = token1.balanceOf(address(this)) - _global.reserve1;
        require(sent0 != 0 || sent1 != 0, "LBE: Insufficient amounts");
        if (_amount0 != 0) {
            token0.transfer(msg.sender, _amount0); // sends tokens
            if (sent0 != 0) {
                // if some token0 are stuck, we take them in account here
                if ((sent0 * fee) / BP_PRECISION < _amount0) {
                    _amount0 =
                        _amount0 -
                        _safe112((sent0 * fee) / BP_PRECISION);
                } else {
                    _amount0 = 0;
                }
            }
        }
        if (_amount1 != 0) {
            token1.transfer(msg.sender, _amount1);
            if (sent1 != 0) {
                // if some token1 are stuck, we take them in account here
                if ((sent1 * fee) / BP_PRECISION < _amount0) {
                    _amount1 =
                        _amount1 -
                        _safe112((sent1 * fee) / BP_PRECISION);
                } else {
                    _amount1 = 0;
                }
            }
        }
        require(_amount0 == 0 || _amount1 == 0, "LBE: Wrong amounts"); // If this is wrong, then we're sure the amounts sent are wrong

        while (
            _global.firstPrice <= _global.currentPrice &&
            _global.currentPrice <= _global.lastPrice // to make sure this loop stops
        ) {
            Bin memory _bin = bins[_global.currentPrice];
            if (_bin.reserve0 != 0 || _bin.reserve1 != 0) {
                if (_amount0 != 0) {
                    if (_amount0 <= _bin.reserve0) {
                        // the bin can cover the swap
                        _bin.reserve0 -= _amount0;
                        _global.reserve0 -= _amount0;
                        uint256 sent1ToBin = _global.currentPrice.mulDiv(
                            _amount0 * BP_PRECISION,
                            PRICE_PRECISION * fee
                        );
                        sent1 -= sent1ToBin;
                        _bin.reserve1 += _safe112(sent1ToBin);
                        _global.reserve1 += _safe112(sent1ToBin);

                        _amount0 = 0;
                    } else {
                        // the swap will empty current bin
                        uint256 sent1ToBin = _global.currentPrice.mulDiv(
                            _bin.reserve0 * BP_PRECISION,
                            PRICE_PRECISION * fee
                        );
                        sent1 -= sent1ToBin;
                        _bin.reserve1 += _safe112(sent1ToBin);
                        _global.reserve1 += _safe112(sent1ToBin);

                        _amount0 -= _bin.reserve0;
                        _global.reserve0 -= _bin.reserve0;
                        _bin.reserve0 = 0;
                    }
                }
                if (_amount1 != 0) {
                    if (_amount1 <= _bin.reserve1) {
                        // the bin can cover the swap
                        _bin.reserve1 -= _amount1;
                        _global.reserve1 -= _amount1;
                        uint256 sent0ToBin = PRICE_PRECISION.mulDiv(
                            _amount1 * BP_PRECISION,
                            _global.currentPrice * fee
                        );
                        sent0 -= sent0ToBin;
                        _bin.reserve0 += _safe112(sent0ToBin);
                        _global.reserve0 += _safe112(sent0ToBin);

                        _amount1 = 0;
                    } else {
                        // the swap will empty current bin
                        uint256 sent0ToBin = _safe112(
                            PRICE_PRECISION.mulDiv(
                                _bin.reserve1 * BP_PRECISION,
                                _global.currentPrice * fee
                            )
                        );
                        sent0 -= sent0ToBin;
                        _bin.reserve0 += _safe112(sent0ToBin);
                        _global.reserve0 += _safe112(sent0ToBin);

                        _amount1 -= _bin.reserve1;
                        _global.reserve1 -= _bin.reserve1;
                        _bin.reserve1 = 0;
                    }
                }
                uint256 l = _global.currentPrice.mulDiv(
                    _bin.reserve0,
                    PRICE_PRECISION
                ) + _bin.reserve1;
                require(_bin.l <= l, "LBE: Constant liquidity not respected"); // not sure this is even needed as this checks is forced thanks to the fees added
                _bin.l = l;

                bins[_global.currentPrice] = _bin;
            }

            if (_amount0 == 0 && _amount1 == 0) {
                break;
            } else if (_amount0 != 0) {
                uint256 binStep = _getBinStep(_global.currentPrice);
                if (
                    (_global.currentPrice - binStep) / binStep >= BIN_PRECISION
                ) {
                    _global.currentPrice -= binStep;
                } else {
                    _global.currentPrice -= binStep / 10; // @note won't work if precision is not a multiple of 10.
                }
            } else if (_amount1 != 0) {
                _global.currentPrice += _getBinStep(_global.currentPrice);
            }
        }
        global = _global;
        require(_amount0 == 0 && _amount1 == 0, "LBE: Broken safety check"); // @note safety check, but should never be false (would revert on transfer)
    }

    function addLiquidity(
        // only seed
        uint256[] calldata prices,
        uint112[] calldata amounts0,
        uint112[] calldata amounts1
    ) external {
        uint256 _len = prices.length;
        require(
            _len == amounts0.length && amounts0.length == amounts1.length,
            "LBE: Wrong lengths"
        );
        GlobalInfo memory _global = global;
        uint256 _maxAmount0 = token0.balanceOf(address(this)) -
            _global.reserve0;
        uint256 _maxAmount1 = token1.balanceOf(address(this)) -
            _global.reserve1;

        uint256 i;
        for (i; i < _len; i++) {
            uint112 amount0 = amounts0[i];
            uint112 amount1 = amounts1[i];
            if (amount0 != 0 || amount1 != 0) {
                uint256 price = _getBinPrice(prices[i]);
                Bin storage bin = bins[price];
                if (_global.lastPrice < price) {
                    _global.lastPrice = price;
                }
                if (_global.firstPrice > price) {
                    _global.firstPrice = price;
                }
                if (price < _global.currentPrice) {
                    require(amount0 != 0 && amount1 == 0, "LBE: Forbidden");
                    _maxAmount0 -= amount0; // revert if too much
                    bin.reserve0 += amount0;
                    _global.reserve0 += amount0;
                } else if (price > _global.currentPrice) {
                    require(amount1 != 0 && amount0 == 0, "LBE: Forbidden");
                    _maxAmount1 -= amount1; // revert if too much
                    bin.reserve1 += amount1;
                    _global.reserve1 += amount1;
                } else {
                    uint112 _reserve1 = bin.reserve1;
                    if (_reserve1 != 0) {
                        require(
                            (amount1 * bin.reserve0) / bin.reserve1 == amount0,
                            "LBE: Forbidden"
                        ); // @audit question -> how add liquidity as price moves, hard to add to the exact f
                    } else {
                        require(
                            amount1 == 0 || bin.reserve0 == 0,
                            "LBE: Forbidden"
                        ); // @audit question -> how add liquidity as price moves, hard to add to the exact f
                    }
                    _maxAmount0 -= amount0; // revert if too much
                    _maxAmount1 -= amount1; // revert if too much

                    bin.reserve0 += amount0;
                    bin.reserve1 += amount1;

                    _global.reserve0 += amount0;
                    _global.reserve1 += amount1;
                }
                bin.l += (price * amount0) / PRICE_PRECISION + amount1;
            }
        }
        global = _global;
    }

    function getBin(uint256 price) external view returns (Bin memory) {
        return bins[_getBinPrice(price)];
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

            return decimals;
        }
    }

    function _mostSignificantBit(uint256 x) internal pure returns (uint256 msb) {
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

            return msb;
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

            return 256 - lsb;
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
