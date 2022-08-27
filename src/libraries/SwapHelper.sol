// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

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
    /// @param bin The bin information
    /// @param fp The fee parameters
    /// @param activeId The active id of the pair
    /// @param swapForY Whether you've swapping token X for token Y (true) or token Y for token X (false)
    /// @param amountIn The amount sent to the user
    /// @return amountInToBin The amount of token that is added to the bin without the fees
    /// @return amountOutOfBin The amount of token that is removed from the bin
    /// @return fees The swap fees
    function getAmounts(
        ILBPair.Bin memory bin,
        FeeHelper.FeeParameters memory fp,
        uint256 activeId,
        bool swapForY,
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
            uint256 _price = BinHelper.getPriceFromId(activeId, fp.binStep);

            uint256 _reserve;
            uint256 _maxAmountInToBin;
            if (swapForY) {
                _reserve = bin.reserveY;
                _maxAmountInToBin = _reserve.shiftDiv(Constants.SCALE_OFFSET, _price, false);
            } else {
                _reserve = bin.reserveX;
                _maxAmountInToBin = _price.mulShift(_reserve, Constants.SCALE_OFFSET, false);
            }

            fp.updateVolatilityAccumulated(activeId);
            fees = fp.getFeesDistribution(fp.getFees(_maxAmountInToBin));

            if (_maxAmountInToBin.add(fees.total) <= amountIn) {
                amountInToBin = _maxAmountInToBin;
                amountOutOfBin = _reserve;
            } else {
                fees = fp.getFeesDistribution(fp.getFeesFrom(amountIn));
                amountInToBin = amountIn.sub(fees.total);
                amountOutOfBin = swapForY
                    ? _price.mulShift(amountInToBin, Constants.SCALE_OFFSET, true)
                    : amountInToBin.shiftDiv(Constants.SCALE_OFFSET, _price, true);
                // Safety check in case rounding returns a higher value than expected
                if (amountOutOfBin > _reserve) amountOutOfBin = _reserve;
            }
        }
    }

    /// @notice Update the fees of the pair and accumulated token per share of the bin
    /// @param bin The bin information
    /// @param pairFees The current fees of the pair information
    /// @param fees The fees amounts added to the pairFees
    /// @param swapForY whether the token sent was Y (true) or X (false)
    /// @param totalSupply The total supply of the token id
    function updateFees(
        ILBPair.Bin memory bin,
        FeeHelper.FeesDistribution memory pairFees,
        FeeHelper.FeesDistribution memory fees,
        bool swapForY,
        uint256 totalSupply
    ) internal pure {
        uint256 tokenPerShare;

        pairFees.total += fees.total;
        // unsafe math is fine because total >= protocol
        unchecked {
            pairFees.protocol += fees.protocol;

            tokenPerShare = (uint256(fees.total - fees.protocol) << Constants.SCALE_OFFSET) / totalSupply;
        }

        if (swapForY) {
            bin.accTokenXPerShare += tokenPerShare;
        } else {
            bin.accTokenYPerShare += tokenPerShare;
        }
    }

    /// @notice Update reserves
    /// @param bin The bin information
    /// @param pair The pair information
    /// @param swapForY whether the token sent was Y (true) or X (false)
    /// @param amountInToBin The amount of token that is added to the bin without fees
    /// @param amountOutOfBin The amount of token that is removed from the bin
    function updateReserves(
        ILBPair.Bin memory bin,
        ILBPair.PairInformation memory pair,
        bool swapForY,
        uint256 amountInToBin,
        uint256 amountOutOfBin
    ) internal pure {
        if (swapForY) {
            bin.reserveX += uint112(amountInToBin);
            unchecked {
                bin.reserveY -= uint112(amountOutOfBin);

                pair.reserveX += uint136(amountInToBin);
                pair.reserveY -= uint136(amountOutOfBin);
            }
        } else {
            bin.reserveY += uint112(amountInToBin);
            unchecked {
                bin.reserveX -= uint112(amountOutOfBin);

                pair.reserveX -= uint136(amountOutOfBin);
                pair.reserveY += uint136(amountInToBin);
            }
        }
    }
}
