// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IHooks} from "../interfaces/IHooks.sol";

library Hooks {
    error Hooks__CallFailed();

    bytes32 private constant _BEFORE_SWAP_FLAG = bytes32(uint256(1 << 160));
    bytes32 private constant _AFTER_SWAP_FLAG = bytes32(uint256(1 << 161));
    bytes32 private constant _BEFORE_FLASH_LOAN_FLAG = bytes32(uint256(1 << 162));
    bytes32 private constant _AFTER_FLASH_LOAN_FLAG = bytes32(uint256(1 << 163));
    bytes32 private constant _BEFORE_MINT_FLAG = bytes32(uint256(1 << 164));
    bytes32 private constant _AFTER_MINT_FLAG = bytes32(uint256(1 << 165));
    bytes32 private constant _BEFORE_BURN_FLAG = bytes32(uint256(1 << 166));
    bytes32 private constant _AFTER_BURN_FLAG = bytes32(uint256(1 << 167));

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
    }

    function encode(Parameters memory parameters) internal pure returns (bytes32 hooksParameters) {
        if (parameters.hooks == address(0)) return 0;

        hooksParameters = bytes32(uint256(uint160(address(parameters.hooks))));

        if (parameters.beforeSwap) hooksParameters |= _BEFORE_SWAP_FLAG;
        if (parameters.afterSwap) hooksParameters |= _AFTER_SWAP_FLAG;
        if (parameters.beforeFlashLoan) hooksParameters |= _BEFORE_FLASH_LOAN_FLAG;
        if (parameters.afterFlashLoan) hooksParameters |= _AFTER_FLASH_LOAN_FLAG;
        if (parameters.beforeMint) hooksParameters |= _BEFORE_MINT_FLAG;
        if (parameters.afterMint) hooksParameters |= _AFTER_MINT_FLAG;
        if (parameters.beforeBurn) hooksParameters |= _BEFORE_BURN_FLAG;
        if (parameters.afterBurn) hooksParameters |= _AFTER_BURN_FLAG;
    }

    function decode(bytes32 hooksParameters) internal pure returns (Parameters memory parameters) {
        parameters.hooks = address(uint160(uint256(hooksParameters)));

        parameters.beforeSwap = (hooksParameters & _BEFORE_SWAP_FLAG) != 0;
        parameters.afterSwap = (hooksParameters & _AFTER_SWAP_FLAG) != 0;
        parameters.beforeFlashLoan = (hooksParameters & _BEFORE_FLASH_LOAN_FLAG) != 0;
        parameters.afterFlashLoan = (hooksParameters & _AFTER_FLASH_LOAN_FLAG) != 0;
        parameters.beforeMint = (hooksParameters & _BEFORE_MINT_FLAG) != 0;
        parameters.afterMint = (hooksParameters & _AFTER_MINT_FLAG) != 0;
        parameters.beforeBurn = (hooksParameters & _BEFORE_BURN_FLAG) != 0;
        parameters.afterBurn = (hooksParameters & _AFTER_BURN_FLAG) != 0;
    }

    function beforeSwap(bytes32 hooksParameters, address sender, address to, bool swapForY, bytes32 amountsIn)
        internal
    {
        if ((hooksParameters & _BEFORE_SWAP_FLAG) != 0) {
            _safeCall(
                hooksParameters, abi.encodeWithSelector(IHooks.beforeSwap.selector, sender, to, swapForY, amountsIn)
            );
        }
    }

    function afterSwap(bytes32 hooksParameters, address sender, address to, bool swapForY, bytes32 amountsOut)
        internal
    {
        if ((hooksParameters & _AFTER_SWAP_FLAG) != 0) {
            _safeCall(
                hooksParameters, abi.encodeWithSelector(IHooks.afterSwap.selector, sender, to, swapForY, amountsOut)
            );
        }
    }

    function beforeFlashLoan(bytes32 hooksParameters, address sender, address to, bytes32 amounts) internal {
        if ((hooksParameters & _BEFORE_FLASH_LOAN_FLAG) != 0) {
            _safeCall(hooksParameters, abi.encodeWithSelector(IHooks.beforeFlashLoan.selector, sender, to, amounts));
        }
    }

    function afterFlashLoan(bytes32 hooksParameters, address sender, address to, bytes32 amounts) internal {
        if ((hooksParameters & _AFTER_FLASH_LOAN_FLAG) != 0) {
            _safeCall(hooksParameters, abi.encodeWithSelector(IHooks.afterFlashLoan.selector, sender, to, amounts));
        }
    }

    function beforeMint(
        bytes32 hooksParameters,
        address sender,
        address to,
        bytes32[] calldata liquidityConfigs,
        bytes32 amountsReceived
    ) internal {
        if ((hooksParameters & _BEFORE_MINT_FLAG) != 0) {
            _safeCall(
                hooksParameters,
                abi.encodeWithSelector(IHooks.beforeMint.selector, sender, to, liquidityConfigs, amountsReceived)
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
        if ((hooksParameters & _AFTER_MINT_FLAG) != 0) {
            _safeCall(
                hooksParameters,
                abi.encodeWithSelector(IHooks.afterMint.selector, sender, to, liquidityConfigs, amountsIn)
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
        if ((hooksParameters & _BEFORE_BURN_FLAG) != 0) {
            _safeCall(
                hooksParameters,
                abi.encodeWithSelector(IHooks.beforeBurn.selector, sender, from, to, ids, amountsToBurn)
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
        if ((hooksParameters & _AFTER_BURN_FLAG) != 0) {
            _safeCall(
                hooksParameters, abi.encodeWithSelector(IHooks.afterBurn.selector, sender, from, to, ids, amountsToBurn)
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
