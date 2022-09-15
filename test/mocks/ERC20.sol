// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/ERC20.sol";

/// @title ERC20Mock
/// @author Trader Joe
/// @dev ONLY FOR TESTS
contract ERC20Mock is ERC20 {
    uint8 private decimalsOverride;

    /// @dev Constructor
    /// @param _decimals The number of decimals for this token
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        decimalsOverride = _decimals;
    }

    /// @dev Define the number of decimals
    /// @return The number of decimals
    function decimals() public view override returns (uint8) {
        return decimalsOverride;
    }

    /// @dev Mint _amount to _to.
    /// @param _to The address that will receive the mint
    /// @param _amount The amount to be minted
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
