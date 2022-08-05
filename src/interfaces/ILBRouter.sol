// SPDX-License-Identifier: MIT

pragma solidity >=0.8.7;

import "./ILBPair.sol";
import "./ILBRouter.sol";
import "./IWAVAX.sol";
import "./IJoeFactory.sol";

interface ILBRouter {
    /// - The liquidity parameters, such as:
    /// - tokenX: The address of token X
    /// - tokenY: The address of token Y
    /// - binStep: The bin step of the pair
    /// - amountX: The amount to send of token X
    /// - amountY: The amount to send of token Y
    /// - amountXMin: The min amount of token X added to liquidity
    /// - amountYMin: The min amount of token Y added to liquidity
    /// - activeIdDesired: The active id that user wants to add liquidity from
    /// - idSlippage: The number of id that are allowed to slip
    /// - deltaIds: The list of delta ids to add liquidity (`deltaId = activeId - desiredId`)
    /// - distributionX: The distribution of tokenX with sum(distributionX) = 100e18 (100%) or 0 (0%)
    /// - distributionY: The distribution of tokenY with sum(distributionY) = 100e18 (100%) or 0 (0%)
    /// - to: The address of the recipient
    /// - deadline: The deadline of the tx
    struct LiquidityParameters {
        IERC20 tokenX;
        IERC20 tokenY;
        uint256 binStep;
        uint256 amountX;
        uint256 amountY;
        uint256 amountXMin;
        uint256 amountYMin;
        uint256 activeIdDesired;
        uint256 idSlippage;
        int256[] deltaIds;
        uint256[] distributionX;
        uint256[] distributionY;
        address to;
        uint256 deadline;
    }

    function factory() external view returns (ILBFactory);

    function oldFactory() external view returns (IJoeFactory);

    function wavax() external view returns (IWAVAX);

    function getIdFromPrice(ILBPair LBPair, uint256 price) external view returns (uint24);

    function getPriceFromId(ILBPair LBPair, uint24 id) external view returns (uint256);

    function getSwapIn(
        ILBPair LBPair,
        uint256 amountOut,
        bool swapForY
    ) external view returns (uint256 amountIn);

    function getSwapOut(
        ILBPair LBPair,
        uint256 amountIn,
        bool swapForY
    ) external view returns (uint256 amountOut);

    function createLBPair(
        IERC20 tokenX,
        IERC20 tokenY,
        uint24 activeId,
        uint16 binStep
    ) external;

    function addLiquidity(LiquidityParameters memory liquidityParameters) external;

    function addLiquidityAVAX(LiquidityParameters memory liquidityParameters) external payable;

    function removeLiquidity(
        IERC20 tokenX,
        IERC20 tokenY,
        uint8 binStep,
        uint256 amountXMin,
        uint256 amountYMin,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to,
        uint256 deadline
    ) external;

    function removeLiquidityAVAX(
        IERC20 token,
        uint8 binStep,
        uint256 amountTokenMin,
        uint256 amountAVAXMin,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256[] memory pairVersions,
        IERC20[] memory tokenPath,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForAVAX(
        uint256 amountIn,
        uint256 amountOutMinAVAX,
        uint256[] memory pairVersions,
        IERC20[] memory tokenPath,
        address to,
        uint256 deadline
    ) external;

    function swapExactAVAXForTokens(
        uint256 amountOutMin,
        uint256[] memory pairVersions,
        IERC20[] memory tokenPath,
        address to,
        uint256 deadline
    ) external payable;

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        uint256[] memory pairVersions,
        IERC20[] memory tokenPath,
        address to,
        uint256 deadline
    ) external;

    function swapTokensForExactAVAX(
        uint256 amountOut,
        uint256 amountInMax,
        uint256[] memory pairVersions,
        IERC20[] memory tokenPath,
        address to,
        uint256 deadline
    ) external;

    function swapAVAXForExactTokens(
        uint256 amountOut,
        uint256[] memory pairVersions,
        IERC20[] memory tokenPath,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256[] memory pairVersions,
        IERC20[] memory tokenPath,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForAVAXSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMinAVAX,
        uint256[] memory pairVersions,
        IERC20[] memory tokenPath,
        address to,
        uint256 deadline
    ) external;

    function swapExactAVAXForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        uint256[] memory pairVersions,
        IERC20[] memory tokenPath,
        address to,
        uint256 deadline
    ) external payable;

    function sweep(
        IERC20 token,
        address to,
        uint256 amount
    ) external;
}
