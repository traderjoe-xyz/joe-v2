// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Liquidity Book Token Helper Library
 * @author Trader Joe
 * @notice Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using TokenHelper for IERC20;` statement to your contract,
 * which allows you to call the safe operation as `token.safeTransfer(...)`
 */
library TokenHelper {
    error TokenHelper__TransferFailed();

    /**
     * @notice Transfers token and reverts if the transfer fails
     * @param token The address of the token
     * @param owner The owner of the tokens
     * @param recipient The address of the recipient
     * @param amount The amount to send
     */
    function safeTransferFrom(IERC20 token, address owner, address recipient, uint256 amount) internal {
        bytes memory data = abi.encodeWithSelector(token.transferFrom.selector, owner, recipient, amount);

        _callAndCatch(token, data);
    }

    /**
     * @notice Transfers token and reverts if the transfer fails
     * @param token The address of the token
     * @param recipient The address of the recipient
     * @param amount The amount to send
     */
    function safeTransfer(IERC20 token, address recipient, uint256 amount) internal {
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, recipient, amount);

        _callAndCatch(token, data);
    }

    function _callAndCatch(IERC20 token, bytes memory data) internal {
        bool success;

        assembly {
            mstore(0x00, 0)

            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0x00, 0x20)

            switch success
            case 0 {
                if returndatasize() {
                    returndatacopy(0x00, 0x00, returndatasize())
                    revert(0x00, returndatasize())
                }
            }
            default {
                switch returndatasize()
                case 0 { success := iszero(iszero(extcodesize(token))) }
                default { success := and(success, eq(mload(0x00), 1)) }
            }
        }

        if (!success) revert TokenHelper__TransferFailed();
    }
}
