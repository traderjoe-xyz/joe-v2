// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./libraries/PendingOwnable.sol";
import "./LBFactoryHelper.sol";
import "./LBPair.sol";
import "./interfaces/ILBFactoryHelper.sol";

error LBFactory__IdenticalAddresses();
error LBFactory__ZeroAddress();
error LBFactory__LBPairAlreadyExists();

contract LBFactory is PendingOwnable {
    address public feeRecipient;

    ILBFactoryHelper public immutable factoryHelper;

    address[] public allLBPairs;
    mapping(address => mapping(address => address)) private _LBPair;

    event PairCreated(
        address indexed _token0,
        address indexed _token1,
        address pair,
        uint256 pid
    );

    event FeeRecipientChanged(address oldRecipient, address newRecipient);

    /// @notice Constructor
    constructor() {
        factoryHelper = ILBFactoryHelper(
            address(new LBFactoryHelper(address(this)))
        );
    }

    /// @notice View function to return the number of LBPairs created
    /// @return The number of pair
    function allPairsLength() external view returns (uint256) {
        return allLBPairs.length;
    }

    /// @notice Returns the address of the pair if it exists,
    /// if not, then the address 0 is returned. The order doesn't matter
    /// @param _tokenA The address of the first token
    /// @param _tokenB The address of the second token
    /// @return pair The address of the pair
    function getLBPair(address _tokenA, address _tokenB)
        external
        view
        returns (address)
    {
        (address _token0, address _token1) = _sortAddresses(_tokenA, _tokenB);
        return _LBPair[_token0][_token1];
    }

    /// @notice Create a liquidity bin pair for _tokenA and _tokenB
    /// @param _tokenA The address of the first token
    /// @param _tokenB The address of the second token
    /// @param _baseFee The base fee of the pair
    /// @param _bp The basis point, used to calculate log(1 + _bp)
    /// @return pair The address of the newly created pair
    function createLBPair(
        address _tokenA,
        address _tokenB,
        uint16 _baseFee,
        uint16 _bp
    ) external returns (address pair) {
        if (_tokenA == _tokenB) revert LBFactory__IdenticalAddresses();
        (address _token0, address _token1) = _sortAddresses(_tokenA, _tokenB);
        if (address(_token0) == address(0)) revert LBFactory__ZeroAddress();
        if (_LBPair[_token0][_token1] != address(0))
            revert LBFactory__LBPairAlreadyExists(); // single check is sufficient

        pair = factoryHelper.createLBPair(_token0, _token1, _baseFee, _bp);

        _LBPair[_token0][_token1] = pair;
        allLBPairs.push(pair);

        emit PairCreated(_token0, _token1, pair, allLBPairs.length - 1);
    }

    /// @notice Function to set the recipient of the fees
    /// @param _feeRecipient The address of the recipient
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        address oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientChanged(oldFeeRecipient, _feeRecipient);
    }

    function _sortAddresses(address _tokenA, address _tokenB)
        internal
        pure
        returns (address, address)
    {
        return _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
    }
}
