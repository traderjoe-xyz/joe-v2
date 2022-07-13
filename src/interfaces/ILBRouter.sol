// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9;

import "./ILBPair.sol";
import "./ILBRouter.sol";
import "./IWAVAX.sol";
import "./IJoeFactory.sol";

interface ILBRouter {
    struct LiquidityParam {
        IERC20 tokenX;
        IERC20 tokenY;
        ILBPair LBPair;
        uint256 amountX;
        uint256 amountY;
        uint256 amountXMin;
        uint256 amountYMin;
        uint256 activeIdDesired;
        uint256 idSlippage;
        int256[] deltaIds;
        uint256[] ids;
        uint256[] distributionX;
        uint256[] distributionY;
        address to;
        uint256 deadline;
    }

    function factory() external view returns (ILBFactory);

    function oldFactory() external view returns (IJoeFactory);

    function wavax() external view returns (IWAVAX);

    function getIdFromPrice(ILBPair LBPair, uint256 _price) external view returns (uint24);

    function getPriceFromId(ILBPair LBPair, uint24 _id) external view returns (uint256);

    function getSwapIn(
        ILBPair _LBPair,
        uint256 _amountOut,
        bool _swapForY
    ) external view returns (uint256 _amountIn);

    function getSwapOut(
        ILBPair _LBPair,
        uint256 _amountIn,
        bool _swapForY
    ) external view returns (uint256 _amountOut);

    function createLBPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _activeId,
        uint256 sampleLifetime,
        uint64 _maxAccumulator,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint16 _binStep,
        uint16 _baseFactor,
        uint16 _protocolShare
    ) external;

    function addLiquidity(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _amountX,
        uint256 _amountY,
        uint256 _amountSlippage,
        uint256 _activeIdDesired,
        uint256 _idSlippage,
        int256[] memory _deltaIds,
        uint256[] memory _distributionX,
        uint256[] memory _distributionY,
        address _to,
        uint256 _deadline
    ) external;

    function addLiquidityAVAX(
        IERC20 _token,
        uint256 _amount,
        uint256 _amountSlippage,
        uint256 _activeIdDesired,
        uint256 _idSlippage,
        int256[] memory _deltaIds,
        uint256[] memory _distributionToken,
        uint256[] memory _distributionAVAX,
        address _to,
        uint256 _deadline
    ) external payable;

    function removeLiquidity(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint256 _amountXMin,
        uint256 _amountYMin,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to,
        uint256 _deadline
    ) external;

    function removeLiquidityAVAX(
        IERC20 _token,
        uint256 _amountTokenMin,
        uint256 _amountAVAXMin,
        uint256[] memory _ids,
        uint256[] memory _amounts,
        address _to,
        uint256 _deadline
    ) external;

    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external;

    function swapExactTokensForAVAX(
        uint256 _amountIn,
        uint256 _amountOutMinAVAX,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external;

    function swapExactAVAXForTokens(
        uint256 _amountOutMin,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external payable;

    function swapTokensForExactTokens(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external;

    function swapTokensForExactAVAX(
        uint256 _amountOut,
        uint256 _amountInMax,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external;

    function swapAVAXForExactTokens(
        uint256 _amountOut,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external payable;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external;

    function swapExactTokensForAVAXSupportingFeeOnTransferTokens(
        uint256 _amountIn,
        uint256 _amountOutMinAVAX,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external;

    function swapExactAVAXForTokensSupportingFeeOnTransferTokens(
        uint256 _amountOutMin,
        uint256[] memory _pairVersions,
        IERC20[] memory _tokenPath,
        address _to,
        uint256 _deadline
    ) external payable;

    function sweep(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;
}
