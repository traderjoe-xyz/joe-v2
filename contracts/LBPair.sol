// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

/** Imports **/

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import "./LBToken.sol";
import "./libraries/BinHelper.sol";
import "./libraries/Math512Bits.sol";
import "./libraries/MathS40x36.sol";
import "./libraries/SafeCast.sol";
import "./libraries/TreeMath.sol";
import "./interfaces/ILBFactoryHelper.sol";
import "./interfaces/ILBFlashLoanCallback.sol";
import "./interfaces/ILBPair.sol";

/** Errors **/

error LBPair__BaseFeeTooBig(uint256 baseFee);
error LBPair__InsufficientAmounts();
error LBPair__WrongAmounts(uint256 amount0Out, uint256 amount1Out);
error LBPair__BrokenSwapSafetyCheck();
error LBPair__ForbiddenFillFactor(uint256 id);
error LBPair__InsufficientLiquidityMinted(uint24 id);
error LBPair__InsufficientLiquidityBurned(uint24 id);
error LBPair__BurnExceedsReserve(uint24 id);
error LBPair__WrongLengths();
error LBPair__TransferFailed(address token, address to, uint256 value);
error LBPair__BasisPointTooBig();
error LBPair__SwapExceedsAmountIn(uint24 id);
error LBPair__BinReserveOverflows(uint24 id);
error LBPair__SwapOverflows(uint24 id);
error LBPair__TooMuchTokensIn(uint256 amount0In, uint256 amount1In);
error LBPair__BrokenFlashLoanSafetyChecks(uint256 amount0In, uint256 amount1In);

// TODO add oracle price, distribute fees
/// @title Liquidity Bin Exchange
/// @author Trader Joe
/// @notice DexV2 POC
contract LBPair is LBToken, ReentrancyGuard, ILBPair {
    /** Libraries **/

    using Math512Bits for uint256;
    using MathS40x36 for int256;
    using TreeMath for mapping(uint256 => uint256)[3];
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;

    /** Events **/

    event ProtocolFeesCollected(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1
    );

    /** Public constant variables **/

    uint256 public constant override PRICE_PRECISION = 1e36;

    /** Public immutable variables **/

    IERC20 public immutable override token0;
    IERC20 public immutable override token1;
    ILBFactory public immutable override factory;
    /// @notice The `log2(1 + α binStep)` value as a signed 39.36-decimal fixed-point number
    int256 public immutable override log2Value;

    /** Private constant variables **/

    uint256 private constant BASIS_POINT_MAX = 10_000;
    /// @dev Hardcoded value of bytes4(keccak256(bytes('transfer(address,uint256)')))
    bytes4 private constant SELECTOR = 0xa9059cbb;

    PairInformation private _pairInformation;
    FeeHelper.FeeParameters private _feeParameters;

    /** Private variables **/

    /// @dev the reserves of tokens for every bin. This is the amount
    /// of token1 if `id < _pairInformation.id`; of token0 if `id > _pairInformation.id`
    /// and a mix of both if `id == _pairInformation.id`
    mapping(uint256 => Bin) private _bins;
    /// @dev Tree to find bins with non zero liquidity
    mapping(uint256 => uint256)[3] private _tree;

    /** Constructor **/

    /// @notice Initialize the parameters
    /// @param _factory The address of the factory.
    /// @param _token0 The address of the token0. Can't be address 0
    /// @param _token1 The address of the token1. Can't be address 0
    /// @param _log2Value The log(1 + binStep) value
    /// @param _packedFeeParameters The fee parameters
    constructor(
        ILBFactory _factory,
        IERC20 _token0,
        IERC20 _token1,
        int256 _log2Value,
        bytes32 _packedFeeParameters
    ) LBToken("Liquidity Book Token", "LBT") {
        factory = _factory;
        token0 = _token0;
        token1 = _token1;

        assembly {
            sstore(add(_feeParameters.slot, 1), _packedFeeParameters)
        }

        log2Value = _log2Value;
    }

    /** External View Functions **/

    /// @notice View function to get the _pairInformation information
    /// @return The _pairInformation information
    function pairInformation() external view returns (PairInformation memory) {
        return _pairInformation;
    }

    /// @notice View function to get the fee parameters
    /// @return The fee parameters
    function feeParameters()
        external
        view
        returns (FeeHelper.FeeParameters memory)
    {
        return _feeParameters;
    }

    /// @notice View function to get the bin at `id`
    /// @param _id The bin id
    /// @return price The exchange price of y per x inside this bin (multiplied by 1e36)
    /// @return reserve0 The reserve of token0 of the bin
    /// @return reserve1 The reserve of token1 of the bin
    function getBin(uint24 _id)
        external
        view
        override
        returns (
            uint256 price,
            uint112 reserve0,
            uint112 reserve1
        )
    {
        uint256 _price = BinHelper.getPriceFromId(_id, log2Value);
        return (_price, _bins[_id].reserve0, _bins[_id].reserve1);
    }

    /// @notice Returns the approximate id corresponding to the inputted price.
    /// Warning, the returned id may be inaccurate close to the start price of a bin
    /// @param _price The price of y per x (multiplied by 1e36)
    /// @return The id corresponding to this price
    function getIdFromPrice(uint256 _price)
        external
        view
        override
        returns (uint24)
    {
        return BinHelper.getIdFromPrice(_price, log2Value);
    }

    /// @notice Returns the price corresponding to the inputted id
    /// @param _id The id
    /// @return The price corresponding to this id
    function getPriceFromId(uint24 _id)
        external
        view
        override
        returns (uint256)
    {
        return BinHelper.getPriceFromId(_id, log2Value);
    }

    /// @notice Simulate a swap in
    /// @param _amount0Out The amount of token0 to receive
    /// @param _amount1Out The amount of token1 to receive
    /// @return amount0In The amount of token0 to send in order to receive _amount1Out token1
    /// @return amount1In The amount of token1 to send in order to receive _amount0Out token0
    function getSwapIn(uint256 _amount0Out, uint256 _amount1Out)
        external
        view
        override
        returns (uint256 amount0In, uint256 amount1In)
    {
        PairInformation memory _pair = _pairInformation;

        if (
            (_amount0Out != 0 && _amount1Out != 0) ||
            _amount0Out > _pair.reserve0 ||
            _amount1Out > _pair.reserve1
        ) revert LBPair__WrongAmounts(_amount0Out, _amount1Out); // If this is wrong, then we're sure the amounts sent are wrong

        FeeHelper.FeeParameters memory _fp = _feeParameters;
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.id;

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            Bin memory _bin = _bins[_pair.id];
            if (_bin.reserve0 != 0 || _bin.reserve1 != 0) {
                uint256 _price = BinHelper.getPriceFromId(
                    uint24(_pair.id),
                    log2Value
                );
                if (_amount0Out != 0) {
                    uint256 _amount0OutOfBin = _amount0Out > _bin.reserve0
                        ? _bin.reserve0
                        : _amount0Out;
                    uint256 _amount1InToBin = _price.mulDivRoundUp(
                        _amount0OutOfBin,
                        PRICE_PRECISION
                    );
                    uint256 _amount1InWithFees = _amount1InToBin +
                        _fp.getFees(_amount1InToBin, _pair.id - _startId);

                    unchecked {
                        if (_amount1InWithFees > type(uint112).max)
                            revert LBPair__SwapOverflows(_pair.id);

                        _amount0Out -= _amount0OutOfBin;
                        amount1In += _amount1InWithFees;
                    }
                } else {
                    uint256 _amount1OutOfBin = _amount1Out > _bin.reserve1
                        ? _bin.reserve1
                        : _amount1Out;
                    uint256 _amount0InToBin = PRICE_PRECISION.mulDivRoundUp(
                        _amount1OutOfBin,
                        _price
                    );
                    uint256 _amount0InWithFees = _amount0InToBin +
                        _fp.getFees(_amount0InToBin, _startId - _pair.id);

                    unchecked {
                        if (_amount0InWithFees > type(uint112).max)
                            revert LBPair__SwapOverflows(_pair.id);

                        amount0In += _amount0InWithFees;
                        _amount1Out -= _amount1OutOfBin;
                    }
                }
            }

            if (_amount0Out != 0 || _amount1Out != 0) {
                _pair.id = uint24(
                    _tree.findFirstBin(_pair.id, _amount0Out == 0)
                );
            } else {
                break;
            }
        }
        if (_amount0Out != 0 || _amount1Out != 0)
            revert LBPair__BrokenSwapSafetyCheck(); // Safety check, but should never be false as it would have reverted on transfer
    }

    /// @notice Simulate a swap out
    /// @param _amount0In The amount of token0 sent
    /// @param _amount1In The amount of token1 sent
    /// @return amount0Out The amount of token0 received if _amount0In token0 are sent
    /// @return amount1Out The amount of token1 received if _amount1In token1 are sent
    function getSwapOut(uint256 _amount0In, uint256 _amount1In)
        external
        view
        override
        returns (uint256 amount0Out, uint256 amount1Out)
    {
        PairInformation memory _pair = _pairInformation;

        if (_amount0In != 0 && _amount1In != 0)
            revert LBPair__WrongAmounts(amount0Out, amount1Out); // If this is wrong, then we're sure the amounts sent are wrong

        FeeHelper.FeeParameters memory _fp = _feeParameters;
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.id;

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            Bin memory _bin = _bins[_pair.id];
            if (_bin.reserve0 != 0 || _bin.reserve1 != 0) {
                uint256 _price = BinHelper.getPriceFromId(
                    uint24(_pair.id),
                    log2Value
                );
                if (_amount1In != 0) {
                    uint256 _maxAmount1In = _price.mulDivRoundUp(
                        _bin.reserve0,
                        PRICE_PRECISION
                    );

                    uint256 _maxAmount1InWithFees = _maxAmount1In +
                        _fp.getFees(_maxAmount1In, _pair.id - _startId);

                    uint256 _amount1InWithFees = _amount1In >
                        _maxAmount1InWithFees
                        ? _maxAmount1InWithFees
                        : _amount1In;

                    if (_amount1InWithFees > type(uint112).max)
                        revert LBPair__SwapOverflows(_pair.id);

                    unchecked {
                        uint256 _amount0OutOfBin = _amount1InWithFees != 0
                            ? ((_amount1InWithFees - 1) * _bin.reserve0) /
                                _maxAmount1InWithFees
                            : 0; // Forces round down to match the round up during a swap

                        _amount1In -= _amount1InWithFees;
                        amount0Out += _amount0OutOfBin;
                    }
                } else {
                    uint256 _maxAmount0In = PRICE_PRECISION.mulDivRoundUp(
                        _bin.reserve1,
                        _price
                    );

                    uint256 _maxAmount0InWithFees = _maxAmount0In +
                        _fp.getFees(_maxAmount0In, _startId - _pair.id);

                    uint256 _amount0InWithFees = _amount0In >
                        _maxAmount0InWithFees
                        ? _maxAmount0InWithFees
                        : _amount0In;

                    if (_amount0InWithFees > type(uint112).max)
                        revert LBPair__SwapOverflows(_pair.id);

                    unchecked {
                        uint256 _amount1OutOfBin = _amount0InWithFees != 0
                            ? ((_amount0InWithFees - 1) * _bin.reserve1) /
                                _maxAmount0InWithFees
                            : 0; // Forces round down to match the round up during a swap

                        _amount0In -= _amount0InWithFees;
                        amount1Out += _amount1OutOfBin;
                    }
                }
            }

            if (_amount0In != 0 || _amount1In != 0) {
                _pair.id = _tree
                    .findFirstBin(_pair.id, _amount1In == 0)
                    .safe24();
            } else {
                break;
            }
        }
        if (_amount0In != 0 || _amount1In != 0)
            revert LBPair__TooMuchTokensIn(_amount0In, _amount1In);
    }

    /** External Functions **/

    /// @notice Performs a low level swap, this needs to be called from a contract which performs important safety checks
    /// @param _amount0Out The amount of token0
    /// @param _amount1Out The amount of token1
    /// @param _to The address of the recipient
    function swap(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to
    ) external override nonReentrant {
        PairInformation memory _pair = _pairInformation;

        uint256 _amount0In = token0.balanceOf(address(this)) -
            (_pair.reserve0 + _pair.fees0);
        uint256 _amount1In = token1.balanceOf(address(this)) -
            (_pair.reserve1 + _pair.fees1);

        if (_amount0In == 0 && _amount1In == 0)
            revert LBPair__InsufficientAmounts();

        if (_amount0Out != 0) {
            token0.safeTransfer(_to, _amount0Out);
            _amount0Out = _getAmountOut(_amount0In, _amount0Out);
        }
        if (_amount1Out != 0) {
            token1.safeTransfer(_to, _amount1Out);
            _amount1Out = _getAmountOut(_amount1In, _amount1Out);
        }

        if (_amount0Out != 0 && _amount1Out != 0)
            revert LBPair__WrongAmounts(_amount0Out, _amount1Out); // If this is wrong, then we're sure the amounts sent are wrong

        FeeHelper.FeeParameters memory _fp = _feeParameters;
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.id;

        uint256 _fees;
        uint256 _amountOutOfBin;
        uint256 _amountInToBin;
        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            Bin memory _bin = _bins[_pair.id];
            if (_bin.reserve0 != 0 || _bin.reserve1 != 0) {
                uint256 _price = BinHelper.getPriceFromId(_pair.id, log2Value);
                if (_amount0Out != 0) {
                    _amountOutOfBin = _amount0Out > _bin.reserve0
                        ? _bin.reserve0
                        : _amount0Out;
                    _amountInToBin = _price.mulDivRoundUp(
                        _amountOutOfBin,
                        PRICE_PRECISION
                    );
                    _fees = _fp.getFees(_amountInToBin, _pair.id - _startId);

                    if (_amount1In < _amountInToBin + _fees)
                        revert LBPair__SwapExceedsAmountIn(_pair.id);
                    if (_bin.reserve1 + _amountInToBin > type(uint112).max)
                        revert LBPair__BinReserveOverflows(_pair.id);

                    _pair.fees1 = (_pair.fees1 + _fees).safe128();

                    unchecked {
                        _amount0Out -= _amountOutOfBin;
                        _amount1In -= _amountInToBin + _fees;

                        _bin.reserve0 -= uint112(_amountOutOfBin);
                        _bin.reserve1 += uint112(_amountInToBin);

                        _pair.reserve0 -= uint136(_amountOutOfBin);
                        _pair.reserve1 += uint136(_amountInToBin);
                    }
                } else {
                    _amountOutOfBin = _amount1Out > _bin.reserve1
                        ? _bin.reserve1
                        : _amount1Out;
                    _amountInToBin = PRICE_PRECISION.mulDivRoundUp(
                        _amountOutOfBin,
                        _price
                    );

                    _fees = _fp.getFees(_amountInToBin, _startId - _pair.id);

                    if (_amount0In < _amountInToBin + _fees)
                        revert LBPair__SwapExceedsAmountIn(_pair.id);
                    if (_bin.reserve0 + _amountInToBin > type(uint112).max)
                        revert LBPair__BinReserveOverflows(_pair.id);

                    // The addition can't overflows as max(_amountInToBin) < 1e36 * 2**112 / 1 < 2 ** 256
                    _pair.fees0 = (_pair.fees0 + _fees).safe128();

                    unchecked {
                        _amount0In -= _amountInToBin + _fees;
                        _amount1Out -= _amountOutOfBin;

                        _bin.reserve0 += uint112(_amountInToBin);
                        _bin.reserve1 -= uint112(_amountOutOfBin);

                        _pair.reserve0 += uint136(_amountInToBin);
                        _pair.reserve1 -= uint136(_amountOutOfBin);
                    }
                }
                _bins[_pair.id] = _bin;
            }

            if (_amount0Out != 0 || _amount1Out != 0) {
                _pair.id = uint24(
                    _tree.findFirstBin(_pair.id, _amount0Out == 0)
                );
            } else {
                break;
            }
        }

        _pairInformation = _pair;
        _feeParameters.updateStoredFeeParameters(
            _fp.accumulator,
            delta(_startId, _pair.id)
        );

        if (_amount0Out != 0 || _amount1Out != 0)
            revert LBPair__BrokenSwapSafetyCheck(); // Safety check
    }

    /// @notice Performs a flash loan
    /// @param _to the address that will execute the external call
    /// @param _amount0Out The amount of token0
    /// @param _amount1Out The amount of token0
    /// @param _data The bytes data that will be forwarded to _to
    function flashLoan(
        address _to,
        uint256 _amount0Out,
        uint256 _amount1Out,
        bytes calldata _data
    ) external override nonReentrant {
        FeeHelper.FeeParameters memory _fp = _feeParameters;
        PairInformation memory _pair = _pairInformation;
        _fp.updateAccumulatorValue();

        uint256 _fees0 = _fp.getFees(_amount0Out, 0);
        uint256 _fees1 = _fp.getFees(_amount1Out, 0);

        if (_amount0Out != 0) token0.safeTransfer(_to, _amount0Out);
        if (_amount1Out != 0) token0.safeTransfer(_to, _amount1Out);

        ILBFlashLoanCallback(_to).LBFlashLoanCallback(
            msg.sender,
            _fees0,
            _fees1,
            _data
        );

        uint256 _balance0After = token0.balanceOf(address(this));
        uint256 _balance1After = token1.balanceOf(address(this));

        if (_pair.reserve0 + _fees0 > _balance0After) revert();
        if (_pair.reserve1 + _fees1 > _balance1After) revert();

        uint256 _received0 = _balance0After - _pair.reserve0;
        uint256 _received1 = _balance1After - _pair.reserve1;

        if (_received0 != 0) {
            _pair.fees0 = (_pair.fees0 + _received0).safe128();
        }
        if (_received1 != 0) {
            _pair.fees1 = (_pair.fees1 + _received1).safe128();
        }
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
    ) external override nonReentrant {
        uint256 _len = _amounts0.length;
        if (
            _len != _amounts1.length &&
            _len != 0 &&
            _startId + _len - 1 > type(uint24).max
        ) revert LBPair__WrongLengths();

        PairInformation memory _pair = _pairInformation;
        uint256 _amount0In = token0.balanceOf(address(this)) - _pair.reserve0;
        uint256 _amount1In = token1.balanceOf(address(this)) - _pair.reserve1;

        // seeding liquidity
        if (_pair.id == 0) {
            _pair.id = (_startId +
                BinHelper.binarySearchMiddle(_amounts0, 0, _len - 1)).safe24();
        }

        for (uint256 _id = _startId; _id < _startId + _len; ++_id) {
            uint256 _amount0 = _amounts0[_id - _startId];
            uint256 _amount1 = _amounts1[_id - _startId];
            if (_amount0 != 0 || _amount1 != 0) {
                Bin memory _bin = _bins[_id];

                if (_amount0 * _bin.reserve1 != _amount1 * _bin.reserve0)
                    revert LBPair__ForbiddenFillFactor(_id);

                uint256 _price = BinHelper.getPriceFromId(
                    uint24(_id),
                    log2Value
                );

                if (_bin.reserve0 == 0 || _bin.reserve1 == 0) {
                    // add 1 at the right indices if the _pairInformation was empty
                    _tree[2][_id / 256] |= 1 << (_id % 256);
                    _tree[1][_id / 65_536] |= 1 << ((_id / 256) % 256);
                    _tree[0][0] |= 1 << (_id / 65_536);
                }

                uint256 _pastL = _price.mulDivRoundUp(
                    _bin.reserve0,
                    PRICE_PRECISION
                ) + _bin.reserve1;

                _amount0In -= _amount0;
                _amount1In -= _amount1;

                _bin.reserve0 += uint112(_amount0);
                _bin.reserve1 += uint112(_amount1);

                _pair.reserve0 += uint136(_amount0);
                _pair.reserve1 += uint136(_amount1);

                uint256 _newL = _price.mulDivRoundUp(
                    _bin.reserve0,
                    PRICE_PRECISION
                ) + _bin.reserve1;

                if (_pastL != 0) {
                    _newL = _newL.mulDivRoundUp(totalSupply(_id), _pastL);
                }
                if (_newL == 0)
                    revert LBPair__InsufficientLiquidityMinted(uint24(_id));

                _bins[_id] = _bin;
                _mint(_to, _id, _newL);
            }
        }
        _pairInformation = _pair;
    }

    /// @notice Performs a low level remove, this needs to be called from a contract which performs important safety checks
    /// @param _ids The ids the user want to remove its liquidity
    /// @param _to The address of the recipient
    function burn(uint24[] calldata _ids, address _to)
        external
        override
        nonReentrant
    {
        uint256 _len = _ids.length;

        PairInformation memory _pair = _pairInformation;

        uint256 _amounts0;
        uint256 _amounts1;

        for (uint256 i; i < _len; ++i) {
            uint256 _id = _ids[i];
            uint256 _amount = balanceOf(address(this), _id);

            if (_amount == 0)
                revert LBPair__InsufficientLiquidityBurned(uint24(_id));

            Bin memory _bin = _bins[_id];

            uint256 totalSupply = totalSupply(_id);

            if (_id <= _pair.id) {
                uint256 _amount1 = _amount.mulDivRoundDown(
                    _bin.reserve1,
                    totalSupply
                );

                if (_bin.reserve1 < _amount1)
                    revert LBPair__BurnExceedsReserve(uint24(_id));

                unchecked {
                    _amounts1 += _amount1;
                    _bin.reserve1 -= uint112(_amount1);
                    _pair.reserve1 -= uint136(_amount1);
                }
            }
            if (_id >= _pair.id) {
                uint256 _amount0 = _amount.mulDivRoundDown(
                    _bin.reserve0,
                    totalSupply
                );

                if (_bin.reserve0 < _amount0)
                    revert LBPair__BurnExceedsReserve(uint24(_id));
                unchecked {
                    _amounts0 += _amount0;
                    _bin.reserve0 -= uint112(_amount0);
                    _pair.reserve0 -= uint136(_amount0);
                }
            }

            if (_bin.reserve0 == 0 && _bin.reserve1 == 0) {
                // removes 1 at the right indices
                uint256 _idDepth2 = _id / 256;
                _tree[2][_idDepth2] -= 1 << (_id % 256);
                if (_tree[2][_idDepth2] == 0) {
                    uint256 _idDepth1 = _id / 65_536;
                    _tree[1][_idDepth1] -= 1 << (_idDepth2 % 256);
                    if (_tree[1][_idDepth1] == 0) {
                        _tree[0][0] -= 1 << _idDepth1;
                    }
                }
            }

            _bins[_id] = _bin;
            _burn(address(this), _id, _amount);
        }
        _pairInformation = _pair;
        if (_amounts0 != 0) token0.safeTransfer(_to, _amounts0);
        if (_amounts1 != 0) token1.safeTransfer(_to, _amounts1);
    }

    /** Public Functions **/

    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(LBToken, IERC165)
        returns (bool)
    {
        return
            _interfaceId == type(ILBPair).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /** Private Functions **/

    /// @notice Returns the amount that needs to be swapped
    /// @param _amountIn The amount sent to the _pairInformation
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

    /// @notice Returns the difference between two values
    /// @param x The first value
    /// @param y The second value
    /// @return The difference between the two
    function delta(uint256 x, uint256 y) private pure returns (uint256) {
        unchecked {
            return x > y ? x - y : y - x;
        }
    }
}
