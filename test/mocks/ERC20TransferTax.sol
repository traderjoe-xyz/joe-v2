// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ERC20Mock} from "./ERC20.sol";

/// @title ERC20MockTransferTax
/// @author Trader Joe
/// @dev ONLY FOR TESTS
contract ERC20TransferTaxMock is ERC20Mock {
    /// @dev Constructor
    constructor() ERC20Mock(18) {}

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        uint256 tax = amount / 2;
        _transfer(from, to, amount - tax);
        _burn(from, tax);
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        uint256 tax = amount / 2;
        _transfer(msg.sender, to, amount - tax);
        _burn(msg.sender, tax);
        return true;
    }
}
