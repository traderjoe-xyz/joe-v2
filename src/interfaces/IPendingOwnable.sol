// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

/// @title Liquidity Book Pending Ownable Interface
/// @author Trader Joe
/// @notice Required interface of Pending Ownable contract used for LBFactory
interface IPendingOwnable {
    event PendingOwnerSet(address indexed pendingOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function setPendingOwner(address pendingOwner) external;

    function revokePendingOwner() external;

    function becomeOwner() external;

    function renounceOwnership() external;
}
