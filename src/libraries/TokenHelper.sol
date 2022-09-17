// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/IERC20.sol";

error TokenHelper__TransferFailed(IERC20 token, address recipient, uint256 amount);

/// @title Safe Transfer
/// @author Trader Joe
/// @notice Wrappers around ERC20 operations that throw on failure (when the token
/// contract returns false). Tokens that return no value (and instead revert or
/// throw on failure) are also supported, non-reverting calls are assumed to be
/// successful.
/// To use this library you can add a `using TokenHelper for IERC20;` statement to your contract,
/// which allows you to call the safe operation as `token.safeTransfer(...)`
library TokenHelper {
    /// @notice Transfers token only if the amount is greater than zero
    /// @param token The address of the token
    /// @param recipient The address of the recipient
    /// @param amount The amount to send
    function safeTransfer(
        IERC20 token,
        address recipient,
        uint256 amount
    ) internal {
        if (amount != 0) {
            (bool success, bytes memory result) = address(token).call(
                abi.encodeWithSelector(token.transfer.selector, recipient, amount)
            );
            // Look for revert reason and bubble it up if present
            if (!(success && (result.length == 0 || abi.decode(result, (bool))))) {
                assembly {
                    revert(add(32, result), mload(result))
                }
            }
        }
    }

    /// @notice Returns the amount of token received by the pair
    /// @param token The address of the token
    /// @param reserve The total reserve of token
    /// @param fees The total fees of token
    /// @return The amount received by the pair
    function received(
        IERC20 token,
        uint256 reserve,
        uint256 fees
    ) internal view returns (uint256) {
        uint256 _internalBalance;
        unchecked {
            _internalBalance = reserve + fees;
        }
        return token.balanceOf(address(this)) - _internalBalance;
    }
}
