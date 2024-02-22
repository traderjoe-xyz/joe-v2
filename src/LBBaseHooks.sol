// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Hooks} from "./libraries/Hooks.sol";
import {ILBHooks} from "./interfaces/ILBHooks.sol";
import {ILBPair} from "./interfaces/ILBPair.sol";

/**
 * @title Liquidity Book Base Hooks Contract
 * @notice Base contract for LBPair hooks
 * This contract is meant to be inherited by any contract that wants to implement LBPair hooks
 */
abstract contract LBBaseHooks is ILBHooks {
    error LBBaseHooks__InvalidCaller(address caller);
    error LBBaseHooks__NotLinked();

    /**
     * @dev Modifier to check that the caller is the trusted caller
     */
    modifier onlyTrustedCaller() {
        _checkTrustedCaller();
        _;
    }

    /**
     * @dev Returns the LBPair contract
     * @return The LBPair contract
     */
    function getLBPair() external view override returns (ILBPair) {
        return _getLBPair();
    }

    /**
     * @dev Returns whether the contract is linked to the pair or not
     * @return Whether the contract is linked to the pair or not
     */
    function isLinked() external view override returns (bool) {
        return _isLinked();
    }

    /**
     * @notice Hook called by the pair when the hooks parameters are set
     * @dev Only callable by the pair
     * @param hooksParameters The hooks parameters
     * @param onHooksSetData The onHooksSet data
     * @return The function selector
     */
    function onHooksSet(bytes32 hooksParameters, bytes calldata onHooksSetData)
        external
        override
        onlyTrustedCaller
        returns (bytes4)
    {
        if (!_isLinked()) revert LBBaseHooks__NotLinked();

        _onHooksSet(hooksParameters, onHooksSetData);

        return this.onHooksSet.selector;
    }

    /**
     * @notice Hook called by the pair before a swap
     * @dev Only callable by the pair
     * @param sender The address that initiated the swap
     * @param to The address that will receive the swapped tokens
     * @param swapForY Whether the swap is for token Y
     * @param amountsIn The amounts in
     * @return The function selector
     */
    function beforeSwap(address sender, address to, bool swapForY, bytes32 amountsIn)
        external
        override
        onlyTrustedCaller
        returns (bytes4)
    {
        _beforeSwap(sender, to, swapForY, amountsIn);

        return this.beforeSwap.selector;
    }

    /**
     * @notice Hook called by the pair after a swap
     * @dev Only callable by the pair
     * @param sender The address that initiated the swap
     * @param to The address that received the swapped tokens
     * @param swapForY Whether the swap was for token Y
     * @param amountsOut The amounts out
     * @return The function selector
     */
    function afterSwap(address sender, address to, bool swapForY, bytes32 amountsOut)
        external
        override
        onlyTrustedCaller
        returns (bytes4)
    {
        _afterSwap(sender, to, swapForY, amountsOut);

        return this.afterSwap.selector;
    }

    /**
     * @notice Hook called by the pair before a flash loan
     * @dev Only callable by the pair
     * @param sender The address that initiated the flash loan
     * @param to The address that will receive the flash loaned tokens
     * @param amounts The amounts
     * @return The function selector
     */
    function beforeFlashLoan(address sender, address to, bytes32 amounts)
        external
        override
        onlyTrustedCaller
        returns (bytes4)
    {
        _beforeFlashLoan(sender, to, amounts);

        return this.beforeFlashLoan.selector;
    }

    /**
     * @notice Hook called by the pair after a flash loan
     * @dev Only callable by the pair
     * @param sender The address that initiated the flash loan
     * @param to The address that received the flash loaned tokens
     * @param fees The flashloan fees
     * @param feesReceived The fees received
     * @return The function selector
     */
    function afterFlashLoan(address sender, address to, bytes32 fees, bytes32 feesReceived)
        external
        override
        onlyTrustedCaller
        returns (bytes4)
    {
        _afterFlashLoan(sender, to, fees, feesReceived);

        return this.afterFlashLoan.selector;
    }

    /**
     * @notice Hook called by the pair before minting
     * @dev Only callable by the pair
     * @param sender The address that initiated the mint
     * @param to The address that will receive the minted tokens
     * @param liquidityConfigs The liquidity configurations
     * @param amountsReceived The amounts received
     * @return The function selector
     */
    function beforeMint(address sender, address to, bytes32[] calldata liquidityConfigs, bytes32 amountsReceived)
        external
        override
        onlyTrustedCaller
        returns (bytes4)
    {
        _beforeMint(sender, to, liquidityConfigs, amountsReceived);

        return this.beforeMint.selector;
    }

    /**
     * @notice Hook called by the pair after minting
     * @dev Only callable by the pair
     * @param sender The address that initiated the mint
     * @param to The address that received the minted tokens
     * @param liquidityConfigs The liquidity configurations
     * @param amountsIn The amounts in
     * @return The function selector
     */
    function afterMint(address sender, address to, bytes32[] calldata liquidityConfigs, bytes32 amountsIn)
        external
        override
        onlyTrustedCaller
        returns (bytes4)
    {
        _afterMint(sender, to, liquidityConfigs, amountsIn);

        return this.afterMint.selector;
    }

    /**
     * @notice Hook called by the pair before burning
     * @dev Only callable by the pair
     * @param sender The address that initiated the burn
     * @param from The address that will burn the tokens
     * @param to The address that will receive the burned tokens
     * @param ids The token ids
     * @param amountsToBurn The amounts to burn
     * @return The function selector
     */
    function beforeBurn(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amountsToBurn
    ) external override onlyTrustedCaller returns (bytes4) {
        _beforeBurn(sender, from, to, ids, amountsToBurn);

        return this.beforeBurn.selector;
    }

    /**
     * @notice Hook called by the pair after burning
     * @dev Only callable by the pair
     * @param sender The address that initiated the burn
     * @param from The address that burned the tokens
     * @param to The address that received the burned tokens
     * @param ids The token ids
     * @param amountsToBurn The amounts to burn
     * @return The function selector
     */
    function afterBurn(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amountsToBurn
    ) external override onlyTrustedCaller returns (bytes4) {
        _afterBurn(sender, from, to, ids, amountsToBurn);

        return this.afterBurn.selector;
    }

    /**
     * @notice Hook called by the pair before a batch transfer
     * @dev Only callable by the pair
     * @param sender The address that initiated the transfer
     * @param from The address that will transfer the tokens
     * @param to The address that will receive the tokens
     * @param ids The token ids
     * @param amounts The amounts
     * @return The function selector
     */
    function beforeBatchTransferFrom(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external override onlyTrustedCaller returns (bytes4) {
        _beforeBatchTransferFrom(sender, from, to, ids, amounts);

        return this.beforeBatchTransferFrom.selector;
    }

    /**
     * @notice Hook called by the pair after a batch transfer
     * @dev Only callable by the pair
     * @param sender The address that initiated the transfer
     * @param from The address that transferred the tokens
     * @param to The address that received the tokens
     * @param ids The token ids
     * @param amounts The amounts
     * @return The function selector
     */
    function afterBatchTransferFrom(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external override onlyTrustedCaller returns (bytes4) {
        _afterBatchTransferFrom(sender, from, to, ids, amounts);

        return this.afterBatchTransferFrom.selector;
    }

    /**
     * @dev Checks that the caller is the trusted caller, otherwise reverts
     */
    function _checkTrustedCaller() internal view virtual {
        if (msg.sender != address(_getLBPair())) revert LBBaseHooks__InvalidCaller(msg.sender);
    }

    /**
     * @dev Checks if the contract is linked to the pair
     * @return Whether the contract is linked to the pair or not
     */
    function _isLinked() internal view virtual returns (bool) {
        address hooks = Hooks.getHooks(_getLBPair().getLBHooksParameters());
        return hooks == address(this);
    }

    /**
     * @dev Returns the LBPair contract
     */
    function _getLBPair() internal view virtual returns (ILBPair);

    /**
     * @notice Internal function to be overridden that is called when the hooks parameters are set
     * @param hooksParameters The hooks parameters
     * @param onHooksSetData The onHooksSet data
     */
    function _onHooksSet(bytes32 hooksParameters, bytes calldata onHooksSetData) internal virtual {}

    /**
     * @notice Internal function to be overridden that is called before a swap
     * @param sender The address that initiated the swap
     * @param to The address that will receive the swapped tokens
     * @param swapForY Whether the swap is for token Y
     * @param amountsIn The amounts in
     */
    function _beforeSwap(address sender, address to, bool swapForY, bytes32 amountsIn) internal virtual {}

    /**
     * @notice Internal function to be overridden that is called after a swap
     * @param sender The address that initiated the swap
     * @param to The address that received the swapped tokens
     * @param swapForY Whether the swap was for token Y
     * @param amountsOut The amounts out
     */
    function _afterSwap(address sender, address to, bool swapForY, bytes32 amountsOut) internal virtual {}

    /**
     * @notice Internal function to be overridden that is called before a flash loan
     * @param sender The address that initiated the flash loan
     * @param to The address that will receive the flash loaned tokens
     * @param amounts The amounts
     */
    function _beforeFlashLoan(address sender, address to, bytes32 amounts) internal virtual {}

    /**
     * @notice Internal function to be overridden that is called after a flash loan
     * @param sender The address that initiated the flash loan
     * @param to The address that received the flash loaned tokens
     * @param fees The flashloan fees
     * @param feesReceived The fees received
     */
    function _afterFlashLoan(address sender, address to, bytes32 fees, bytes32 feesReceived) internal virtual {}

    /**
     * @notice Internal function to be overridden that is called before minting
     * @param sender The address that initiated the mint
     * @param to The address that will receive the minted tokens
     * @param liquidityConfigs The liquidity configurations
     * @param amountsReceived The amounts received
     */
    function _beforeMint(address sender, address to, bytes32[] calldata liquidityConfigs, bytes32 amountsReceived)
        internal
        virtual
    {}

    /**
     * @notice Internal function to be overridden that is called after minting
     * @param sender The address that initiated the mint
     * @param to The address that received the minted tokens
     * @param liquidityConfigs The liquidity configurations
     * @param amountsIn The amounts in
     */
    function _afterMint(address sender, address to, bytes32[] calldata liquidityConfigs, bytes32 amountsIn)
        internal
        virtual
    {}

    /**
     * @notice Internal function to be overridden that is called before burning
     * @param sender The address that initiated the burn
     * @param from The address that will burn the tokens
     * @param to The address that will receive the burned tokens
     * @param ids The token ids
     * @param amountsToBurn The amounts to burn
     */
    function _beforeBurn(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amountsToBurn
    ) internal virtual {}

    /**
     * @notice Internal function to be overridden that is called after burning
     * @param sender The address that initiated the burn
     * @param from The address that burned the tokens
     * @param to The address that received the burned tokens
     * @param ids The token ids
     * @param amountsToBurn The amounts to burn
     */
    function _afterBurn(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amountsToBurn
    ) internal virtual {}

    /**
     * @notice Internal function to be overridden that is called before a batch transfer
     * @param sender The address that initiated the transfer
     * @param from The address that will transfer the tokens
     * @param to The address that will receive the tokens
     * @param ids The token ids
     * @param amounts The amounts
     */
    function _beforeBatchTransferFrom(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) internal virtual {}

    /**
     * @notice Internal function to be overridden that is called after a batch transfer
     * @param sender The address that initiated the transfer
     * @param from The address that transferred the tokens
     * @param to The address that received the tokens
     * @param ids The token ids
     * @param amounts The amounts
     */
    function _afterBatchTransferFrom(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) internal virtual {}
}
