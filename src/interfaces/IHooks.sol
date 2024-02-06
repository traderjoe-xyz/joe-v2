// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IHooks {
    function lbPair() external view returns (address);

    function beforeSwap(address sender, address to, bool swapForY, bytes32 amountsIn) external returns (bytes4);

    function afterSwap(address sender, address to, bool swapForY, bytes32 amountsOut) external returns (bytes4);

    function beforeFlashLoan(address sender, address to, bytes32 amounts) external returns (bytes4);

    function afterFlashLoan(address sender, address to, bytes32 amounts) external returns (bytes4);

    function beforeMint(address sender, address to, bytes32[] calldata liquidityConfigs, bytes32 amountsReceived)
        external
        returns (bytes4);

    function afterMint(address sender, address to, bytes32[] calldata liquidityConfigs, bytes32 amountsIn)
        external
        returns (bytes4);

    function beforeBurn(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amountsToBurn
    ) external returns (bytes4);

    function afterBurn(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amountsToBurn
    ) external returns (bytes4);
}
