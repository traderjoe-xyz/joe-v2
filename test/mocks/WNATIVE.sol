// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract WNATIVE is ERC20 {
    constructor() ERC20("Wrapped Native", "WNATIVE") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount) external {
        _burn(msg.sender, _amount);
        (bool success,) = msg.sender.call{value: _amount}("");

        if (!success) {
            revert("Withdraw failed");
        }
    }
}
