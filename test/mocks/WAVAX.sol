// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "openzeppelin/token/ERC20/ERC20.sol";

/// @title WAVAX
/// @author Trader Joe
/// @dev ONLY FOR TESTS
contract WAVAX is ERC20 {
    /// @dev Constructor
    constructor() ERC20("Wrapped Avax", "WAVAX") {
        bool _shh;
        _shh;
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount) external {
        _burn(msg.sender, _amount);
        (bool success, ) = msg.sender.call{value: _amount}("");

        if (!success) {
            revert("Withdraw failed");
        }
    }
}
