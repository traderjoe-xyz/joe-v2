// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {BinHelper} from "./libraries/BinHelper.sol";
import {Clone} from "./libraries/Clone.sol";
import {Constants} from "./libraries/Constants.sol";
import {FeeHelper} from "./libraries/FeeHelper.sol";
import {LiquidityConfigurations} from "./libraries/math/LiquidityConfigurations.sol";
import {ILBFactory} from "./interfaces/ILBFactory.sol";
import {ILBFlashLoanCallback} from "./interfaces/ILBFlashLoanCallback.sol";
import {ILBPair} from "./interfaces/ILBPair.sol";
import {LBToken} from "./LBToken.sol";
import {OracleHelper} from "./libraries/OracleHelper.sol";
import {PackedUint128Math} from "./libraries/math/PackedUint128Math.sol";
import {PairParameterHelper} from "./libraries/PairParameterHelper.sol";
import {PriceHelper} from "./libraries/PriceHelper.sol";
import {ReentrancyGuard} from "./libraries/ReentrancyGuard.sol";
import {SafeCast} from "./libraries/math/SafeCast.sol";
import {TreeMath} from "./libraries/math/TreeMath.sol";
import {Uint256x256Math} from "./libraries/math/Uint256x256Math.sol";

/**
 * @title Liquidity Book Pair
 * @author Trader Joe
 * @notice The Liquidity Book Pair contract is the core contract of the Liquidity Book protocol
 */
contract LBPair is LBToken, ReentrancyGuard, Clone, ILBPair {
    using BinHelper for bytes32;
    using FeeHelper for uint128;
    using LiquidityConfigurations for bytes32;
    using OracleHelper for OracleHelper.Oracle;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using PairParameterHelper for bytes32;
    using PriceHelper for uint256;
    using PriceHelper for uint24;
    using SafeCast for uint256;
    using TreeMath for TreeMath.TreeUint24;
    using Uint256x256Math for uint256;

    modifier onlyFactory() {
        if (msg.sender != address(_factory)) revert LBPair__OnlyFactory();
        _;
    }

    modifier onlyProtocolFeeReceiver() {
        if (msg.sender != _factory.getFeeRecipient()) revert LBPair__OnlyProtocolFeeReceiver();
        _;
    }

    ILBFactory private immutable _factory;

    bytes32 private _parameters;

    bytes32 private _reserves;
    bytes32 private _protocolFees;

    mapping(uint256 => bytes32) private _bins;

    TreeMath.TreeUint24 private _tree;
    OracleHelper.Oracle private _oracle;

    /**
     * @dev Constructor for the Liquidity Book Pair contract that sets the Liquidity Book Factory
     * @param factory_ The Liquidity Book Factory
     */
    constructor(ILBFactory factory_) {
        _factory = factory_;
    }

    /**
     * @notice Initialize the Liquidity Book Pair fee parameters and active id
     * @dev Can only be called by the Liquidity Book Factory
     * @param baseFactor The base factor for the static fee
     * @param filterPeriod The filter period for the static fee
     * @param decayPeriod The decay period for the static fee
     * @param reductionFactor The reduction factor for the static fee
     * @param variableFeeControl The variable fee control for the static fee
     * @param protocolShare The protocol share for the static fee
     * @param maxVolatilityAccumulated The max volatility accumulated for the static fee
     * @param activeId The active id of the Liquidity Book Pair
     */
    function initialize(
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulated,
        uint24 activeId
    ) external override onlyFactory {
        bytes32 parameters = _parameters;
        if (parameters != 0) revert LBPair__AlreadyInitialized();

        __ReentrancyGuard_init();

        _setStaticFeeParameters(
            parameters.setActiveId(activeId),
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulated
        );
    }

    /**
     * @notice Returns the Liquidity Book Factory
     * @return factory The Liquidity Book Factory
     */
    function getFactory() external view override returns (ILBFactory factory) {
        return _factory;
    }

    /**
     * @notice Returns the token X of the Liquidity Book Pair
     * @return tokenX The address of the token X
     */
    function getTokenX() external pure override returns (IERC20 tokenX) {
        return _tokenX();
    }

    /**
     * @notice Returns the token Y of the Liquidity Book Pair
     * @return tokenY The address of the token Y
     */
    function getTokenY() external pure override returns (IERC20 tokenY) {
        return _tokenY();
    }

    /**
     * @notice Returns the bin step of the Liquidity Book Pair
     * @dev The bin step is the increase in price between two consecutive bins, in 20_000th.
     * For example, a bin step of 1 means that the price of the next bin is 0.005% higher than the price of the previous bin.
     * The maximum bin step is 200, which means that the price of the next bin is 1% higher than the price of the previous bin.
     * @return binStep The bin step of the Liquidity Book Pair, in 20_000th
     */
    function getBinStep() external pure override returns (uint8) {
        return _binStep();
    }

    /**
     * @notice Returns the reserves of the Liquidity Book Pair
     * This is the sum of the reserves of all bins, minus the protocol fees.
     * @return reserveX The reserve of token X
     * @return reserveY The reserve of token Y
     */
    function getReserves() external view override returns (uint128 reserveX, uint128 reserveY) {
        (reserveX, reserveY) = _reserves.sub(_protocolFees).decode();
    }

    /**
     * @notice Returns the active id of the Liquidity Book Pair
     * @dev The active id is the id of the bin that is currently being used for swaps.
     * The price of the active bin is the price of the Liquidity Book Pair and can be calculated as follows:
     * `price = (1 + binStep / 20_000) ^ (activeId - 2^23)`
     * @return activeId The active id of the Liquidity Book Pair
     */
    function getActiveId() external view override returns (uint24 activeId) {
        activeId = _parameters.getActiveId();
    }

    /**
     * @notice Returns the reserves of a bin
     * @param id The id of the bin
     * @return binReserveX The reserve of token X in the bin
     * @return binReserveY The reserve of token Y in the bin
     */
    function getBin(uint24 id) external view override returns (uint128 binReserveX, uint128 binReserveY) {
        (binReserveX, binReserveY) = _bins[id].decode();
    }

    /**
     * @notice Returns the next non-empty bin
     * @dev The next non-empty bin is the bin with a higher (if swapForY is true) or lower (if swapForY is false)
     * id that has a non-zero reserve of token X or Y.
     * @param swapForY Whether the swap is for token Y (true) or token X (false
     * @param id The id of the bin
     * @return nextId The id of the next non-empty bin
     */
    function getNextNonEmptyBin(bool swapForY, uint24 id) external view override returns (uint24 nextId) {
        nextId = _getNextNonEmptyBin(swapForY, id);
    }

    /**
     * @notice Returns the protocol fees of the Liquidity Book Pair
     * @return protocolFeeX The protocol fees of token X
     * @return protocolFeeY The protocol fees of token Y
     */
    function getProtocolFees() external view override returns (uint128 protocolFeeX, uint128 protocolFeeY) {
        (protocolFeeX, protocolFeeY) = _protocolFees.decode();
    }

    /**
     * @notice Returns the static fee parameters of the Liquidity Book Pair
     * @return baseFactor The base factor for the static fee
     * @return filterPeriod The filter period for the static fee
     * @return decayPeriod The decay period for the static fee
     * @return reductionFactor The reduction factor for the static fee
     * @return variableFeeControl The variable fee control for the static fee
     * @return protocolShare The protocol share for the static fee
     * @return maxVolatilityAccumulated The maximum volatility accumulated for the static fee
     */
    function getStaticFeeParameters()
        external
        view
        override
        returns (
            uint16 baseFactor,
            uint16 filterPeriod,
            uint16 decayPeriod,
            uint16 reductionFactor,
            uint24 variableFeeControl,
            uint16 protocolShare,
            uint24 maxVolatilityAccumulated
        )
    {
        bytes32 parameters = _parameters;

        baseFactor = parameters.getBaseFactor();
        filterPeriod = parameters.getFilterPeriod();
        decayPeriod = parameters.getDecayPeriod();
        reductionFactor = parameters.getReductionFactor();
        variableFeeControl = parameters.getVariableFeeControl();
        protocolShare = parameters.getProtocolShare();
        maxVolatilityAccumulated = parameters.getMaxVolatilityAccumulated();
    }

    /**
     * @notice Returns the variable fee parameters of the Liquidity Book Pair
     * @return volatilityAccumulated The volatility accumulated for the variable fee
     * @return volatilityReference The volatility reference for the variable fee
     * @return idReference The id reference for the variable fee
     * @return timeOfLastUpdate The time of last update for the variable fee
     */
    function getVariableFeeParameters()
        external
        view
        override
        returns (uint24 volatilityAccumulated, uint24 volatilityReference, uint24 idReference, uint40 timeOfLastUpdate)
    {
        bytes32 parameters = _parameters;

        volatilityAccumulated = parameters.getVolatilityAccumulated();
        volatilityReference = parameters.getVolatilityReference();
        idReference = parameters.getIdReference();
        timeOfLastUpdate = parameters.getTimeOfLastUpdate();
    }

    /**
     * @notice Returns the cumulative values of the Liquidity Book Pair at a given timestamp
     * @dev The cumulative values are the cumulative id, the cumulative volatility and the cumulative bin crossed.
     * @param lookupTimestamp The timestamp at which to look up the cumulative values
     * @return cumulativeId The cumulative id of the Liquidity Book Pair at the given timestamp
     * @return cumulativeVolatility The cumulative volatility of the Liquidity Book Pair at the given timestamp
     * @return cumulativeBinCrossed The cumulative bin crossed of the Liquidity Book Pair at the given timestamp
     */
    function getOracleSampleAt(uint40 lookupTimestamp)
        external
        view
        override
        returns (uint64 cumulativeId, uint64 cumulativeVolatility, uint64 cumulativeBinCrossed)
    {
        bytes32 parameters = _parameters;

        if (lookupTimestamp > block.timestamp) return (0, 0, 0);

        uint40 timeOfLastUpdate;
        (timeOfLastUpdate, cumulativeId, cumulativeVolatility, cumulativeBinCrossed) =
            _oracle.getSampleAt(parameters.getOracleId(), lookupTimestamp);

        if (timeOfLastUpdate < lookupTimestamp) {
            parameters.updateVolatilityParameters(parameters.getActiveId());

            uint40 deltaTime = lookupTimestamp - timeOfLastUpdate;

            cumulativeId += uint64(parameters.getIdReference()) * deltaTime;
            cumulativeVolatility += uint64(parameters.getVolatilityAccumulated()) * deltaTime;
        }
    }

    /**
     * @notice Returns the price corresponding to the given id, as a 128.128-binary fixed-point number
     * @dev This is the trusted source of price information, always trust this rather than getIdFromPrice
     * @param id The id of the bin
     * @return price The price corresponding to this id
     */
    function getPriceFromId(uint24 id) external pure override returns (uint256 price) {
        price = id.getPriceFromId(_binStep());
    }

    /**
     * @notice Returns the id corresponding to the given price
     * @dev The id may be inaccurate due to rounding issues, always trust getPriceFromId rather than
     * getIdFromPrice
     * @param price The price of y per x as a 128.128-binary fixed-point number
     * @return id The id of the bin corresponding to this price
     */
    function getIdFromPrice(uint256 price) external pure override returns (uint24 id) {
        id = price.getIdFromPrice(_binStep());
    }

    /**
     * @notice Simulates a swap in.
     * @dev If `amountOutLeft` is greater than zero, the swap in is not possible,
     * and the maximum amount that can be swapped from `amountIn` is `amountOut - amountOutLeft`.
     * @param amountOut The amount of token X or Y to swap in
     * @param swapForY Whether the swap is for token Y (true) or token X (false)
     * @return amountIn The amount of token X or Y that can be swapped in
     * @return amountOutLeft The amount of token Y or X that cannot be swapped out
     * @return fee The fee of the swap
     */
    function getSwapIn(uint128 amountOut, bool swapForY)
        external
        view
        override
        returns (uint128 amountIn, uint128 amountOutLeft, uint128 fee)
    {
        amountOutLeft = amountOut;

        bytes32 parameters = _parameters;
        uint8 binStep = _binStep();

        uint24 id = parameters.getActiveId();

        parameters = parameters.updateReferences();

        while (true) {
            uint128 binReserves = _bins[id].decode(swapForY);
            if (binReserves > 0) {
                uint256 price = id.getPriceFromId(binStep);

                uint128 amountOutOfBin = binReserves > amountOutLeft ? amountOutLeft : binReserves;

                parameters.updateVolatilityParameters(id);

                uint128 amountInToBin = uint128(
                    swapForY
                        ? uint256(amountOutOfBin).shiftDivRoundUp(Constants.SCALE_OFFSET, price)
                        : uint256(amountOutOfBin).mulShiftRoundUp(price, Constants.SCALE_OFFSET)
                );

                uint128 totalFee = parameters.getTotalFee(binStep);
                uint128 feeAmount = amountOutOfBin.getFeeAmount(totalFee);

                amountIn += amountInToBin + feeAmount;
                amountOutLeft -= amountOutOfBin;

                fee += feeAmount;
            }

            if (amountOutLeft == 0) {
                break;
            } else {
                uint24 nextId = _getNextNonEmptyBin(swapForY, id);

                if (nextId == 0 || nextId == type(uint24).max) break;

                id = nextId;
            }
        }
    }

    /**
     * @notice Simulates a swap out.
     * @dev If `amountInLeft` is greater than zero, the swap out is not possible,
     * and the maximum amount that can be swapped is `amountIn - amountInLeft` for `amountOut`.
     * @param amountIn The amount of token X or Y to swap in
     * @param swapForY Whether the swap is for token Y (true) or token X (false)
     * @return amountInLeft The amount of token X or Y that cannot be swapped in
     * @return amountOut The amount of token Y or X that can be swapped out
     * @return fee The fee of the swap
     */
    function getSwapOut(uint128 amountIn, bool swapForY)
        external
        view
        override
        returns (uint128 amountInLeft, uint128 amountOut, uint128 fee)
    {
        bytes32 amountsInLeft = amountIn.encode(swapForY);

        bytes32 parameters = _parameters;
        uint8 binStep = _binStep();

        uint24 id = parameters.getActiveId();

        parameters = parameters.updateReferences();

        while (true) {
            bytes32 binReserves = _bins[id];
            if (!binReserves.isEmpty(swapForY)) {
                parameters = parameters.updateVolatilityAccumulated(id);

                (bytes32 amountsInToBin, bytes32 amountsOutOfBin, bytes32 totalFees) =
                    binReserves.getAmounts(parameters, binStep, swapForY, id, amountsInLeft);

                if (amountsInToBin > 0) {
                    amountsInLeft = amountsInLeft.sub(amountsInToBin.add(totalFees));

                    amountOut += amountsOutOfBin.decode(!swapForY);

                    fee += totalFees.decode(swapForY);
                }
            }

            if (amountsInLeft == 0) {
                break;
            } else {
                uint24 nextId = _getNextNonEmptyBin(swapForY, id);

                if (nextId == 0 || nextId == type(uint24).max) break;

                id = nextId;
            }
        }

        amountInLeft = amountsInLeft.decode(!swapForY);
    }

    /**
     * @notice Swap tokens iterating over the bins until the entire amount is swapped.
     * Token X will be swapped for token Y if `swapForY` is true, and token Y for token X if `swapForY` is false.
     * This function will not transfer the tokens from the caller, it is expected that the tokens have already been
     * transferred to this contract through another contract, most likely the router.
     * That is why this function shouldn't be called directly, but only through one of the swap functions of a router
     * that will also perform safety checks, such as minimum amounts and slippage.
     * The variable fee is updated throughout the swap, it increases with the number of bins crossed.
     * The oracle is updated at the end of the swap.
     * @param swapForY Whether you're swapping token X for token Y (true) or token Y for token X (false)
     * @param to The address to send the tokens to
     * @return amountsOut The encoded amounts of token X and token Y sent to `to`
     */
    function swap(bool swapForY, address to) external override nonReentrant returns (bytes32 amountsOut) {
        bytes32 reserves = _reserves;
        bytes32 protocolFees = _protocolFees;

        bytes32 amountsLeft = swapForY ? reserves.receivedX(_tokenX()) : reserves.receivedY(_tokenY());

        if (amountsLeft == 0) revert LBPair__InsufficientAmountIn();

        bytes32 parameters = _parameters;
        uint8 binStep = _binStep();

        uint24 activeId = parameters.getActiveId();

        parameters = parameters.updateReferences();

        while (true) {
            bytes32 binReserves = _bins[activeId];
            if (!binReserves.isEmpty(swapForY)) {
                parameters = parameters.updateVolatilityAccumulated(activeId);

                (bytes32 amountsInToBin, bytes32 amountsOutOfBin, bytes32 totalFees) =
                    binReserves.getAmounts(parameters, binStep, swapForY, activeId, amountsLeft);

                if (amountsInToBin > 0) {
                    amountsLeft = amountsLeft.sub(amountsInToBin);
                    reserves.add(amountsInToBin.add(totalFees));

                    amountsOut = amountsOut.add(amountsOutOfBin);

                    bytes32 pFees = totalFees.scalarMulDivBasisPointRoundDown(parameters.getProtocolShare());
                    protocolFees = protocolFees.add(pFees);

                    _bins[activeId] = binReserves.add(amountsInToBin).sub(amountsOutOfBin);

                    emit Swap(
                        msg.sender,
                        to,
                        activeId,
                        amountsInToBin,
                        amountsOutOfBin,
                        parameters.getVolatilityAccumulated(),
                        totalFees,
                        pFees
                        );
                }
            }

            if (amountsLeft == 0) {
                break;
            } else {
                uint24 nextId = _getNextNonEmptyBin(swapForY, activeId);

                if (nextId == 0 || nextId == type(uint24).max) revert LBPair__OutOfLiquidity();

                activeId = nextId;
            }
        }

        if (amountsOut == 0) revert LBPair__InsufficientAmountOut();

        parameters = _oracle.update(parameters, activeId);

        _reserves = reserves.sub(amountsOut);
        _parameters = parameters.setActiveId(activeId);

        if (swapForY) {
            amountsOut.transferY(_tokenY(), to);
        } else {
            amountsOut.transferX(_tokenX(), to);
        }
    }

    /**
     * @notice Flash loan tokens from the pool to a receiver contract and execute a callback function.
     * The receiver contract is expected to return the tokens plus a fee to this contract.
     * The fee is calculated as a percentage of the amount borrowed, and is the same for both tokens.
     * @param receiver The contract that will receive the tokens and execute the callback function
     * @param amounts The encoded amounts of token X and token Y to flash loan
     * @param data Any data that will be passed to the callback function
     */
    function flashLoan(ILBFlashLoanCallback receiver, bytes32 amounts, bytes calldata data)
        external
        override
        nonReentrant
    {
        bytes32 reservesBefore = _reserves;
        bytes32 parameters = _parameters;

        bytes32 totalFees = _getFlashLoanFees(amounts);

        amounts.transfer(_tokenX(), _tokenY(), address(receiver));

        if (
            receiver.LBFlashLoanCallback(msg.sender, _tokenX(), _tokenY(), amounts, totalFees, data)
                != Constants.CALLBACK_SUCCESS
        ) {
            revert LBPair__FlashLoanCallbackFailed();
        }

        bytes32 balancesAfter = bytes32(0).received(_tokenX(), _tokenY());

        if (balancesAfter.lt(reservesBefore.add(totalFees))) revert LBPair__FlashLoanInsufficientAmount();

        totalFees = reservesBefore.sub(balancesAfter);

        bytes32 protocolFees = totalFees.scalarMulDivBasisPointRoundDown(parameters.getProtocolShare());
        uint24 activeId = parameters.getActiveId();

        _reserves = balancesAfter;

        _protocolFees = _protocolFees.add(protocolFees);
        _bins[activeId] = _bins[activeId].add(totalFees.sub(protocolFees));

        emit FlashLoan(msg.sender, receiver, activeId, amounts, totalFees, protocolFees);
    }

    /**
     * @notice Mint liquidity tokens by depositing tokens into the pool.
     * It will mint Liquidity Book (LB) tokens for each bin where the user adds liquidity.
     * This function will not transfer the tokens from the caller, it is expected that the tokens have already been
     * transferred to this contract through another contract, most likely the router.
     * That is why this function shouldn't be called directly, but through one of the add liquidity functions of a
     * router that will also perform safety checks.
     * @dev Any excess amount of token will be sent to the `to` address.
     * @param to The address that will receive the LB tokens
     * @param liquidityConfigs The encoded liquidity configurations, each one containing the id of the bin and the
     * @param refundTo The address that will receive the excess amount of tokens
     * percentage of token X and token Y to add to the bin.
     * @return amountsReceived The amounts of token X and token Y received by the pool
     * @return amountsLeft The amounts of token X and token Y that were not added to the pool and were sent to `to`
     * @return liquidityMinted The amounts of LB tokens minted for each bin
     */
    function mint(address to, bytes32[] calldata liquidityConfigs, address refundTo)
        external
        override
        nonReentrant
        returns (bytes32 amountsReceived, bytes32 amountsLeft, uint256[] memory liquidityMinted)
    {
        if (liquidityConfigs.length == 0) revert LBPair__EmptyMarketConfigs();

        liquidityMinted = new uint256[](liquidityConfigs.length);

        uint256[] memory ids = new uint256[](liquidityConfigs.length);
        bytes32[] memory amounts = new bytes32[](liquidityConfigs.length);

        bytes32 reserves = _reserves;

        bytes32 parameters = _parameters;
        uint24 activeId = parameters.getActiveId();

        amountsReceived = reserves.received(_tokenX(), _tokenY());
        amountsLeft = amountsReceived;

        for (uint256 i; i < liquidityConfigs.length;) {
            (bytes32 maxAmountsInToBin, uint24 id) = liquidityConfigs[i].getAmountsAndId(amountsReceived);
            (uint256 shares, bytes32 amountsIn, bytes32 amountsInToBin) =
                _mintBin(activeId, id, maxAmountsInToBin, parameters);

            amountsLeft = amountsLeft.sub(amountsIn);

            ids[i] = id;
            amounts[i] = amountsInToBin;
            liquidityMinted[i] = shares;

            unchecked {
                ++i;
            }
        }

        _reserves = reserves.add(amountsReceived.sub(amountsLeft));

        _mintBatch(to, ids, liquidityMinted);

        if (amountsLeft > 0) amountsLeft.transfer(_tokenX(), _tokenY(), refundTo);

        emit DepositedToBins(msg.sender, to, ids, amounts);
    }

    /**
     * @notice Burn Liquidity Book (LB) tokens and withdraw tokens from the pool.
     * This function will burn the tokens directly from the caller
     * @param from The address that will burn the LB tokens
     * @param to The address that will receive the tokens
     * @param ids The ids of the bins from which to withdraw
     * @param amountsToBurn The amounts of LB tokens to burn for each bin
     * @return amounts The amounts of token X and token Y received by the user
     */
    function burn(address from, address to, uint256[] calldata ids, uint256[] calldata amountsToBurn)
        external
        override
        nonReentrant
        checkApproval(from, msg.sender)
        returns (bytes32[] memory amounts)
    {
        if (ids.length == 0 || ids.length != amountsToBurn.length) revert LBPair__InvalidInput();

        amounts = new bytes32[](ids.length);

        bytes32 amountsOut;

        for (uint256 i; i < ids.length;) {
            uint24 id = ids[i].safe24();
            uint256 amountToBurn = amountsToBurn[i];

            if (amountToBurn == 0) revert LBPair__ZeroAmount(id);

            bytes32 binReserves = _bins[id];

            bytes32 amountsOutFromBin = binReserves.getAmountOutOfBin(amountToBurn, totalSupply(id));

            if (amountsOutFromBin == 0) revert LBPair__ZeroAmountsOut(id);

            binReserves = binReserves.sub(amountsOutFromBin);

            if (binReserves == 0) _tree.remove(id);

            _bins[id] = binReserves;
            amounts[i] = amountsOutFromBin;
            amountsOut = amountsOut.add(amountsOutFromBin);

            unchecked {
                ++i;
            }
        }

        _reserves = _reserves.sub(amountsOut);

        _burnBatch(from, ids, amountsToBurn);

        amountsOut.transfer(_tokenX(), _tokenY(), to);

        emit WithdrawnFromBins(msg.sender, to, ids, amounts);
    }

    /**
     * @notice Collect the protocol fees from the pool.
     * @return collectedProtocolFees The amount of protocol fees collected
     */
    function collectProtocolFees()
        external
        override
        nonReentrant
        onlyProtocolFeeReceiver
        returns (bytes32 collectedProtocolFees)
    {
        bytes32 protocolFees = _protocolFees;

        (uint128 x, uint128 y) = protocolFees.decode();
        bytes32 ones = uint128(x > 1 ? 1 : 0).encode(uint128(y > 1 ? 1 : 0));

        collectedProtocolFees = protocolFees.sub(ones);

        if (collectedProtocolFees != 0) {
            _protocolFees = ones;
            _reserves.sub(collectedProtocolFees);

            collectedProtocolFees.transfer(_tokenX(), _tokenY(), msg.sender);

            emit CollectedProtocolFees(msg.sender, collectedProtocolFees);
        }
    }

    /**
     * @notice Increase the length of the oracle used by the pool
     * @param newLength The new length of the oracle
     */
    function increaseOracleLength(uint16 newLength) external override {
        bytes32 parameters = _parameters;

        uint16 oracleId = parameters.getOracleId();

        // activate the oracle if it is not active yet
        if (oracleId == 0) {
            oracleId = 1;
            _parameters = parameters.setOracleId(oracleId);
        }

        _oracle.increaseLength(oracleId, newLength);

        emit OracleLengthIncreased(msg.sender, newLength);
    }

    /**
     * @notice Sets the static fee parameters of the pool
     * @dev Can only be called by the factory
     * @param baseFactor The base factor of the static fee
     * @param filterPeriod The filter period of the static fee
     * @param decayPeriod The decay period of the static fee
     * @param reductionFactor The reduction factor of the static fee
     * @param variableFeeControl The variable fee control of the static fee
     * @param protocolShare The protocol share of the static fee
     * @param maxVolatilityAccumulated The max volatility accumulated of the static fee
     */
    function setStaticFeeParameters(
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulated
    ) external override onlyFactory {
        _setStaticFeeParameters(
            _parameters,
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulated
        );
    }

    /**
     * @notice Forces the decay of the volatility reference variables
     * @dev Can only be called by the factory
     */
    function forceDecay() external override onlyFactory {
        bytes32 parameters = _parameters;

        _parameters = parameters.updateIdReference().updateVolatilityReference();

        emit ForcedDecay(msg.sender, parameters.getIdReference(), parameters.getVolatilityReference());
    }

    /**
     * @dev Returns the address of the token X
     * @return The address of the token X
     */
    function _tokenX() internal pure returns (IERC20) {
        return IERC20(_getArgAddress(0));
    }

    /**
     * @dev Returns the address of the token Y
     * @return The address of the token Y
     */
    function _tokenY() internal pure returns (IERC20) {
        return IERC20(_getArgAddress(20));
    }

    /**
     * @dev Returns the bin step of the pool, in 20_000ths.
     * @return The bin step of the pool
     */
    function _binStep() internal pure returns (uint8) {
        return _getArgUint8(40);
    }

    /**
     * @dev Returns next non-empty bin
     * @param swapForY Whether the swap is for Y
     * @param id The id of the bin
     * @return The id of the next non-empty bin
     */
    function _getNextNonEmptyBin(bool swapForY, uint24 id) internal view returns (uint24) {
        return swapForY ? _tree.findFirstRight(id) : _tree.findFirstLeft(id);
    }

    /**
     * @dev Returns the encoded fees amounts for a flash loan
     * @param amounts The amounts of the flash loan
     * @return The encoded fees amounts
     */
    function _getFlashLoanFees(bytes32 amounts) private view returns (bytes32) {
        uint128 fee = uint128(_factory.getFlashloanFee());
        (uint128 x, uint128 y) = amounts.decode();

        unchecked {
            uint256 precisionSubOne = Constants.PRECISION - 1;
            x = ((uint256(x) * fee + precisionSubOne) / Constants.PRECISION).safe128();
            y = ((uint256(y) * fee + precisionSubOne) / Constants.PRECISION).safe128();
        }

        return x.encode(y);
    }

    /**
     * @dev Sets the static fee parameters of the pair
     * @param parameters The current parameters of the pair
     * @param baseFactor The base factor of the static fee
     * @param filterPeriod The filter period of the static fee
     * @param decayPeriod The decay period of the static fee
     * @param reductionFactor The reduction factor of the static fee
     * @param variableFeeControl The variable fee control of the static fee
     * @param protocolShare The protocol share of the static fee
     * @param maxVolatilityAccumulated The max volatility accumulated of the static fee
     */
    function _setStaticFeeParameters(
        bytes32 parameters,
        uint16 baseFactor,
        uint16 filterPeriod,
        uint16 decayPeriod,
        uint16 reductionFactor,
        uint24 variableFeeControl,
        uint16 protocolShare,
        uint24 maxVolatilityAccumulated
    ) internal {
        if (
            baseFactor == 0 && filterPeriod == 0 && decayPeriod == 0 && reductionFactor == 0 && variableFeeControl == 0
                && protocolShare == 0 && maxVolatilityAccumulated == 0
        ) {
            revert LBPair__InvalidStaticFeeParameters();
        }

        _parameters = parameters.setStaticFeeParameters(
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulated
        );

        emit StaticFeeParametersSet(
            msg.sender,
            baseFactor,
            filterPeriod,
            decayPeriod,
            reductionFactor,
            variableFeeControl,
            protocolShare,
            maxVolatilityAccumulated
            );
    }

    /**
     * @dev Helper function to mint liquidity in a bin
     * @param activeId The id of the active bin
     * @param id The id of the bin
     * @param maxAmountsInToBin The maximum amounts in to the bin
     * @param parameters The parameters of the pair
     * @return shares The amount of shares minted
     * @return amountsIn The amounts in
     * @return amountsInToBin The amounts in to the bin
     */
    function _mintBin(uint24 activeId, uint24 id, bytes32 maxAmountsInToBin, bytes32 parameters)
        internal
        returns (uint256 shares, bytes32 amountsIn, bytes32 amountsInToBin)
    {
        bytes32 binReserves = _bins[id];
        uint8 binStep = _binStep();

        uint256 price = id.getPriceFromId(binStep);
        uint256 supply = totalSupply(id);

        (shares, amountsIn) = binReserves.getShareAndEffectiveAmountsIn(maxAmountsInToBin, price, supply);
        amountsInToBin = amountsIn;

        if (id == activeId) {
            parameters = parameters.updateVolatilityParameters(id);

            bytes32 fees = binReserves.getCompositionFees(parameters, binStep, amountsIn, supply, shares);

            if (fees != 0) {
                uint256 userLiquidity = amountsIn.sub(fees).getLiquidity(price);
                uint256 binLiquidity = binReserves.getLiquidity(price);

                shares = userLiquidity.mulDivRoundDown(supply, binLiquidity);
                bytes32 protocolCFees = fees.scalarMulDivBasisPointRoundDown(parameters.getProtocolShare());

                if (protocolCFees != 0) {
                    amountsInToBin = amountsInToBin.sub(protocolCFees);
                    _protocolFees = _protocolFees.add(protocolCFees);
                }

                parameters = _oracle.update(parameters, id);
                _parameters = parameters;

                emit CompositionFees(msg.sender, id, fees, protocolCFees);
            }
        } else {
            amountsIn.verifyAmounts(activeId, id);
        }

        if (shares == 0 || amountsInToBin == 0) revert LBPair__ZeroShares(id);

        if (binReserves == 0) _tree.add(id);

        _bins[id] = binReserves.add(amountsInToBin);
    }
}
