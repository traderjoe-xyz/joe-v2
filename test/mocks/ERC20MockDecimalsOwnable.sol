// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/ERC20.sol";

/// @title ERC20MockDecimalsOwnable
/// @author Trader Joe
/// @dev ONLY FOR TESTS
contract ERC20MockDecimalsOwnable is ERC20 {
    address public immutable owner;

    uint8 private immutable decimalsOverride;

    modifier onlyOwner() {
        require(owner == msg.sender, "Function is restricted to owner");
        _;
    }

    /// @dev Constructor
    /// @param _decimals The number of decimals for this token
    constructor(
        string memory name,
        string memory symbol,
        uint8 _decimals
    ) ERC20(name, symbol) {
        owner = msg.sender;
        decimalsOverride = _decimals;
    }

    /// @dev Define the number of decimals
    /// @return The number of decimals
    function decimals() public view override returns (uint8) {
        return decimalsOverride;
    }

    /// @dev Mint _amount to _to, only callable by the owner
    /// @param _to The address that will receive the mint
    /// @param _amount The amount to be minted
    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}
