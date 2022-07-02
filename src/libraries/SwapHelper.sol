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
    /// @param sentTokenY Wether the token sent was Y (true) or X (false)
    /// @param startId The id at which the swap started
    /// @param amountIn The amount sent to the user
    /// @return amountInToBin The amount of token that is added to the bin without the fees
    /// @return amountOutOfBin The amount of token that is removed from the bin
    /// @return fees The swap fees
    function getAmounts(
        ILBPair.PairInformation memory pair,
        ILBPair.Bin memory bin,
        FeeHelper.FeeParameters memory fp,
        bool sentTokenY,
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
            uint256 _price = BinHelper.getPriceFromId(pair.id, fp.binStep);

            uint256 _reserve;
            uint256 _maxAmountInToBin;
            if (sentTokenY) {
                _reserve = bin.reserveX;
                _maxAmountInToBin = _price.mulDivRoundUp(
                    _reserve,
                    Constants.SCALE
                );
            } else {
                _reserve = bin.reserveY;
                _maxAmountInToBin = Constants.SCALE.mulDivRoundUp(
                    _reserve,
                    _price
                );
            }

            uint256 _deltaId = startId > pair.id
                ? startId - pair.id
                : pair.id - startId;

            fees = fp.getFeesDistribution(fp.getFees(_reserve, _deltaId));

            if (_maxAmountInToBin.add(fees.total) <= amountIn) {
                amountInToBin = _maxAmountInToBin;
                amountOutOfBin = _reserve;
            } else {
                fees = fp.getFeesDistribution(
                    fp.getFeesFrom(amountIn, _deltaId)
                );
                amountInToBin = amountIn.sub(fees.total);
                amountOutOfBin = amountInToBin.mulDivRoundDown(
                    _reserve,
                    _maxAmountInToBin
                );
                // Safety check in case rounding returns a higher value because of rounding
                if (amountOutOfBin > _reserve) amountOutOfBin = _reserve;
            }
        }
    }

    /// @notice Update the memory variables of the bin
    /// @param pair The pair information
    /// @param bin The bin information
    /// @param fees The fees amounts
    /// @param sentTokenY Wether the token sent was Y (true) or X (false)
    /// @param totalSupply The total supply of the token id
    /// @param amountInToBin The amount of token that is added to the bin without fees
    /// @param amountOutOfBin The amount of token that is removed from the bin
    function update(
        ILBPair.PairInformation memory pair,
        ILBPair.Bin memory bin,
        FeeHelper.FeesDistribution memory fees,
        bool sentTokenY,
        uint256 totalSupply,
        uint256 amountInToBin,
        uint256 amountOutOfBin
    ) internal pure {
        if (sentTokenY) {
            pair.feesY.total += fees.total;
            pair.feesY.protocol += fees.protocol;

            bin.accTokenYPerShare +=
                ((fees.total - fees.protocol) * Constants.SCALE) /
                totalSupply;

            bin.reserveY += uint112(amountInToBin);
            unchecked {
                bin.reserveX -= uint112(amountOutOfBin);

                pair.reserveX -= uint136(amountOutOfBin);
                pair.reserveY += uint136(amountInToBin);
            }
        } else {
            pair.feesX.total += fees.total;
            pair.feesX.protocol += fees.protocol;

            bin.accTokenXPerShare +=
                ((fees.total - fees.protocol) * Constants.SCALE) /
                totalSupply;

            bin.reserveX += uint112(amountInToBin);
            unchecked {
                bin.reserveY -= uint112(amountOutOfBin);

                pair.reserveX += uint136(amountInToBin);
                pair.reserveY -= uint136(amountOutOfBin);
            }
        }
    }
}
