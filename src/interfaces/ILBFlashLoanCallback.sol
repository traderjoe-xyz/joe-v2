// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/// @title Liquidity Book Flashloan Callback Interface
/// @author Trader Joe
/// @notice Required interface to interact with LB flashloans
interface ILBFlashLoanCallback {
    function LBFlashLoanCallback(
        address sender,
        uint256 amountX,
        uint256 amountY,
        uint256 feeX,
        uint256 feeY,
        bytes memory data
    ) external;
}
