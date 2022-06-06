// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./libraries/PendingOwnable.sol";
import "./LBFactoryHelper.sol";
import "./LBPair.sol";
import "./interfaces/ILBFactoryHelper.sol";

error LBFactory__IdenticalAddresses(address token);
error LBFactory__ZeroAddress();
error LBFactory__LBPairAlreadyExists(address token0, address token1);
error LBFactory__BinStepTooBig(uint16 binStep, uint16 max);
error LBFactory__fFTooBig(uint16 fF, uint16 max);
error LBFactory__fVTooBig(uint16 fV, uint16 max);
error LBFactory__maxFeeTooBig(uint16 maxFee, uint16 max);
error LBFactory___protocolShareTooBig(uint16 protocolShare, uint16 max);
error LBFactory___protocolShareTooLow(uint16 protocolShare, uint16 min);

contract LBFactory is PendingOwnable {
    ILBFactoryHelper public immutable factoryHelper;
    
    address public feeRecipient;

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
    constructor(address _feeRecipient) {
        factoryHelper = ILBFactoryHelper(
            address(new LBFactoryHelper(address(this)))
        );
        _setFeeRecipient(_feeRecipient);
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
    /// @param _coolDownTime The cool down time, the accumulator slowly decrease to 0 over the cool down time
    /// @param _binStep The bin step in basis point, used to calculate log(1 + _binStep)
    /// @param _fF //TODO
    /// @param _fV //TODO
    /// @param _maxFee The max fee that users will have to pay
    /// @param _protocolShare The share of the fees received by the protocol
    /// @return pair The address of the newly created pair
    function createLBPair(
        address _tokenA,
        address _tokenB,
        uint16 _coolDownTime,
        uint16 _binStep,
        uint16 _fF,
        uint16 _fV,
        uint16 _maxFee,
        uint16 _protocolShare
    ) external returns (address pair) {
        if (_tokenA == _tokenB) revert LBFactory__IdenticalAddresses(_tokenA);
        (address _token0, address _token1) = _sortAddresses(_tokenA, _tokenB);
        if (address(_token0) == address(0)) revert LBFactory__ZeroAddress();
        if (_LBPair[_token0][_token1] != address(0))
            revert LBFactory__LBPairAlreadyExists(_token0, _token1); // single check is sufficient
        if (_binStep > 100) revert LBFactory__BinStepTooBig(_binStep, 100);
        if (_fF > 10_000) revert LBFactory__fFTooBig(_fF, 10_000);
        if (_fV > 10_000) revert LBFactory__fVTooBig(_fV, 10_000);
        if (_maxFee > 1_000) revert LBFactory__maxFeeTooBig(_maxFee, 1_000);
        if (_protocolShare < 1_000)
            revert LBFactory___protocolShareTooLow(_protocolShare, 1_000);
        if (_protocolShare > 10_000)
            revert LBFactory___protocolShareTooBig(_protocolShare, 10_000);

        uint256 _feeParameters = uint256(
            bytes32(
                abi.encodePacked(
                    _protocolShare,
                    _maxFee,
                    _fV,
                    _fF,
                    _binStep,
                    _coolDownTime
                )
            )
        );

        pair = factoryHelper.createLBPair(_token0, _token1, _feeParameters);

        _LBPair[_token0][_token1] = pair;
        allLBPairs.push(pair);

        emit PairCreated(_token0, _token1, pair, allLBPairs.length - 1);
    }

    /// @notice Function to set the recipient of the fees
    /// @param _feeRecipient The address of the recipient
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        _setFeeRecipient(_feeRecipient);
    }

    /// @notice Internal function to set the recipient of the fees
    /// @param _feeRecipient The address of the recipient
    function _setFeeRecipient(address _feeRecipient) internal {
        address oldFeeRecipient = feeRecipient;
        feeRecipient = _feeRecipient;
        emit FeeRecipientChanged(oldFeeRecipient, _feeRecipient);
    }

    /// @notice Internal function to sort token addresses
    /// @param _tokenA The address of the tokenA
    /// @param _tokenB The address of the tokenB
    /// @return The address of the token0
    /// @return The address of the token1
    function _sortAddresses(address _tokenA, address _tokenB)
        internal
        pure
        returns (address, address)
    {
        return _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
    }
}
