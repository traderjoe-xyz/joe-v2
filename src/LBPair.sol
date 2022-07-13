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
import "./interfaces/ILBFactoryHelper.sol";
import "./interfaces/ILBFlashLoanCallback.sol";
import "./interfaces/ILBPair.sol";

/** Errors **/

error LBPair__InsufficientAmounts();
error LBPair__WrongAmounts(uint256 amountXOut, uint256 amountYOut);
error LBPair__BrokenSwapSafetyCheck();
error LBPair__BrokenMintSafetyCheck(uint256 totalDistributionX, uint256 totalDistributionY);
error LBPair__InsufficientLiquidityMinted(uint256 id);
error LBPair__InsufficientLiquidityBurned(uint256 id);
error LBPair__BurnExceedsReserve(uint256 id);
error LBPair__WrongLengths();
error LBPair__MintExceedsAmountsIn(uint256 id);
error LBPair__BinReserveOverflows(uint256 id);
error LBPair__IdOverflows(uint256 index);
error LBPair__FlashLoanUnderflow(uint256 expectedBalance, uint256 balance);
error LBPair__BrokenFlashLoanSafetyChecks(uint256 amountXIn, uint256 amountYIn);
error LBPair__OnlyStrictlyIncreasingId();
error LBPair__OnlyFactory();
error LBPair__DepthTooDeep();
error LBPair__DistributionOverflow(uint256 id, uint256 distribution);
error LBPair__OracleOverflow(uint256 currentOracleSize, uint256 increase);
error LBPair__OracleRequestTooOld(uint256 minTimestamp, uint256 requestedTimestamp);
error LBPair__OracleInvalidRequest(uint256 currentTimestamp, uint256 requestedAgo);
error LBPair__OnlyFeeRecipient(address feeRecipient, address sender);

// TODO add oracle price, Add oracle id and size to pair info
/// @title Liquidity Bin Exchange
/// @author Trader Joe
/// @notice DexV2 POC
contract LBPair is LBToken, ReentrancyGuard, ILBPair {
    /** Libraries **/

    using Math512Bits for uint256;
    using TreeMath for mapping(uint256 => uint256)[3];
    using SafeCast for uint256;
    using TokenHelper for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;
    using SwapHelper for PairInformation;
    using Decoder for bytes32;

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
    /// @dev the reserves of tokens for every bin. This is the amount
    /// of tokenY if `id < _pairInformation.activeId`; of tokenX if `id > _pairInformation.activeId`
    /// and a mix of both if `id == _pairInformation.activeId`
    mapping(uint256 => Bin) private _bins;
    /// @dev Tree to find bins with non zero liquidity
    mapping(uint256 => uint256)[3] private _tree;
    /// @notice mappings from account to user's unclaimed fees.
    mapping(address => UnclaimedFees) private _unclaimedFees;
    /// @notice mappings from account to id to user's accruedDebt.
    mapping(address => mapping(uint256 => Debts)) private _accruedDebts;

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
    /// @param _id The active id of the pair
    /// @param _sampleLifetime The lifetime of a sample. It's the min time between 2 oracle's sample
    /// @param _packedFeeParameters The fee parameters packed in a single 256 bits slot
    constructor(
        ILBFactory _factory,
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _id,
        uint256 _sampleLifetime,
        bytes32 _packedFeeParameters
    ) LBToken("Liquidity Book Token", "LBT") {
        factory = _factory;
        tokenX = _tokenX;
        tokenY = _tokenY;

        _pairInformation.activeId = _id.safe24();
        _pairInformation.oracleSampleLifetime = _sampleLifetime.safe16();

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
    /// @return feesX the fees distribution of asset X
    /// @return feesY the fees distribution of asset Y
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
    function getOracleParameters()
        external
        view
        override
        returns (
            uint256 oracleSampleLifetime,
            uint256 oracleSize,
            uint256 oracleActiveSize,
            uint256 oracleLastTimestamp,
            uint256 oracleId
        )
    {
        return _getOracleParameters();
    }

    /// @notice View function to get the safe query windows of the oracle
    /// Outside of these bounds, it might not be returned every time
    /// @return min The min delta time of two samples
    /// @return max The safe max delta time of two samples
    function getSafeQueryWindows() external view returns (uint256 min, uint256 max) {
        (uint256 _oracleSampleLifetime, , uint256 _oracleActiveSize, , ) = _getOracleParameters();

        min = _oracleActiveSize == 0 ? 0 : _oracleSampleLifetime;
        max = _oracleSampleLifetime * _oracleActiveSize;
    }

    /// @notice View function to get the oracle's sample at `_ago` seconds
    /// @dev Return a linearized sample, the weighted average of 2 neighboring samples
    /// @param _ago The number of seconds before the current timestamp
    /// @return cumulativeId The weighted average cumulative id
    /// @return cumulativeAccumulator The weighted average cumulative accumulator
    /// @return cumulativeBinCrossed The weighted average cumulative bin crossed
    function getOracleSampleAt(uint256 _ago)
        external
        view
        returns (
            uint256 cumulativeId,
            uint256 cumulativeAccumulator,
            uint256 cumulativeBinCrossed
        )
    {
        if (_ago >= block.timestamp) revert LBPair__OracleInvalidRequest(block.timestamp, _ago);

        unchecked {
            uint256 _lookUpTimestamp = block.timestamp - _ago;

            (, , uint256 _oracleActiveSize, , uint256 _oracleId) = _getOracleParameters();

            {
                Oracle.Sample memory _sample = Oracle.getSample(_oracleId);

                if (_sample.timestamp < _lookUpTimestamp) {
                    FeeHelper.FeeParameters memory _fp = _feeParameters;
                    _fp.updateAccumulatorValue();
                    uint256 _activeId = _pairInformation.activeId;

                    uint256 _delta = _lookUpTimestamp - _sample.timestamp;
                    return (
                        _sample.cumulativeId + _activeId * _delta,
                        _sample.cumulativeAccumulator + _fp.accumulator * _delta,
                        _sample.cumulativeBinCrossed
                    );
                }
            }

            // We use active size to search inside the samples that have non empty data
            (bytes32 prev_, bytes32 next_) = Oracle.binarySearch(_oracleId, _lookUpTimestamp, _oracleActiveSize);

            Oracle.Sample memory _prev = Oracle.decodeSample(prev_);

            Oracle.Sample memory _next = Oracle.decodeSample(next_);

            if (_prev.timestamp > _lookUpTimestamp)
                revert LBPair__OracleRequestTooOld(_prev.timestamp, _lookUpTimestamp);

            if (_prev.timestamp == _next.timestamp)
                return (_next.cumulativeId, _next.cumulativeAccumulator, _next.cumulativeBinCrossed);

            uint256 _weightPrev = _next.timestamp - _lookUpTimestamp; // _next.timestamp - _prev.timestamp - (_lookUpTimestamp - _prev.timestamp)
            uint256 _weightNext = _lookUpTimestamp - _prev.timestamp; // _next.timestamp - _prev.timestamp - (_next.timestamp - _lookUpTimestamp)
            uint256 _totalWeight = _weightPrev + _weightNext;

            cumulativeId = (_prev.cumulativeId * _weightPrev + _next.cumulativeId * _weightNext) / _totalWeight;
            cumulativeAccumulator =
                (_prev.cumulativeAccumulator * _weightPrev + _next.cumulativeAccumulator * _weightNext) /
                _totalWeight;
            cumulativeBinCrossed =
                (_prev.cumulativeBinCrossed * _weightPrev + _next.cumulativeBinCrossed * _weightNext) /
                _totalWeight;
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
    function getBin(uint24 _id) external view override returns (uint112 reserveX, uint112 reserveY) {
        return (_bins[_id].reserveX, _bins[_id].reserveY);
    }

    /// @notice View function to get the pending fees of a user
    /// @dev The array must be strictly increasing to ensure uniqueness
    /// @param _account The address of the user
    /// @param _ids The list of ids
    /// @return The unclaimed fees
    function pendingFees(address _account, uint256[] memory _ids)
        external
        view
        override
        returns (UnclaimedFees memory)
    {
        uint256 _len = _ids.length;
        UnclaimedFees memory _fees = _unclaimedFees[_account];

        uint256 _lastId;
        for (uint256 i; i < _len; ++i) {
            uint256 _id = _ids[i];
            uint256 _balance = balanceOf(_account, _id);

            if (_lastId >= _id && i != 0) revert LBPair__OnlyStrictlyIncreasingId();

            if (_balance != 0) {
                Bin memory _bin = _bins[_id];

                _collectFees(_fees, _bin, _account, _id, _balance);
            }

            _lastId = _id;
        }

        return _fees;
    }

    /** External Functions **/

    /// @notice Performs a low level swap, this needs to be called from a contract which performs important safety checks
    /// @dev Will swap the full amount that this contract received of token X or Y
    /// @param _swapForY whether the token sent was Y (true) or X (false)
    /// @param _to The address of the recipient
    function swap(bool _swapForY, address _to) external override nonReentrant returns (uint256, uint256) {
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

                if (_amountInToBin > type(uint112).max) revert LBPair__BinReserveOverflows(_pair.activeId);

                _pair.update(_bin, _fees, _swapForY, totalSupply(_pair.activeId), _amountInToBin, _amountOutOfBin);

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

        uint256 _binCrossed = _startId > _pair.activeId ? _startId - _pair.activeId : _pair.activeId - _startId;
        _fp.updateFeeParameters(_binCrossed);

        // We use oracleSize so it can start filling empty slot that were added recently
        uint256 _updatedOracleId = Oracle.update(
            _pair.oracleSize,
            _pair.oracleSampleLifetime,
            _pair.oracleLastTimestamp,
            _pair.oracleId,
            _pair.activeId,
            _fp.accumulator,
            _binCrossed
        );

        // We update the oracleId and lastTimestamp if the sample write on another slot
        if (_updatedOracleId != _pair.oracleId) {
            _pair.oracleId = uint24(_updatedOracleId);
            _pair.oracleLastTimestamp = block.timestamp.safe40();

            // We increase the activeSize if the updated sample is written in a new slot
            if (_updatedOracleId == _pair.oracleActiveSize) _pair.oracleActiveSize += 1;
        }

        _feeParameters = _fp;
        _pairInformation = _pair;

        if (_swapForY) {
            tokenY.safeTransfer(_to, _amountOut);
            emit Swap(msg.sender, _to, _pair.activeId, 0, _amountOut);
            return (0, _amountOut);
        } else {
            tokenX.safeTransfer(_to, _amountOut);
            emit Swap(msg.sender, _to, _pair.activeId, _amountOut, 0);
            return (_amountOut, 0);
        }
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
        uint256 _reserveX = _pairInformation.reserveX;
        uint256 _reserveY = _pairInformation.reserveY;

        _fp.updateAccumulatorValue();

        FeeHelper.FeesDistribution memory _feesX = _fp.getFeesDistribution(_fp.getFees(_amountXOut, 0));
        FeeHelper.FeesDistribution memory _feesY = _fp.getFeesDistribution(_fp.getFees(_amountYOut, 0));

        tokenX.safeTransfer(_to, _amountXOut);
        tokenY.safeTransfer(_to, _amountYOut);

        ILBFlashLoanCallback(_to).LBFlashLoanCallback(msg.sender, _feesX.total, _feesY.total, _data);

        _flashLoanHelper(_pairInformation.feesX, _feesX, tokenX, _reserveX);
        _flashLoanHelper(_pairInformation.feesY, _feesY, tokenY, _reserveY);

        uint256 _id = _pairInformation.activeId;
        uint256 _totalSupply = totalSupply(_id);
        _bins[_id].accTokenXPerShare += ((_feesX.total - _feesX.protocol) * Constants.SCALE) / _totalSupply;

        _bins[_id].accTokenYPerShare += ((_feesY.total - _feesY.protocol) * Constants.SCALE) / _totalSupply;

        emit FlashLoan(msg.sender, _to, _amountXOut, _amountYOut, _feesX.total, _feesY.total);
    }

    /// @notice Performs a low level add, this needs to be called from a contract which performs important safety checks.
    /// @param _ids The list of ids to add liquidity
    /// @param _distributionX The distribution of tokenX with sum(_distributionX) = 100e36 (100%) or 0 (0%)
    /// @param _distributionY The distribution of tokenY with sum(_distributionY) = 100e36 (100%) or 0 (0%)
    /// @param _to The address of the recipient
    /// @return The amount of token X that was added to the pair
    /// @return The amount of token Y that was added to the pair
    function mint(
        uint256[] memory _ids,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        address _to
    ) external override nonReentrant returns (uint256, uint256) {
        uint256 _len = _ids.length;
        if (_len == 0 || _len != _distributionX.length || _len != _distributionY.length) revert LBPair__WrongLengths();

        PairInformation memory _pair = _pairInformation;

        uint256 _binStep = _feeParameters.binStep;

        MintInfo memory _mintInfo;

        _mintInfo.amountXIn = tokenX.received(_pair.reserveX, _pair.feesX.total).safe128();
        _mintInfo.amountYIn = tokenY.received(_pair.reserveY, _pair.feesY.total).safe128();

        unchecked {
            for (uint256 i; i < _len; ++i) {
                _mintInfo.id = _ids[i];
                if (_mintInfo.id > uint256(type(uint24).max)) revert LBPair__IdOverflows(i);
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

                    if (_distribution > Constants.SCALE)
                        revert LBPair__DistributionOverflow(_mintInfo.id, _distribution);

                    uint256 _price = BinHelper.getPriceFromId(uint24(_mintInfo.id), _binStep);

                    _mintInfo.amount = (_mintInfo.amountXIn * _distribution) / Constants.SCALE;
                    _liquidity = _price.mulDivRoundDown(_mintInfo.amount, Constants.SCALE);

                    _bin.reserveX = (_bin.reserveX + _mintInfo.amount).safe112();
                    _pair.reserveX += uint136(_mintInfo.amount);

                    _mintInfo.totalDistributionX += _distribution;
                    _mintInfo.amountXAddedToPair += _mintInfo.amount;
                }

                if (_mintInfo.id <= _pair.activeId) {
                    uint256 _distribution = _distributionY[i];

                    if (_distribution > Constants.SCALE)
                        revert LBPair__DistributionOverflow(_mintInfo.id, _distribution);

                    _mintInfo.amount = (_mintInfo.amountYIn * _distribution) / Constants.SCALE;
                    _liquidity = _liquidity + _mintInfo.amount;

                    _bin.reserveY = (_bin.reserveY + _mintInfo.amount).safe112();
                    _pair.reserveY += uint136(_mintInfo.amount);

                    _mintInfo.totalDistributionY += _distribution;
                    _mintInfo.amountYAddedToPair += _mintInfo.amount;
                }

                if (_liquidity == 0) revert LBPair__InsufficientLiquidityMinted(_mintInfo.id);

                _bins[_mintInfo.id] = _bin;
                _mint(_to, _mintInfo.id, _liquidity);
            }
        }

        if (
            _mintInfo.totalDistributionX > 100 * Constants.SCALE || _mintInfo.totalDistributionY > 100 * Constants.SCALE
        ) revert LBPair__BrokenMintSafetyCheck(_mintInfo.totalDistributionX, _mintInfo.totalDistributionY);

        // If user sent too much tokens, we add them to the claimable fees so they're not lost.
        unchecked {
            if (
                _mintInfo.amountXIn > _mintInfo.amountXAddedToPair || _mintInfo.amountYIn > _mintInfo.amountYAddedToPair
            ) {
                UnclaimedFees memory _fees = _unclaimedFees[_to];

                uint256 _excessX = (_mintInfo.amountXIn - _mintInfo.amountXAddedToPair);
                uint256 _excessY = (_mintInfo.amountYIn - _mintInfo.amountYAddedToPair);

                _pair.feesX.total = (_pair.feesX.total + _excessX).safe128();
                _pair.feesY.total = (_pair.feesY.total + _excessY).safe128();

                _fees.tokenX = uint128(_fees.tokenX + _excessX);
                _fees.tokenY = uint128(_fees.tokenY + _excessY);

                _unclaimedFees[_to] = _fees;
            }
        }

        _pairInformation = _pair;

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

    /// @notice Performs a low level remove, this needs to be called from a contract which performs important safety checks
    /// @param _ids The ids the user want to remove its liquidity
    /// @param _amounts The amount of token to burn
    /// @param _to The address of the recipient
    function burn(
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to
    ) external override nonReentrant returns (uint256, uint256) {
        uint256 _len = _ids.length;

        PairInformation memory _pair = _pairInformation;

        uint256 _amountsX;
        uint256 _amountsY;

        unchecked {
            for (uint256 i; i < _len; ++i) {
                uint256 _id = _ids[i];
                uint256 _amountToBurn = _amounts[i];
                if (_id > type(uint24).max) revert LBPair__IdOverflows(i);

                if (_amountToBurn == 0) revert LBPair__InsufficientLiquidityBurned(_id);

                Bin memory _bin = _bins[_id];

                uint256 totalSupply = totalSupply(_id);

                if (_id <= _pair.activeId) {
                    uint256 _amountY = _amountToBurn.mulDivRoundDown(_bin.reserveY, totalSupply);

                    if (_bin.reserveY < _amountY) revert LBPair__BurnExceedsReserve(_id);

                    _amountsY += _amountY;
                    _bin.reserveY -= uint112(_amountY);
                    _pair.reserveY -= uint136(_amountY);
                }
                if (_id >= _pair.activeId) {
                    uint256 _amountX = _amountToBurn.mulDivRoundDown(_bin.reserveX, totalSupply);

                    if (_bin.reserveX < _amountX) revert LBPair__BurnExceedsReserve(_id);

                    _amountsX += _amountX;
                    _bin.reserveX -= uint112(_amountX);
                    _pair.reserveX -= uint136(_amountX);
                }

                if (_bin.reserveX == 0 && _bin.reserveY == 0) {
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
                _burn(address(this), _id, _amountToBurn);
            }
        }

        _pairInformation = _pair;

        tokenX.safeTransfer(_to, _amountsX);
        tokenY.safeTransfer(_to, _amountsY);

        emit Burn(msg.sender, _to, _ids, _amounts);

        return (_amountsX, _amountsY);
    }

    /// @notice Collect fees of an user
    /// @param _account The address of the user
    /// @param _ids The list of bin ids to collect fees in
    function collectFees(address _account, uint256[] memory _ids) external nonReentrant {
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

    /// @notice Collect the protocol fees and send them to the feeRecipient
    /// @dev The balances are not zeroed to save gas by not resetting the storage slot
    /// Only callable by the fee recipient
    function collectProtocolFees() external nonReentrant {
        address _feeRecipient = factory.feeRecipient();

        if (msg.sender != _feeRecipient) revert LBPair__OnlyFeeRecipient(_feeRecipient, msg.sender);

        FeeHelper.FeesDistribution memory _feesX = _pairInformation.feesX;
        FeeHelper.FeesDistribution memory _feesY = _pairInformation.feesY;

        uint256 _feesXOut;
        uint256 _feesYOut;

        if (_feesX.protocol != 0) {
            unchecked {
                _feesXOut = _feesX.protocol - 1;
                _feesX.total -= uint128(_feesXOut);
                _feesX.protocol = 1;
                _pairInformation.feesX = _feesX;
            }
        }
        if (_feesY.protocol != 0) {
            unchecked {
                _feesYOut = _feesY.protocol - 1;
                _feesY.total -= uint128(_feesYOut);
                _feesY.protocol = 1;
                _pairInformation.feesY = _feesY;
            }
        }

        if (_feesXOut != 0) tokenX.safeTransfer(_feeRecipient, _feesXOut);
        if (_feesYOut != 0) tokenY.safeTransfer(_feeRecipient, _feesYOut);

        emit ProtocolFeesCollected(msg.sender, _feeRecipient, _feesXOut, _feesYOut);
    }

    /// @notice Set the fees parameters
    /// @dev Needs to be called by the factory that will validate the values
    /// The bin step will not change
    /// Only callable by the factory
    /// @param _packedFeeParameters The packed fee parameters
    function setFeesParameters(bytes32 _packedFeeParameters) external override OnlyFactory {
        _setFeesParameters(_packedFeeParameters);
    }

    /** Public Functions **/

    /// @notice Function to support EIP165
    /// @param _interfaceId The id of the interface
    /// @return Whether the interface is supported (true), or not (false)
    function supportsInterface(bytes4 _interfaceId) public view override(LBToken, IERC165) returns (bool) {
        return _interfaceId == type(ILBPair).interfaceId || super.supportsInterface(_interfaceId);
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
        super._beforeTokenTransfer(_from, _to, _id, _amount);

        Bin memory _bin = _bins[_id];

        if (_from != address(0) && _from != address(this)) {
            UnclaimedFees memory _feesFrom = _unclaimedFees[_from];
            uint256 _balanceFrom = balanceOf(_from, _id);

            _collectFees(_feesFrom, _bin, _from, _id, _balanceFrom);
            _updateUserDebts(_bin, _from, _id, _balanceFrom - _amount);

            _unclaimedFees[_from] = _feesFrom;
        }

        if (_to != address(0) && _to != address(this) && _from != _to) {
            UnclaimedFees memory _feesTo = _unclaimedFees[_to];

            uint256 _balanceTo = balanceOf(_to, _id);

            _collectFees(_feesTo, _bin, _to, _id, _balanceTo);
            _updateUserDebts(_bin, _to, _id, _balanceTo + _amount);

            _unclaimedFees[_to] = _feesTo;
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

        _fees.tokenX += (_bin.accTokenXPerShare.mulDivRoundDown(_balance, Constants.SCALE) - _debts.debtX).safe128();

        _fees.tokenY += (_bin.accTokenYPerShare.mulDivRoundDown(_balance, Constants.SCALE) - _debts.debtY).safe128();
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
        uint256 _debtX = _bin.accTokenXPerShare.mulDivRoundDown(_balance, Constants.SCALE);
        uint256 _debtY = _bin.accTokenYPerShare.mulDivRoundDown(_balance, Constants.SCALE);

        _accruedDebts[_account][_id] = Debts(_debtX, _debtY);
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
        uint256 _amountSentToPair = _token.received(_reserve, _totalFees);

        if (_fees.total > _amountSentToPair) revert LBPair__FlashLoanUnderflow(_fees.total, _amountSentToPair);

        _pairFees.total = _totalFees + _fees.total;
        // unsafe math is fine because total >= protocol
        unchecked {
            _pairFees.protocol += _fees.protocol;
        }
    }

    /// @notice Internal function to set the fee parameters of the pair
    /// @param _packedFeeParameters The packed fee parameters
    function _setFeesParameters(bytes32 _packedFeeParameters) internal {
        uint256 mask = type(uint104).max;
        assembly {
            let variableParameters := sload(_feeParameters.slot)
            let parameters := add(and(variableParameters, mask), _packedFeeParameters)
            sstore(_feeParameters.slot, parameters)
        }
    }

    /// @notice Private function to increase the oracle's number of sample
    /// @param _nb The number of sample to add to the oracle
    function _increaseOracle(uint256 _nb) private {
        uint256 _oracleSize = _pairInformation.oracleSize;
        uint256 _newSize = _oracleSize + _nb;

        if (_newSize > type(uint16).max) revert LBPair__OracleOverflow(_oracleSize, _nb);

        unchecked {
            _pairInformation.oracleSize = uint16(_newSize);
            for (uint256 i; i < _nb; ++i) {
                Oracle.initialize(_oracleSize + i);
            }
        }
        emit OracleSizeIncreased(_oracleSize, _newSize);
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
