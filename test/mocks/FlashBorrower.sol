// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";

import {ILBPair} from "src/LBPair.sol";
import {ILBFlashLoanCallback} from "src/interfaces/ILBFlashLoanCallback.sol";
import {Constants} from "src/libraries/Constants.sol";
import {PackedUint128Math} from "src/libraries/math/PackedUint128Math.sol";
import {TokenHelper} from "src/libraries/TokenHelper.sol";
import {AddressHelper} from "src/libraries/AddressHelper.sol";

contract FlashBorrower is ILBFlashLoanCallback {
    using PackedUint128Math for bytes32;
    using TokenHelper for IERC20;
    using AddressHelper for address;

    enum Action {
        NORMAL,
        REENTRANT
    }

    error FlashBorrower__UntrustedLender();
    error FlashBorrower__UntrustedLoanInitiator();

    ILBPair private immutable _lender;

    constructor(ILBPair lender_) {
        _lender = lender_;
    }

    function LBFlashLoanCallback(
        address,
        IERC20 tokenX,
        IERC20 tokenY,
        bytes32 amounts,
        bytes32 totalFees,
        bytes calldata data
    ) external override returns (bytes32) {
        (uint128 paybackX, uint128 paybackY, bytes32 callback, Action a) =
            abi.decode(data, (uint128, uint128, bytes32, Action));

        if (a == Action.REENTRANT) {
            _lender.flashLoan(this, amounts, "");
        }

        if (paybackX == type(uint128).max) {
            paybackX = amounts.decodeX() + totalFees.decodeX();
        }

        if (paybackY == type(uint128).max) {
            paybackY = amounts.decodeY() + totalFees.decodeY();
        }

        if (paybackX > 0) {
            tokenX.safeTransfer(msg.sender, paybackX);
        }

        if (paybackY > 0) {
            tokenY.safeTransfer(msg.sender, paybackY);
        }

        return callback;
    }
}
