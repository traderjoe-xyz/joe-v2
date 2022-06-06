// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./LBPair.sol";
import "./interfaces/ILBFactoryHelper.sol";

error LBFactoryHelper__NotFactory();

contract LBFactoryHelper {
    address public immutable factory;

    modifier OnlyFactory() {
        if (msg.sender != factory) revert LBFactoryHelper__NotFactory();
        _;
    }

    /// @notice Initialize the factory address
    /// @param _factory The factory address
    constructor(address _factory) {
        factory = _factory;
    }

    /// @notice Create a liquidity bin pair with a given salt
    function createLBPair(
        address _token0,
        address _token1,
        uint256 _feeParameters
    ) external OnlyFactory returns (address) {
        return
            address(
                new LBPair{salt: keccak256(abi.encode(_token0, _token1))}(
                    factory,
                    _token0,
                    _token1,
                    _feeParameters
                )
            );
    }
}
