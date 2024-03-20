// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ILBHooks} from "../interfaces/ILBHooks.sol";

/**
 * @title Hooks library
 * @notice This library contains functions that should be used to interact with hooks
 */
library Hooks {
    error Hooks__CallFailed();

    bytes32 internal constant BEFORE_SWAP_FLAG = bytes32(uint256(1 << 160));
    bytes32 internal constant AFTER_SWAP_FLAG = bytes32(uint256(1 << 161));
    bytes32 internal constant BEFORE_FLASH_LOAN_FLAG = bytes32(uint256(1 << 162));
    bytes32 internal constant AFTER_FLASH_LOAN_FLAG = bytes32(uint256(1 << 163));
    bytes32 internal constant BEFORE_MINT_FLAG = bytes32(uint256(1 << 164));
    bytes32 internal constant AFTER_MINT_FLAG = bytes32(uint256(1 << 165));
    bytes32 internal constant BEFORE_BURN_FLAG = bytes32(uint256(1 << 166));
    bytes32 internal constant AFTER_BURN_FLAG = bytes32(uint256(1 << 167));
    bytes32 internal constant BEFORE_TRANSFER_FLAG = bytes32(uint256(1 << 168));
    bytes32 internal constant AFTER_TRANSFER_FLAG = bytes32(uint256(1 << 169));

    struct Parameters {
        address hooks;
        bool beforeSwap;
        bool afterSwap;
        bool beforeFlashLoan;
        bool afterFlashLoan;
        bool beforeMint;
        bool afterMint;
        bool beforeBurn;
        bool afterBurn;
        bool beforeBatchTransferFrom;
        bool afterBatchTransferFrom;
    }

    /**
     * @dev Helper function to encode the hooks parameters to a single bytes32 value
     * @param parameters The hooks parameters
     * @return hooksParameters The encoded hooks parameters
     */
    function encode(Parameters memory parameters) internal pure returns (bytes32 hooksParameters) {
        hooksParameters = bytes32(uint256(uint160(address(parameters.hooks))));

        if (parameters.beforeSwap) hooksParameters |= BEFORE_SWAP_FLAG;
        if (parameters.afterSwap) hooksParameters |= AFTER_SWAP_FLAG;
        if (parameters.beforeFlashLoan) hooksParameters |= BEFORE_FLASH_LOAN_FLAG;
        if (parameters.afterFlashLoan) hooksParameters |= AFTER_FLASH_LOAN_FLAG;
        if (parameters.beforeMint) hooksParameters |= BEFORE_MINT_FLAG;
        if (parameters.afterMint) hooksParameters |= AFTER_MINT_FLAG;
        if (parameters.beforeBurn) hooksParameters |= BEFORE_BURN_FLAG;
        if (parameters.afterBurn) hooksParameters |= AFTER_BURN_FLAG;
        if (parameters.beforeBatchTransferFrom) hooksParameters |= BEFORE_TRANSFER_FLAG;
        if (parameters.afterBatchTransferFrom) hooksParameters |= AFTER_TRANSFER_FLAG;
    }

    /**
     * @dev Helper function to decode the hooks parameters from a single bytes32 value
     * @param hooksParameters The encoded hooks parameters
     * @return parameters The hooks parameters
     */
    function decode(bytes32 hooksParameters) internal pure returns (Parameters memory parameters) {
        parameters.hooks = getHooks(hooksParameters);

        parameters.beforeSwap = (hooksParameters & BEFORE_SWAP_FLAG) != 0;
        parameters.afterSwap = (hooksParameters & AFTER_SWAP_FLAG) != 0;
        parameters.beforeFlashLoan = (hooksParameters & BEFORE_FLASH_LOAN_FLAG) != 0;
        parameters.afterFlashLoan = (hooksParameters & AFTER_FLASH_LOAN_FLAG) != 0;
        parameters.beforeMint = (hooksParameters & BEFORE_MINT_FLAG) != 0;
        parameters.afterMint = (hooksParameters & AFTER_MINT_FLAG) != 0;
        parameters.beforeBurn = (hooksParameters & BEFORE_BURN_FLAG) != 0;
        parameters.afterBurn = (hooksParameters & AFTER_BURN_FLAG) != 0;
        parameters.beforeBatchTransferFrom = (hooksParameters & BEFORE_TRANSFER_FLAG) != 0;
        parameters.afterBatchTransferFrom = (hooksParameters & AFTER_TRANSFER_FLAG) != 0;
    }

    /**
     * @dev Helper function to get the hooks address from the encoded hooks parameters
     * @param hooksParameters The encoded hooks parameters
     * @return hooks The hooks address
     */
    function getHooks(bytes32 hooksParameters) internal pure returns (address hooks) {
        hooks = address(uint160(uint256(hooksParameters)));
    }

    /**
     * @dev Helper function to set the hooks address in the encoded hooks parameters
     * @param hooksParameters The encoded hooks parameters
     * @param newHooks The new hooks address
     * @return hooksParameters The updated hooks parameters
     */
    function setHooks(bytes32 hooksParameters, address newHooks) internal pure returns (bytes32) {
        return bytes32(bytes12(hooksParameters)) | bytes32(uint256(uint160(newHooks)));
    }

    /**
     * @dev Helper function to get the flags from the encoded hooks parameters
     * @param hooksParameters The encoded hooks parameters
     * @return flags The flags
     */
    function getFlags(bytes32 hooksParameters) internal pure returns (bytes12 flags) {
        flags = bytes12(hooksParameters);
    }

    /**
     * @dev Helper function call the onHooksSet function on the hooks contract, only if the
     * hooksParameters is not 0
     * @param hooksParameters The encoded hooks parameters
     * @param onHooksSetData The data to pass to the onHooksSet function
     */
    function onHooksSet(bytes32 hooksParameters, bytes calldata onHooksSetData) internal {
        if (hooksParameters != 0) {
            _safeCall(
                hooksParameters, abi.encodeWithSelector(ILBHooks.onHooksSet.selector, hooksParameters, onHooksSetData)
            );
        }
    }

    /**
     * @dev Helper function to call the beforeSwap function on the hooks contract, only if the
     * BEFORE_SWAP_FLAG is set in the hooksParameters
     * @param hooksParameters The encoded hooks parameters
     * @param sender The sender
     * @param to The recipient
     * @param swapForY Whether the swap is for Y
     * @param amountsIn The amounts in
     */
    function beforeSwap(bytes32 hooksParameters, address sender, address to, bool swapForY, bytes32 amountsIn)
        internal
    {
        if ((hooksParameters & BEFORE_SWAP_FLAG) != 0) {
            _safeCall(
                hooksParameters, abi.encodeWithSelector(ILBHooks.beforeSwap.selector, sender, to, swapForY, amountsIn)
            );
        }
    }

    /**
     * @dev Helper function to call the afterSwap function on the hooks contract, only if the
     * AFTER_SWAP_FLAG is set in the hooksParameters
     * @param hooksParameters The encoded hooks parameters
     * @param sender The sender
     * @param to The recipient
     * @param swapForY Whether the swap is for Y
     * @param amountsOut The amounts out
     */
    function afterSwap(bytes32 hooksParameters, address sender, address to, bool swapForY, bytes32 amountsOut)
        internal
    {
        if ((hooksParameters & AFTER_SWAP_FLAG) != 0) {
            _safeCall(
                hooksParameters, abi.encodeWithSelector(ILBHooks.afterSwap.selector, sender, to, swapForY, amountsOut)
            );
        }
    }

    /**
     * @dev Helper function to call the beforeFlashLoan function on the hooks contract, only if the
     * BEFORE_FLASH_LOAN_FLAG is set in the hooksParameters
     * @param hooksParameters The encoded hooks parameters
     * @param sender The sender
     * @param to The recipient
     * @param amounts The amounts
     */
    function beforeFlashLoan(bytes32 hooksParameters, address sender, address to, bytes32 amounts) internal {
        if ((hooksParameters & BEFORE_FLASH_LOAN_FLAG) != 0) {
            _safeCall(hooksParameters, abi.encodeWithSelector(ILBHooks.beforeFlashLoan.selector, sender, to, amounts));
        }
    }

    /**
     * @dev Helper function to call the afterFlashLoan function on the hooks contract, only if the
     * AFTER_FLASH_LOAN_FLAG is set in the hooksParameters
     * @param hooksParameters The encoded hooks parameters
     * @param sender The sender
     * @param to The recipient
     * @param fees The fees
     * @param feesReceived The fees received
     */
    function afterFlashLoan(bytes32 hooksParameters, address sender, address to, bytes32 fees, bytes32 feesReceived)
        internal
    {
        if ((hooksParameters & AFTER_FLASH_LOAN_FLAG) != 0) {
            _safeCall(
                hooksParameters,
                abi.encodeWithSelector(ILBHooks.afterFlashLoan.selector, sender, to, fees, feesReceived)
            );
        }
    }

    /**
     * @dev Helper function to call the beforeMint function on the hooks contract, only if the
     * BEFORE_MINT_FLAG is set in the hooksParameters
     * @param hooksParameters The encoded hooks parameters
     * @param sender The sender
     * @param to The recipient
     * @param liquidityConfigs The liquidity configs
     * @param amountsReceived The amounts received
     */
    function beforeMint(
        bytes32 hooksParameters,
        address sender,
        address to,
        bytes32[] calldata liquidityConfigs,
        bytes32 amountsReceived
    ) internal {
        if ((hooksParameters & BEFORE_MINT_FLAG) != 0) {
            _safeCall(
                hooksParameters,
                abi.encodeWithSelector(ILBHooks.beforeMint.selector, sender, to, liquidityConfigs, amountsReceived)
            );
        }
    }

    /**
     * @dev Helper function to call the afterMint function on the hooks contract, only if the
     * AFTER_MINT_FLAG is set in the hooksParameters
     * @param hooksParameters The encoded hooks parameters
     * @param sender The sender
     * @param to The recipient
     * @param liquidityConfigs The liquidity configs
     * @param amountsIn The amounts in
     */
    function afterMint(
        bytes32 hooksParameters,
        address sender,
        address to,
        bytes32[] calldata liquidityConfigs,
        bytes32 amountsIn
    ) internal {
        if ((hooksParameters & AFTER_MINT_FLAG) != 0) {
            _safeCall(
                hooksParameters,
                abi.encodeWithSelector(ILBHooks.afterMint.selector, sender, to, liquidityConfigs, amountsIn)
            );
        }
    }

    /**
     * @dev Helper function to call the beforeBurn function on the hooks contract, only if the
     * BEFORE_BURN_FLAG is set in the hooksParameters
     * @param hooksParameters The encoded hooks parameters
     * @param sender The sender
     * @param from The sender
     * @param to The recipient
     * @param ids The ids
     * @param amountsToBurn The amounts to burn
     */
    function beforeBurn(
        bytes32 hooksParameters,
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amountsToBurn
    ) internal {
        if ((hooksParameters & BEFORE_BURN_FLAG) != 0) {
            _safeCall(
                hooksParameters,
                abi.encodeWithSelector(ILBHooks.beforeBurn.selector, sender, from, to, ids, amountsToBurn)
            );
        }
    }

    /**
     * @dev Helper function to call the afterBurn function on the hooks contract, only if the
     * AFTER_BURN_FLAG is set in the hooksParameters
     * @param hooksParameters The encoded hooks parameters
     * @param sender The sender
     * @param from The sender
     * @param to The recipient
     * @param ids The ids
     * @param amountsToBurn The amounts to burn
     */
    function afterBurn(
        bytes32 hooksParameters,
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amountsToBurn
    ) internal {
        if ((hooksParameters & AFTER_BURN_FLAG) != 0) {
            _safeCall(
                hooksParameters,
                abi.encodeWithSelector(ILBHooks.afterBurn.selector, sender, from, to, ids, amountsToBurn)
            );
        }
    }

    /**
     * @dev Helper function to call the beforeTransferFrom function on the hooks contract, only if the
     * BEFORE_TRANSFER_FLAG is set in the hooksParameters
     * @param hooksParameters The encoded hooks parameters
     * @param sender The sender
     * @param from The sender
     * @param to The recipient
     * @param ids The list of ids
     * @param amounts The list of amounts
     */
    function beforeBatchTransferFrom(
        bytes32 hooksParameters,
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) internal {
        if ((hooksParameters & BEFORE_TRANSFER_FLAG) != 0) {
            _safeCall(
                hooksParameters,
                abi.encodeWithSelector(ILBHooks.beforeBatchTransferFrom.selector, sender, from, to, ids, amounts)
            );
        }
    }

    /**
     * @dev Helper function to call the afterTransferFrom function on the hooks contract, only if the
     * AFTER_TRANSFER_FLAG is set in the hooksParameters
     * @param hooksParameters The encoded hooks parameters
     * @param sender The sender
     * @param from The sender
     * @param to The recipient
     * @param ids The list of ids
     * @param amounts The list of amounts
     */
    function afterBatchTransferFrom(
        bytes32 hooksParameters,
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) internal {
        if ((hooksParameters & AFTER_TRANSFER_FLAG) != 0) {
            _safeCall(
                hooksParameters,
                abi.encodeWithSelector(ILBHooks.afterBatchTransferFrom.selector, sender, from, to, ids, amounts)
            );
        }
    }

    /**
     * @dev Helper function to call the hooks contract and verify the call was successful
     * by matching the expected selector with the returned data
     * @param hooksParameters The encoded hooks parameters
     * @param data The data to pass to the hooks contract
     */
    function _safeCall(bytes32 hooksParameters, bytes memory data) private {
        bool success;

        address hooks = getHooks(hooksParameters);

        assembly {
            let expectedSelector := shr(224, mload(add(data, 0x20)))

            success := call(gas(), hooks, 0, add(data, 0x20), mload(data), 0, 0x20)

            if and(iszero(success), iszero(iszero(returndatasize()))) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            success := and(success, and(gt(returndatasize(), 0x1f), eq(shr(224, mload(0)), expectedSelector)))
        }

        if (!success) revert Hooks__CallFailed();
    }
}
