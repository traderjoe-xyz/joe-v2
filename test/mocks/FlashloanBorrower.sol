// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "openzeppelin/interfaces/IERC20.sol";

import "src/LBPair.sol";

error FlashBorrower__UntrustedLender();
error FlashBorrower__UntrustedLoanInitiator();

contract FlashBorrower {
    enum Action {
        NORMAL,
        OTHER
    }

    event CalldataTransmitted();

    ILBPair private lender;

    constructor(ILBPair lender_) {
        lender = lender_;
    }

    function LBFlashLoanCallback(
        address sender,
        uint256 amountX,
        uint256 amountY,
        uint256 feeX,
        uint256 feeY,
        bytes calldata data
    ) external {
        if (msg.sender != address(lender)) {
            revert FlashBorrower__UntrustedLender();
        }
        (Action action, uint256 amountXBorrowed, uint256 amountYBorrowed, bool isReentrant) = abi.decode(
            data,
            (Action, uint256, uint256, bool)
        );
        if (isReentrant) {
            lender.flashLoan(address(this), amountXBorrowed, amountYBorrowed, data);
        }
        if (action == Action.NORMAL) {
            emit CalldataTransmitted();
        }

        IERC20(lender.tokenX()).transfer(address(lender), amountXBorrowed + feeX);
        IERC20(lender.tokenY()).transfer(address(lender), amountYBorrowed + feeY);
    }

    /// @dev Initiate a flash loan
    function flashBorrow(uint256 amountXBorrowed, uint256 amountYBorrowed) public {
        bytes memory data = abi.encode(Action.NORMAL, amountXBorrowed, amountYBorrowed, false);

        lender.flashLoan(address(this), amountXBorrowed, amountYBorrowed, data);
    }

    function flashBorrowWithReentrancy(uint256 amountXBorrowed, uint256 amountYBorrowed) public {
        bytes memory data = abi.encode(Action.NORMAL, amountXBorrowed, amountYBorrowed, true);

        lender.flashLoan(address(this), amountXBorrowed, amountYBorrowed, data);
    }
}
