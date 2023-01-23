// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ERC20Mock} from "./ERC20.sol";

/// @title ERC20MockTransferTax
/// @author Trader Joe
/// @dev ONLY FOR TESTS
contract ERC20TransferTaxMock is ERC20Mock {
    /// @dev Constructor
    constructor() ERC20Mock(18) {}

    function _transfer(address from, address to, uint256 amount) internal override {
        uint256 tax = amount / 2;
        _burn(from, tax);
        super._transfer(from, to, amount - tax);
    }
}
