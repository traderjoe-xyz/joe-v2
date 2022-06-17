// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error SafeTransfer__TransferFailed();

/// @title Safe Transfer
/// @author Trader Joe
/// @notice Wrappers around ERC20 operations that throw on failure (when the token
/// contract returns false). Tokens that return no value (and instead revert or
/// throw on failure) are also supported, non-reverting calls are assumed to be
/// successful.
/// To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
/// which allows you to call the safe operation as `token.safeTransfer(...)`
library SafeTransfer {
    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
        if (!(success && (data.length == 0 || abi.decode(data, (bool)))))
            revert SafeTransfer__TransferFailed();
    }
}
