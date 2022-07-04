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
import "./libraries/SwapHelper.sol";
import "./libraries/Constants.sol";

error LBRouter__SenderIsNotWAVAX();
error LBRouter__LBPairNotCreated(IERC20 tokenX, IERC20 tokenY);
error LBRouter__WrongAmounts(uint256 amount, uint256 reserve);
error LBRouter__SwapOverflows(uint256 id);
error LBRouter__BrokenSwapSafetyCheck();
error LBRouter__NotFactoryOwner();
error LBRouter__TooMuchTokensIn(uint256 excess);
error LBRouter__BinReserveOverflows(uint256 id);
error LBRouter__IdOverflows(uint256 id);
error LBRouter__LengthsMismatch();
error LBRouter__IdSlippageCaught(
    uint256 activeIdDesired,
    uint256 idSlippage,
    uint256 activeId
);
error LBRouter__AmountSlippageCaught(
    uint256 amountXMin,
    uint256 amountYMin,
    uint256 amountX,
    uint256 amountY,
    uint256 amountSlippage
);
error LBRouter__IdDesiredOverflows(uint256 idDesired, uint256 idSlippage);
error LBRouter__FailedToSendAVAX(address recipient, uint256 amount);
error LBRouter__DeadlineExceeded(uint256 deadline, uint256 currentTimestamp);

contract LBRouter is ILBRouter {
    using SafeERC20 for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;
    using Math512Bits for uint256;
    using SwapHelper for ILBPair.PairInformation;

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

    ///@dev Receive function that only accept AVAX from the WAVAX contract
    receive() external payable {
        if (msg.sender != address(wavax)) revert LBRouter__SenderIsNotWAVAX();
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
        return
            BinHelper.getIdFromPrice(_price, _LBPair.feeParameters().binStep);
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
    ) external view override returns (uint256 amountIn) {
        ILBPair.PairInformation memory _pair = _LBPair.pairInformation();

        if (
            _amountOut == 0 ||
            (
                _swapForY
                    ? _amountOut > _pair.reserveY
                    : _amountOut > _pair.reserveX
            )
        )
            revert LBRouter__WrongAmounts(
                _amountOut,
                _swapForY ? _pair.reserveY : _pair.reserveX
            ); // If this is wrong, then we're sure the amounts sent are wrong

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
                (uint256 _reserveX, uint256 _reserveY) = _LBPair.getBin(
                    _pair.activeId
                );
                _reserve = _swapForY ? _reserveY : _reserveX;
            }
            uint256 _price = BinHelper.getPriceFromId(
                _pair.activeId,
                _fp.binStep
            );
            if (_reserve != 0) {
                _amountOutOfBin = _amountOut > _reserve ? _reserve : _amountOut;

                uint256 _amountInToBin = _swapForY
                    ? Constants.SCALE.mulDivRoundUp(_amountOutOfBin, _price)
                    : _price.mulDivRoundUp(_amountOutOfBin, Constants.SCALE);

                _amountInWithFees =
                    _amountInToBin +
                    _fp.getFees(
                        _amountInToBin,
                        _startId > _pair.activeId
                            ? _startId - _pair.activeId
                            : _pair.activeId - _startId
                    );

                if (_amountInWithFees + _reserve > type(uint112).max)
                    revert LBRouter__SwapOverflows(_pair.activeId);
                amountIn += _amountInWithFees;
                _amountOut -= _amountOutOfBin;
            }

            if (_amountOut != 0) {
                _pair.activeId = uint24(
                    _LBPair.findFirstBin(_pair.activeId, _swapForY)
                );
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
                (uint256 _reserveX, uint256 _reserveY) = _LBPair.getBin(
                    _pair.activeId
                );
                _bin = ILBPair.Bin(
                    uint112(_reserveX),
                    uint112(_reserveY),
                    0,
                    0
                );
            }
            if (_bin.reserveX != 0 || _bin.reserveY != 0) {
                (
                    uint256 _amountInToBin,
                    uint256 _amountOutOfBin,
                    FeeHelper.FeesDistribution memory _fees
                ) = _pair.getAmounts(
                        _bin,
                        _fp,
                        !_swapForY,
                        _startId,
                        _amountIn
                    );

                if (_amountInToBin > type(uint112).max)
                    revert LBRouter__BinReserveOverflows(_pair.activeId);

                _amountIn -= _amountInToBin + _fees.total;
                _amountOut += _amountOutOfBin;
            }

            if (_amountIn != 0) {
                _pair.activeId = uint24(
                    _LBPair.findFirstBin(_pair.activeId, _swapForY)
                );
            } else {
                break;
            }
        }
        if (_amountIn != 0) revert LBRouter__TooMuchTokensIn(_amountIn);
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
            (bool success, ) = _to.call{value: _amount}("");
            if (!success) revert LBRouter__FailedToSendAVAX(_to, _amount);
        } else {
            if (_amount == type(uint256).max)
                _amount = _token.balanceOf(address(this));
            _token.safeTransfer(_to, _amount);
        }
    }

    function createLBPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _id,
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
            _id,
            _maxAccumulator,
            _filterPeriod,
            _decayPeriod,
            _binStep,
            _baseFactor,
            _protocolShare
        );
    }

    function addLiquidity(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _amountXDesired,
        uint256 _amountYDesired,
        uint256 _amountSlippage,
        uint256 _activeIdDesired,
        uint256 _idSlippage,
        int256[] memory _deltaIds,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        address _to,
        uint256 _deadline
    ) external {
        _addLiquidity(
            _tokenX,
            _tokenY,
            _amountXDesired,
            _amountYDesired,
            _amountSlippage,
            _activeIdDesired,
            _idSlippage,
            _deltaIds,
            _distributionX,
            _distributionY,
            _to,
            _deadline
        );
    }

    function addLiquidityAvax(
        IERC20 _token,
        uint256 _amountDesired,
        uint256 _amountSlippage,
        uint256 _activeIdDesired,
        uint256 _idSlippage,
        int256[] memory _deltaIds,
        uint256[] memory _distributionAVAX,
        uint256[] memory _distributionToken,
        address _to,
        uint256 _deadline
    ) external payable {
        wavax.deposit{value: msg.value}();
        _addLiquidity(
            IERC20(wavax),
            _token,
            msg.value,
            _amountDesired,
            _amountSlippage,
            _activeIdDesired,
            _idSlippage,
            _deltaIds,
            _distributionAVAX,
            _distributionToken,
            _to,
            _deadline
        );
    }

    function _addLiquidity(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _amountXDesired,
        uint256 _amountYDesired,
        uint256 _amountSlippage,
        uint256 _activeIdDesired,
        uint256 _idSlippage,
        int256[] memory _deltaIds,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        address _to,
        uint256 _deadline
    ) private {
        (ILBPair _LBPair, uint256[] memory _ids) = _verifyLiquidityValues(
            _tokenX,
            _tokenY,
            _activeIdDesired,
            _idSlippage,
            _deltaIds,
            _distributionX,
            _distributionY,
            _deadline
        );

        _transferAndAddLiquidity(
            _tokenX,
            _tokenY,
            _LBPair,
            _amountXDesired,
            _amountYDesired,
            _amountSlippage,
            _ids,
            _distributionX,
            _distributionY,
            _to
        );
    }

    function _verifyLiquidityValues(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _activeIdDesired,
        uint256 _idSlippage,
        int256[] memory _deltaIds,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        uint256 _deadline
    ) private view returns (ILBPair, uint256[] memory) {
        unchecked {
            if (block.timestamp > _deadline)
                revert LBRouter__DeadlineExceeded(_deadline, block.timestamp);
            if (
                _deltaIds.length != _distributionX.length &&
                _deltaIds.length != _distributionY.length
            ) revert LBRouter__LengthsMismatch();

            ILBPair _LBPair = factory.getLBPair(_tokenX, _tokenY);
            if (address(_LBPair) == address(0))
                revert LBRouter__LBPairNotCreated(_tokenX, _tokenY);

            if (
                _activeIdDesired > type(uint24).max &&
                _idSlippage > type(uint24).max
            )
                revert LBRouter__IdDesiredOverflows(
                    _activeIdDesired,
                    _idSlippage
                );

            uint256 _activeId = _LBPair.pairInformation().activeId;
            if (
                _activeIdDesired + _idSlippage < _activeId ||
                _activeId + _idSlippage < _activeIdDesired
            )
                revert LBRouter__IdSlippageCaught(
                    _activeIdDesired,
                    _idSlippage,
                    _activeId
                );

            uint256[] memory _ids = new uint256[](_deltaIds.length);
            for (uint256 i; i < _ids.length; ++i) {
                uint256 _id = uint256(int256(_activeId) + _deltaIds[i]);
                if (_id > type(uint256).max) revert LBRouter__IdOverflows(_id);
                _ids[i] = _id;
            }
            return (_LBPair, _ids);
        }
    }

    function _transferAndAddLiquidity(
        IERC20 _tokenX,
        IERC20 _tokenY,
        ILBPair _LBPair,
        uint256 _amountXDesired,
        uint256 _amountYDesired,
        uint256 _amountSlippage,
        uint256[] memory _ids,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        address _to
    ) private {
        unchecked {
            _tokenX.transferFrom(msg.sender, address(_LBPair), _amountXDesired);
            _tokenY.transferFrom(msg.sender, address(_LBPair), _amountYDesired);

            (uint256 _amountX, uint256 _amountY) = _LBPair.mint(
                _ids,
                _distributionX,
                _distributionY,
                _to
            );

            if (
                _amountXDesired * _amountSlippage <
                _amountX * Constants.BASIS_POINT_MAX ||
                _amountYDesired * _amountSlippage <
                _amountY * Constants.BASIS_POINT_MAX
            )
                revert LBRouter__AmountSlippageCaught(
                    _amountXDesired,
                    _amountYDesired,
                    _amountX,
                    _amountY,
                    _amountSlippage
                );
        }
    }
}
