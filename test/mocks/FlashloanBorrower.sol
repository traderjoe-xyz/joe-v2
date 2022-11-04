// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "openzeppelin/interfaces/IERC20.sol";

import "src/LBPair.sol";
import "src/interfaces/ILBFlashLoanCallback.sol";
import "src/libraries/Constants.sol";

error FlashBorrower__UntrustedLender();
error FlashBorrower__UntrustedLoanInitiator();

contract FlashBorrower is ILBFlashLoanCallback {
    enum Action {
        NORMAL,
        OTHER
    }

    event CalldataTransmitted();

    address private immutable _owner;

    ILBPair private immutable _lender;

    IERC20 private immutable _tokenX;
    IERC20 private immutable _tokenY;

    constructor(ILBPair lender_) {
        _owner = msg.sender;
        _lender = lender_;

        (_tokenX, _tokenY) = (lender_.tokenX(), lender_.tokenY());
    }

    function LBFlashLoanCallback(
        address sender,
        IERC20 token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        if (msg.sender != address(_lender)) {
            revert FlashBorrower__UntrustedLender();
        }
        (Action action, bool isReentrant) = abi.decode(data, (Action, bool));
        if (isReentrant) {
            _lender.flashLoan(this, token, amount, data);
        }
        if (action == Action.NORMAL) {
            emit CalldataTransmitted();
        }

        token.transfer(address(_lender), amount + fee);

        return Constants.CALLBACK_SUCCESS;
    }

    /// @dev Initiate a flash loan
    function flashBorrow(uint256 amountXBorrowed, uint256 amountYBorrowed) public {
        bytes memory data = abi.encode(Action.NORMAL, false);

        if (amountXBorrowed > 0) {
            _lender.flashLoan(this, _tokenX, amountXBorrowed, data);
        }
        if (amountYBorrowed > 0) {
            _lender.flashLoan(this, _tokenY, amountYBorrowed, data);
        }
    }

    function flashBorrowWithReentrancy(uint256 amountXBorrowed, uint256 amountYBorrowed) public {
        bytes memory data = abi.encode(Action.NORMAL, true);

        if (amountXBorrowed > 0) {
            _lender.flashLoan(this, _tokenX, amountXBorrowed, data);
        }
        if (amountYBorrowed > 0) {
            _lender.flashLoan(this, _tokenY, amountYBorrowed, data);
        }
    }
}
