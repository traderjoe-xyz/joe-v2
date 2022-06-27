// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "openzeppelin/token/ERC20/IERC20.sol";

error TokenHelper__TransferFailed(
    IERC20 token,
    address recipient,
    uint256 amount
);
error TokenHelper__ReserveUnderflow();

/// @title Safe Transfer
/// @author Trader Joe
/// @notice Wrappers around ERC20 operations that throw on failure (when the token
/// contract returns false). Tokens that return no value (and instead revert or
/// throw on failure) are also supported, non-reverting calls are assumed to be
/// successful.
/// To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
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
            (bool success, bytes memory data) = address(token).call(
                abi.encodeWithSelector(
                    token.transfer.selector,
                    recipient,
                    amount
                )
            );
            if (!(success && (data.length == 0 || abi.decode(data, (bool)))))
                revert TokenHelper__TransferFailed(token, recipient, amount);
        }
    }

    /// @notice Returns the balance of the pair
    /// @param token The address of the token
    /// @return The balance of the pair
    function received(
        IERC20 token,
        uint256 reserve,
        uint256 fees
    ) internal view returns (uint256) {
        uint256 _internalBalance = reserve + fees;
        uint256 _balance = token.balanceOf(address(this));
        if (_internalBalance < _balance) revert TokenHelper__ReserveUnderflow();
        unchecked {
            return _balance - _internalBalance;
        }
    }
}
