// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "./interfaces/ILBPair.sol";
import "./LBPair.sol";

error LBFactory__IdenticalAddresses();
error LBFactory__ZeroAddress();
error LBFactory__LBPairAlreadyExists();

contract LBFactory is Ownable {
    address public feeRecipient;
    address public immutable implementation;

    address[] public allLBPairs;
    mapping(IERC20Upgradeable => mapping(IERC20Upgradeable => address))
        private _LBPair;

    event PairCreated(
        IERC20Upgradeable indexed _token0,
        IERC20Upgradeable indexed _token1,
        address pair,
        uint256 pid
    );

    event FeeRecipientChanged(address oldRecipient, address newRecipient);

    /// @notice Constructor
    /// @param _implementation The address of the LB implementation
    constructor(address _implementation) {
        implementation = _implementation;
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
    function getLBPair(IERC20Upgradeable _tokenA, IERC20Upgradeable _tokenB)
        external
        view
        returns (address)
    {
        (IERC20Upgradeable _token0, IERC20Upgradeable _token1) = _tokenA <
            _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);
        return _LBPair[_token0][_token1];
    }

    /// @notice Create a liquidity bin pair for _tokenA and _tokenB, using the
    /// Clones pattern from Open Zeppelin
    /// @param _tokenA The address of the first token
    /// @param _tokenB The address of the second token
    /// @param _baseFee The base fee of the pair
    /// @param _bp The basis point, used to calculate log(1 + _bp)
    /// @return pair The address of the newly created pair
    function createLBPair(
        IERC20Upgradeable _tokenA,
        IERC20Upgradeable _tokenB,
        uint256 _baseFee,
        uint256 _bp
    ) external returns (address pair) {
        if (_tokenA == _tokenB) revert LBFactory__IdenticalAddresses();
        (IERC20Upgradeable _token0, IERC20Upgradeable _token1) = _tokenA <
            _tokenB
            ? (_tokenA, _tokenB)
            : (_tokenB, _tokenA);
        if (address(_token0) == address(0)) revert LBFactory__ZeroAddress();
        if (_LBPair[_token0][_token1] != address(0))
            revert LBFactory__LBPairAlreadyExists(); // single check is sufficient
        // pair = address(
        //     new LBPair{salt: keccak256(abi.encodePacked(_token0, _token1))}(
        //         _token0,
        //         _token1,
        //         _baseFee,
        //         _bp
        //     )
        // );

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
}
