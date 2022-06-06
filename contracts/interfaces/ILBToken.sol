// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ILBToken {
    event TransferSingle(
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    event TransferFromSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    event ApprovalForAll(
        address indexed account,
        address indexed operator,
        bool approved
    );

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function balanceOf(address _account, uint256 _id)
        external
        view
        returns (uint256);

    function totalSupply(uint256 _id) external view returns (uint256);

    function safeTransfer(
        address to,
        uint256 id,
        uint256 amount
    ) external;

    function isApprovedForAll(address _owner, address _spender)
        external
        view
        returns (bool);

    function setApprovalForAll(address _operator, bool _approved) external;

    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount
    ) external;
}
