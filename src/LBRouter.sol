// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ILBPair.sol";
import "./interfaces/ILBToken.sol";
import "./interfaces/IJoePair.sol";
import "./interfaces/ILBRouter.sol";
import "./interfaces/ILBFactory.sol";
import "./libraries/BinHelper.sol";
import "./libraries/FeeHelper.sol";
import "./libraries/Math512Bits.sol";
import "./libraries/SwapHelper.sol";
import "./libraries/Constants.sol";

error LBRouter__SenderIsNotWAVAX();
error LBRouter__PairNotCreated(uint256 version, IERC20 tokenX, IERC20 tokenY);
error LBRouter__WrongAmounts(uint256 amount, uint256 reserve);
error LBRouter__SwapOverflows(uint256 id);
error LBRouter__BrokenSwapSafetyCheck();
error LBRouter__NotFactoryOwner();
error LBRouter__TooMuchTokensIn(uint256 excess);
error LBRouter__BinReserveOverflows(uint256 id);
error LBRouter__IdOverflows(uint256 id);
error LBRouter__LengthsMismatch();
error LBRouter__IdSlippageCaught(uint256 activeIdDesired, uint256 idSlippage, uint256 activeId);
error LBRouter__AmountSlippageCaught(uint256 amountXMin, uint256 amountX, uint256 amountYMin, uint256 amountY);
error LBRouter__IdDesiredOverflows(uint256 idDesired, uint256 idSlippage);
error LBRouter__FailedToSendAVAX(address recipient, uint256 amount);
error LBRouter__DeadlineExceeded(uint256 deadline, uint256 currentTimestamp);
error LBRouter__AmountSlippageBPTooBig(uint256 amountSlippage);
error LBRouter__AmountsMismatch(uint256 amountAVAX, uint256 msgValue);
error LBRouter__InsufficientAmountOut(uint256 amountOutMin, uint256 amountOut);
error LBRouter__MaxAmountInExceeded(uint256 amountInMax, uint256 amountIn);
error LBRouter__InsufficientAVAXAmount(uint256 amountAVAXNeeded, uint256 amountAVAX);
error LBRouter__AmountInOverflows(uint256 amountIn);
error LBRouter__AmountOutOverflows(uint256 amountOut);
error LBRouter__InvalidTokenPath(IERC20 wrongToken);

contract LBRouter is ILBRouter {
    using SafeERC20 for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;
    using Math512Bits for uint256;
    using SwapHelper for ILBPair.PairInformation;

    ILBFactory public immutable override factory;
    IJoeFactory public immutable oldFactory;
    IWAVAX public immutable wavax;

    modifier onlyFactoryOwner() {
        if (msg.sender != factory.owner()) revert LBRouter__NotFactoryOwner();
        _;
    }

    modifier ensure(uint256 _deadline) {
        if (block.timestamp > _deadline) revert LBRouter__DeadlineExceeded(_deadline, block.timestamp);
        _;
    }

    constructor(
        ILBFactory _factory,
        IJoeFactory _oldFactory,
        IWAVAX _wavax
    ) {
        factory = _factory;
        oldFactory = _oldFactory;
        wavax = _wavax;
    }

    ///@dev Receive function that only accept AVAX from the WAVAX contract
    receive() external payable {
        if (msg.sender != address(wavax)) revert LBRouter__SenderIsNotWAVAX();
    }

    /// @notice Returns the approximate id corresponding to the inputted price.
    /// Warning, the returned id may be inaccurate close to the start price of a bin
    /// @param _LBPair The address of the LBPair
    /// @param _price The price of y per x (multiplied by 1e36)
    /// @return The id corresponding to this price
    function getIdFromPrice(ILBPair _LBPair, uint256 _price) external view override returns (uint24) {
        return BinHelper.getIdFromPrice(_price, _LBPair.feeParameters().binStep);
    }

    /// @notice Returns the price corresponding to the inputted id
    /// @param _LBPair The address of the LBPair
    /// @param _id The id
    /// @return The price corresponding to this id
    function getPriceFromId(ILBPair _LBPair, uint24 _id) external view override returns (uint256) {
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
    ) public view override returns (uint256 amountIn) {
        (uint256 _pairReserveX, uint256 _pairReserveY, uint256 _activeId) = _LBPair.getReservesAndId();

        if (_amountOut == 0 || (_swapForY ? _amountOut > _pairReserveY : _amountOut > _pairReserveX))
            revert LBRouter__WrongAmounts(_amountOut, _swapForY ? _pairReserveY : _pairReserveX); // If this is wrong, then we're sure the amounts sent are wrong

        FeeHelper.FeeParameters memory _fp = _LBPair.feeParameters();
        _fp.updateAccumulatorValue();
        uint256 _startId = _activeId;

        uint256 _amountOutOfBin;
        uint256 _amountInWithFees;
        uint256 _reserve;
        // Performs the actual swap, bin per bin
        // It uses the findFirstNonEmptyBinId function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            {
                (uint256 _reserveX, uint256 _reserveY) = _LBPair.getBin(uint24(_activeId));
                _reserve = _swapForY ? _reserveY : _reserveX;
            }
            uint256 _price = BinHelper.getPriceFromId(_activeId, _fp.binStep);
            if (_reserve != 0) {
                _amountOutOfBin = _amountOut > _reserve ? _reserve : _amountOut;

                uint256 _amountInToBin = _swapForY
                    ? Constants.SCALE.mulDivRoundUp(_amountOutOfBin, _price)
                    : _price.mulDivRoundUp(_amountOutOfBin, Constants.SCALE);

                _amountInWithFees =
                    _amountInToBin +
                    _fp.getFees(_amountInToBin, _startId > _activeId ? _startId - _activeId : _activeId - _startId);

                if (_amountInWithFees + _reserve > type(uint112).max) revert LBRouter__SwapOverflows(_activeId);
                amountIn += _amountInWithFees;
                _amountOut -= _amountOutOfBin;
            }

            if (_amountOut != 0) {
                _activeId = uint24(_LBPair.findFirstNonEmptyBinId(uint24(_activeId), _swapForY));
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
        ILBPair.PairInformation memory _pair;
        {
            (, , uint256 _activeId) = _LBPair.getReservesAndId();
            _pair.activeId = uint24(_activeId);
        }

        FeeHelper.FeeParameters memory _fp = _LBPair.feeParameters();
        _fp.updateAccumulatorValue();
        ILBPair.Bin memory _bin;

        uint256 _startId = _pair.activeId;

        // Performs the actual swap, bin per bin
        // It uses the findFirstNonEmptyBinId function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            {
                (uint256 _reserveX, uint256 _reserveY) = _LBPair.getBin(_pair.activeId);
                _bin = ILBPair.Bin(uint112(_reserveX), uint112(_reserveY), 0, 0);
            }
            if (_bin.reserveX != 0 || _bin.reserveY != 0) {
                (uint256 _amountInToBin, uint256 _amountOutOfBin, FeeHelper.FeesDistribution memory _fees) = _pair
                    .getAmounts(_bin, _fp, !_swapForY, _startId, _amountIn);

                if (_amountInToBin > type(uint112).max) revert LBRouter__BinReserveOverflows(_pair.activeId);

                _amountIn -= _amountInToBin + _fees.total;
                _amountOut += _amountOutOfBin;
            }

            if (_amountIn != 0) {
                _pair.activeId = uint24(_LBPair.findFirstNonEmptyBinId(_pair.activeId, _swapForY));
            } else {
                break;
            }
        }
        if (_amountIn != 0) revert LBRouter__TooMuchTokensIn(_amountIn);
    }

    /// @notice Create a liquidity bin LBPair for _tokenX and _tokenY using the factory
    /// @param _tokenX The address of the first token
    /// @param _tokenY The address of the second token
    /// @param _activeId The active id of the pair
    /// @param _sampleLifetime The lifetime of a sample. It's the min time between 2 oracle's sample
    /// @param _maxAccumulator The max value of the accumulator
    /// @param _filterPeriod The period where the accumulator value is untouched, prevent spam
    /// @param _decayPeriod The period where the accumulator value is halved
    /// @param _binStep The bin step in basis point, used to calculate log(1 + binStep)
    /// @param _baseFactor The base factor, used to calculate the base fee, baseFee = baseFactor * binStep
    /// @param _protocolShare The share of the fees received by the protocol
    function createLBPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _activeId,
        uint256 _sampleLifetime,
        uint64 _maxAccumulator,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint16 _binStep,
        uint16 _baseFactor,
        uint16 _protocolShare
    ) external override {
        factory.createLBPair(
            _tokenX,
            _tokenY,
            _activeId,
            _sampleLifetime,
            _maxAccumulator,
            _filterPeriod,
            _decayPeriod,
            _binStep,
            _baseFactor,
            _protocolShare
        );
    }

    /// @notice Add liquidity while performing safety checks
    /// @param _tokenX The address of token X
    /// @param _tokenY The address of token Y
    /// @param _amountX The amount to send of token X
    /// @param _amountY The amount to send of token Y
    /// @param _amountSlippageBP The slippage of amounts in basis point (1 is 0.01%, 10_000 is 100%)
    /// @param _activeIdDesired The active id that user wants to add liquidity from
    /// @param _idSlippage The number of id that are allowed to slip
    /// @param _deltaIds The list of delta ids to add liquidity (`deltaId = activeId - desiredId`)
    /// @param _distributionX The distribution of tokenX with sum(_distributionX) = 100e36 (100%) or 0 (0%)
    /// @param _distributionY The distribution of tokenY with sum(_distributionY) = 100e36 (100%) or 0 (0%)
    /// @param _to The address of the recipient
    /// @param _deadline The deadline of the tx
    function addLiquidity(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _amountX,
        uint256 _amountY,
        uint256 _amountSlippageBP,
        uint256 _activeIdDesired,
        uint256 _idSlippage,
        int256[] memory _deltaIds,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        address _to,
        uint256 _deadline
    ) external override {
        LiquidityParam memory _liq = LiquidityParam(
            _tokenX,
            _tokenY,
            _getLBPair(_tokenX, _tokenY),
            _amountX,
            _amountY,
            _getMinAmount(_amountX, _amountSlippageBP),
            _getMinAmount(_amountY, _amountSlippageBP),
            _activeIdDesired,
            _idSlippage,
            _deltaIds,
            new uint256[](_deltaIds.length),
            _distributionX,
            _distributionY,
            _to,
            _deadline
        );
        _addLiquidity(_liq);
    }

    /// @notice Add liquidity with AVAX while performing safety checks
    /// @param _token The address of token
    /// @param _amount The amount to send of token
    /// @param _amountSlippageBP The slippage of amounts in basis point (1 is 0.01%, 10_000 is 100%)
    /// @param _activeIdDesired The active id that user wants to add liquidity from
    /// @param _idSlippage The number of id that are allowed to slip
    /// @param _deltaIds The list of delta ids to add liquidity (`deltaId = activeId - desiredId`)
    /// @param _distributionToken The distribution of token with sum(_distributionToken) = 100e36 (100%) or 0 (0%)
    /// @param _distributionAVAX The distribution of AVAX with sum(_distributionAVAX) = 100e36 (100%) or 0 (0%)
    /// @param _to The address of the recipient
    /// @param _deadline The deadline of the tx
    function addLiquidityAVAX(
        IERC20 _token,
        uint256 _amount,
        uint256 _amountSlippageBP,
        uint256 _activeIdDesired,
        uint256 _idSlippage,
        int256[] memory _deltaIds,
        uint256[] memory _distributionToken,
        uint256[] memory _distributionAVAX,
        address _to,
        uint256 _deadline
    ) external payable override {
        LiquidityParam memory _liq = LiquidityParam(
            _token,
            IERC20(address(0)),
            _getLBPair(_token, IERC20(wavax)),
            _amount,
            msg.value,
            _getMinAmount(_amount, _amountSlippageBP),
            msg.value,
            _activeIdDesired,
            _idSlippage,
            _deltaIds,
            new uint256[](_deltaIds.length),
            _distributionToken,
            _distributionAVAX,
            _to,
            _deadline
        );
        _addLiquidity(_liq);
    }

    /// @notice Remove liquidity while performing safety checks
    /// @param _tokenX The address of token X
    /// @param _tokenY The address of token Y
    /// @param _amountXMin The min amount to receive of token X
    /// @param _amountYMin The min amount to receive of token Y
    /// @param _ids The list of ids to burn
    /// @param _amounts The list of amounts to burn of each id in `_ids`
    /// @param _to The address of the recipient
    /// @param _deadline The deadline of the tx
    function removeLiquidity(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _amountXMin,
        uint256 _amountYMin,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to,
        uint256 _deadline
    ) external override ensure(_deadline) {
        ILBPair _LBPair = _getLBPair(_tokenX, _tokenY);
        if (_tokenX != _LBPair.tokenX()) {
            (_tokenX, _tokenY) = (_tokenY, _tokenX);
            (_amountXMin, _amountYMin) = (_amountYMin, _amountXMin);
        }

        _removeLiquidity(_LBPair, _amountXMin, _amountYMin, _ids, _amounts, _to);
    }

    /// @notice Remove AVAX liquidity while performing safety checks
    /// @param _token The address of token
    /// @param _amountTokenMin The min amount to receive of token
    /// @param _amountAVAXMin The min amount to receive of AVAX
    /// @param _ids The list of ids to burn
    /// @param _amounts The list of amounts to burn of each id in `_ids`
    /// @param _to The address of the recipient
    /// @param _deadline The deadline of the tx
    function removeLiquidityAVAX(
        IERC20 _token,
        uint256 _amountTokenMin,
        uint256 _amountAVAXMin,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to,
        uint256 _deadline
    ) external override ensure(_deadline) {
        ILBPair _LBPair = _getLBPair(_token, IERC20(wavax));

        bool _isAVAXTokenY = IERC20(wavax) == _LBPair.tokenY();

        uint256 _amountToken;
        uint256 _amountAVAX;
        {
            if (!_isAVAXTokenY) {
                (_amountTokenMin, _amountAVAXMin) = (_amountAVAXMin, _amountTokenMin);
            }

            (uint256 _amountX, uint256 _amountY) = _removeLiquidity(
                _LBPair,
                _amountTokenMin,
                _amountAVAXMin,
                _ids,
                _amounts,
                address(this)
            );

            (_amountToken, _amountAVAX) = _isAVAXTokenY ? (_amountX, _amountY) : (_amountY, _amountX);
        }

        _token.safeTransfer(_to, _amountToken);

        wavax.withdraw(_amountAVAX);
        _safeTransferAVAX(_to, _amountAVAX);
    }

    /// @notice Swaps exact tokens for tokens while performing safety checks
    /// @param _amountIn The amount of token to send
    /// @param _amountOutMin The min amount of token to receive
    /// @param _pairVersions The versions of the pairs (1: DexV1, 2: dexV2)
    /// @param _tokenPath The swap path using the versions following `_pairVersions`
    /// @param _to The address of the recipient
    /// @param _deadline The deadline of the tx
    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external override ensure(_deadline) {
        if (_pairVersions.length + 1 != _tokenPath.length || _pairVersions.length == 0)
            revert LBRouter__LengthsMismatch();
        if (_amountIn > type(uint112).max) revert LBRouter__AmountInOverflows(_amountIn);

        address _pair = _getPair(_pairVersions[0], _tokenPath[0], _tokenPath[1]);

        _tokenPath[0].safeTransferFrom(msg.sender, _pair, _amountIn);

        _swapExactTokensForTokens(_amountIn, _amountOutMin, _pair, _pairVersions, _tokenPath, _to);
    }

    /// @notice Swaps exact tokens for AVAX while performing safety checks
    /// @param _amountIn The amount of token to send
    /// @param _amountOutMinAVAX The min amount of AVAX to receive
    /// @param _pairVersions The versions of the pairs (1: DexV1, 2: dexV2)
    /// @param _tokenPath The swap path using the versions following `_pairVersions`
    /// @param _to The address of the recipient
    /// @param _deadline The deadline of the tx
    function swapExactTokensForAVAX(
        uint256 _amountIn,
        uint256 _amountOutMinAVAX,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external override ensure(_deadline) {
        if (_pairVersions.length + 1 != _tokenPath.length || _pairVersions.length == 0)
            revert LBRouter__LengthsMismatch();
        if (_tokenPath[_pairVersions.length] != IERC20(wavax))
            revert LBRouter__InvalidTokenPath(_tokenPath[_pairVersions.length]);

        address _pair = _getPair(_pairVersions[0], _tokenPath[0], _tokenPath[1]);

        _tokenPath[0].safeTransferFrom(msg.sender, _pair, _amountIn);

        uint256 _amountOut = _swapExactTokensForTokens(
            _amountIn,
            _amountOutMinAVAX,
            _pair,
            _pairVersions,
            _tokenPath,
            address(this)
        );

        wavax.withdraw(_amountOut);
        _safeTransferAVAX(_to, _amountOut);
    }

    /// @notice Swaps exact AVAX for tokens while performing safety checks
    /// @param _amountOutMin The min amount of token to receive
    /// @param _pairVersions The versions of the pairs (1: DexV1, 2: dexV2)
    /// @param _tokenPath The swap path using the versions following `_pairVersions`
    /// @param _to The address of the recipient
    /// @param _deadline The deadline of the tx
    function swapExactAVAXForTokens(
        uint256 _amountOutMin,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external payable override ensure(_deadline) {
        if (_pairVersions.length + 1 != _tokenPath.length || _pairVersions.length == 0)
            revert LBRouter__LengthsMismatch();
        if (_tokenPath[0] != IERC20(wavax)) revert LBRouter__InvalidTokenPath(_tokenPath[0]);

        address _pair = _getPair(_pairVersions[0], _tokenPath[0], _tokenPath[1]);

        wavax.deposit{value: msg.value}();
        wavax.transfer(_pair, msg.value);

        _swapExactTokensForTokens(msg.value, _amountOutMin, _pair, _pairVersions, _tokenPath, _to);
    }

    /// @notice Swaps tokens for exact tokens while performing safety checks
    /// @param _amountOut The amount of token to receive
    /// @param _amountInMax The max amount of token to send
    /// @param _pairVersions The versions of the pairs (1: DexV1, 2: dexV2)
    /// @param _tokenPath The swap path using the versions following `_pairVersions`
    /// @param _to The address of the recipient
    /// @param _deadline The deadline of the tx
    function swapTokensForExactTokens(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external override ensure(_deadline) {
        (address[] memory _pairs, uint256[] memory _amountsIn) = _getPairsAndAmountsIn(
            _amountOut,
            _amountInMax,
            _pairVersions,
            _tokenPath
        );

        _tokenPath[0].safeTransferFrom(msg.sender, _pairs[0], _amountsIn[0]);

        _swapTokensForExactTokens(_amountOut, _pairs, _pairVersions, _tokenPath, _amountsIn, _to);
    }

    /// @notice Swaps tokens for exact AVAX while performing safety checks
    /// @param _amountAVAXOut The amount of AVAX to receive
    /// @param _amountInMax The max amount of token to send
    /// @param _pairVersions The versions of the pairs (1: DexV1, 2: dexV2)
    /// @param _tokenPath The swap path using the versions following `_pairVersions`
    /// @param _to The address of the recipient
    /// @param _deadline The deadline of the tx
    function swapTokensForExactAVAX(
        uint256 _amountAVAXOut,
        uint256 _amountInMax,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external override ensure(_deadline) {
        if (_tokenPath[_pairVersions.length] != IERC20(wavax))
            revert LBRouter__InvalidTokenPath(_tokenPath[_pairVersions.length]);

        (address[] memory _pairs, uint256[] memory _amountsIn) = _getPairsAndAmountsIn(
            _amountAVAXOut,
            _amountInMax,
            _pairVersions,
            _tokenPath
        );

        _tokenPath[0].safeTransferFrom(msg.sender, _pairs[0], _amountsIn[0]);

        uint256 _amountOutReal = _swapTokensForExactTokens(
            _amountAVAXOut,
            _pairs,
            _pairVersions,
            _tokenPath,
            _amountsIn,
            address(this)
        );

        if (_amountOutReal < _amountAVAXOut) revert LBRouter__InsufficientAmountOut(_amountAVAXOut, _amountOutReal);

        wavax.withdraw(_amountOutReal);
        _safeTransferAVAX(_to, _amountOutReal);
    }

    /// @notice Swaps AVAX for exact tokens while performing safety checks
    /// @dev will refund any excess sent
    /// @param _amountOut The amount of tokens to receive
    /// @param _pairVersions The versions of the pairs (1: DexV1, 2: dexV2)
    /// @param _tokenPath The swap path using the versions following `_pairVersions`
    /// @param _to The address of the recipient
    /// @param _deadline The deadline of the tx
    function swapAVAXForExactTokens(
        uint256 _amountOut,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external payable override ensure(_deadline) {
        if (_tokenPath[0] != IERC20(wavax)) revert LBRouter__InvalidTokenPath(_tokenPath[0]);

        (address[] memory _pairs, uint256[] memory _amountsIn) = _getPairsAndAmountsIn(
            _amountOut,
            msg.value,
            _pairVersions,
            _tokenPath
        );

        if (msg.value < _amountsIn[0]) revert LBRouter__InsufficientAVAXAmount(_amountsIn[0], msg.value);

        wavax.deposit{value: _amountsIn[0]}();
        wavax.transfer(_pairs[0], _amountsIn[0]);

        _swapTokensForExactTokens(_amountOut, _pairs, _pairVersions, _tokenPath, _amountsIn, _to);

        if (msg.value > _amountsIn[0]) _safeTransferAVAX(_to, _amountsIn[0] - msg.value);
    }

    /// @notice Unstuck tokens that are sent to this contract by mistake
    /// @dev Only callable by the factory owner
    /// @param _token THe address of the token
    /// @param _to The address of the user to send back the tokens
    /// @param _amount The amount to send
    function sweep(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external override onlyFactoryOwner {
        if (address(_token) == address(0)) {
            if (_amount == type(uint256).max) _amount = address(this).balance;
            _safeTransferAVAX(_to, _amount);
        } else {
            if (_amount == type(uint256).max) _amount = _token.balanceOf(address(this));
            _token.safeTransfer(_to, _amount);
        }
    }

    /// @notice Helper function to add liquidity
    /// @param _liq The liquidity parameter
    function _addLiquidity(LiquidityParam memory _liq) private ensure(_liq.deadline) {
        _liq.tokenX.safeTransferFrom(msg.sender, address(_liq.LBPair), _liq.amountX);

        if (_liq.tokenY == IERC20(address(0))) {
            _liq.tokenY = IERC20(wavax);
            _liq.amountY = msg.value;
            wavax.deposit{value: _liq.amountY}();
            wavax.transfer(address(_liq.LBPair), _liq.amountY);
        } else {
            _liq.tokenY.safeTransferFrom(msg.sender, address(_liq.LBPair), _liq.amountY);
        }

        if (_liq.tokenX != _liq.LBPair.tokenX()) {
            (_liq.amountXMin, _liq.amountYMin) = (_liq.amountYMin, _liq.amountXMin);
            (_liq.distributionX, _liq.distributionY) = (_liq.distributionY, _liq.distributionX);
        }

        _verifyLiquidityValues(_liq);

        (uint256 _amountXAdded, uint256 _amountYAdded) = _liq.LBPair.mint(
            _liq.ids,
            _liq.distributionX,
            _liq.distributionY,
            _liq.to
        );

        if (_amountXAdded < _liq.amountXMin || _amountYAdded < _liq.amountYMin)
            revert LBRouter__AmountSlippageCaught(_liq.amountXMin, _amountXAdded, _liq.amountYMin, _amountYAdded);
    }

    /// @notice Helper function to return the amounts in
    /// @param _pairVersions The list of pair version
    /// @param _tokenPath The swap path
    /// @param _pairs The array of pairs
    /// @param _amountOut The amount out
    /// @return The list of amounts in
    function _getAmountsIn(
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address[] memory _pairs,
        uint256 _amountOut
    ) private view returns (uint256[] memory) {
        uint256[] memory _amountsIn = new uint256[](_pairVersions.length);
        // Avoid doing -1, as `_pairs.length == _pairVersions.length-1`
        _amountsIn[_pairs.length] = _amountOut;

        for (uint256 i = _pairs.length; i != 0; i--) {
            IERC20 _token = _tokenPath[i - 1];
            uint256 _version = _pairVersions[i];

            address _pair = _getPair(_version, _token, _tokenPath[i]);
            _pairs[i - 1] = _pair;

            if (_version == 2) {
                _amountsIn[i - 1] = getSwapIn(ILBPair(_pair), _amountsIn[i], ILBPair(_pair).tokenX() == _token);
            } else if (_version == 1) {
                (uint256 _reserveIn, uint256 _reserveOut, ) = IJoePair(_pair).getReserves();
                if (IJoePair(_pair).token1() == address(_token)) {
                    (_reserveIn, _reserveOut) = (_reserveOut, _reserveIn);
                }

                uint256 amountOut = _amountsIn[i];
                // Legacy uniswap way of rounding
                _amountsIn[i - 1] = (_reserveIn * amountOut * 1_000) / (_reserveOut - amountOut * 997) + 1;
            }
        }
        return _amountsIn;
    }

    /// @notice Helper function to verify that the liquidity values are valid
    /// @param _liq The liquidity parameters
    function _verifyLiquidityValues(LiquidityParam memory _liq) private view {
        unchecked {
            if (_liq.deltaIds.length != _liq.distributionX.length && _liq.deltaIds.length != _liq.distributionY.length)
                revert LBRouter__LengthsMismatch();

            if (_liq.activeIdDesired > type(uint24).max && _liq.idSlippage > type(uint24).max)
                revert LBRouter__IdDesiredOverflows(_liq.activeIdDesired, _liq.idSlippage);

            (, , uint256 _activeId) = _liq.LBPair.getReservesAndId();
            if (
                _liq.activeIdDesired + _liq.idSlippage < _activeId || _activeId + _liq.idSlippage < _liq.activeIdDesired
            ) revert LBRouter__IdSlippageCaught(_liq.activeIdDesired, _liq.idSlippage, _activeId);

            for (uint256 i; i < _liq.ids.length; ++i) {
                uint256 _id = uint256(int256(_activeId) + _liq.deltaIds[i]);
                if (_id > type(uint256).max) revert LBRouter__IdOverflows(_id);
                _liq.ids[i] = _id;
            }
        }
    }

    /// @notice Helper function to remove liquidity
    /// @param _LBPair The address of the LBPair
    /// @param _amountXMin The min amount to receive of token X
    /// @param _amountYMin The min amount to receive of token Y
    /// @param _ids The list of ids to burn
    /// @param _amounts The list of amounts to burn of each id in `_ids`
    /// @param _to The address of the recipient
    /// @param amountX The amount of token X sent by the pair
    /// @param amountY The amount of token Y sent by the pair
    function _removeLiquidity(
        ILBPair _LBPair,
        uint256 _amountXMin,
        uint256 _amountYMin,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to
    ) private returns (uint256 amountX, uint256 amountY) {
        ILBToken(address(_LBPair)).safeBatchTransferFrom(msg.sender, address(_LBPair), _ids, _amounts);
        (amountX, amountY) = _LBPair.burn(_ids, _amounts, _to);
        if (amountX < _amountXMin || amountY < _amountYMin)
            revert LBRouter__AmountSlippageCaught(_amountXMin, amountX, _amountYMin, amountY);
    }

    /// @notice Helper function to swap exact tokens for tokens
    /// @param _amountIn The amount of token to send
    /// @param _amountOutMin The min amount of token to receive
    /// @param _pairVersions The versions of the pairs (1: DexV1, 2: dexV2)
    /// @param _tokenPath The swap path using the versions following `_pairVersions`
    /// @param _to The address of the recipient
    function _swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _pair,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to
    ) private returns (uint256) {
        IERC20 _token = _tokenPath[0];
        uint256 _version = _pairVersions[0];
        uint256 _amountOut = _amountIn;
        address _recipient;

        unchecked {
            for (uint256 i; i < _pairVersions.length; ++i) {
                if (i != 0) {
                    _version = _pairVersions[i];
                    _token = _tokenPath[i];
                    _pair = _getPair(_version, _token, _tokenPath[i + 1]);
                }
                _recipient = i != _pairVersions.length - 1 ? _pair : _to;

                if (_version == 2) {
                    bool _isTokenYSent = _token == ILBPair(_pair).tokenY();
                    (uint256 _amountXOut, uint256 _amountYOut) = ILBPair(_pair).swap(_isTokenYSent, _recipient);
                    if (_isTokenYSent) _amountOut = _amountXOut;
                    else _amountOut = _amountYOut;
                } else if (_version == 1) {
                    (uint256 _reserve0, uint256 _reserve1, ) = IJoePair(_pair).getReserves();
                    if (address(_token) == IJoePair(_pair).token0()) {
                        _amountOut = (_reserve1 * _amountOut * 9_97) / (_reserve0 + _amountOut * 1_000);
                        IJoePair(_pair).swap(0, _amountOut, _recipient, "");
                    } else {
                        _amountOut = (_reserve0 * _amountOut * 997) / (_reserve1 + _amountOut * 1_000);
                        IJoePair(_pair).swap(_amountOut, 0, _recipient, "");
                    }
                }
            }
        }
        if (_amountOut < _amountOutMin) revert LBRouter__InsufficientAmountOut(_amountOutMin, _amountOut);
        return _amountOut;
    }

    /// @notice Helper function to swap tokens for exact tokens
    /// @param _amountOut The amount of token to receive
    /// @param _pairs The array of pairs
    /// @param _pairVersions The versions of each pair (1: DexV1, 2: dexV2)
    /// @param _tokenPath The swap path using the versions following `_pairVersions`
    /// @param _amountsIn The list of amounts in
    /// @param _to The address of the recipient
    function _swapTokensForExactTokens(
        uint256 _amountOut,
        address[] memory _pairs,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        uint256[] memory _amountsIn,
        address _to
    ) private returns (uint256) {
        IERC20 _token = _tokenPath[0];
        uint256 _version = _pairVersions[0];
        address _pair = _pairs[0];
        address _recipient;

        unchecked {
            for (uint256 i; i < _pairs.length; ++i) {
                _version = _pairVersions[i];
                _token = _tokenPath[i];
                _pair = _pairs[i];

                _recipient = i != _pairVersions.length - 1 ? _pair : _to;

                if (_version == 2) {
                    (uint256 _amountXOut, uint256 _amountYOut) = ILBPair(_pair).swap(
                        _token == ILBPair(_pair).tokenY(),
                        _recipient
                    );
                    // if final iteration
                    if (_recipient == _to) {
                        if (_amountXOut < _amountOut && _amountYOut < _amountOut)
                            revert LBRouter__InsufficientAmountOut(
                                _amountOut,
                                _amountXOut == 0 ? _amountYOut : _amountXOut
                            );
                        return _amountXOut == 0 ? _amountYOut : _amountXOut;
                    }
                } else if (_version == 1) {
                    if (_token < _tokenPath[i + 1]) {
                        IJoePair(_pair).swap(0, _amountsIn[i], _recipient, "");
                    } else {
                        IJoePair(_pair).swap(_amountsIn[i], 0, _recipient, "");
                    }
                }
            }
        }
        return _amountsIn[_amountsIn.length - 1];
    }

    /// @notice Helper function to return the pairs and amounts in
    /// @param _amountOut The amount of token to receive
    /// @param _amountInMax The max amount of token to send
    /// @param _pairVersions The versions of the pairs (1: DexV1, 2: dexV2)
    /// @param _tokenPath The swap path using the versions following `_pairVersions`
    function _getPairsAndAmountsIn(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath
    ) private view returns (address[] memory, uint256[] memory) {
        if (_pairVersions.length + 1 != _tokenPath.length || _pairVersions.length == 0)
            revert LBRouter__LengthsMismatch();
        if (_amountOut > type(uint112).max) revert LBRouter__AmountOutOverflows(_amountOut);

        address[] memory _pairs = new address[](_pairVersions.length);
        uint256[] memory _amountsIn = _getAmountsIn(_pairVersions, _tokenPath, _pairs, _amountOut);

        if (_amountsIn[0] > _amountInMax) revert LBRouter__MaxAmountInExceeded(_amountInMax, _amountsIn[0]);
        return (_pairs, _amountsIn);
    }

    /// @notice Helper function to return the address of the LBPair
    /// @dev Revert if the pair is not created yet
    /// @param _tokenX The address of the tokenX
    /// @param _tokenY The address of the tokenY
    /// @return _LBPair The address of the LBPair
    function _getLBPair(IERC20 _tokenX, IERC20 _tokenY) private view returns (ILBPair _LBPair) {
        _LBPair = factory.getLBPair(_tokenX, _tokenY);
        if (address(_LBPair) == address(0)) revert LBRouter__PairNotCreated(2, _tokenX, _tokenY);
    }

    /// @notice Helper function to return the address of the pair (v1 or v2, according to `_version`)
    /// @dev Revert if the pair is not created yet
    /// @param _version The version of the pair (1 for v1, 2 for v2)
    /// @param _tokenX The address of the tokenX
    /// @param _tokenY The address of the tokenY
    /// @return _pair The address of the pair of version `_version`
    function _getPair(
        uint256 _version,
        IERC20 _tokenX,
        IERC20 _tokenY
    ) private view returns (address _pair) {
        if (_version == 2) _pair = address(factory.getLBPair(_tokenX, _tokenY));
        else if (_version == 1) _pair = oldFactory.getPair(address(_tokenX), address(_tokenY));

        if (_pair == address(0)) revert LBRouter__PairNotCreated(_version, _tokenX, _tokenY);
    }

    /// @notice Helper function to return the min amount calculate using the slippage
    /// @param _amount The amount of token
    /// @param _amountSlippageBP The slippage amount in basis point (1 is 0.01%, 10_000 is 100%)
    /// @return The min amount calculated (rounded down)
    function _getMinAmount(uint256 _amount, uint256 _amountSlippageBP) private pure returns (uint256) {
        if (_amountSlippageBP > Constants.BASIS_POINT_MAX) revert LBRouter__AmountSlippageBPTooBig(_amountSlippageBP);
        return (_amount * _amountSlippageBP) / Constants.BASIS_POINT_MAX;
    }

    /// @notice Helper function to transfer AVAX
    /// @param _to The address of the recipient
    /// @param _amount The AVAX amount to send
    function _safeTransferAVAX(address _to, uint256 _amount) private {
        (bool success, ) = _to.call{value: _amount}("");
        if (!success) revert LBRouter__FailedToSendAVAX(_to, _amount);
    }
}
