// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./LBPair.sol";
import "./interfaces/ILBFactoryHelper.sol";

error LBFactoryHelper__NotFactory();

contract LBFactoryHelper is ILBFactoryHelper {
    ILBFactory public immutable factory;

    modifier OnlyFactory() {
        if (msg.sender != address(factory))
            revert LBFactoryHelper__NotFactory();
        _;
    }

    /// @notice Initialize the factory address
    constructor() {
        factory = ILBFactory(msg.sender);
    }

    /// @notice Create a liquidity bin pair with a given salt
    /// @param _token0 The address of the token0. Can't be address 0
    /// @param _token1 The address of the token1. Can't be address 0
    /// @param _log2Value The log(1 + binStep) value
    /// @param _salt The salt used to create the pair
    /// @param _packedFeeParameters The fee parameters packed in a single 256 bits slot
    /// @return The address of the pair newly created
    function createLBPair(
        IERC20 _token0,
        IERC20 _token1,
        int256 _log2Value,
        bytes32 _salt,
        bytes32 _packedFeeParameters
    ) external override OnlyFactory returns (ILBPair) {
        return
            new LBPair{salt: _salt}(
                factory,
                _token0,
                _token1,
                _log2Value,
                _packedFeeParameters
            );
    }
}
