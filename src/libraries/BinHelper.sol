// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./math/PackedUint128Math.sol";
import "./math/Uint256x256Math.sol";
import "./math/SafeCast.sol";
import "./Constants.sol";
import "./PairParameterHelper.sol";
import "./FeeHelper.sol";
import "./PriceHelper.sol";
import "./TokenHelper.sol";

/**
 * @title Liquidity Book Bin Helper Library
 * @author Trader Joe
 * @notice This library contains functions to help interaction with bins.
 */
library BinHelper {
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using Uint256x256Math for uint256;
    using PriceHelper for uint24;
    using SafeCast for uint256;
    using PairParameterHelper for bytes32;
    using FeeHelper for uint128;
    using TokenHelper for IERC20;

    error BinMath__CompositionFactorFlawed(uint24 id);

    /**
     * @dev Returns the amount of tokens that will be received when burning the given amount of liquidity
     * @param binReserves The reserves of the bin
     * @param amountToBurn The amount of liquidity to burn
     * @param totalSupply The total supply of the liquidity book
     * @return amountsOut The encoded amount of tokens that will be received
     */
    function getAmountOutOfBin(bytes32 binReserves, uint256 amountToBurn, uint256 totalSupply)
        internal
        pure
        returns (bytes32 amountsOut)
    {
        (uint128 binReserveX, uint128 binReserveY) = binReserves.decode();

        uint128 amountXOutFromBin;
        uint128 amountYOutFromBin;

        if (binReserveX > 0) {
            amountXOutFromBin = (amountToBurn.mulDivRoundDown(binReserveX, totalSupply)).safe128();
        }

        if (binReserveY > 0) {
            amountYOutFromBin = (amountToBurn.mulDivRoundDown(binReserveY, totalSupply)).safe128();
        }

        amountsOut = amountXOutFromBin.encode(amountYOutFromBin);
    }

    /**
     * @dev Returns the share and the effective amounts in when adding liquidity
     * @param binReserves The reserves of the bin
     * @param amountsIn The amounts of tokens to add
     * @param price The price of the bin
     * @param totalSupply The total supply of the liquidity book
     * @return shares The share of the liquidity book that the user will receive
     * @return effectiveAmountsIn The encoded effective amounts of tokens that the user will add.
     * This is the amount of tokens that the user will actually add to the liquidity book,
     * and will always be less than or equal to the amountsIn.
     */
    function getShareAndEffectiveAmountsIn(bytes32 binReserves, bytes32 amountsIn, uint256 price, uint256 totalSupply)
        internal
        pure
        returns (uint256 shares, bytes32 effectiveAmountsIn)
    {
        uint256 userLiquidity = getLiquidity(amountsIn, price);
        if (totalSupply == 0) return (userLiquidity, amountsIn);

        uint256 binLiquidity = getLiquidity(binReserves, price);

        shares = userLiquidity.mulDivRoundDown(totalSupply, binLiquidity);
        uint256 effectiveLiquidity = shares.mulDivRoundDown(binLiquidity, totalSupply);

        uint256 ratioLiquidity = effectiveLiquidity.shiftDivRoundUp(Constants.SCALE_OFFSET, userLiquidity);
        effectiveAmountsIn = amountsIn.scalarMulShift128RoundUp(ratioLiquidity.safe128());
    }

    /**
     * @dev Returns the amount of liquidity following the constant sum formula `L = price * x + y`
     * @param amounts The amounts of tokens
     * @param price The price of the bin
     * @return liquidity The amount of liquidity
     */
    function getLiquidity(bytes32 amounts, uint256 price) internal pure returns (uint256 liquidity) {
        (uint128 x, uint128 y) = amounts.decode();
        if (x > 0) {
            liquidity = price.mulShiftRoundDown(x, Constants.SCALE_OFFSET);
        }
        if (y > 0) {
            liquidity += y;
        }
    }

    /**
     * @dev Verify that the amounts are correct and that the composition factor is not flawed
     * @param amounts The amounts of tokens
     * @param activeId The id of the active bin
     * @param id The id of the bin
     */
    function verifyAmounts(bytes32 amounts, uint24 activeId, uint24 id) internal pure {
        if (
            uint256(amounts) <= type(uint128).max && id < activeId
                || uint256(amounts) > type(uint128).max && id > activeId
        ) revert BinMath__CompositionFactorFlawed(id);
    }

    /**
     * @dev Returns the composition fees when adding liquidity to the active bin with a different
     * composition factor than the bin's one, as it does an implicit swap
     * @param binReserves The reserves of the bin
     * @param parameters The parameters of the liquidity book
     * @param binStep The step of the bin
     * @param amountsIn The amounts of tokens to add
     * @param totalSupply The total supply of the liquidity book
     * @param shares The share of the liquidity book that the user will receive
     * @return fees The encoded fees that will be charged
     */
    function getCompositionFees(
        bytes32 binReserves,
        bytes32 parameters,
        uint8 binStep,
        bytes32 amountsIn,
        uint256 totalSupply,
        uint256 shares
    ) internal pure returns (bytes32 fees) {
        (uint128 amountX, uint128 amountY) = amountsIn.decode();
        (uint128 receivedAmountX, uint128 receivedAmountY) =
            getAmountOutOfBin(binReserves.add(amountsIn), shares, totalSupply + shares).decode();

        if (receivedAmountX > amountX) {
            uint128 feeY = (amountY - receivedAmountY).getCompositionFee(parameters.getTotalFee(binStep));

            fees = feeY.encodeSecond();
        } else if (receivedAmountY > amountY) {
            uint128 feeX = (amountX - receivedAmountX).getCompositionFee(parameters.getTotalFee(binStep));

            fees = feeX.encodeFirst();
        }
    }

    /**
     * @dev Returns whether the bin is empty (true) or not (false)
     * @param binReserves The reserves of the bin
     * @param isX Whether the reserve to check is the X reserve (true) or the Y reserve (false)
     * @return Whether the bin is empty (true) or not (false)
     */
    function isEmpty(bytes32 binReserves, bool isX) internal pure returns (bool) {
        return isX ? binReserves.decodeFirst() == 0 : binReserves.decodeSecond() == 0;
    }

    /**
     * @dev Returns the amounts of tokens that will be added and removed from the bin during a swap
     * along with the fees that will be charged
     * @param binReserves The reserves of the bin
     * @param parameters The parameters of the liquidity book
     * @param binStep The step of the bin
     * @param swapForY Whether the swap is for Y (true) or for X (false)
     * @param activeId The id of the active bin
     * @param amountsLeft The amounts of tokens left to swap
     * @return amountsInToBin The encoded amounts of tokens that will be added to the bin
     * @return amountsOutOfBin The encoded amounts of tokens that will be removed from the bin
     * @return totalFees The encoded fees that will be charged
     */
    function getAmounts(
        bytes32 binReserves,
        bytes32 parameters,
        uint8 binStep,
        bool swapForY, // swap `swapForY` and `activeId` to avoid stack too deep
        uint24 activeId,
        bytes32 amountsLeft
    ) internal pure returns (bytes32 amountsInToBin, bytes32 amountsOutOfBin, bytes32 totalFees) {
        uint256 price = activeId.getPriceFromId(binStep);

        uint128 binReserveOut = binReserves.decode(!swapForY);

        uint128 maxAmountIn = swapForY
            ? uint256(binReserveOut).shiftDivRoundUp(Constants.SCALE_OFFSET, price).safe128()
            : uint256(binReserveOut).mulShiftRoundUp(price, Constants.SCALE_OFFSET).safe128();

        uint128 totalFee = parameters.getTotalFee(binStep);
        uint128 maxFee = maxAmountIn.getFeeAmount(totalFee);

        uint128 fee128;
        uint128 amountIn128;
        uint128 amountOut128;

        uint128 amountIn = amountsLeft.decode(swapForY);

        if (amountIn >= maxAmountIn + maxFee) {
            fee128 = maxFee;

            amountIn128 = maxAmountIn + maxFee;
            amountOut128 = binReserveOut;
        } else {
            fee128 = amountIn.getFeeAmountFrom(totalFee);

            amountIn128 = amountIn;

            amountIn -= fee128;
            amountOut128 = swapForY
                ? uint256(amountIn).mulShiftRoundDown(price, Constants.SCALE_OFFSET).safe128()
                : uint256(amountIn).shiftDivRoundDown(Constants.SCALE_OFFSET, price).safe128();

            if (amountOut128 > binReserveOut) amountOut128 = binReserveOut;
        }

        (amountsInToBin, amountsOutOfBin, totalFees) = swapForY
            ? (amountIn128.encodeFirst(), amountOut128.encodeSecond(), fee128.encodeFirst())
            : (amountIn128.encodeSecond(), amountOut128.encodeFirst(), fee128.encodeSecond());
    }

    /**
     * @dev Returns the encoded amounts that was transferred to the contract
     * @param reserves The reserves
     * @param tokenX The token X
     * @param tokenY The token Y
     * @return amounts The amounts, encoded as follows:
     * [0 - 128[: amountX
     * [128 - 256[: amountY
     */
    function received(bytes32 reserves, IERC20 tokenX, IERC20 tokenY) internal view returns (bytes32 amounts) {
        amounts = _balanceOf(tokenX).encode(_balanceOf(tokenY)).sub(reserves);
    }

    /**
     * @dev Returns the encoded amounts that was transferred to the contract, only for token X
     * @param reserves The reserves
     * @param tokenX The token X
     * @return amounts The amounts, encoded as follows:
     * [0 - 128[: amountX
     * [128 - 256[: empty
     */
    function receivedX(bytes32 reserves, IERC20 tokenX) internal view returns (bytes32) {
        uint128 reserveX = reserves.decodeFirst();
        return (_balanceOf(tokenX) - reserveX).encodeFirst();
    }

    /**
     * @dev Returns the encoded amounts that was transferred to the contract, only for token Y
     * @param reserves The reserves
     * @param tokenY The token Y
     * @return amounts The amounts, encoded as follows:
     * [0 - 128[: empty
     * [128 - 256[: amountY
     */
    function receivedY(bytes32 reserves, IERC20 tokenY) internal view returns (bytes32) {
        uint128 reserveY = reserves.decodeSecond();
        return (_balanceOf(tokenY) - reserveY).encodeSecond();
    }

    /**
     * @dev Transfers the encoded amounts to the recipient
     * @param amounts The amounts, encoded as follows:
     * [0 - 128[: amountX
     * [128 - 256[: amountY
     * @param tokenX The token X
     * @param tokenY The token Y
     * @param recipient The recipient
     */
    function transfer(bytes32 amounts, IERC20 tokenX, IERC20 tokenY, address recipient) internal {
        (uint128 amountX, uint128 amountY) = amounts.decode();

        if (amountX > 0) tokenX.safeTransfer(recipient, amountX);
        if (amountY > 0) tokenY.safeTransfer(recipient, amountY);
    }

    /**
     * @dev Transfers the encoded amounts to the recipient, only for token X
     * @param amounts The amounts, encoded as follows:
     * [0 - 128[: amountX
     * [128 - 256[: empty
     * @param tokenX The token X
     * @param recipient The recipient
     */
    function transferX(bytes32 amounts, IERC20 tokenX, address recipient) internal {
        uint128 amountX = amounts.decodeFirst();

        if (amountX > 0) tokenX.safeTransfer(recipient, amountX);
    }

    /**
     * @dev Transfers the encoded amounts to the recipient, only for token Y
     * @param amounts The amounts, encoded as follows:
     * [0 - 128[: empty
     * [128 - 256[: amountY
     * @param tokenY The token Y
     * @param recipient The recipient
     */
    function transferY(bytes32 amounts, IERC20 tokenY, address recipient) internal {
        uint128 amountY = amounts.decodeSecond();

        if (amountY > 0) tokenY.safeTransfer(recipient, amountY);
    }

    function _balanceOf(IERC20 token) private view returns (uint128) {
        return token.balanceOf(address(this)).safe128();
    }
}
