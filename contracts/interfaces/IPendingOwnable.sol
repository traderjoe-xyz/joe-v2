// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IPendingOwnable {
    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function setPendingOwner(address pendingOwner) external;

    function revokePendingOwner() external;

    function becomeOwner() external;

    function renounceOwnership() external;
}
