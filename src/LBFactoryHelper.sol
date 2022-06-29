// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./LBPair.sol";
import "./interfaces/ILBFactoryHelper.sol";

error LBFactoryHelper__CallerIsNotFactory();

contract LBFactoryHelper is ILBFactoryHelper {
    ILBFactory public immutable factory;

    modifier OnlyFactory() {
        if (msg.sender != address(factory))
            revert LBFactoryHelper__CallerIsNotFactory();
        _;
    }

    /// @notice Initialize the factory address
    constructor(ILBFactory _lbFactory) {
        factory = _lbFactory;
        _lbFactory.setFactoryHelper();
    }

    /// @notice Create a liquidity bin pair with a given salt
    /// @param _tokenX The address of the tokenX. Can't be address 0
    /// @param _tokenY The address of the tokenY. Can't be address 0
    /// @param _salt The salt used to create the pair
    /// @param _packedFeeParameters The fee parameters packed in a single 256 bits slot
    /// @return The address of the pair newly created
    function createLBPair(
        IERC20 _tokenX,
        IERC20 _tokenY,
        bytes32 _salt,
        bytes32 _packedFeeParameters
    ) external override OnlyFactory returns (ILBPair) {
        return
            new LBPair{salt: _salt}(
                factory,
                _tokenX,
                _tokenY,
                _packedFeeParameters
            );
    }
}
