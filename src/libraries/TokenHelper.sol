// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "openzeppelin/token/ERC20/IERC20.sol";

import "../LBErrors.sol";

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
    /// @param owner The owner of the tokens
    /// @param recipient The address of the recipient
    /// @param amount The amount to send
    function safeTransferFrom(
        IERC20 token,
        address owner,
        address recipient,
        uint256 amount
    ) internal {
        if (amount != 0) {
            bytes memory data = abi.encodeWithSelector(token.transferFrom.selector, owner, recipient, amount);

            bytes memory returnData = _callAndCatchError(address(token), data);

            if (returnData.length > 0 && !abi.decode(returnData, (bool))) revert TokenHelper__TransferFailed();
        }
    }

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
            bytes memory data = abi.encodeWithSelector(token.transfer.selector, recipient, amount);

            bytes memory returnData = _callAndCatchError(address(token), data);

            if (returnData.length > 0 && !abi.decode(returnData, (bool))) revert TokenHelper__TransferFailed();
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

    /// @notice Private view function to perform a low level call on `target`
    /// @dev Revert if the call doesn't succeed
    /// @param target The address of the account
    /// @param data The data to execute on `target`
    /// @return returnData The data returned by the call
    function _callAndCatchError(address target, bytes memory data) private returns (bytes memory) {
        (bool success, bytes memory returnData) = target.call(data);

        if (success) {
            if (returnData.length == 0 && !_isContract(target)) revert TokenHelper__NonContract();
        } else {
            if (returnData.length == 0) revert TokenHelper__CallFailed();
            else {
                // Look for revert reason and bubble it up if present
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }

        return returnData;
    }

    /// @notice Private view function to return if an address is a contract
    /// @dev It is unsafe to assume that an address for which this function returns
    /// false is an externally-owned account (EOA) and not a contract.
    ///
    /// Among others, `isContract` will return false for the following
    /// types of addresses:
    ///  - an externally-owned account
    ///  - a contract in construction
    ///  - an address where a contract will be created
    ///  - an address where a contract lived, but was destroyed
    /// @param account The address of the account
    /// @return Whether the account is a contract (true) or not (false)
    function _isContract(address account) private view returns (bool) {
        return account.code.length > 0;
    }
}
