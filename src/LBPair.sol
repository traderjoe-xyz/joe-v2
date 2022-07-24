// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

/** Imports **/

import "./LBToken.sol";
import "./libraries/BinHelper.sol";
import "./libraries/Math512Bits.sol";
import "./libraries/SafeCast.sol";
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
error LBPair__BrokenMintSafetyCheck(uint256 totalDistributionX, uint256 totalDistributionY);
error LBPair__InsufficientLiquidityMinted(uint256 id);
error LBPair__InsufficientLiquidityBurned(uint256 id);
error LBPair__WrongLengths();
error LBPair__FlashLoanUnderflow(uint256 expectedBalance, uint256 balance);
error LBPair__OnlyStrictlyIncreasingId();
error LBPair__OnlyFactory();
error LBPair__DistributionOverflow(uint256 id, uint256 distribution);
error LBPair__OnlyFeeRecipient(address feeRecipient, address sender);
error LBPair__OracleNotEnoughSample();

/// @title Liquidity Bin Exchange
/// @author Trader Joe
/// @notice Implemention of pair
contract LBPair is LBToken, ReentrancyGuard, ILBPair {
    /** Libraries **/

    using Math512Bits for uint256;
    using TreeMath for mapping(uint256 => uint256)[3];
    using SafeCast for uint256;
    using TokenHelper for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;
    using SwapHelper for PairInformation;
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

    event ProtocolFeeCollected(address indexed sender, address indexed recipient, uint256 amountX, uint256 amountY);

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
    mapping(address => UnclaimedFees) private _unclaimedFees;
    /// @dev Mapping from account to id to user's accruedDebt.
    mapping(address => mapping(uint256 => Debts)) private _accruedDebts;
    /// @dev Oracle array
    bytes32[65_536] private _oracle;

    /** OffSets */

    uint256 private constant _OFFSET_ACTIVE_ID = 0;
    uint256 private constant _OFFSET_RESERVE_X = 24;
    uint256 private constant _OFFSET_RESERVE_Y = 0;
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
    ) LBToken("Liquidity Book Token", "LBT") {
        factory = _factory;
        tokenX = _tokenX;
        tokenY = _tokenY;

        _pairInformation.activeId = _activeId;
        _pairInformation.oracleSampleLifetime = _sampleLifetime;

        _increaseOracle(2);
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
        bytes32 _slot0;
        bytes32 _slot1;
        assembly {
            _slot0 := sload(_pairInformation.slot)
            _slot1 := sload(add(_pairInformation.slot, 1))
        }
        activeId = _slot0.decode(type(uint24).max, _OFFSET_ACTIVE_ID);
        reserveX = _slot0.decode(type(uint136).max, _OFFSET_RESERVE_X);
        reserveY = _slot1.decode(type(uint136).max, _OFFSET_RESERVE_Y);
    }

    /// @notice View function to get the global fees information, the total fees and those for protocol
    /// @dev The fees for users are `total - protocol`
    /// @return feesX The fees distribution of asset X
    /// @return feesY The fees distribution of asset Y
    function getGlobalFees()
        external
        view
        override
        returns (FeeHelper.FeesDistribution memory feesX, FeeHelper.FeesDistribution memory feesY)
    {
        feesX = _pairInformation.feesX;
        feesY = _pairInformation.feesY;
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
    /// @return cumulativeAccumulator The weighted average cumulative accumulator
    /// @return cumulativeBinCrossed The weighted average cumulative bin crossed
    function getOracleSampleFrom(uint256 _ago)
        external
        view
        override
        returns (
            uint256 cumulativeId,
            uint256 cumulativeAccumulator,
            uint256 cumulativeBinCrossed
        )
    {
        uint256 _lookUpTimestamp = block.timestamp - _ago;

        unchecked {
            (, , uint256 _oracleActiveSize, , uint256 _oracleId) = _getOracleParameters();

            uint256 timestamp;
            (timestamp, cumulativeId, cumulativeAccumulator, cumulativeBinCrossed) = _oracle.getSampleAt(
                _oracleActiveSize,
                _oracleId,
                _lookUpTimestamp
            );

            if (timestamp < _lookUpTimestamp) {
                FeeHelper.FeeParameters memory _fp = _feeParameters;
                _fp.updateAccumulatorValue();

                uint256 _delta = _lookUpTimestamp - timestamp;

                cumulativeId += _pairInformation.activeId * _delta;
                cumulativeAccumulator += _fp.accumulator * _delta;
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
    /// @param _swapForY Wether you've swapping token X for token Y (true) or token Y for token X (false)
    /// @return The id of the non empty bin
    function findFirstNonEmptyBinId(uint24 _id, bool _swapForY) external view override returns (uint256) {
        return _tree.findFirstBin(_id, _swapForY);
    }

    /// @notice View function to get the bin at `id`
    /// @param _id The bin id
    /// @return reserveX The reserve of tokenX of the bin
    /// @return reserveY The reserve of tokenY of the bin
    function getBin(uint24 _id) external view override returns (uint256 reserveX, uint256 reserveY) {
        uint256 _mask = type(uint112).max;
        // low level read of mapping to only load 1 storage slot
        assembly {
            mstore(0, _id)
            mstore(32, _bins.slot)
            let _data := sload(keccak256(0, 64))

            reserveX := and(_data, _mask)
            reserveY := and(shr(112, _data), _mask)
        }
    }

    /// @notice View function to get the pending fees of a user
    /// @dev The array must be strictly increasing to ensure uniqueness
    /// @param _account The address of the user
    /// @param _ids The list of ids
    /// @return fees The unclaimed fees
    function pendingFees(address _account, uint256[] memory _ids)
        external
        view
        override
        returns (UnclaimedFees memory fees)
    {
        unchecked {
            fees = _unclaimedFees[_account];

            uint256 _lastId;
            uint256 _len = _ids.length;
            for (uint256 i; i < _len; ++i) {
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
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.activeId;

        uint256 _amountOut;
        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            Bin memory _bin = _bins[_pair.activeId];
            if ((!_swapForY && _bin.reserveX != 0) || (_swapForY && _bin.reserveY != 0)) {
                (uint256 _amountInToBin, uint256 _amountOutOfBin, FeeHelper.FeesDistribution memory _fees) = _pair
                    .getAmounts(_bin, _fp, _swapForY, _startId, _amountIn);

                _pair.updateLiquidity(
                    _bin,
                    _fees,
                    _swapForY,
                    totalSupply(_pair.activeId),
                    _amountInToBin.safe112(),
                    _amountOutOfBin
                );

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
            uint256 _binCrossed = _startId > _pair.activeId ? _startId - _pair.activeId : _pair.activeId - _startId;
            _fp.updateFeeParameters(_binCrossed);

            // We use oracleSize so it can start filling empty slot that were added recently
            uint256 _updatedOracleId = _oracle.update(
                _pair.oracleSize,
                _pair.oracleSampleLifetime,
                _pair.oracleLastTimestamp,
                _pair.oracleId,
                _pair.activeId,
                _fp.accumulator,
                _binCrossed
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
        bytes memory _data
    ) external override nonReentrant {
        FeeHelper.FeeParameters memory _fp = _feeParameters;
        _fp.updateAccumulatorValue();
        FeeHelper.FeesDistribution memory _feesX = _fp.getFeesDistribution(_fp.getFees(_amountXOut, 0));
        FeeHelper.FeesDistribution memory _feesY = _fp.getFeesDistribution(_fp.getFees(_amountYOut, 0));

        uint256 _reserveX = _pairInformation.reserveX;
        uint256 _reserveY = _pairInformation.reserveY;
        uint256 _id = _pairInformation.activeId;

        tokenX.safeTransfer(_to, _amountXOut);
        tokenY.safeTransfer(_to, _amountYOut);

        ILBFlashLoanCallback(msg.sender).LBFlashLoanCallback(_feesX.total, _feesY.total, _data);

        _flashLoanHelper(_pairInformation.feesX, _feesX, tokenX, _reserveX);
        _flashLoanHelper(_pairInformation.feesY, _feesY, tokenY, _reserveY);

        uint256 _totalSupply = totalSupply(_id);

        _bins[_id].accTokenXPerShare +=
            (uint256(_feesX.total - _feesX.protocol) << Constants.SCALE_OFFSET) /
            _totalSupply;
        _bins[_id].accTokenYPerShare +=
            (uint256(_feesY.total - _feesY.protocol) << Constants.SCALE_OFFSET) /
            _totalSupply;

        emit FlashLoan(msg.sender, _to, _amountXOut, _amountYOut, _feesX.total, _feesY.total);
    }

    /// @notice Performs a low level add, this needs to be called from a contract which performs important safety checks.
    /// @param _ids The list of ids to add liquidity
    /// @param _distributionX The distribution of tokenX with sum(_distributionX) = 100e18 (100%) or 0 (0%)
    /// @param _distributionY The distribution of tokenY with sum(_distributionY) = 100e18 (100%) or 0 (0%)
    /// @param _to The address of the recipient
    /// @return The amount of token X that was added to the pair
    /// @return The amount of token Y that was added to the pair
    function mint(
        uint256[] memory _ids,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        address _to
    ) external override nonReentrant returns (uint256, uint256) {
        unchecked {
            uint256 _len = _ids.length;
            if (_len == 0 || _len != _distributionX.length || _len != _distributionY.length)
                revert LBPair__WrongLengths();

            PairInformation memory _pair = _pairInformation;

            uint256 _binStep = _feeParameters.binStep;

            MintInfo memory _mintInfo;

            _mintInfo.amountXIn = tokenX.received(_pair.reserveX, _pair.feesX.total).safe128();
            _mintInfo.amountYIn = tokenY.received(_pair.reserveY, _pair.feesY.total).safe128();

            for (uint256 i; i < _len; ++i) {
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

                uint256 _liquidity;
                if (_mintInfo.id >= _pair.activeId) {
                    uint256 _distribution = _distributionX[i];

                    if (_distribution > Constants.PRECISION)
                        revert LBPair__DistributionOverflow(_mintInfo.id, _distribution);

                    uint256 _price = BinHelper.getPriceFromId(_mintInfo.id, _binStep);

                    _mintInfo.amount = (_mintInfo.amountXIn * _distribution) / Constants.PRECISION;
                    _liquidity = _price.mulShift(_mintInfo.amount, Constants.SCALE_OFFSET, true);

                    _bin.reserveX = (_bin.reserveX + _mintInfo.amount).safe112();
                    _pair.reserveX += uint136(_mintInfo.amount);

                    _mintInfo.totalDistributionX += _distribution;
                    _mintInfo.amountXAddedToPair += _mintInfo.amount;
                }

                if (_mintInfo.id <= _pair.activeId) {
                    uint256 _distribution = _distributionY[i];

                    if (_distribution > Constants.PRECISION)
                        revert LBPair__DistributionOverflow(_mintInfo.id, _distribution);

                    _mintInfo.amount = (_mintInfo.amountYIn * _distribution) / Constants.PRECISION;
                    _liquidity = _liquidity + _mintInfo.amount;

                    _bin.reserveY = (_bin.reserveY + _mintInfo.amount).safe112();
                    _pair.reserveY += uint136(_mintInfo.amount);

                    _mintInfo.totalDistributionY += _distribution;
                    _mintInfo.amountYAddedToPair += _mintInfo.amount;
                }

                // we shift the liquidity to increase the precision of the accTokenPerShare
                if (_liquidity == 0) revert LBPair__InsufficientLiquidityMinted(_mintInfo.id);

                _bins[_mintInfo.id] = _bin;
                _mint(_to, _mintInfo.id, _liquidity);
            }

            if (
                _mintInfo.totalDistributionX > 100 * Constants.PRECISION ||
                _mintInfo.totalDistributionY > 100 * Constants.PRECISION
            ) revert LBPair__BrokenMintSafetyCheck(_mintInfo.totalDistributionX, _mintInfo.totalDistributionY);

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

            return (_mintInfo.amountXAddedToPair, _mintInfo.amountYAddedToPair);
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

            uint256 _len = _ids.length;
            for (uint256 i; i < _len; ++i) {
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
    function collectFees(address _account, uint256[] memory _ids) external override nonReentrant {
        unchecked {
            uint256 _len = _ids.length;

            UnclaimedFees memory _fees = _unclaimedFees[_account];
            delete _unclaimedFees[_account];

            for (uint256 i; i < _len; ++i) {
                uint256 _id = _ids[i];
                uint256 _balance = balanceOf(_account, _id);

                if (_balance != 0) {
                    Bin memory _bin = _bins[_id];

                    _collectFees(_fees, _bin, _account, _id, _balance);
                    _updateUserDebts(_bin, _account, _id, _balance);
                }
            }

            if (_fees.tokenX != 0) {
                _pairInformation.feesX.total -= _fees.tokenX;
            }
            if (_fees.tokenY != 0) {
                _pairInformation.feesY.total -= _fees.tokenY;
            }

            tokenX.safeTransfer(_account, _fees.tokenX);
            tokenY.safeTransfer(_account, _fees.tokenY);

            emit FeesCollected(msg.sender, _account, _fees.tokenX, _fees.tokenY);
        }
    }

    /// @notice Collect the protocol fees and send them to the feeRecipient
    /// @dev The balances are not zeroed to save gas by not resetting the storage slot
    /// Only callable by the fee recipient
    function collectProtocolFees() external override nonReentrant {
        unchecked {
            address _feeRecipient = factory.feeRecipient();

            if (msg.sender != _feeRecipient) revert LBPair__OnlyFeeRecipient(_feeRecipient, msg.sender);

            FeeHelper.FeesDistribution memory _feesX = _pairInformation.feesX;
            uint256 _feesXOut;
            if (_feesX.protocol != 0) {
                _feesXOut = _feesX.protocol - 1;
                _feesX.total -= uint128(_feesXOut);
                _feesX.protocol = 1;
                _pairInformation.feesX = _feesX;
            }

            FeeHelper.FeesDistribution memory _feesY = _pairInformation.feesY;
            uint256 _feesYOut;
            if (_feesY.protocol != 0) {
                _feesYOut = _feesY.protocol - 1;
                _feesY.total -= uint128(_feesYOut);
                _feesY.protocol = 1;
                _pairInformation.feesY = _feesY;
            }

            tokenX.safeTransfer(_feeRecipient, _feesXOut);
            tokenY.safeTransfer(_feeRecipient, _feesYOut);

            emit ProtocolFeeCollected(msg.sender, _feeRecipient, _feesXOut, _feesYOut);
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
                UnclaimedFees memory _feesFrom = _unclaimedFees[_from];
                uint256 _balanceFrom = balanceOf(_from, _id);

                _collectFees(_feesFrom, _bin, _from, _id, _balanceFrom);
                _updateUserDebts(_bin, _from, _id, _balanceFrom - _amount);

                _unclaimedFees[_from] = _feesFrom;
            }

            if (_to != address(0) && _to != address(this) && _to != _from) {
                UnclaimedFees memory _feesTo = _unclaimedFees[_to];

                uint256 _balanceTo = balanceOf(_to, _id);

                _collectFees(_feesTo, _bin, _to, _id, _balanceTo);
                _updateUserDebts(_bin, _to, _id, _balanceTo + _amount);

                _unclaimedFees[_to] = _feesTo;
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
        UnclaimedFees memory _fees,
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
            let variableParameters := and(sload(_feeParameters.slot), shl(144, _mask112))
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
}
