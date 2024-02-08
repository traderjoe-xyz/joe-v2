// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ILBHooks} from "../interfaces/ILBHooks.sol";

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

    function decode(bytes32 hooksParameters) internal pure returns (Parameters memory parameters) {
        parameters.hooks = address(uint160(uint256(hooksParameters)));

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

    function onHooksSet(bytes32 hooksParameters, bytes memory onHooksSetData) internal {
        _safeCall(
            hooksParameters, abi.encodeWithSelector(ILBHooks.onHooksSet.selector, hooksParameters, onHooksSetData)
        );
    }

    function beforeSwap(bytes32 hooksParameters, address sender, address to, bool swapForY, bytes32 amountsIn)
        internal
    {
        if ((hooksParameters & BEFORE_SWAP_FLAG) != 0) {
            _safeCall(
                hooksParameters, abi.encodeWithSelector(ILBHooks.beforeSwap.selector, sender, to, swapForY, amountsIn)
            );
        }
    }

    function afterSwap(bytes32 hooksParameters, address sender, address to, bool swapForY, bytes32 amountsOut)
        internal
    {
        if ((hooksParameters & AFTER_SWAP_FLAG) != 0) {
            _safeCall(
                hooksParameters, abi.encodeWithSelector(ILBHooks.afterSwap.selector, sender, to, swapForY, amountsOut)
            );
        }
    }

    function beforeFlashLoan(bytes32 hooksParameters, address sender, address to, bytes32 amounts) internal {
        if ((hooksParameters & BEFORE_FLASH_LOAN_FLAG) != 0) {
            _safeCall(hooksParameters, abi.encodeWithSelector(ILBHooks.beforeFlashLoan.selector, sender, to, amounts));
        }
    }

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

    function _safeCall(bytes32 hooksParameters, bytes memory data) private {
        bool success;

        assembly {
            let expectedSelector := shr(224, mload(add(data, 0x20)))

            let hooks := and(hooksParameters, 0xffffffffffffffffffffffffffffffffffffffff)
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
