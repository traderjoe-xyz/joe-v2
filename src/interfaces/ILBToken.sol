// SPDX-License-Identifier: MIT

pragma solidity >=0.8.7;

interface ILBToken {
    /// @dev Structure representing a LBToken amount tranfered or withdrawn:
    /// - id: Id of the bin
    /// - amount: Amount of LBToken
    struct LiquidityAmount {
        uint256 id;
        uint256 amount;
    }

    event TransferSingle(address indexed sender, address indexed from, address indexed to, uint256 id, uint256 amount);

    event TransferBatch(address indexed sender, address indexed from, address indexed to, LiquidityAmount[] amounts);

    event ApprovalForAll(address indexed account, address indexed sender, bool approved);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external view returns (uint8);

    function balanceOf(address account, uint256 id) external view returns (uint256);

    function userPositionAtIndex(address _account, uint256 _index) external view returns (uint256);

    function userPositionNumber(address _account) external view returns (uint256);

    function totalSupply(uint256 id) external view returns (uint256);

    function isApprovedForAll(address owner, address spender) external view returns (bool);

    function setApprovalForAll(address sender, bool approved) external;

    function safeBatchTransferFrom(
        address from,
        address to,
        LiquidityAmount[] memory amounts
    ) external;
}
