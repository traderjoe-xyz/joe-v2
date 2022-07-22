// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../interfaces/ILBPair.sol";
import "./FeeHelper.sol";
import "./Constants.sol";
import "./BinHelper.sol";
import "./SafeMath.sol";
import "./Math512Bits.sol";

library SwapHelper {
    using Math512Bits for uint256;
    using FeeHelper for FeeHelper.FeeParameters;
    using SafeMath for uint256;

    /// @notice Returns the swap amounts in the current bin
    /// @param pair The pair information
    /// @param bin The bin information
    /// @param fp The fee parameters
    /// @param swapForY Wether you've swapping token X for token Y (true) or token Y for token X (false)
    /// @param startId The id at which the swap started
    /// @param amountIn The amount sent to the user
    /// @return amountInToBin The amount of token that is added to the bin without the fees
    /// @return amountOutOfBin The amount of token that is removed from the bin
    /// @return fees The swap fees
    function getAmounts(
        ILBPair.PairInformation memory pair,
        ILBPair.Bin memory bin,
        FeeHelper.FeeParameters memory fp,
        bool swapForY,
        uint256 startId,
        uint256 amountIn
    )
        internal
        pure
        returns (
            uint256 amountInToBin,
            uint256 amountOutOfBin,
            FeeHelper.FeesDistribution memory fees
        )
    {
        unchecked {
            uint256 _price = BinHelper.getPriceFromId(pair.activeId, fp.binStep);

            uint256 _reserve;
            uint256 _maxAmountInToBin;
            if (swapForY) {
                _reserve = bin.reserveY;
                _maxAmountInToBin = _reserve.shiftDiv(Constants.SCALE_OFFSET, _price, false);
            } else {
                _reserve = bin.reserveX;
                _maxAmountInToBin = _price.mulShift(_reserve, Constants.SCALE_OFFSET, false);
            }

            uint256 _deltaId = startId > pair.activeId ? startId - pair.activeId : pair.activeId - startId;

            fees = fp.getFeesDistribution(fp.getFees(_maxAmountInToBin, _deltaId));

            if (_maxAmountInToBin.add(fees.total) <= amountIn) {
                amountInToBin = _maxAmountInToBin;
                amountOutOfBin = _reserve;
            } else {
                fees = fp.getFeesDistribution(fp.getFeesFrom(amountIn, _deltaId));
                amountInToBin = amountIn.sub(fees.total);
                amountOutOfBin = swapForY
                    ? _price.mulShift(amountInToBin, Constants.SCALE_OFFSET, true)
                    : amountInToBin.shiftDiv(Constants.SCALE_OFFSET, _price, true);
                // Safety check in case rounding returns a higher value because of rounding
                if (amountOutOfBin > _reserve) amountOutOfBin = _reserve;
            }
        }
    }

    /// @notice Update the liquidity variables of the bin
    /// @param pair The pair information
    /// @param bin The bin information
    /// @param fees The fees amounts
    /// @param swapForY whether the token sent was Y (true) or X (false)
    /// @param totalSupply The total supply of the token id
    /// @param amountInToBin The amount of token that is added to the bin without fees
    /// @param amountOutOfBin The amount of token that is removed from the bin
    function updateLiquidity(
        ILBPair.PairInformation memory pair,
        ILBPair.Bin memory bin,
        FeeHelper.FeesDistribution memory fees,
        bool swapForY,
        uint256 totalSupply,
        uint256 amountInToBin,
        uint256 amountOutOfBin
    ) internal pure {
        if (swapForY) {
            pair.feesX.total += fees.total;
            pair.feesX.protocol += fees.protocol;

            bin.accTokenXPerShare += (uint256(fees.total - fees.protocol) << Constants.SCALE_OFFSET) / totalSupply;

            bin.reserveX += uint112(amountInToBin);
            unchecked {
                bin.reserveY -= uint112(amountOutOfBin);

                pair.reserveX += uint136(amountInToBin);
                pair.reserveY -= uint136(amountOutOfBin);
            }
        } else {
            pair.feesY.total += fees.total;
            pair.feesY.protocol += fees.protocol;

            bin.accTokenYPerShare += (uint256(fees.total - fees.protocol) << Constants.SCALE_OFFSET) / totalSupply;

            bin.reserveY += uint112(amountInToBin);
            unchecked {
                bin.reserveX -= uint112(amountOutOfBin);

                pair.reserveX -= uint136(amountOutOfBin);
                pair.reserveY += uint136(amountInToBin);
            }
        }
    }
}
