// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./LBPair.sol";

error LBFactoryHelper__NotFactory();

contract LBFactoryHelper {
    address public immutable factory;

    modifier OnlyFactory() {
        if (msg.sender != factory) revert LBFactoryHelper__NotFactory();
        _;
    }

    /// @notice Initialize the factory address
    constructor() {
        factory = msg.sender;
    }

    /// @notice Create a liquidity bin pair with a given salt
    function createLBPair(
        address _token0,
        address _token1,
        int256 _log2Value,
        bytes32 _salt,
        bytes32 _feeParameters
    ) external OnlyFactory returns (address) {
        return
            address(
                new LBPair{salt: _salt}(
                    factory,
                    _token0,
                    _token1,
                    _log2Value,
                    _feeParameters
                )
            );
    }
}
