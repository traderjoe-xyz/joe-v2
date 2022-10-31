// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "openzeppelin/token/ERC20/ERC20.sol";

/// @title ERC20MockDecimals
/// @author Trader Joe
/// @dev ONLY FOR TESTS
contract ERC20WithTransferTax is ERC20 {
    /// @dev Constructor
    constructor() ERC20("ERC20Mock", "ERC20M") {}

    /// @dev Mint _amount to _to.
    /// @param _to The address that will receive the mint
    /// @param _amount The amount to be minted
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
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
