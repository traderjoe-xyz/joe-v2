// SPDX-License-Identifier: MIT

pragma solidity >=0.8.7;

interface ILBFlashLoanCallback {
    function LBFlashLoanCallback(
        uint256 fee0,
        uint256 fee1,
        bytes memory data
    ) external;
}
