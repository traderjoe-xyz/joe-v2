// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

/** Imports **/

import "./LBToken.sol";
import "./libraries/BinHelper.sol";
import "./libraries/Math512Bits.sol";
import "./libraries/SafeCast.sol";
import "./libraries/SafeMath.sol";
import "./libraries/TreeMath.sol";
import "./libraries/Constants.sol";
import "./libraries/ReentrancyGuard.sol";
import "./libraries/Oracle.sol";
import "./libraries/Decoder.sol";
import "./libraries/SwapHelper.sol";
import "./libraries/TokenHelper.sol";
import "./interfaces/ILBFlashLoanCallback.sol";
import "./interfaces/ILBPair.sol";

/** Errors **/

error LBPair__InsufficientAmounts();
error LBPair__BrokenSwapSafetyCheck();
error LBPair__CompositionFactorFlawed(uint256 id);
error LBPair__InsufficientLiquidityMinted(uint256 id);
error LBPair__InsufficientLiquidityBurned(uint256 id);
error LBPair__WrongLengths();
error LBPair__FlashLoanUnderflow(uint256 expectedBalance, uint256 balance);
error LBPair__OnlyStrictlyIncreasingId();
error LBPair__OnlyFactory();
error LBPair__DistributionsOverflow();
error LBPair__OnlyFeeRecipient(address feeRecipient, address sender);
error LBPair__OracleNotEnoughSample();

/// @title Liquidity Bin Exchange
/// @author Trader Joe
/// @notice Implementation of pair
contract LBPair is LBToken, ReentrancyGuard, ILBPair {
    /** Libraries **/

    using Math512Bits for uint256;
    using TreeMath for mapping(uint256 => uint256)[3];
    using SafeCast for uint256;
    using SafeMath for uint256;
    using TokenHelper for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;
    using SwapHelper for Bin;
    using Decoder for bytes32;
    using Oracle for bytes32[65_536];

    /** Events **/

    event Swap(address indexed sender, address indexed recipient, uint24 indexed _id, uint256 amountX, uint256 amountY);

    event FlashLoan(
        address indexed sender,
        address indexed recipient,
        uint256 amountX,
        uint256 amountY,
        uint256 feesX,
        uint256 feesY
    );

    event Mint(
        address indexed sender,
        address indexed recipient,
        uint256 indexed activeId,
        uint256[] ids,
        uint256[] distributionX,
        uint256[] distributionY,
        uint256 amountX,
        uint256 amountY
    );

    event Burn(address indexed sender, address indexed recipient, uint256[] ids, uint256[] amounts);

    event FeesCollected(address indexed sender, address indexed recipient, uint256 amountX, uint256 amountY);

    event ProtocolFeesCollected(address indexed sender, address indexed recipient, uint256 amountX, uint256 amountY);

    event OracleSizeIncreased(uint256 previousSize, uint256 newSize);

    /** Modifiers **/

    modifier OnlyFactory() {
        if (msg.sender != address(factory)) revert LBPair__OnlyFactory();
        _;
    }

    /** Public immutable variables **/

    IERC20 public immutable override tokenX;
    IERC20 public immutable override tokenY;
    ILBFactory public immutable override factory;

    /** Private variables **/

    PairInformation private _pairInformation;
    FeeHelper.FeeParameters private _feeParameters;
    /// @dev The reserves of tokens for every bin. This is the amount
    /// of tokenY if `id < _pairInformation.activeId`; of tokenX if `id > _pairInformation.activeId`
    /// and a mix of both if `id == _pairInformation.activeId`
    mapping(uint256 => Bin) private _bins;
    /// @dev Tree to find bins with non zero liquidity
    mapping(uint256 => uint256)[3] private _tree;
    /// @dev Mapping from account to user's unclaimed fees.
    mapping(address => Fees) private _unclaimedFees;
    /// @dev Mapping from account to id to user's accruedDebt.
    mapping(address => mapping(uint256 => Debts)) private _accruedDebts;
    /// @dev Oracle array
    bytes32[65_536] private _oracle;

    /** OffSets */

    uint256 private constant _OFFSET_PAIR_RESERVE_X = 24;
    uint256 private constant _OFFSET_PROTOCOL_FEE = 128;
    uint256 private constant _OFFSET_BIN_RESERVE_Y = 112;
    uint256 private constant _OFFSET_VARIABLE_FEE_PARAMETERS = 144;
    uint256 private constant _OFFSET_ORACLE_SAMPLE_LIFETIME = 136;
    uint256 private constant _OFFSET_ORACLE_SIZE = 152;
    uint256 private constant _OFFSET_ORACLE_ACTIVE_SIZE = 168;
    uint256 private constant _OFFSET_ORACLE_LAST_TIMESTAMP = 184;
    uint256 private constant _OFFSET_ORACLE_ID = 224;

    /** Constructor **/

    /// @notice Initialize the parameters
    /// @dev The different parameters needs to be validated very cautiously.
    /// It is highly recommended to never deploy this contract directly, use the factory
    /// as it validates the different parameters
    /// @param _factory The address of the factory.
    /// @param _tokenX The address of the tokenX. Can't be address 0
    /// @param _tokenY The address of the tokenY. Can't be address 0
    /// @param _activeId The active id of the pair
    /// @param _sampleLifetime The lifetime of a sample. It's the min time between 2 oracle's sample
    /// @param _packedFeeParameters The fee parameters packed in a single 256 bits slot
    constructor(
        ILBFactory _factory,
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint24 _activeId,
        uint16 _sampleLifetime,
        bytes32 _packedFeeParameters
    ) LBToken() {
        factory = _factory;
        tokenX = _tokenX;
        tokenY = _tokenY;

        _pairInformation.activeId = _activeId;
        _pairInformation.oracleSampleLifetime = _sampleLifetime;

        _setFeesParameters(_packedFeeParameters);
    }

    /** External View Functions **/

    /// @notice View function to get the reserves and active id
    /// @return reserveX The reserve of asset X
    /// @return reserveY The reserve of asset Y
    /// @return activeId The active id of the pair
    function getReservesAndId()
        external
        view
        override
        returns (
            uint256 reserveX,
            uint256 reserveY,
            uint256 activeId
        )
    {
        return _getReservesAndId();
    }

    /// @notice View function to get the global fees information, the total fees and those for protocol
    /// @dev The fees for users are `total - protocol`
    /// @return feesXTotal The total fees of asset X
    /// @return feesYTotal The total fees of asset Y
    /// @return feesXProtocol The protocol fees of asset X
    /// @return feesYProtocol The protocol fees of asset Y
    function getGlobalFees()
        external
        view
        override
        returns (
            uint256 feesXTotal,
            uint256 feesYTotal,
            uint256 feesXProtocol,
            uint256 feesYProtocol
        )
    {
        uint256 _mask128 = type(uint128).max;
        bytes32 _slotX;
        bytes32 _slotY;
        assembly {
            _slotX := sload(add(_pairInformation.slot, 2))
            _slotY := sload(add(_pairInformation.slot, 3))

            feesXTotal := and(_slotX, _mask128)
            feesYTotal := and(_slotY, _mask128)
        }
        feesXProtocol = _slotX.decode(_mask128, _OFFSET_PROTOCOL_FEE);
        feesYProtocol = _slotY.decode(_mask128, _OFFSET_PROTOCOL_FEE);
    }

    /// @notice View function to get the oracle parameters
    /// @return oracleSampleLifetime The lifetime of a sample, it accumulates information for up to this timestamp
    /// @return oracleSize The size of the oracle (last ids can be empty)
    /// @return oracleActiveSize The active size of the oracle (no empty data)
    /// @return oracleLastTimestamp The timestamp of the creation of the oracle's latest sample
    /// @return oracleId The index of the oracle's latest sample
    /// @return min The min delta time of two samples
    /// @return max The safe max delta time of two samples
    function getOracleParameters()
        external
        view
        override
        returns (
            uint256 oracleSampleLifetime,
            uint256 oracleSize,
            uint256 oracleActiveSize,
            uint256 oracleLastTimestamp,
            uint256 oracleId,
            uint256 min,
            uint256 max
        )
    {
        (oracleSampleLifetime, oracleSize, oracleActiveSize, oracleLastTimestamp, oracleId) = _getOracleParameters();
        min = oracleActiveSize == 0 ? 0 : oracleSampleLifetime;
        max = oracleSampleLifetime * oracleActiveSize;
    }

    /// @notice View function to get the oracle's sample at `_ago` seconds
    /// @dev Return a linearized sample, the weighted average of 2 neighboring samples
    /// @param _ago The number of seconds before the current timestamp
    /// @return cumulativeId The weighted average cumulative id
    /// @return cumulativeVolatilityAccumulated The weighted average cumulative volatility accumulated
    /// @return cumulativeBinCrossed The weighted average cumulative bin crossed
    function getOracleSampleFrom(uint256 _ago)
        external
        view
        override
        returns (
            uint256 cumulativeId,
            uint256 cumulativeVolatilityAccumulated,
            uint256 cumulativeBinCrossed
        )
    {
        unchecked {
            uint256 _lookUpTimestamp = block.timestamp - _ago;
            (, , uint256 _oracleActiveSize, , uint256 _oracleId) = _getOracleParameters();

            uint256 timestamp;
            (timestamp, cumulativeId, cumulativeVolatilityAccumulated, cumulativeBinCrossed) = _oracle.getSampleAt(
                _oracleActiveSize,
                _oracleId,
                _lookUpTimestamp
            );

            if (timestamp < _lookUpTimestamp) {
                FeeHelper.FeeParameters memory _fp = _feeParameters;
                uint256 _activeId = _pairInformation.activeId;
                _fp.updateVariableFeeParameters(_activeId);

                uint256 _deltaT = _lookUpTimestamp - timestamp;

                cumulativeId += _activeId * _deltaT;
                cumulativeVolatilityAccumulated += _fp.volatilityAccumulated * _deltaT;
            }
        }
    }

    /// @notice View function to get the fee parameters
    /// @return The fee parameters
    function feeParameters() external view override returns (FeeHelper.FeeParameters memory) {
        return _feeParameters;
    }

    /// @notice View function to get the first bin that isn't empty, will not be `_id` itself
    /// @param _id The bin id
    /// @param _swapForY Whether you've swapping token X for token Y (true) or token Y for token X (false)
    /// @return The id of the non empty bin
    function findFirstNonEmptyBinId(uint24 _id, bool _swapForY) external view override returns (uint256) {
        return _tree.findFirstBin(_id, _swapForY);
    }

    /// @notice View function to get the bin at `id`
    /// @param _id The bin id
    /// @return reserveX The reserve of tokenX of the bin
    /// @return reserveY The reserve of tokenY of the bin
    function getBin(uint24 _id) external view override returns (uint256 reserveX, uint256 reserveY) {
        uint256 _mask112 = type(uint112).max;
        bytes32 _data;
        // low level read of mapping to only load 1 storage slot
        assembly {
            mstore(0, _id)
            mstore(32, _bins.slot)
            _data := sload(keccak256(0, 64))

            reserveX := and(_data, _mask112)
        }
        reserveY = _data.decode(_mask112, _OFFSET_BIN_RESERVE_Y);
    }

    /// @notice View function to get the pending fees of a user
    /// @dev The array must be strictly increasing to ensure uniqueness
    /// @param _account The address of the user
    /// @param _ids The list of ids
    /// @return fees The unclaimed fees
    function pendingFees(address _account, uint256[] memory _ids) external view override returns (Fees memory fees) {
        unchecked {
            fees = _unclaimedFees[_account];

            uint256 _lastId;
            for (uint256 i; i < _ids.length; ++i) {
                uint256 _id = _ids[i];

                if (_lastId >= _id && i != 0) revert LBPair__OnlyStrictlyIncreasingId();

                uint256 _balance = balanceOf(_account, _id);

                if (_balance != 0) {
                    Bin memory _bin = _bins[_id];

                    _collectFees(fees, _bin, _account, _id, _balance);
                }

                _lastId = _id;
            }
        }
    }

    /** External Functions **/

    /// @notice Performs a low level swap, this needs to be called from a contract which performs important safety checks
    /// @dev Will swap the full amount that this contract received of token X or Y
    /// @param _swapForY whether the token sent was Y (true) or X (false)
    /// @param _to The address of the recipient
    /// @return amountXOut The amount of token X sent to `_to`
    /// @return amountYOut The amount of token Y sent to `_to`
    function swap(bool _swapForY, address _to)
        external
        override
        nonReentrant
        returns (uint256 amountXOut, uint256 amountYOut)
    {
        PairInformation memory _pair = _pairInformation;

        uint256 _amountIn = _swapForY
            ? tokenX.received(_pair.reserveX, _pair.feesX.total)
            : tokenY.received(_pair.reserveY, _pair.feesY.total);

        if (_amountIn == 0) revert LBPair__InsufficientAmounts();

        FeeHelper.FeeParameters memory _fp = _feeParameters;
        _fp.updateVariableFeeParameters(_pair.activeId);
        uint256 _startId = _pair.activeId;

        uint256 _amountOut;
        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            Bin memory _bin = _bins[_pair.activeId];
            if ((!_swapForY && _bin.reserveX != 0) || (_swapForY && _bin.reserveY != 0)) {
                (uint256 _amountInToBin, uint256 _amountOutOfBin, FeeHelper.FeesDistribution memory _fees) = _bin
                    .getAmounts(_fp, _pair.activeId, _swapForY, _amountIn);

                _bin.updateFees(_swapForY ? _pair.feesX : _pair.feesY, _fees, _swapForY, totalSupply(_pair.activeId));

                _bin.updateReserves(_pair, _swapForY, _amountInToBin.safe112(), _amountOutOfBin);

                _amountIn -= _amountInToBin + _fees.total;
                _amountOut += _amountOutOfBin;

                _bins[_pair.activeId] = _bin;
            }

            if (_amountIn != 0) {
                _pair.activeId = uint24(_tree.findFirstBin(_pair.activeId, _swapForY));
            } else {
                break;
            }
        }

        if (_amountOut == 0) revert LBPair__BrokenSwapSafetyCheck(); // Safety check
        unchecked {
            // We use oracleSize so it can start filling empty slot that were added recently
            uint256 _updatedOracleId = _oracle.update(
                _pair.oracleSize,
                _pair.oracleSampleLifetime,
                _pair.oracleLastTimestamp,
                _pair.oracleId,
                _pair.activeId,
                _fp.volatilityAccumulated,
                _startId.absSub(_pair.activeId)
            );

            // We update the oracleId and lastTimestamp if the sample write on another slot
            if (_updatedOracleId != _pair.oracleId || _pair.oracleLastTimestamp == 0) {
                _pair.oracleId = uint24(_updatedOracleId);
                _pair.oracleLastTimestamp = block.timestamp.safe40();

                // We increase the activeSize if the updated sample is written in a new slot
                if (_updatedOracleId == _pair.oracleActiveSize) _pair.oracleActiveSize += 1;
            }
        }

        _feeParameters = _fp;
        _pairInformation = _pair;

        if (_swapForY) {
            amountYOut = _amountOut;
            tokenY.safeTransfer(_to, _amountOut);
        } else {
            amountXOut = _amountOut;
            tokenX.safeTransfer(_to, _amountOut);
        }

        emit Swap(msg.sender, _to, _pair.activeId, amountXOut, amountYOut);
    }

    /// @notice Performs a flash loan
    /// @param _to the address that will execute the external call
    /// @param _amountXOut The amount of tokenX
    /// @param _amountYOut The amount of tokenY
    /// @param _data The bytes data that will be forwarded to _to
    function flashLoan(
        address _to,
        uint256 _amountXOut,
        uint256 _amountYOut,
        bytes calldata _data
    ) external override nonReentrant {
        FeeHelper.FeeParameters memory _fp = _feeParameters;

        uint256 _fee = factory.flashLoanFee();

        FeeHelper.FeesDistribution memory _feesX = _fp.getFeesDistribution(_fp.getFlashLoanFee(_amountXOut, _fee));
        FeeHelper.FeesDistribution memory _feesY = _fp.getFeesDistribution(_fp.getFlashLoanFee(_amountYOut, _fee));

        (uint256 _reserveX, uint256 _reserveY, uint256 _id) = _getReservesAndId();

        tokenX.safeTransfer(_to, _amountXOut);
        tokenY.safeTransfer(_to, _amountYOut);

        ILBFlashLoanCallback(msg.sender).LBFlashLoanCallback(_feesX.total, _feesY.total, _data);

        _flashLoanHelper(_pairInformation.feesX, _feesX, tokenX, _reserveX);
        _flashLoanHelper(_pairInformation.feesY, _feesY, tokenY, _reserveY);

        uint256 _totalSupply = totalSupply(_id);

        _bins[_id].accTokenXPerShare +=
            ((uint256(_feesX.total) - _feesX.protocol) << Constants.SCALE_OFFSET) /
            _totalSupply;
        _bins[_id].accTokenYPerShare +=
            ((uint256(_feesY.total) - _feesY.protocol) << Constants.SCALE_OFFSET) /
            _totalSupply;

        emit FlashLoan(msg.sender, _to, _amountXOut, _amountYOut, _feesX.total, _feesY.total);
    }

    /// @notice Performs a low level add, this needs to be called from a contract which performs important safety checks.
    /// @param _ids The list of ids to add liquidity
    /// @param _distributionX The distribution of tokenX with sum(_distributionX) = 1e18 (100%) or 0 (0%)
    /// @param _distributionY The distribution of tokenY with sum(_distributionY) = 1e18 (100%) or 0 (0%)
    /// @param _to The address of the recipient
    /// @return The amount of token X that was added to the pair
    /// @return The amount of token Y that was added to the pair
    function mint(
        uint256[] memory _ids,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        address _to
    )
        external
        override
        nonReentrant
        returns (
            uint256,
            uint256,
            uint256[] memory liquidityMinted
        )
    {
        unchecked {
            if (_ids.length == 0 || _ids.length != _distributionX.length || _ids.length != _distributionY.length)
                revert LBPair__WrongLengths();

            PairInformation memory _pair = _pairInformation;

            FeeHelper.FeeParameters memory _fp = _feeParameters;

            MintInfo memory _mintInfo;

            _mintInfo.amountXIn = tokenX.received(_pair.reserveX, _pair.feesX.total).safe128();
            _mintInfo.amountYIn = tokenY.received(_pair.reserveY, _pair.feesY.total).safe128();

            liquidityMinted = new uint256[](_ids.length);

            for (uint256 i; i < _ids.length; ++i) {
                _mintInfo.id = _ids[i].safe24();
                Bin memory _bin = _bins[_mintInfo.id];

                if (_bin.reserveX == 0 && _bin.reserveY == 0) {
                    // add 1 at the right indices if the _pairInformation was empty
                    uint256 _idDepth2 = _mintInfo.id / 256;
                    uint256 _idDepth1 = _mintInfo.id / 65_536;

                    _tree[2][_idDepth2] |= 1 << (_mintInfo.id % 256);
                    _tree[1][_idDepth1] |= 1 << (_idDepth2 % 256);
                    _tree[0][0] |= 1 << _idDepth1;
                }

                {
                    uint256 _distribX = _distributionX[i];
                    uint256 _distribY = _distributionY[i];

                    if (
                        _distribX > Constants.PRECISION ||
                        _distribY > Constants.PRECISION ||
                        (_mintInfo.totalDistributionX += _distribX) > Constants.PRECISION ||
                        (_mintInfo.totalDistributionY += _distribY) > Constants.PRECISION
                    ) revert LBPair__DistributionsOverflow();

                    _mintInfo.amountX = (_mintInfo.amountXIn * _distribX) / Constants.PRECISION;
                    _mintInfo.amountY = (_mintInfo.amountYIn * _distribY) / Constants.PRECISION;
                }

                uint256 _price = BinHelper.getPriceFromId(_mintInfo.id, _fp.binStep);
                if (_mintInfo.id >= _pair.activeId) {
                    if (_mintInfo.id == _pair.activeId) {
                        uint256 _totalSupply = totalSupply(_mintInfo.id);

                        uint256 _userL = _price.mulShift(_mintInfo.amountX, Constants.SCALE_OFFSET, true) +
                            _mintInfo.amountY;

                        uint256 _receivedX = (_userL * (_bin.reserveX + _mintInfo.amountX)) / (_totalSupply + _userL);
                        uint256 _receivedY = (_userL * (_bin.reserveY + _mintInfo.amountY)) / (_totalSupply + _userL);

                        _fp.updateVariableFeeParameters(_mintInfo.id);

                        if (_mintInfo.amountX > _receivedX) {
                            FeeHelper.FeesDistribution memory _fees = _fp.getFeesDistribution(
                                _fp.getFeesForC(_mintInfo.amountX - _receivedX)
                            );

                            _mintInfo.amountX -= _fees.total;

                            _bin.updateFees(_pair.feesX, _fees, true, _totalSupply);
                        } else if (_mintInfo.amountY > _receivedY) {
                            FeeHelper.FeesDistribution memory _fees = _fp.getFeesDistribution(
                                _fp.getFeesForC(_mintInfo.amountY - _receivedY)
                            );

                            _mintInfo.amountY -= _fees.total;

                            _bin.updateFees(_pair.feesY, _fees, false, _totalSupply);
                        }
                    } else if (_mintInfo.amountY != 0) revert LBPair__CompositionFactorFlawed(_mintInfo.id);
                } else if (_mintInfo.amountX != 0) revert LBPair__CompositionFactorFlawed(_mintInfo.id);

                liquidityMinted[i] =
                    _price.mulShift(_mintInfo.amountX, Constants.SCALE_OFFSET, true) +
                    _mintInfo.amountY;

                if (liquidityMinted[i] == 0) revert LBPair__InsufficientLiquidityMinted(_mintInfo.id);

                _bin.reserveX = (_bin.reserveX + _mintInfo.amountX).safe112();
                _bin.reserveY = (_bin.reserveY + _mintInfo.amountY).safe112();

                _pair.reserveX += uint136(_mintInfo.amountX);
                _pair.reserveY += uint136(_mintInfo.amountY);

                _mintInfo.amountXAddedToPair += _mintInfo.amountX;
                _mintInfo.amountYAddedToPair += _mintInfo.amountY;

                _bins[_mintInfo.id] = _bin;
                _mint(_to, _mintInfo.id, liquidityMinted[i]);
            }

            _pairInformation = _pair;

            // If user sent too much tokens, We send them back the excess
            if (_mintInfo.amountXIn > _mintInfo.amountXAddedToPair) {
                tokenX.safeTransfer(_to, _mintInfo.amountXIn - _mintInfo.amountXAddedToPair);
            }
            if (_mintInfo.amountYIn > _mintInfo.amountYAddedToPair) {
                tokenY.safeTransfer(_to, _mintInfo.amountYIn - _mintInfo.amountYAddedToPair);
            }

            emit Mint(
                msg.sender,
                _to,
                _pair.activeId,
                _ids,
                _distributionX,
                _distributionY,
                _mintInfo.amountXAddedToPair,
                _mintInfo.amountYAddedToPair
            );

            return (_mintInfo.amountXAddedToPair, _mintInfo.amountYAddedToPair, liquidityMinted);
        }
    }

    /// @notice Performs a low level remove, this needs to be called from a contract which performs important safety checks
    /// @param _ids The ids the user want to remove its liquidity
    /// @param _amounts The amount of token to burn
    /// @param _to The address of the recipient
    /// @return amountX The amount of token X sent to `_to`
    /// @return amountY The amount of token Y sent to `_to`
    function burn(
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to
    ) external override nonReentrant returns (uint256 amountX, uint256 amountY) {
        unchecked {
            PairInformation memory _pair = _pairInformation;

            for (uint256 i; i < _ids.length; ++i) {
                uint256 _id = _ids[i].safe24();
                uint256 _amountToBurn = _amounts[i];

                if (_amountToBurn == 0) revert LBPair__InsufficientLiquidityBurned(_id);

                Bin memory _bin = _bins[_id];

                uint256 _totalSupply = totalSupply(_id);

                if (_id <= _pair.activeId) {
                    uint256 _amountY = _amountToBurn.mulDivRoundDown(_bin.reserveY, _totalSupply);

                    amountY += _amountY;
                    _bin.reserveY -= uint112(_amountY);
                    _pair.reserveY -= uint136(_amountY);
                }
                if (_id >= _pair.activeId) {
                    uint256 _amountX = _amountToBurn.mulDivRoundDown(_bin.reserveX, _totalSupply);

                    amountX += _amountX;
                    _bin.reserveX -= uint112(_amountX);
                    _pair.reserveX -= uint136(_amountX);
                }

                if (_bin.reserveX == 0 && _bin.reserveY == 0) {
                    // removes 1 at the right indices
                    uint256 _idDepth2 = _id / 256;
                    uint256 _newLeafValue = _tree[2][_idDepth2] & (type(uint256).max - (1 << (_id % 256)));
                    _tree[2][_idDepth2] = _newLeafValue;
                    if (_newLeafValue == 0) {
                        uint256 _idDepth1 = _id / 65_536;
                        _newLeafValue = _tree[1][_idDepth1] & (type(uint256).max - (1 << (_idDepth2 % 256)));
                        _tree[1][_idDepth1] = _newLeafValue;
                        if (_newLeafValue == 0) {
                            _tree[0][0] &= type(uint256).max - (1 << _idDepth1);
                        }
                    }
                }

                _bins[_id] = _bin;
                _burn(address(this), _id, _amountToBurn);
            }

            _pairInformation = _pair;

            tokenX.safeTransfer(_to, amountX);
            tokenY.safeTransfer(_to, amountY);

            emit Burn(msg.sender, _to, _ids, _amounts);
        }
    }

    /// @notice Increase the length of the oracle
    /// @param _nb The number of sample to add to the oracle
    function increaseOracleLength(uint16 _nb) external override {
        _increaseOracle(_nb);
    }

    /// @notice Collect fees of an user
    /// @param _account The address of the user
    /// @param _ids The list of bin ids to collect fees in
    function collectFees(address _account, uint256[] memory _ids)
        external
        override
        nonReentrant
        returns (Fees memory fees)
    {
        unchecked {
            fees = _unclaimedFees[_account];
            delete _unclaimedFees[_account];

            for (uint256 i; i < _ids.length; ++i) {
                uint256 _id = _ids[i];
                uint256 _balance = balanceOf(_account, _id);

                if (_balance != 0) {
                    Bin memory _bin = _bins[_id];

                    _collectFees(fees, _bin, _account, _id, _balance);
                    _updateUserDebts(_bin, _account, _id, _balance);
                }
            }

            if (fees.tokenX != 0) {
                _pairInformation.feesX.total -= fees.tokenX;
            }
            if (fees.tokenY != 0) {
                _pairInformation.feesY.total -= fees.tokenY;
            }

            tokenX.safeTransfer(_account, fees.tokenX);
            tokenY.safeTransfer(_account, fees.tokenY);

            emit FeesCollected(msg.sender, _account, fees.tokenX, fees.tokenY);
        }
    }

    /// @notice Collect the protocol fees and send them to the feeRecipient
    /// @dev The balances are not zeroed to save gas by not resetting the storage slot
    /// Only callable by the fee recipient
    function collectProtocolFees() external override nonReentrant returns (Fees memory fees) {
        unchecked {
            address _feeRecipient = factory.feeRecipient();

            if (msg.sender != _feeRecipient) revert LBPair__OnlyFeeRecipient(_feeRecipient, msg.sender);

            FeeHelper.FeesDistribution memory _fees = _pairInformation.feesX;
            if (_fees.protocol != 0) {
                fees.tokenX = _fees.protocol - 1;
                _fees.total -= fees.tokenX;
                _fees.protocol = 1;
                _pairInformation.feesX = _fees;
            }

            _fees = _pairInformation.feesY;
            if (_fees.protocol != 0) {
                fees.tokenY = _fees.protocol - 1;
                _fees.total -= fees.tokenY;
                _fees.protocol = 1;
                _pairInformation.feesY = _fees;
            }

            tokenX.safeTransfer(_feeRecipient, fees.tokenX);
            tokenY.safeTransfer(_feeRecipient, fees.tokenY);

            emit ProtocolFeesCollected(msg.sender, _feeRecipient, fees.tokenX, fees.tokenY);
        }
    }

    /// @notice Set the fees parameters
    /// @dev Needs to be called by the factory that will validate the values
    /// The bin step will not change
    /// Only callable by the factory
    /// @param _packedFeeParameters The packed fee parameters
    function setFeesParameters(bytes32 _packedFeeParameters) external override OnlyFactory {
        _setFeesParameters(_packedFeeParameters);
    }

    function forceDecay() external override OnlyFactory {
        unchecked {
            _feeParameters.volatilityReference = uint24(
                (uint256(_feeParameters.reductionFactor) * _feeParameters.volatilityReference) /
                    Constants.BASIS_POINT_MAX
            );
        }
    }

    /** Internal Functions **/

    /// @notice Collect and update fees before any token transfer, mint or burn
    /// @param _from The address of the owner of the token
    /// @param _to The address of the recipient of the  token
    /// @param _id The id of the token
    /// @param _amount The amount of token of type `id`
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount
    ) internal override(LBToken) {
        unchecked {
            super._beforeTokenTransfer(_from, _to, _id, _amount);

            Bin memory _bin = _bins[_id];

            if (_from != address(0) && _from != address(this)) {
                uint256 _balanceFrom = balanceOf(_from, _id);

                _cacheFees(_bin, _from, _id, _balanceFrom, _balanceFrom - _amount);
            }

            if (_to != address(0) && _to != address(this) && _to != _from) {
                uint256 _balanceTo = balanceOf(_to, _id);

                _cacheFees(_bin, _to, _id, _balanceTo, _balanceTo + _amount);
            }
        }
    }

    /** Private Functions **/

    /// @notice View function to collect fees of a given bin to memory
    /// @param _fees The user's unclaimed fees
    /// @param _bin  The bin where the user is collecting fees
    /// @param _account The address of the user
    /// @param _id The id where the user is collecting fees
    /// @param _balance The previous balance of the user
    function _collectFees(
        Fees memory _fees,
        Bin memory _bin,
        address _account,
        uint256 _id,
        uint256 _balance
    ) private view {
        Debts memory _debts = _accruedDebts[_account][_id];

        _fees.tokenX += (_bin.accTokenXPerShare.mulShift(_balance, Constants.SCALE_OFFSET, true) - _debts.debtX)
            .safe128();

        _fees.tokenY += (_bin.accTokenYPerShare.mulShift(_balance, Constants.SCALE_OFFSET, true) - _debts.debtY)
            .safe128();
    }

    /// @notice Update fees of a given user
    /// @param _bin The bin where the user has collected fees
    /// @param _account The address of the user
    /// @param _id The id where the user has collected fees
    /// @param _balance The new balance of the user
    function _updateUserDebts(
        Bin memory _bin,
        address _account,
        uint256 _id,
        uint256 _balance
    ) private {
        uint256 _debtX = _bin.accTokenXPerShare.mulShift(_balance, Constants.SCALE_OFFSET, true);
        uint256 _debtY = _bin.accTokenYPerShare.mulShift(_balance, Constants.SCALE_OFFSET, true);

        _accruedDebts[_account][_id].debtX = _debtX;
        _accruedDebts[_account][_id].debtY = _debtY;
    }

    /// @notice Update the unclaimed fees of a given user before a transfer
    /// @param _bin The bin where the user has collected fees
    /// @param _user The address of the user
    /// @param _id The id where the user has collected fees
    /// @param _previousBalance The previous balance of the user
    /// @param _newBalance The new balance of the user
    function _cacheFees(
        Bin memory _bin,
        address _user,
        uint256 _id,
        uint256 _previousBalance,
        uint256 _newBalance
    ) private {
        Fees memory _fees = _unclaimedFees[_user];

        _collectFees(_fees, _bin, _user, _id, _previousBalance);
        _updateUserDebts(_bin, _user, _id, _newBalance);

        _unclaimedFees[_user] = _fees;
    }

    /// @notice Checks that the flash loan was done accordingly
    /// @param _pairFees The fees of the pair
    /// @param _fees The fees received by the pair
    /// @param _token The address of the token received
    /// @param _reserve The stored reserve of the current bin
    function _flashLoanHelper(
        FeeHelper.FeesDistribution storage _pairFees,
        FeeHelper.FeesDistribution memory _fees,
        IERC20 _token,
        uint256 _reserve
    ) private {
        uint128 _totalFees = _pairFees.total;
        uint256 _amountReceived = _token.received(_reserve, _totalFees);

        if (_fees.total > _amountReceived) revert LBPair__FlashLoanUnderflow(_fees.total, _amountReceived);

        _fees.total = _amountReceived.safe128();

        _pairFees.total = _totalFees + _fees.total;
        // unsafe math is fine because total >= protocol
        unchecked {
            _pairFees.protocol += _fees.protocol;
        }
    }

    /// @notice Internal function to set the fee parameters of the pair
    /// @param _packedFeeParameters The packed fee parameters
    function _setFeesParameters(bytes32 _packedFeeParameters) internal {
        uint256 _mask112 = type(uint112).max;
        uint256 _mask144 = type(uint144).max;
        assembly {
            let variableParameters := and(sload(_feeParameters.slot), shl(_OFFSET_VARIABLE_FEE_PARAMETERS, _mask112))
            let parameters := add(variableParameters, and(_packedFeeParameters, _mask144))
            sstore(_feeParameters.slot, parameters)
        }
    }

    /// @notice Private function to increase the oracle's number of sample
    /// @param _nb The number of sample to add to the oracle
    function _increaseOracle(uint16 _nb) private {
        unchecked {
            uint256 _oracleSize = _pairInformation.oracleSize;
            uint256 _newSize = _oracleSize + uint256(_nb);

            _pairInformation.oracleSize = uint16(_newSize);
            for (uint256 _id = _oracleSize; _id < _newSize; ++_id) {
                _oracle.initialize(_id);
            }
            emit OracleSizeIncreased(_oracleSize, _newSize);
        }
    }

    /// @notice Private view function to return the oracle's parameters
    /// @return oracleSampleLifetime The lifetime of a sample, it accumulates information for up to this timestamp
    /// @return oracleSize The size of the oracle (last ids can be empty)
    /// @return oracleActiveSize The active size of the oracle (no empty data)
    /// @return oracleLastTimestamp The timestamp of the creation of the oracle's latest sample
    /// @return oracleId The index of the oracle's latest sample
    function _getOracleParameters()
        internal
        view
        returns (
            uint256 oracleSampleLifetime,
            uint256 oracleSize,
            uint256 oracleActiveSize,
            uint256 oracleLastTimestamp,
            uint256 oracleId
        )
    {
        bytes32 _slot;
        assembly {
            _slot := sload(add(_pairInformation.slot, 1))
        }
        oracleSampleLifetime = _slot.decode(type(uint16).max, _OFFSET_ORACLE_SAMPLE_LIFETIME);
        oracleSize = _slot.decode(type(uint16).max, _OFFSET_ORACLE_SIZE);
        oracleActiveSize = _slot.decode(type(uint16).max, _OFFSET_ORACLE_ACTIVE_SIZE);
        oracleLastTimestamp = _slot.decode(type(uint40).max, _OFFSET_ORACLE_LAST_TIMESTAMP);
        oracleId = _slot.decode(type(uint24).max, _OFFSET_ORACLE_ID);
    }

    /// @notice Internal view function to get the reserves and active id
    /// @return reserveX The reserve of asset X
    /// @return reserveY The reserve of asset Y
    /// @return activeId The active id of the pair
    function _getReservesAndId()
        internal
        view
        returns (
            uint256 reserveX,
            uint256 reserveY,
            uint256 activeId
        )
    {
        uint256 _mask24 = type(uint24).max;
        uint256 _mask136 = type(uint136).max;
        bytes32 _slot;
        assembly {
            _slot := sload(add(_pairInformation.slot, 1))
            reserveY := and(_slot, _mask136)

            _slot := sload(_pairInformation.slot)
            activeId := and(_slot, _mask24)
        }
        reserveX = _slot.decode(_mask136, _OFFSET_PAIR_RESERVE_X);
    }
}
