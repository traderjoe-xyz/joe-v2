// SPDX-License-Identifier: MIT

pragma solidity >=0.8.7;

interface ILBToken {
    event TransferSingle(address indexed sender, address indexed from, address indexed to, uint256 id, uint256 amount);

    event TransferBatch(
        address indexed sender,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] amounts
    );

    event ApprovalForAll(address indexed account, address indexed sender, bool approved);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function balanceOf(address account, uint256 id) external view returns (uint256);

    function userPositionAt(address _account, uint256 _index) external view returns (uint256);

    function userPositionNb(address _account) external view returns (uint256);

    function totalSupply(uint256 id) external view returns (uint256);

    function isApprovedForAll(address owner, address spender) external view returns (bool);

    function setApprovalForAll(address sender, bool approved) external;

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory id,
        uint256[] memory amount
    ) external;
}
