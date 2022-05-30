// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ILBToken {
    event TransferSingle(
        address indexed from,
        address indexed to,
        int24 id,
        uint256 amount
    );

    event TransferFromSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        int24 id,
        uint256 amount
    );

    event ApprovalForAll(
        address indexed account,
        address indexed operator,
        bool approved
    );

    function balanceOf(address account, int24 id)
        external
        view
        returns (uint256);

    function totalSupply(int24 id) external view returns (uint256);

    function safeTransfer(
        address to,
        int24 id,
        uint256 amount
    ) external;

    function isApprovedForAll(address owner, address spender)
        external
        view
        returns (bool);

    function setApprovalForAll(address operator, bool approved) external;

    function safeTransferFrom(
        address from,
        address to,
        int24 id,
        uint256 amount
    ) external;
}
