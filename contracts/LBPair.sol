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
import "./libraries/SwapHelper.sol";
import "./libraries/TokenHelper.sol";
import "./interfaces/ILBFactoryHelper.sol";
import "./interfaces/ILBFlashLoanCallback.sol";
import "./interfaces/ILBPair.sol";

/** Errors **/

error LBPair__InsufficientAmounts();
error LBPair__WrongAmounts(uint256 amountXOut, uint256 amountYOut);
error LBPair__BrokenSwapSafetyCheck();
error LBPair__BrokenMintSafetyCheck(uint256 id);
error LBPair__InsufficientLiquidityBurned(uint256 id);
error LBPair__BurnExceedsReserve(uint256 id);
error LBPair__WrongLengths();
error LBPair__MintExceedsAmountsIn(uint256 id);
error LBPair__BinReserveOverflows(uint256 id);
error LBPair__IdOverflows(uint256 id);
error LBPair__FlashLoanUnderflow(uint256 expectedBalance, uint256 balance);
error LBPair__BrokenFlashLoanSafetyChecks(uint256 amountXIn, uint256 amountYIn);
error LBPair__OnlyStrictlyIncreasingId();
error LBPair__OnlyFactory();
error LBPair__DepthTooDeep();

// TODO add oracle price, distribute fees protocol / sJoe
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

    /** Events **/

    event Swap(
        address indexed sender,
        address indexed recipient,
        uint24 indexed _id,
        uint256 amountX,
        uint256 amountY
    );

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
        uint256[] ids,
        uint256[] liquidities
    );

    event Burn(
        address indexed sender,
        address indexed recipient,
        uint256[] ids,
        uint256[] amounts
    );

    event FeesCollected(
        address indexed sender,
        address indexed recipient,
        uint256 amountX,
        uint256 amountY
    );

    event ProtocolFeesCollected(
        address indexed sender,
        address indexed recipient,
        uint256 amountX,
        uint256 amountY
    );

    event FeesParametersSet(bytes32 packedFeeParameters);

    /** Modifiers **/

    modifier OnlyFactory() {
        if (msg.sender != address(factory)) revert LBPair__OnlyFactory();
        _;
    }

    /** Public immutable variables **/

    IERC20 public immutable override tokenX;
    IERC20 public immutable override tokenY;
    ILBFactory public immutable override factory;
    /// @notice The `log2(1 + α binStep)` value as a signed 39.36-decimal fixed-point number
    int256 public immutable override log2Value;

    /** Private variables **/

    PairInformation private _pairInformation;
    FeeHelper.FeeParameters private _feeParameters;
    /// @dev the reserves of tokens for every bin. This is the amount
    /// of tokenY if `id < _pairInformation.id`; of tokenX if `id > _pairInformation.id`
    /// and a mix of both if `id == _pairInformation.id`
    mapping(uint256 => Bin) private _bins;
    /// @dev Tree to find bins with non zero liquidity
    mapping(uint256 => uint256)[3] private _tree;
    /// @notice mappings from account to user's unclaimed fees.
    mapping(address => Amounts) private _unclaimedFees;
    /// @notice mappings from account to id to user's accruedDebt.
    mapping(address => mapping(uint256 => Debts)) private _accruedDebts;

    /** Constructor **/

    /// @notice Initialize the parameters
    /// @dev The different parameters needs to be validated very cautiously.
    /// It is highly recommended to never deploy this contract directly, use the factory
    /// as it validates the different parameters
    /// @param _factory The address of the factory.
    /// @param _tokenX The address of the tokenX. Can't be address 0
    /// @param _tokenY The address of the tokenY. Can't be address 0
    /// @param _log2Value The log(1 + binStep) value
    /// @param _packedFeeParameters The fee parameters packed in a single 256 bits slot
    constructor(
        ILBFactory _factory,
        IERC20 _tokenX,
        IERC20 _tokenY,
        int256 _log2Value,
        bytes32 _packedFeeParameters
    ) LBToken("Liquidity Book Token", "LBT") {
        factory = _factory;
        tokenX = _tokenX;
        tokenY = _tokenY;

        _setFeesParameters(_packedFeeParameters);

        log2Value = _log2Value;
    }

    /** External View Functions **/

    /// @notice View function to get the _pairInformation information
    /// @return The _pairInformation information
    function pairInformation()
        external
        view
        override
        returns (PairInformation memory)
    {
        return _pairInformation;
    }

    /// @notice View function to get the fee parameters
    /// @return The fee parameters
    function feeParameters()
        external
        view
        override
        returns (FeeHelper.FeeParameters memory)
    {
        return _feeParameters;
    }

    /// @notice View function to get the tree
    /// @param _id The bin id
    /// @param _isSearchingRight Wether to search right or left
    /// @return The value of the leaf at (depth, id)
    function findFirstBin(uint24 _id, bool _isSearchingRight)
        external
        view
        override
        returns (uint256)
    {
        return _tree.findFirstBin(_id, _isSearchingRight);
    }

    /// @notice View function to get the bin at `id`
    /// @param _id The bin id
    /// @return price The exchange price of y per x inside this bin (multiplied by 1e36)
    /// @return reserveX The reserve of tokenX of the bin
    /// @return reserveY The reserve of tokenY of the bin
    function getBin(uint24 _id)
        external
        view
        override
        returns (
            uint256 price,
            uint112 reserveX,
            uint112 reserveY
        )
    {
        uint256 _price = BinHelper.getPriceFromId(_id, log2Value);
        return (_price, _bins[_id].reserveX, _bins[_id].reserveY);
    }

    /// @notice View function to get the pending fees of a user
    /// @param _account The address of the user
    /// @param _ids The list of ids
    /// @return The unclaimed fees
    function pendingFees(address _account, uint256[] memory _ids)
        external
        view
        override
        returns (Amounts memory)
    {
        uint256 _len = _ids.length;
        Amounts memory _fees = _unclaimedFees[_account];

        uint256 _lastId;
        for (uint256 i; i < _len; ++i) {
            uint256 _id = _ids[i];
            uint256 _balance = balanceOf(_account, _id);

            if (_lastId >= _id && i != 0)
                revert LBPair__OnlyStrictlyIncreasingId();

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
    /// @param _sentTokenY Wether the token sent was Y (true) or X (false)
    /// @param _to The address of the recipient
    function swap(bool _sentTokenY, address _to)
        external
        override
        nonReentrant
    {
        PairInformation memory _pair = _pairInformation;

        uint256 _amountIn = _getAmountIn(_pair, _sentTokenY);

        if (_amountIn == 0) revert LBPair__InsufficientAmounts();

        FeeHelper.FeeParameters memory _fp = _feeParameters;
        _fp.updateAccumulatorValue();
        uint256 _startId = _pair.id;

        uint256 _amountOut;
        // Performs the actual swap, bin per bin
        // It uses the findFirstBin function to make sure the bin we're currently looking at
        // has liquidity in it.
        while (true) {
            Bin memory _bin = _bins[_pair.id];
            if (_bin.reserveX != 0 || _bin.reserveY != 0) {
                (
                    uint256 _amountInToBin,
                    uint256 _amountOutOfBin,
                    FeeHelper.FeesDistribution memory _fees
                ) = _pair.getAmounts(
                        _bin,
                        _fp,
                        log2Value,
                        _sentTokenY,
                        _startId,
                        _amountIn
                    );

                if (_amountInToBin > type(uint112).max)
                    revert LBPair__BinReserveOverflows(_pair.id);

                _pair.update(
                    _bin,
                    _fees,
                    _sentTokenY,
                    totalSupply(_pair.id),
                    _amountInToBin,
                    _amountOutOfBin
                );

                _amountIn -= _amountInToBin + _fees.total;
                _amountOut += _amountOutOfBin;

                _bins[_pair.id] = _bin;
            }

            if (_amountIn != 0) {
                _pair.id = uint24(_tree.findFirstBin(_pair.id, !_sentTokenY));
            } else {
                break;
            }
        }

        _pairInformation = _pair;
        unchecked {
            _feeParameters.updateStoredFeeParameters(
                _fp.accumulator,
                _startId > _pair.id ? _startId - _pair.id : _pair.id - _startId
            );
        }
        if (_amountOut == 0) revert LBPair__BrokenSwapSafetyCheck(); // Safety check

        if (_sentTokenY) {
            tokenX.safeTransfer(_to, _amountOut);
            emit Swap(msg.sender, _to, _pair.id, _amountOut, 0);
        } else {
            tokenY.safeTransfer(_to, _amountOut);
            emit Swap(msg.sender, _to, _pair.id, 0, _amountOut);
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

        FeeHelper.FeesDistribution memory _feesX = _fp.getFeesDistribution(
            _fp.getFees(_amountXOut, 0)
        );
        FeeHelper.FeesDistribution memory _feesY = _fp.getFeesDistribution(
            _fp.getFees(_amountYOut, 0)
        );

        tokenX.safeTransfer(_to, _amountXOut);
        tokenY.safeTransfer(_to, _amountYOut);

        ILBFlashLoanCallback(_to).LBFlashLoanCallback(
            msg.sender,
            _feesX.total,
            _feesY.total,
            _data
        );

        _flashLoanHelper(_pairInformation.feesX, _feesX, tokenX, _reserveX);
        _flashLoanHelper(_pairInformation.feesY, _feesY, tokenY, _reserveY);

        uint256 _id = _pairInformation.id;
        uint256 _totalSupply = totalSupply(_id);
        _bins[_id].accTokenXPerShare +=
            ((_feesX.total - _feesX.protocol) * Constants.PRICE_PRECISION) /
            _totalSupply;

        _bins[_id].accTokenYPerShare +=
            ((_feesY.total - _feesY.protocol) * Constants.PRICE_PRECISION) /
            _totalSupply;

        emit FlashLoan(
            msg.sender,
            _to,
            _amountXOut,
            _amountYOut,
            _feesX.total,
            _feesY.total
        );
    }

    /// @notice Performs a low level add, this needs to be called from a contract which performs important safety checks.
    /// The first LP provider sets the current id with the first index of its ids
    /// @param _ids The list of ids to add liquidity
    /// @param _liquidities The amounts of L you want to add
    /// @param _to The address of the recipient
    function mint(
        uint256[] memory _ids,
        uint256[] memory _liquidities,
        address _to
    ) external override nonReentrant {
        uint256 _len = _ids.length;
        if (_len == 0 || _len != _liquidities.length)
            revert LBPair__WrongLengths();

        PairInformation memory _pair = _pairInformation;
        if (_pair.reserveX == 0 && _pair.reserveY == 0) {
            _pair.id = uint24(_ids[0]);
        }

        uint256 _amountXIn = tokenX.received(_pair.reserveX, _pair.feesX.total);
        uint256 _amountYIn = tokenY.received(_pair.reserveY, _pair.feesY.total);

        uint256 _amountX;
        uint256 _amountY;

        unchecked {
            for (uint256 i; i < _len; ++i) {
                uint256 _id = _ids[i];
                uint256 _liquidity = _liquidities[i];
                if (_id > type(uint24).max) revert LBPair__IdOverflows(_id);

                if (_liquidity != 0) {
                    Bin memory _bin = _bins[_id];
                    uint256 _totalSupply = totalSupply(_id);
                    if (_totalSupply != 0) {
                        _amountX = _liquidity.mulDivRoundUp(
                            _bin.reserveX,
                            _totalSupply
                        );
                        _amountY = _liquidity.mulDivRoundUp(
                            _bin.reserveY,
                            _totalSupply
                        );
                    } else {
                        uint256 _price = BinHelper.getPriceFromId(
                            uint24(_id),
                            log2Value
                        );

                        if (_id < _pair.id) {
                            _amountY = _liquidity.safe128();
                        } else if (_id > _pair.id) {
                            _amountX = _liquidity.mulDivRoundUp(
                                Constants.PRICE_PRECISION,
                                _price
                            );
                        } else if (_id == _pair.id) {
                            _amountX = (_liquidity - _liquidity / 2)
                                .mulDivRoundUp(
                                    Constants.PRICE_PRECISION,
                                    _price
                                );
                            _amountY = (_liquidity / 2).safe128();
                        }

                        // add 1 at the right indices if the _pairInformation was empty
                        uint256 _idDepth2 = _id / 256;
                        uint256 _idDepth1 = _id / 65_536;

                        _tree[2][_idDepth2] |= 1 << (_id % 256);
                        _tree[1][_idDepth1] |= 1 << (_idDepth2 % 256);
                        _tree[0][0] |= 1 << _idDepth1;
                    }

                    if (_amountX == 0 && _amountY == 0)
                        revert LBPair__BrokenMintSafetyCheck(_id);

                    if (_amountX != 0) {
                        if (_amountXIn < _amountX)
                            revert LBPair__MintExceedsAmountsIn(_id);
                        if (_amountX > type(uint112).max)
                            revert LBPair__BinReserveOverflows(_id);
                        _amountXIn -= _amountX;
                        _bin.reserveX = (_bin.reserveX + _amountX).safe112();
                        _pair.reserveX += uint136(_amountX);
                    }

                    if (_amountY != 0) {
                        if (_amountYIn < _amountY)
                            revert LBPair__MintExceedsAmountsIn(_id);
                        if (_amountY > type(uint112).max)
                            revert LBPair__BinReserveOverflows(_id);
                        _amountYIn -= _amountY;
                        _bin.reserveY = (_bin.reserveY + _amountY).safe112();
                        _pair.reserveY += uint136(_amountY);
                    }

                    _bins[_id] = _bin;
                    _mint(_to, _id, _liquidity);
                }
            }
        }

        _pairInformation = _pair;
        emit Mint(msg.sender, _to, _ids, _liquidities);
    }

    /// @notice Performs a low level remove, this needs to be called from a contract which performs important safety checks
    /// @param _ids The ids the user want to remove its liquidity
    /// @param _amounts The amount of token to burn
    /// @param _to The address of the recipient
    function burn(
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to
    ) external override nonReentrant {
        uint256 _len = _ids.length;

        PairInformation memory _pair = _pairInformation;

        uint256 _amountsX;
        uint256 _amountsY;

        unchecked {
            for (uint256 i; i < _len; ++i) {
                uint256 _id = _ids[i];
                uint256 _amountToBurn = _amounts[i];
                if (_id > type(uint24).max) revert LBPair__IdOverflows(_id);

                if (_amountToBurn == 0)
                    revert LBPair__InsufficientLiquidityBurned(_id);

                Bin memory _bin = _bins[_id];

                uint256 totalSupply = totalSupply(_id);

                if (_id <= _pair.id) {
                    uint256 _amountY = _amountToBurn.mulDivRoundDown(
                        _bin.reserveY,
                        totalSupply
                    );

                    if (_bin.reserveY < _amountY)
                        revert LBPair__BurnExceedsReserve(_id);

                    _amountsY += _amountY;
                    _bin.reserveY -= uint112(_amountY);
                    _pair.reserveY -= uint136(_amountY);
                }
                if (_id >= _pair.id) {
                    uint256 _amountX = _amountToBurn.mulDivRoundDown(
                        _bin.reserveX,
                        totalSupply
                    );

                    if (_bin.reserveX < _amountX)
                        revert LBPair__BurnExceedsReserve(_id);

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
    }

    /// @notice Collect fees of an user
    /// @param _account The address of the user
    /// @param _ids The list of bin ids to collect fees in
    function collectFees(address _account, uint256[] memory _ids)
        external
        nonReentrant
    {
        uint256 _len = _ids.length;

        Amounts memory _fees = _unclaimedFees[_account];
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

    /// @notice Distribute the protocol fees to the feeRecipient
    /// @dev The balances are not zeroed to save gas by not resetting the memory slot
    function distributeProtocolFees() external nonReentrant {
        FeeHelper.FeesDistribution memory _feesX = _pairInformation.feesX;
        FeeHelper.FeesDistribution memory _feesY = _pairInformation.feesY;

        address _feeRecipient = factory.feeRecipient();
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

        tokenX.safeTransfer(_feeRecipient, _feesXOut);
        tokenY.safeTransfer(_feeRecipient, _feesYOut);

        emit ProtocolFeesCollected(
            msg.sender,
            _feeRecipient,
            _feesXOut,
            _feesYOut
        );
    }

    function setFeesParameters(bytes32 _packedFeeParameters)
        external
        override
        OnlyFactory
    {
        _setFeesParameters(_packedFeeParameters);
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

        Amounts memory _feesFrom = _unclaimedFees[_from];
        Amounts memory _feesTo = _unclaimedFees[_to];

        Bin memory _bin = _bins[_id];

        if (_from != address(0) && _from != address(this)) {
            uint256 _balanceFrom = balanceOf(_from, _id);

            _collectFees(_feesFrom, _bin, _from, _id, _balanceFrom);
            _updateUserDebts(_bin, _from, _id, _balanceFrom - _amount);

            _unclaimedFees[_from] = _feesFrom;
        }

        if (_to != address(0) && _to != address(this) && _from != _to) {
            uint256 _balanceTo = balanceOf(_to, _id);

            _collectFees(_feesTo, _bin, _to, _id, _balanceTo);
            _updateUserDebts(_bin, _to, _id, _balanceTo + _amount);

            _unclaimedFees[_to] = _feesTo;
        }
    }

    /** Private Functions **/

    /// @notice Collect fees of a given bin
    /// @param _fees The user's unclaimed fees
    /// @param _bin  The bin where the user is collecting fees
    /// @param _account The address of the user
    /// @param _id The id where the user is collecting fees
    /// @param _balance The previous balance of the user
    function _collectFees(
        Amounts memory _fees,
        Bin memory _bin,
        address _account,
        uint256 _id,
        uint256 _balance
    ) private view {
        Debts memory _debts = _accruedDebts[_account][_id];

        _fees.tokenX += (_bin.accTokenXPerShare.mulDivRoundDown(
            _balance,
            Constants.PRICE_PRECISION
        ) - _debts.debtX).safe128();

        _fees.tokenY += (_bin.accTokenYPerShare.mulDivRoundDown(
            _balance,
            Constants.PRICE_PRECISION
        ) - _debts.debtY).safe128();
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
        uint256 _debtX = _bin.accTokenXPerShare.mulDivRoundDown(
            _balance,
            Constants.PRICE_PRECISION
        );
        uint256 _debtY = _bin.accTokenYPerShare.mulDivRoundDown(
            _balance,
            Constants.PRICE_PRECISION
        );

        _accruedDebts[_account][_id] = Debts(_debtX, _debtY);
    }

    /// @notice Returns the amount of token that was sent to the contract
    /// @param _pair The current pair information
    /// @param _sentTokenY Wether the token sent was Y (true) or X (false)
    /// @return The amount of token that was sent to the contract
    function _getAmountIn(PairInformation memory _pair, bool _sentTokenY)
        private
        view
        returns (uint256)
    {
        if (_sentTokenY) {
            return tokenY.received(_pair.reserveY, _pair.feesY.total);
        }
        return tokenX.received(_pair.reserveX, _pair.feesX.total);
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

        if (_fees.total > _amountSentToPair)
            revert LBPair__FlashLoanUnderflow(_fees.total, _amountSentToPair);

        _pairFees.total = _totalFees + _fees.total;
        // unsafe math is fine because total >= protocol
        unchecked {
            _pairFees.protocol += _fees.protocol;
        }
    }

    /// @notice Internal function to set the fee parameters of the pair
    /// @param _packedFeeParameters The packed fee parameters
    function _setFeesParameters(bytes32 _packedFeeParameters) internal {
        assembly {
            sstore(add(_feeParameters.slot, 1), _packedFeeParameters)
        }
        emit FeesParametersSet(_packedFeeParameters);
    }
}
