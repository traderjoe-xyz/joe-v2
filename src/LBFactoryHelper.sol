// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./LBPair.sol";
import "./interfaces/ILBFactoryHelper.sol";

error LBFactoryHelper__CallerIsNotFactory();

contract LBFactoryHelper is ILBFactoryHelper {
    ILBFactory public immutable override factory;

    modifier OnlyFactory() {
        if (msg.sender != address(factory)) revert LBFactoryHelper__CallerIsNotFactory();
        _;
    }

    /// @notice Initialize the factory address
    /// @param _LBFactory The address of the LBFactory
    constructor(ILBFactory _LBFactory) {
        factory = _LBFactory;
        _LBFactory.setFactoryHelper();
    }

    /// @notice Create a liquidity bin pair with a given salt
    /// @param _tokenX The address of the tokenX. Can't be address 0
    /// @param _tokenY The address of the tokenY. Can't be address 0
    /// @param _salt The salt used to create the pair
    /// @param _activeId The active id of the pair
    /// @param _sampleLifetime The lifetime of a sample. It's the min time between 2 oracle's sample
    /// @param _packedFeeParameters The fee parameters packed in a single 256 bits slot
    /// @return The address of the pair newly created
    function createLBPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        bytes32 _salt,
        uint24 _activeId,
        uint16 _sampleLifetime,
        bytes32 _packedFeeParameters
    ) external override OnlyFactory returns (ILBPair) {
        return new LBPair{salt: _salt}(factory, _tokenX, _tokenY, _activeId, _sampleLifetime, _packedFeeParameters);
    }
}
