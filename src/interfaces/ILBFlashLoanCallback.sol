// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
