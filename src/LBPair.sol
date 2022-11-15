// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/** Imports **/

import "./LBErrors.sol";
import "./LBToken.sol";
import "./libraries/BinHelper.sol";
import "./libraries/Constants.sol";
import "./libraries/Decoder.sol";
import "./libraries/FeeDistributionHelper.sol";
import "./libraries/Math512Bits.sol";
import "./libraries/Oracle.sol";
import "./libraries/ReentrancyGuardUpgradeable.sol";
import "./libraries/SafeCast.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SwapHelper.sol";
import "./libraries/TokenHelper.sol";
import "./libraries/TreeMath.sol";
import "./interfaces/ILBPair.sol";

/// @title Liquidity Book Pair
/// @author Trader Joe
/// @notice This contract is the implementation of Liquidity Book Pair that also acts as the receipt token for liquidity positions
contract LBPair is LBToken, ReentrancyGuardUpgradeable, ILBPair {
    /** Libraries **/

    using Math512Bits for uint256;
    using TreeMath for mapping(uint256 => uint256)[3];
    using SafeCast for uint256;
    using SafeMath for uint256;
    using TokenHelper for IERC20;
    using FeeHelper for FeeHelper.FeeParameters;
    using SwapHelper for Bin;
    using Decoder for bytes32;
    using FeeDistributionHelper for FeeHelper.FeesDistribution;
    using Oracle for bytes32[65_535];

    /** Modifiers **/

    /// @notice Checks if the caller is the factory
    modifier onlyFactory() {
        if (msg.sender != address(factory)) revert LBPair__OnlyFactory();
        _;
    }

    /** Public immutable variables **/

    /// @notice The factory contract that created this pair
    ILBFactory public immutable override factory;

    /** Public variables **/

    /// @notice The token that is used as the base currency for the pair
    IERC20 public override tokenX;

    /// @notice The token that is used as the quote currency for the pair
    IERC20 public override tokenY;

    /** Private variables **/

    /// @dev The pair information that is used to track reserves, active ids,
    /// fees and oracle parameters
    PairInformation private _pairInformation;

    /// @dev The fee parameters that are used to calculate fees
    FeeHelper.FeeParameters private _feeParameters;

    /// @dev The reserves of tokens for every bin. This is the amount
    /// of tokenY if `id < _pairInformation.activeId`; of tokenX if `id > _pairInformation.activeId`
    /// and a mix of both if `id == _pairInformation.activeId`
    mapping(uint256 => Bin) private _bins;

    /// @dev Tree to find bins with non zero liquidity

    /// @dev The tree that is used to find the first bin with non zero liquidity
    mapping(uint256 => uint256)[3] private _tree;

    /// @dev The mapping from account to user's unclaimed fees. The first 128 bits are tokenX and the last are for tokenY
    mapping(address => bytes32) private _unclaimedFees;

    /// @dev The mapping from account to id to user's accruedDebt
    mapping(address => mapping(uint256 => Debts)) private _accruedDebts;

    /// @dev The oracle samples that are used to calculate the time weighted average data
    bytes32[65_535] private _oracle;

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

    /// @notice Set the factory address
    /// @param _factory The address of the factory
    constructor(ILBFactory _factory) LBToken() {
        if (address(_factory) == address(0)) revert LBPair__AddressZero();
        factory = _factory;
    }

    /// @notice Initialize the parameters of the LBPair
    /// @dev The different parameters needs to be validated very cautiously
    /// It is highly recommended to never call this function directly, use the factory
    /// as it validates the different parameters
    /// @param _tokenX The address of the tokenX. Can't be address 0
    /// @param _tokenY The address of the tokenY. Can't be address 0
    /// @param _activeId The active id of the pair
    /// @param _sampleLifetime The lifetime of a sample. It's the min time between 2 oracle's sample
    /// @param _packedFeeParameters The fee parameters packed in a single 256 bits slot
    function initialize(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint24 _activeId,
        uint16 _sampleLifetime,
        bytes32 _packedFeeParameters
    ) external override onlyFactory {
        if (address(_tokenX) == address(0) || address(_tokenY) == address(0)) revert LBPair__AddressZero();
        if (address(tokenX) != address(0)) revert LBPair__AlreadyInitialized();

        __ReentrancyGuard_init();

        tokenX = _tokenX;
        tokenY = _tokenY;

        _pairInformation.activeId = _activeId;
        _pairInformation.oracleSampleLifetime = _sampleLifetime;

        _setFeesParameters(_packedFeeParameters);
        _increaseOracle(2);
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

    /// @notice View function to get the total fees and the protocol fees of each tokens
    /// @return feesXTotal The total fees of tokenX
    /// @return feesYTotal The total fees of tokenY
    /// @return feesXProtocol The protocol fees of tokenX
    /// @return feesYProtocol The protocol fees of tokenY
    function getGlobalFees()
        external
        view
        override
        returns (
            uint128 feesXTotal,
            uint128 feesYTotal,
            uint128 feesXProtocol,
            uint128 feesYProtocol
        )
    {
        return _getGlobalFees();
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

    /// @notice View function to get the oracle's sample at `_timeDelta` seconds
    /// @dev Return a linearized sample, the weighted average of 2 neighboring samples
    /// @param _timeDelta The number of seconds before the current timestamp
    /// @return cumulativeId The weighted average cumulative id
    /// @return cumulativeVolatilityAccumulated The weighted average cumulative volatility accumulated
    /// @return cumulativeBinCrossed The weighted average cumulative bin crossed
    function getOracleSampleFrom(uint256 _timeDelta)
        external
        view
        override
        returns (
            uint256 cumulativeId,
            uint256 cumulativeVolatilityAccumulated,
            uint256 cumulativeBinCrossed
        )
    {
        uint256 _lookUpTimestamp = block.timestamp - _timeDelta;

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

            unchecked {
                uint256 _deltaT = _lookUpTimestamp - timestamp;

                cumulativeId += _activeId * _deltaT;
                cumulativeVolatilityAccumulated += uint256(_fp.volatilityAccumulated) * _deltaT;
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
    function findFirstNonEmptyBinId(uint24 _id, bool _swapForY) external view override returns (uint24) {
        return _tree.findFirstBin(_id, _swapForY);
    }

    /// @notice View function to get the bin at `id`
    /// @param _id The bin id
    /// @return reserveX The reserve of tokenX of the bin
    /// @return reserveY The reserve of tokenY of the bin
    function getBin(uint24 _id) external view override returns (uint256 reserveX, uint256 reserveY) {
        return _getBin(_id);
    }

    /// @notice View function to get the pending fees of a user
    /// @dev The array must be strictly increasing to ensure uniqueness
    /// @param _account The address of the user
    /// @param _ids The list of ids
    /// @return amountX The amount of tokenX pending
    /// @return amountY The amount of tokenY pending
    function pendingFees(address _account, uint256[] calldata _ids)
        external
        view
        override
        returns (uint256 amountX, uint256 amountY)
    {
        if (_account == address(this) || _account == address(0)) return (0, 0);

        bytes32 _unclaimedData = _unclaimedFees[_account];

        amountX = _unclaimedData.decode(type(uint128).max, 0);
        amountY = _unclaimedData.decode(type(uint128).max, 128);

        uint256 _lastId;
        // Iterate over the ids to get the pending fees of the user for each bin
        unchecked {
            for (uint256 i; i < _ids.length; ++i) {
                uint256 _id = _ids[i];

                // Ensures uniqueness of ids
                if (_lastId >= _id && i != 0) revert LBPair__OnlyStrictlyIncreasingId();

                uint256 _balance = balanceOf(_account, _id);

                if (_balance != 0) {
                    Bin memory _bin = _bins[_id];

                    (uint128 _amountX, uint128 _amountY) = _getPendingFees(_bin, _account, _id, _balance);

                    amountX += _amountX;
                    amountY += _amountY;
                }

                _lastId = _id;
            }
        }
    }

    /// @notice Returns whether this contract implements the interface defined by
    /// `interfaceId` (true) or not (false)
    /// @param _interfaceId The interface identifier
    /// @return Whether the interface is supported (true) or not (false)
    function supportsInterface(bytes4 _interfaceId) public view override returns (bool) {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(ILBPair).interfaceId;
    }

    /** External Functions **/

    /// @notice Swap tokens iterating over the bins until the entire amount is swapped.
    /// Will swap token X for token Y if `_swapForY` is true, and token Y for token X if `_swapForY` is false.
    /// This function will not transfer the tokens from the caller, it is expected that the tokens have already been
    /// transferred to this contract through another contract.
    /// That is why this function shouldn't be called directly, but through one of the swap functions of the router
    /// that will also perform safety checks.
    ///
    /// The variable fee is updated throughout the swap, it increases with the number of bins crossed.
    /// @param _swapForY Whether you've swapping token X for token Y (true) or token Y for token X (false)
    /// @param _to The address to send the tokens to
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

        uint256 _startId = _pair.activeId;
        _fp.updateVariableFeeParameters(_startId);

        uint256 _amountOut;
        /// Performs the actual swap, iterating over the bins until the entire amount is swapped.
        /// It uses the tree to find the next bin to have a non zero reserve of the token we're swapping for.
        /// It will also update the variable fee parameters.
        while (true) {
            Bin memory _bin = _bins[_pair.activeId];
            if ((!_swapForY && _bin.reserveX != 0) || (_swapForY && _bin.reserveY != 0)) {
                (uint256 _amountInToBin, uint256 _amountOutOfBin, FeeHelper.FeesDistribution memory _fees) = _bin
                    .getAmounts(_fp, _pair.activeId, _swapForY, _amountIn);

                _bin.updateFees(_swapForY ? _pair.feesX : _pair.feesY, _fees, _swapForY, totalSupply(_pair.activeId));

                _bin.updateReserves(_pair, _swapForY, _amountInToBin.safe112(), _amountOutOfBin.safe112());

                _amountIn -= _amountInToBin + _fees.total;
                _amountOut += _amountOutOfBin;

                _bins[_pair.activeId] = _bin;

                // Avoids stack too deep error
                _emitSwap(
                    _to,
                    _pair.activeId,
                    _swapForY,
                    _amountInToBin,
                    _amountOutOfBin,
                    _fp.volatilityAccumulated,
                    _fees.total
                );
            }

            /// If the amount in is not 0, it means that we haven't swapped the entire amount yet.
            /// We need to find the next bin to swap for.
            if (_amountIn != 0) {
                _pair.activeId = _tree.findFirstBin(_pair.activeId, _swapForY);
            } else {
                break;
            }
        }

        // Update the oracle and return the updated oracle id. It uses the oracle size to start filling the new slots.
        uint256 _updatedOracleId = _oracle.update(
            _pair.oracleSize,
            _pair.oracleSampleLifetime,
            _pair.oracleLastTimestamp,
            _pair.oracleId,
            _pair.activeId,
            _fp.volatilityAccumulated,
            _startId.absSub(_pair.activeId)
        );

        // Update the oracleId and lastTimestamp if the sample write on another slot
        if (_updatedOracleId != _pair.oracleId || _pair.oracleLastTimestamp == 0) {
            // Can't overflow as the updatedOracleId < oracleSize
            _pair.oracleId = uint16(_updatedOracleId);
            _pair.oracleLastTimestamp = block.timestamp.safe40();

            // Increase the activeSize if the updated sample is written in a new slot
            // Can't overflow as _updatedOracleId < maxSize = 2**16-1
            unchecked {
                if (_updatedOracleId == _pair.oracleActiveSize) ++_pair.oracleActiveSize;
            }
        }

        /// Update the fee parameters and the pair information
        _feeParameters = _fp;
        _pairInformation = _pair;

        if (_swapForY) {
            amountYOut = _amountOut;
            tokenY.safeTransfer(_to, _amountOut);
        } else {
            amountXOut = _amountOut;
            tokenX.safeTransfer(_to, _amountOut);
        }
    }

    /// @notice Perform a flashloan on one of the tokens of the pair. The flashloan will call the `_receiver` contract
    /// to perform the desired operations. The `_receiver` contract is expected to transfer the `amount + fee` of the
    /// token to this contract.
    /// @param _receiver The contract that will receive the flashloan and execute the callback
    /// @param _token The address of the token to flashloan
    /// @param _amount The amount of token to flashloan
    /// @param _data The call data that will be forwarded to the `_receiver` contract during the callback
    function flashLoan(
        ILBFlashLoanCallback _receiver,
        IERC20 _token,
        uint256 _amount,
        bytes calldata _data
    ) external override nonReentrant {
        IERC20 _tokenX = tokenX;
        if ((_token != _tokenX && _token != tokenY)) revert LBPair__FlashLoanInvalidToken();

        uint256 _totalFee = _getFlashLoanFee(_amount);

        FeeHelper.FeesDistribution memory _fees = FeeHelper.FeesDistribution({
            total: _totalFee.safe128(),
            protocol: uint128((_totalFee * _feeParameters.protocolShare) / Constants.BASIS_POINT_MAX)
        });

        uint256 _balanceBefore = _token.balanceOf(address(this));

        _token.safeTransfer(address(_receiver), _amount);

        if (
            _receiver.LBFlashLoanCallback(msg.sender, _token, _amount, _fees.total, _data) != Constants.CALLBACK_SUCCESS
        ) revert LBPair__FlashLoanCallbackFailed();

        uint256 _balanceAfter = _token.balanceOf(address(this));

        if (_balanceAfter != _balanceBefore + _fees.total) revert LBPair__FlashLoanInvalidBalance();

        uint256 _activeId = _pairInformation.activeId;
        uint256 _totalSupply = totalSupply(_activeId);

        if (_totalFee > 0) {
            if (_token == _tokenX) {
                (uint128 _feesXTotal, , uint128 _feesXProtocol, ) = _getGlobalFees();

                _setFees(_pairInformation.feesX, _feesXTotal + _fees.total, _feesXProtocol + _fees.protocol);
                _bins[_activeId].accTokenXPerShare += _fees.getTokenPerShare(_totalSupply);
            } else {
                (, uint128 _feesYTotal, , uint128 _feesYProtocol) = _getGlobalFees();

                _setFees(_pairInformation.feesY, _feesYTotal + _fees.total, _feesYProtocol + _fees.protocol);
                _bins[_activeId].accTokenYPerShare += _fees.getTokenPerShare(_totalSupply);
            }
        }

        emit FlashLoan(msg.sender, _receiver, _token, _amount, _fees.total);
    }

    /// @notice Mint new LB tokens for each bins where the user adds liquidity.
    /// This function will not transfer the tokens from the caller, it is expected that the tokens have already been
    /// transferred to this contract through another contract.
    /// That is why this function shouldn't be called directly, but through one of the add liquidity functions of the
    /// router that will also perform safety checks.
    /// @dev Any excess amount of token will be sent to the `to` address. The lengths of the arrays must be the same.
    /// @param _ids The ids of the bins where the liquidity will be added. It will mint LB tokens for each of these bins.
    /// @param _distributionX The percentage of token X to add to each bin. The sum of all the values must not exceed 100%,
    /// that is 1e18.
    /// @param _distributionY The percentage of token Y to add to each bin. The sum of all the values must not exceed 100%,
    /// that is 1e18.
    /// @param _to The address that will receive the LB tokens and the excess amount of tokens.
    /// @return The amount of token X added to the pair
    /// @return The amount of token Y added to the pair
    /// @return liquidityMinted The amounts of LB tokens minted for each bin
    function mint(
        uint256[] calldata _ids,
        uint256[] calldata _distributionX,
        uint256[] calldata _distributionY,
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
        if (_ids.length == 0 || _ids.length != _distributionX.length || _ids.length != _distributionY.length)
            revert LBPair__WrongLengths();

        PairInformation memory _pair = _pairInformation;

        FeeHelper.FeeParameters memory _fp = _feeParameters;

        MintInfo memory _mintInfo;

        _mintInfo.amountXIn = tokenX.received(_pair.reserveX, _pair.feesX.total).safe112();
        _mintInfo.amountYIn = tokenY.received(_pair.reserveY, _pair.feesY.total).safe112();

        liquidityMinted = new uint256[](_ids.length);

        // Iterate over the ids to calculate the amount of LB tokens to mint for each bin
        for (uint256 i; i < _ids.length; ) {
            _mintInfo.id = _ids[i].safe24();
            Bin memory _bin = _bins[_mintInfo.id];

            if (_bin.reserveX == 0 && _bin.reserveY == 0) _tree.addToTree(_mintInfo.id);

            _mintInfo.totalDistributionX += _distributionX[i];
            _mintInfo.totalDistributionY += _distributionY[i];

            // Can't overflow as amounts are uint112 and total distributions will be checked to be smaller or equal than 1e18
            unchecked {
                _mintInfo.amountX = (_mintInfo.amountXIn * _distributionX[i]) / Constants.PRECISION;
                _mintInfo.amountY = (_mintInfo.amountYIn * _distributionY[i]) / Constants.PRECISION;
            }

            uint256 _price = BinHelper.getPriceFromId(_mintInfo.id, _fp.binStep);
            if (_mintInfo.id >= _pair.activeId) {
                // The active bin is the only bin that can have a non-zero reserve of the two tokens. When adding liquidity
                // with a different ratio than the active bin, the user would actually perform a swap without paying any
                // fees. This is why we calculate the fees for the active bin here.
                if (_mintInfo.id == _pair.activeId) {
                    if (_bin.reserveX != 0 || _bin.reserveY != 0) {
                        uint256 _totalSupply = totalSupply(_mintInfo.id);

                        uint256 _receivedX;
                        uint256 _receivedY;

                        {
                            uint256 _userL = _price.mulShiftRoundDown(_mintInfo.amountX, Constants.SCALE_OFFSET) +
                                _mintInfo.amountY;

                            uint256 _supply = _totalSupply + _userL;

                            // Calculate the amounts received by the user if he were to burn its liquidity directly after adding
                            // it. These amounts will be used to calculate the fees.
                            _receivedX = _userL.mulDivRoundDown(uint256(_bin.reserveX) + _mintInfo.amountX, _supply);
                            _receivedY = _userL.mulDivRoundDown(uint256(_bin.reserveY) + _mintInfo.amountY, _supply);
                        }

                        _fp.updateVariableFeeParameters(_mintInfo.id);

                        FeeHelper.FeesDistribution memory _fees;

                        // Checks if the amount of tokens received after burning its liquidity is greater than the amount of
                        // tokens sent by the user. If it is, we add a composition fee of the difference between the two amounts.
                        if (_mintInfo.amountX > _receivedX) {
                            unchecked {
                                _fees = _fp.getFeeAmountDistribution(
                                    _fp.getFeeAmountForC(_mintInfo.amountX - _receivedX)
                                );
                            }

                            _mintInfo.amountX -= _fees.total;
                            _mintInfo.activeFeeX += _fees.total;

                            _bin.updateFees(_pair.feesX, _fees, true, _totalSupply);
                        }
                        if (_mintInfo.amountY > _receivedY) {
                            unchecked {
                                _fees = _fp.getFeeAmountDistribution(
                                    _fp.getFeeAmountForC(_mintInfo.amountY - _receivedY)
                                );
                            }

                            _mintInfo.amountY -= _fees.total;
                            _mintInfo.activeFeeY += _fees.total;

                            _bin.updateFees(_pair.feesY, _fees, false, _totalSupply);
                        }

                        if (_mintInfo.activeFeeX > 0 || _mintInfo.activeFeeY > 0)
                            emit CompositionFee(
                                msg.sender,
                                _to,
                                _mintInfo.id,
                                _mintInfo.activeFeeX,
                                _mintInfo.activeFeeY
                            );
                    }
                } else if (_mintInfo.amountY != 0) revert LBPair__CompositionFactorFlawed(_mintInfo.id);
            } else if (_mintInfo.amountX != 0) revert LBPair__CompositionFactorFlawed(_mintInfo.id);

            // Calculate the amount of LB tokens to mint for this bin
            uint256 _liquidity = _price.mulShiftRoundDown(_mintInfo.amountX, Constants.SCALE_OFFSET) +
                _mintInfo.amountY;

            if (_liquidity == 0) revert LBPair__InsufficientLiquidityMinted(_mintInfo.id);

            liquidityMinted[i] = _liquidity;

            // Cast can't overflow as amounts are smaller than amountsIn as totalDistribution will be checked to be smaller than 1e18
            _bin.reserveX += uint112(_mintInfo.amountX);
            _bin.reserveY += uint112(_mintInfo.amountY);

            // The addition or the cast can't overflow as it would have reverted during the previous 2 lines if
            // amounts were greater than uint112
            unchecked {
                _pair.reserveX += uint112(_mintInfo.amountX);
                _pair.reserveY += uint112(_mintInfo.amountY);

                _mintInfo.amountXAddedToPair += _mintInfo.amountX;
                _mintInfo.amountYAddedToPair += _mintInfo.amountY;
            }

            _bins[_mintInfo.id] = _bin;

            _mint(_to, _mintInfo.id, _liquidity);

            emit DepositedToBin(msg.sender, _to, _mintInfo.id, _mintInfo.amountX, _mintInfo.amountY);

            unchecked {
                ++i;
            }
        }

        // Assert that the distributions don't exceed 100%
        if (_mintInfo.totalDistributionX > Constants.PRECISION || _mintInfo.totalDistributionY > Constants.PRECISION)
            revert LBPair__DistributionsOverflow();

        _pairInformation = _pair;

        // Send back the excess of tokens to `_to`
        unchecked {
            uint256 _amountXAddedPlusFee = _mintInfo.amountXAddedToPair + _mintInfo.activeFeeX;
            if (_mintInfo.amountXIn > _amountXAddedPlusFee) {
                tokenX.safeTransfer(_to, _mintInfo.amountXIn - _amountXAddedPlusFee);
            }

            uint256 _amountYAddedPlusFee = _mintInfo.amountYAddedToPair + _mintInfo.activeFeeY;
            if (_mintInfo.amountYIn > _amountYAddedPlusFee) {
                tokenY.safeTransfer(_to, _mintInfo.amountYIn - _amountYAddedPlusFee);
            }
        }

        return (_mintInfo.amountXAddedToPair, _mintInfo.amountYAddedToPair, liquidityMinted);
    }

    /// @notice Burns LB tokens and sends the corresponding amounts of tokens to `_to`. The amount of tokens sent is
    /// determined by the ratio of the amount of LB tokens burned to the total supply of LB tokens in the bin.
    /// This function will not transfer the LB Tokens from the caller, it is expected that the tokens have already been
    /// transferred to this contract through another contract.
    /// That is why this function shouldn't be called directly, but through one of the remove liquidity functions of the router
    /// that will also perform safety checks.
    /// @param _ids The ids of the bins from which to remove liquidity
    /// @param _amounts The amounts of LB tokens to burn
    /// @param _to The address that will receive the tokens
    /// @return amountX The amount of token X sent to `_to`
    /// @return amountY The amount of token Y sent to `_to`
    function burn(
        uint256[] calldata _ids,
        uint256[] calldata _amounts,
        address _to
    ) external override nonReentrant returns (uint256 amountX, uint256 amountY) {
        if (_ids.length == 0 || _ids.length != _amounts.length) revert LBPair__WrongLengths();

        (uint256 _pairReserveX, uint256 _pairReserveY, uint256 _activeId) = _getReservesAndId();

        // Iterate over the ids to burn the LB tokens
        unchecked {
            for (uint256 i; i < _ids.length; ++i) {
                uint24 _id = _ids[i].safe24();
                uint256 _amountToBurn = _amounts[i];

                if (_amountToBurn == 0) revert LBPair__InsufficientLiquidityBurned(_id);

                (uint256 _reserveX, uint256 _reserveY) = _getBin(_id);

                uint256 _totalSupply = totalSupply(_id);

                uint256 _amountX;
                uint256 _amountY;

                if (_id <= _activeId) {
                    _amountY = _amountToBurn.mulDivRoundDown(_reserveY, _totalSupply);

                    amountY += _amountY;
                    _reserveY -= _amountY;
                    _pairReserveY -= _amountY;
                }
                if (_id >= _activeId) {
                    _amountX = _amountToBurn.mulDivRoundDown(_reserveX, _totalSupply);

                    amountX += _amountX;
                    _reserveX -= _amountX;
                    _pairReserveX -= _amountX;
                }

                if (_reserveX == 0 && _reserveY == 0) _tree.removeFromTree(_id);

                // Optimized `_bins[_id] = _bin` to do only 1 sstore
                assembly {
                    mstore(0, _id)
                    mstore(32, _bins.slot)
                    let slot := keccak256(0, 64)

                    let reserves := add(shl(_OFFSET_BIN_RESERVE_Y, _reserveY), _reserveX)
                    sstore(slot, reserves)
                }

                _burn(address(this), _id, _amountToBurn);

                emit WithdrawnFromBin(msg.sender, _to, _id, _amountX, _amountY);
            }
        }

        // Optimization to do only 2 sstore
        _pairInformation.reserveX = uint136(_pairReserveX);
        _pairInformation.reserveY = uint136(_pairReserveY);

        tokenX.safeTransfer(_to, amountX);
        tokenY.safeTransfer(_to, amountY);
    }

    /// @notice Increases the length of the oracle to the given `_newLength` by adding empty samples to the end of the oracle.
    /// The samples are however initialized to reduce the gas cost of the updates during a swap.
    /// @param _newLength The new length of the oracle
    function increaseOracleLength(uint16 _newLength) external override {
        _increaseOracle(_newLength);
    }

    /// @notice Collect the fees accumulated by a user.
    /// @param _account The address of the user
    /// @param _ids The ids of the bins for which to collect the fees
    /// @return amountX The amount of token X collected and sent to `_account`
    /// @return amountY The amount of token Y collected and sent to `_account`
    function collectFees(address _account, uint256[] calldata _ids)
        external
        override
        nonReentrant
        returns (uint256 amountX, uint256 amountY)
    {
        if (_account == address(0) || _account == address(this)) revert LBPair__AddressZeroOrThis();

        bytes32 _unclaimedData = _unclaimedFees[_account];
        delete _unclaimedFees[_account];

        amountX = _unclaimedData.decode(type(uint128).max, 0);
        amountY = _unclaimedData.decode(type(uint128).max, 128);

        // Iterate over the ids to collect the fees
        for (uint256 i; i < _ids.length; ) {
            uint256 _id = _ids[i];
            uint256 _balance = balanceOf(_account, _id);

            if (_balance != 0) {
                Bin memory _bin = _bins[_id];

                (uint256 _amountX, uint256 _amountY) = _getPendingFees(_bin, _account, _id, _balance);
                _updateUserDebts(_bin, _account, _id, _balance);

                amountX += _amountX;
                amountY += _amountY;
            }

            unchecked {
                ++i;
            }
        }

        if (amountX != 0) {
            _pairInformation.feesX.total -= uint128(amountX);
        }
        if (amountY != 0) {
            _pairInformation.feesY.total -= uint128(amountY);
        }

        tokenX.safeTransfer(_account, amountX);
        tokenY.safeTransfer(_account, amountY);

        emit FeesCollected(msg.sender, _account, amountX, amountY);
    }

    /// @notice Collect the protocol fees and send them to the fee recipient.
    /// @dev The protocol fees are not set to zero to save gas by not resetting the storage slot.
    /// @return amountX The amount of token X collected and sent to the fee recipient
    /// @return amountY The amount of token Y collected and sent to the fee recipient
    function collectProtocolFees() external override nonReentrant returns (uint128 amountX, uint128 amountY) {
        address _feeRecipient = factory.feeRecipient();

        if (msg.sender != _feeRecipient) revert LBPair__OnlyFeeRecipient(_feeRecipient, msg.sender);

        (uint128 _feesXTotal, uint128 _feesYTotal, uint128 _feesXProtocol, uint128 _feesYProtocol) = _getGlobalFees();

        // The protocol fees are not set to 0 to reduce the gas cost during a swap
        if (_feesXProtocol > 1) {
            amountX = _feesXProtocol - 1;
            _feesXTotal -= amountX;

            _setFees(_pairInformation.feesX, _feesXTotal, 1);

            tokenX.safeTransfer(_feeRecipient, amountX);
        }

        if (_feesYProtocol > 1) {
            amountY = _feesYProtocol - 1;
            _feesYTotal -= amountY;

            _setFees(_pairInformation.feesY, _feesYTotal, 1);

            tokenY.safeTransfer(_feeRecipient, amountY);
        }

        emit ProtocolFeesCollected(msg.sender, _feeRecipient, amountX, amountY);
    }

    /// @notice Set the fees parameters
    /// @dev Needs to be called by the factory that will validate the values
    /// The bin step will not change
    /// Only callable by the factory
    /// @param _packedFeeParameters The packed fee parameters
    function setFeesParameters(bytes32 _packedFeeParameters) external override onlyFactory {
        _setFeesParameters(_packedFeeParameters);
    }

    /// @notice Force the decaying of the references for volatility and index
    /// @dev Only callable by the factory
    function forceDecay() external override onlyFactory {
        _feeParameters.volatilityReference = uint24(
            (uint256(_feeParameters.reductionFactor) * _feeParameters.volatilityReference) / Constants.BASIS_POINT_MAX
        );
        _feeParameters.indexRef = _pairInformation.activeId;
    }

    /** Internal Functions **/

    /// @notice Cache the accrued fees for a user before any transfer, mint or burn of LB tokens.
    /// The tokens are not transferred to reduce the gas cost and to avoid reentrancy.
    /// @param _from The address of the sender of the tokens
    /// @param _to The address of the receiver of the tokens
    /// @param _id The id of the bin
    /// @param _amount The amount of LB tokens transferred
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount
    ) internal override(LBToken) {
        super._beforeTokenTransfer(_from, _to, _id, _amount);

        if (_from != _to) {
            Bin memory _bin = _bins[_id];
            if (_from != address(0) && _from != address(this)) {
                uint256 _balanceFrom = balanceOf(_from, _id);

                _cacheFees(_bin, _from, _id, _balanceFrom, _balanceFrom - _amount);
            }

            if (_to != address(0) && _to != address(this)) {
                uint256 _balanceTo = balanceOf(_to, _id);

                _cacheFees(_bin, _to, _id, _balanceTo, _balanceTo + _amount);
            }
        }
    }

    /** Private Functions **/

    /// @notice View function to get the pending fees of an account on a given bin
    /// @param _bin The bin data where the user is collecting fees
    /// @param _account The address of the user
    /// @param _id The id where the user is collecting fees
    /// @param _balance The previous balance of the user
    /// @return amountX The amount of token X not collected yet by `_account`
    /// @return amountY The amount of token Y not collected yet by `_account`
    function _getPendingFees(
        Bin memory _bin,
        address _account,
        uint256 _id,
        uint256 _balance
    ) private view returns (uint128 amountX, uint128 amountY) {
        Debts memory _debts = _accruedDebts[_account][_id];

        amountX = (_bin.accTokenXPerShare.mulShiftRoundDown(_balance, Constants.SCALE_OFFSET) - _debts.debtX).safe128();
        amountY = (_bin.accTokenYPerShare.mulShiftRoundDown(_balance, Constants.SCALE_OFFSET) - _debts.debtY).safe128();
    }

    /// @notice Update the user debts of a user on a given bin
    /// @param _bin The bin data where the user has collected fees
    /// @param _account The address of the user
    /// @param _id The id where the user has collected fees
    /// @param _balance The new balance of the user
    function _updateUserDebts(
        Bin memory _bin,
        address _account,
        uint256 _id,
        uint256 _balance
    ) private {
        uint256 _debtX = _bin.accTokenXPerShare.mulShiftRoundDown(_balance, Constants.SCALE_OFFSET);
        uint256 _debtY = _bin.accTokenYPerShare.mulShiftRoundDown(_balance, Constants.SCALE_OFFSET);

        _accruedDebts[_account][_id].debtX = _debtX;
        _accruedDebts[_account][_id].debtY = _debtY;
    }

    /// @notice Cache the accrued fees for a user.
    /// @param _bin The bin data where the user is receiving LB tokens
    /// @param _user The address of the user
    /// @param _id The id where the user is receiving LB tokens
    /// @param _previousBalance The previous balance of the user
    /// @param _newBalance The new balance of the user
    function _cacheFees(
        Bin memory _bin,
        address _user,
        uint256 _id,
        uint256 _previousBalance,
        uint256 _newBalance
    ) private {
        bytes32 _unclaimedData = _unclaimedFees[_user];

        uint128 amountX = uint128(_unclaimedData.decode(type(uint128).max, 0));
        uint128 amountY = uint128(_unclaimedData.decode(type(uint128).max, 128));

        (uint128 _amountX, uint128 _amountY) = _getPendingFees(_bin, _user, _id, _previousBalance);
        _updateUserDebts(_bin, _user, _id, _newBalance);

        amountX += _amountX;
        amountY += _amountY;

        _unclaimedFees[_user] = bytes32(uint256((uint256(amountY) << 128) | amountX));
    }

    /// @notice Set the fee parameters of the pair.
    /// @dev Only the first 112 bits can be set, as the last 144 bits are reserved for the variables parameters
    /// @param _packedFeeParameters The packed fee parameters
    function _setFeesParameters(bytes32 _packedFeeParameters) private {
        bytes32 _feeStorageSlot;
        assembly {
            _feeStorageSlot := sload(_feeParameters.slot)
        }

        uint256 _varParameters = _feeStorageSlot.decode(type(uint112).max, _OFFSET_VARIABLE_FEE_PARAMETERS);
        uint256 _newFeeParameters = _packedFeeParameters.decode(type(uint144).max, 0);

        assembly {
            sstore(_feeParameters.slot, or(_newFeeParameters, shl(_OFFSET_VARIABLE_FEE_PARAMETERS, _varParameters)))
        }
    }

    /// @notice Increases the length of the oracle to the given `_newSize` by adding empty samples to the end of the oracle.
    /// The samples are however initialized to reduce the gas cost of the updates during a swap.
    /// @param _newSize The new size of the oracle. Needs to be bigger than current one
    function _increaseOracle(uint16 _newSize) private {
        uint256 _oracleSize = _pairInformation.oracleSize;

        if (_oracleSize >= _newSize) revert LBPair__OracleNewSizeTooSmall(_newSize, _oracleSize);

        _pairInformation.oracleSize = _newSize;

        // Iterate over the uninitialized oracle samples and initialize them
        for (uint256 _id = _oracleSize; _id < _newSize; ) {
            _oracle.initialize(_id);

            unchecked {
                ++_id;
            }
        }

        emit OracleSizeIncreased(_oracleSize, _newSize);
    }

    /// @notice Return the oracle's parameters
    /// @return oracleSampleLifetime The lifetime of a sample, it accumulates information for up to this timestamp
    /// @return oracleSize The size of the oracle (last ids can be empty)
    /// @return oracleActiveSize The active size of the oracle (no empty data)
    /// @return oracleLastTimestamp The timestamp of the creation of the oracle's latest sample
    /// @return oracleId The index of the oracle's latest sample
    function _getOracleParameters()
        private
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
        oracleId = _slot.decode(type(uint16).max, _OFFSET_ORACLE_ID);
    }

    /// @notice Return the reserves and the active id of the pair
    /// @return reserveX The reserve of token X
    /// @return reserveY The reserve of token Y
    /// @return activeId The active id of the pair
    function _getReservesAndId()
        private
        view
        returns (
            uint256 reserveX,
            uint256 reserveY,
            uint256 activeId
        )
    {
        uint256 _mask24 = type(uint24).max;
        uint256 _mask136 = type(uint136).max;
        assembly {
            let slot := sload(add(_pairInformation.slot, 1))
            reserveY := and(slot, _mask136)

            slot := sload(_pairInformation.slot)
            activeId := and(slot, _mask24)
            reserveX := and(shr(_OFFSET_PAIR_RESERVE_X, slot), _mask136)
        }
    }

    /// @notice Return the reserves of the bin at index `_id`
    /// @param _id The id of the bin
    /// @return reserveX The reserve of token X in the bin
    /// @return reserveY The reserve of token Y in the bin
    function _getBin(uint24 _id) private view returns (uint256 reserveX, uint256 reserveY) {
        bytes32 _data;
        uint256 _mask112 = type(uint112).max;
        // low level read of mapping to only load 1 storage slot
        assembly {
            mstore(0, _id)
            mstore(32, _bins.slot)
            _data := sload(keccak256(0, 64))

            reserveX := and(_data, _mask112)
            reserveY := shr(_OFFSET_BIN_RESERVE_Y, _data)
        }

        return (reserveX.safe112(), reserveY.safe112());
    }

    /// @notice Return the total fees and the protocol fees of the pair
    /// @dev The fees for users can be computed by subtracting the protocol fees from the total fees
    /// @return feesXTotal The total fees of token X
    /// @return feesYTotal The total fees of token Y
    /// @return feesXProtocol The protocol fees of token X
    /// @return feesYProtocol The protocol fees of token Y
    function _getGlobalFees()
        private
        view
        returns (
            uint128 feesXTotal,
            uint128 feesYTotal,
            uint128 feesXProtocol,
            uint128 feesYProtocol
        )
    {
        bytes32 _slotX;
        bytes32 _slotY;
        assembly {
            _slotX := sload(add(_pairInformation.slot, 2))
            _slotY := sload(add(_pairInformation.slot, 3))
        }

        feesXTotal = uint128(_slotX.decode(type(uint128).max, 0));
        feesYTotal = uint128(_slotY.decode(type(uint128).max, 0));

        feesXProtocol = uint128(_slotX.decode(type(uint128).max, _OFFSET_PROTOCOL_FEE));
        feesYProtocol = uint128(_slotY.decode(type(uint128).max, _OFFSET_PROTOCOL_FEE));
    }

    /// @notice Return the fee added to a flashloan
    /// @dev Rounds up the amount of fees
    /// @param _amount The amount of the flashloan
    /// @return The fee added to the flashloan
    function _getFlashLoanFee(uint256 _amount) private view returns (uint256) {
        uint256 _fee = factory.flashLoanFee();
        return (_amount * _fee + Constants.PRECISION - 1) / Constants.PRECISION;
    }

    /// @notice Set the total and protocol fees
    /// @dev The assembly block does:
    /// _pairFees = FeeHelper.FeesDistribution({total: _totalFees, protocol: _protocolFees});
    /// @param _pairFees The storage slot of the fees
    /// @param _totalFees The new total fees
    /// @param _protocolFees The new protocol fees
    function _setFees(
        FeeHelper.FeesDistribution storage _pairFees,
        uint128 _totalFees,
        uint128 _protocolFees
    ) private {
        assembly {
            sstore(_pairFees.slot, and(shl(_OFFSET_PROTOCOL_FEE, _protocolFees), _totalFees))
        }
    }

    /// @notice Emit the Swap event and avoid stack too deep error
    /// if `swapForY` is:
    /// - true: tokenIn is tokenX, and tokenOut is tokenY
    /// - false: tokenIn is tokenY, and tokenOut is tokenX
    /// @param _to The address of the recipient of the swap
    /// @param _swapForY Whether the `amountInToBin` is tokenX (true) or tokenY (false),
    /// and if `amountOutOfBin` is tokenY (true) or tokenX (false)
    /// @param _amountInToBin The amount of tokenIn sent by the user
    /// @param _amountOutOfBin The amount of tokenOut received by the user
    /// @param _volatilityAccumulated The volatility accumulated number
    /// @param _fees The amount of fees, always denominated in tokenIn
    function _emitSwap(
        address _to,
        uint24 _activeId,
        bool _swapForY,
        uint256 _amountInToBin,
        uint256 _amountOutOfBin,
        uint256 _volatilityAccumulated,
        uint256 _fees
    ) private {
        emit Swap(
            msg.sender,
            _to,
            _activeId,
            _swapForY,
            _amountInToBin,
            _amountOutOfBin,
            _volatilityAccumulated,
            _fees
        );
    }
}
