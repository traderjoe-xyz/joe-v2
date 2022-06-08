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
