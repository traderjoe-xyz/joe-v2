// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ILBPair.sol";
import "./interfaces/ILBToken.sol";
import "./interfaces/IJoePair.sol";
import "./interfaces/ILBFactory.sol";
import "./interfaces/IWAVAX.sol";
import "./interfaces/ILBRouter.sol";
import "./interfaces/IJoeFactory.sol";
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
error LBRouter__AmountSlippageTooBig(uint256 amountSlippage);
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

    ILBFactory public immutable factory;
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
        ILBPair.PairInformation memory _pair = _LBPair.pairInformation();

        if (_amountOut == 0 || (_swapForY ? _amountOut > _pair.reserveY : _amountOut > _pair.reserveX))
            revert LBRouter__WrongAmounts(_amountOut, _swapForY ? _pair.reserveY : _pair.reserveX); // If this is wrong, then we're sure the amounts sent are wrong

        FeeHelper.FeeParameters memory _fp = _LBPair.feeParameters();
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.activeId;

        uint256 _amountOutOfBin;
        uint256 _amountInWithFees;
        uint256 _reserve;
        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            {
                (uint256 _reserveX, uint256 _reserveY) = _LBPair.getBin(_pair.activeId);
                _reserve = _swapForY ? _reserveY : _reserveX;
            }
            uint256 _price = BinHelper.getPriceFromId(_pair.activeId, _fp.binStep);
            if (_reserve != 0) {
                _amountOutOfBin = _amountOut > _reserve ? _reserve : _amountOut;

                uint256 _amountInToBin = _swapForY
                    ? Constants.SCALE.mulDivRoundUp(_amountOutOfBin, _price)
                    : _price.mulDivRoundUp(_amountOutOfBin, Constants.SCALE);

                _amountInWithFees =
                    _amountInToBin +
                    _fp.getFees(
                        _amountInToBin,
                        _startId > _pair.activeId ? _startId - _pair.activeId : _pair.activeId - _startId
                    );

                if (_amountInWithFees + _reserve > type(uint112).max) revert LBRouter__SwapOverflows(_pair.activeId);
                amountIn += _amountInWithFees;
                _amountOut -= _amountOutOfBin;
            }

            if (_amountOut != 0) {
                _pair.activeId = uint24(_LBPair.findFirstBin(_pair.activeId, _swapForY));
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

        uint256 _startId = _pair.activeId;

        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
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
                _pair.activeId = uint24(_LBPair.findFirstBin(_pair.activeId, _swapForY));
            } else {
                break;
            }
        }
        if (_amountIn != 0) revert LBRouter__TooMuchTokensIn(_amountIn);
    }

    function createLBPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _activeId,
        uint168 _maxAccumulator,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint16 _binStep,
        uint16 _baseFactor,
        uint16 _protocolShare
    ) external {
        factory.createLBPair(
            _tokenX,
            _tokenY,
            _activeId,
            _maxAccumulator,
            _filterPeriod,
            _decayPeriod,
            _binStep,
            _baseFactor,
            _protocolShare
        );
    }

    struct LiquidityStruct {
        IERC20 tokenX;
        IERC20 tokenY;
        ILBPair LBPair;
        uint256 amountX;
        uint256 amountY;
        uint256 amountXMin;
        uint256 amountYMin;
        uint256 activeIdDesired;
        uint256 idSlippage;
        int256[] deltaIds;
        uint256[] ids;
        uint256[] distributionX;
        uint256[] distributionY;
        address to;
        uint256 deadline;
    }

    function addLiquidity(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _amountX,
        uint256 _amountY,
        uint256 _amountSlippage,
        uint256 _activeIdDesired,
        uint256 _idSlippage,
        int256[] memory _deltaIds,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        address _to,
        uint256 _deadline
    ) external {
        LiquidityStruct memory _liq = LiquidityStruct(
            _tokenX,
            _tokenY,
            _getLBPair(_tokenX, _tokenY),
            _amountX,
            _amountY,
            _getMinAmount(_amountX, _amountSlippage),
            _getMinAmount(_amountY, _amountSlippage),
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

    function addLiquidityAVAX(
        IERC20 _token,
        uint256 _amount,
        uint256 _amountSlippage,
        uint256 _activeIdDesired,
        uint256 _idSlippage,
        int256[] memory _deltaIds,
        uint256[] memory _distributionAVAX,
        uint256[] memory _distributionToken,
        address _to,
        uint256 _deadline
    ) external payable {
        LiquidityStruct memory _liq = LiquidityStruct(
            _token,
            IERC20(address(0)),
            _getLBPair(_token, IERC20(wavax)),
            _amount,
            msg.value,
            _getMinAmount(_amount, _amountSlippage),
            msg.value,
            _activeIdDesired,
            _idSlippage,
            _deltaIds,
            new uint256[](_deltaIds.length),
            _distributionAVAX,
            _distributionToken,
            _to,
            _deadline
        );
        _addLiquidity(_liq);
    }

    function _addLiquidity(LiquidityStruct memory _liq) private ensure(_liq.deadline) {
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

    function removeLiquidity(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _amountXMin,
        uint256 _amountYMin,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) {
        ILBPair _LBPair = _getLBPair(_tokenX, _tokenY);
        if (_tokenX != _LBPair.tokenX()) {
            (_tokenX, _tokenY) = (_tokenY, _tokenX);
            (_amountXMin, _amountYMin) = (_amountYMin, _amountXMin);
        }

        _removeLiquidity(_LBPair, _amountXMin, _amountYMin, _ids, _amounts, _to);
    }

    function removeLiquidityAVAX(
        IERC20 _token,
        uint256 _amountTokenMin,
        uint256 _amountAVAXMin,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) {
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

    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) {
        if (_pairVersions.length != _tokenPath.length || _pairVersions.length < 2) revert LBRouter__LengthsMismatch();
        if (_amountIn > type(uint112).max) revert LBRouter__AmountInOverflows(_amountIn);

        address _pair = _getPair(_pairVersions[0], _tokenPath[0], _tokenPath[1]);

        _tokenPath[0].safeTransferFrom(msg.sender, _pair, _amountIn);

        _swapExactTokensForTokens(_amountIn, _amountOutMin, _pair, _pairVersions, _tokenPath, _to);
    }

    function swapExactTokensForAVAX(
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external payable ensure(_deadline) {
        if (_pairVersions.length != _tokenPath.length || _pairVersions.length < 2) revert LBRouter__LengthsMismatch();
        if (_tokenPath[_tokenPath.length - 1] != IERC20(wavax))
            revert LBRouter__InvalidTokenPath(_tokenPath[_tokenPath.length - 1]);

        address _pair = _getPair(_pairVersions[0], _tokenPath[0], _tokenPath[1]);

        _tokenPath[0].safeTransferFrom(msg.sender, _pair, _amountIn);

        uint256 _amountOut = _swapExactTokensForTokens(
            msg.value,
            _amountOutMin,
            _pair,
            _pairVersions,
            _tokenPath,
            address(this)
        );

        wavax.withdraw(_amountOut);
        _safeTransferAVAX(_to, _amountOut);
    }

    function swapExactAVAXForTokens(
        uint256 _amountOutMin,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external payable ensure(_deadline) {
        if (_pairVersions.length != _tokenPath.length || _pairVersions.length < 2) revert LBRouter__LengthsMismatch();
        if (_tokenPath[0] != IERC20(wavax)) revert LBRouter__InvalidTokenPath(_tokenPath[0]);

        address _pair = _getPair(_pairVersions[0], _tokenPath[0], _tokenPath[1]);

        wavax.deposit{value: msg.value}();
        wavax.transfer(_pair, msg.value);

        _swapExactTokensForTokens(msg.value, _amountOutMin, _pair, _pairVersions, _tokenPath, _to);
    }

    function swapTokensForExactTokens(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) {
        (address[] memory _pairs, uint256[] memory _amountsIn) = _getPairsAndAmountsIn(
            _amountOut,
            _amountInMax,
            _pairVersions,
            _tokenPath
        );

        _tokenPath[0].safeTransferFrom(msg.sender, _pairs[0], _amountsIn[0]);

        _swapTokensForExactTokens(_amountOut, _pairs, _pairVersions, _tokenPath, _amountsIn, _to);
    }

    function swapTokensForExactAVAX(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external ensure(_deadline) {
        if (_tokenPath[_tokenPath.length - 1] != IERC20(wavax))
            revert LBRouter__InvalidTokenPath(_tokenPath[_tokenPath.length - 1]);

        (address[] memory _pairs, uint256[] memory _amountsIn) = _getPairsAndAmountsIn(
            _amountOut,
            _amountInMax,
            _pairVersions,
            _tokenPath
        );

        _tokenPath[0].safeTransferFrom(msg.sender, _pairs[0], _amountsIn[0]);

        uint256 _amountOutReal = _swapTokensForExactTokens(
            _amountOut,
            _pairs,
            _pairVersions,
            _tokenPath,
            _amountsIn,
            address(this)
        );

        if (_amountOutReal < _amountOut) revert LBRouter__InsufficientAmountOut(_amountOut, _amountOutReal);

        wavax.withdraw(_amountOutReal);
        _safeTransferAVAX(_to, _amountOutReal);
    }

    function swapAVAXForExactTokens(
        uint256 _amountOut,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external payable ensure(_deadline) {
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
    ) external onlyFactoryOwner {
        if (address(_token) == address(0)) {
            if (_amount == type(uint256).max) _amount = address(this).balance;
            _safeTransferAVAX(_to, _amount);
        } else {
            if (_amount == type(uint256).max) _amount = _token.balanceOf(address(this));
            _token.safeTransfer(_to, _amount);
        }
    }

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

    function _verifyLiquidityValues(LiquidityStruct memory _liq) private view {
        unchecked {
            if (_liq.deltaIds.length != _liq.distributionX.length && _liq.deltaIds.length != _liq.distributionY.length)
                revert LBRouter__LengthsMismatch();

            if (_liq.activeIdDesired > type(uint24).max && _liq.idSlippage > type(uint24).max)
                revert LBRouter__IdDesiredOverflows(_liq.activeIdDesired, _liq.idSlippage);

            uint256 _activeId = _liq.LBPair.pairInformation().activeId;
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

    function _removeLiquidity(
        ILBPair _LBPair,
        uint256 _amountXMin,
        uint256 _amountYMin,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to
    ) private returns (uint256, uint256) {
        ILBToken(address(_LBPair)).safeBatchTransferFrom(msg.sender, address(_LBPair), _ids, _amounts);
        (uint256 _amountX, uint256 _amountY) = _LBPair.burn(_ids, _amounts, _to);
        if (_amountX < _amountXMin || _amountY < _amountYMin)
            revert LBRouter__AmountSlippageCaught(_amountXMin, _amountX, _amountYMin, _amountY);
        return (_amountX, _amountY);
    }

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
        address _recipient = _pair;
        if (_pairVersions.length == 2) _recipient = _to;

        unchecked {
            for (uint256 i; i < _pairVersions.length - 1; ++i) {
                if (i != 0) {
                    _version = _pairVersions[i];
                    _token = _tokenPath[i];
                    _pair = _getPair(_version, _token, _tokenPath[i + 1]);

                    if (i != _pairVersions.length - 2) _recipient = _pair;
                    else _recipient = _to;
                }

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
        address _recipient = _pair;

        unchecked {
            for (uint256 i; i < _pairs.length; ++i) {
                _version = _pairVersions[i];
                _token = _tokenPath[i];
                _pair = _pairs[i];

                if (i != _pairVersions.length - 2) _recipient = _pair;
                else _recipient = _to;

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

    function _getPairsAndAmountsIn(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath
    ) private view returns (address[] memory, uint256[] memory) {
        if (_pairVersions.length != _tokenPath.length || _pairVersions.length < 2) revert LBRouter__LengthsMismatch();
        if (_amountOut > type(uint112).max) revert LBRouter__AmountOutOverflows(_amountOut);

        address[] memory _pairs = new address[](_pairVersions.length - 1);
        uint256[] memory _amountsIn = _getAmountsIn(_pairVersions, _tokenPath, _pairs, _amountOut);

        if (_amountsIn[0] > _amountInMax) revert LBRouter__MaxAmountInExceeded(_amountInMax, _amountsIn[0]);
        return (_pairs, _amountsIn);
    }

    function _getLBPair(IERC20 _tokenX, IERC20 _tokenY) private view returns (ILBPair _LBPair) {
        _LBPair = factory.getLBPair(_tokenX, _tokenY);
        if (address(_LBPair) == address(0)) revert LBRouter__PairNotCreated(2, _tokenX, _tokenY);
    }

    function _getPair(
        uint256 _version,
        IERC20 _tokenX,
        IERC20 _tokenY
    ) private view returns (address _pair) {
        if (_version == 2) _pair = address(factory.getLBPair(_tokenX, _tokenY));
        else if (_version == 1) _pair = oldFactory.getPair(address(_tokenX), address(_tokenY));

        if (_pair == address(0)) revert LBRouter__PairNotCreated(_version, _tokenX, _tokenY);
    }

    function _getMinAmount(uint256 _amount, uint256 _amountSlippage) private pure returns (uint256) {
        if (_amountSlippage > Constants.BASIS_POINT_MAX) revert LBRouter__AmountSlippageTooBig(_amountSlippage);
        return (_amount * _amountSlippage) / Constants.BASIS_POINT_MAX;
    }

    function _safeTransferAVAX(address _to, uint256 _amount) private {
        (bool success, ) = _to.call{value: _amount}("");
        if (!success) revert LBRouter__FailedToSendAVAX(_to, _amount);
    }
}
