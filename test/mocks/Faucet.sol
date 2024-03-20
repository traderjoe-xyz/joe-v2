// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title Faucet contract
/// @author Trader Joe
/// @dev This contract should only be used for testnet
/// @notice Create a faucet contract that create test tokens and allow user to request for tokens.
/// This faucet will also provide NATIVE if native were sent to the contract (either during the construction or after).
/// This contract will not fail if its native balance becomes too low, it will just not send NATIVE but will mint the different tokens.
contract Faucet is Ownable2Step {
    using SafeERC20 for IERC20;

    /// @dev Structure for faucet token, use only 1 storage slot
    struct FaucetToken {
        IERC20 ERC20;
        uint96 amountPerRequest;
    }

    /// @notice The address of the operator that can call request for other address
    address public operator;

    /// @notice The minimum time needed between 2 requests
    uint256 public requestCooldown;

    bool public unlockedRequest;

    /// @notice last time a user has requested tokens
    mapping(address => uint256) public lastRequest;

    /// @notice faucet tokens set, custom to be able to use structures
    FaucetToken[] public faucetTokens;
    mapping(IERC20 => uint256) tokenToIndices;

    modifier onlyOperator() {
        require(msg.sender == operator, "Only operator");
        _;
    }

    modifier verifyRequest(address user) {
        require(block.timestamp >= lastRequest[user] + requestCooldown, "Too many requests");
        _;
    }

    modifier onlyEOA() {
        require(tx.origin == msg.sender, "Only EOA");
        _;
    }

    modifier isRequestUnlocked() {
        require(unlockedRequest, "Direct request is locked");
        _;
    }

    /// @notice Constructor of the faucet, set the request cooldown and add native to the faucet
    /// @param _nativePerRequest The native received per request
    /// @param _requestCooldown The request cooldown
    constructor(address initialOwner, uint96 _nativePerRequest, uint256 _requestCooldown)
        payable
        Ownable(initialOwner)
    {
        _setRequestCooldown(_requestCooldown);
        _addFaucetToken(FaucetToken({ERC20: IERC20(address(0)), amountPerRequest: _nativePerRequest}));
    }

    /// @notice Allows to receive NATIVE directly
    receive() external payable {}

    /// @notice Returns the number of tokens given by the faucet
    function numberOfFaucetTokens() external view returns (uint256) {
        return faucetTokens.length;
    }

    /// @notice User needs to call this function in order to receive test tokens and native
    /// @dev Can be called only once per `requestCooldown` seconds
    function request() external onlyEOA isRequestUnlocked verifyRequest(msg.sender) {
        lastRequest[msg.sender] = block.timestamp;

        _request(msg.sender);
    }

    /// @notice User needs to call this function in order to receive test tokens and native
    /// @dev Can be called only once per `requestCooldown` seconds for every address
    /// Can only be called by the operator
    /// @param _to The address that will receive the tokens
    function request(address _to) external onlyOperator verifyRequest(_to) {
        lastRequest[_to] = block.timestamp;

        _request(_to);
    }

    /// @notice Add a token to the faucet
    /// @dev Tokens need to be owned by the faucet, and only mintable by the owner
    /// @param _token The address of the token
    /// @param _amountPerRequest The amount per request
    function addFaucetToken(IERC20 _token, uint96 _amountPerRequest) external onlyOwner {
        _addFaucetToken(FaucetToken({ERC20: _token, amountPerRequest: _amountPerRequest}));
    }

    /// @notice Remove a token from the faucet
    /// @dev Token needs to be in the set, and NATIVE can't be removed
    /// @param _token The address of the token
    function removeFaucetToken(IERC20 _token) external onlyOwner {
        uint256 index = tokenToIndices[_token];

        require(index >= 2, "Not a faucet token");

        uint256 lastIndex = faucetTokens.length - 1;
        if (--index != lastIndex) {
            FaucetToken memory faucetToken = faucetTokens[lastIndex];

            faucetTokens[index] = faucetToken;

            tokenToIndices[faucetToken.ERC20] = index + 1;
        }

        delete faucetTokens[lastIndex];
        delete tokenToIndices[_token];
    }

    /// @notice Set the request cooldown for every users
    /// @dev This function needs to be called by the owner
    /// @param _requestCooldown The new cooldown
    function setRequestCooldown(uint256 _requestCooldown) external onlyOwner {
        _setRequestCooldown(_requestCooldown);
    }

    /// @notice Set the amount per request of a specific token, designated by its symbol
    /// @dev This function needs to be called by the owner
    /// @param _token The address of the token
    /// @param _amountPerRequest The new amount per request
    function setAmountPerRequest(IERC20 _token, uint96 _amountPerRequest) external onlyOwner {
        _setAmountPerRequest(_token, _amountPerRequest);
    }

    /// @notice Withdraw `amount` of token `token` to `to`
    /// @dev This function needs to be called by the owner
    /// @param _token The address of the token to withdraw
    /// @param _to The recipient address
    /// @param _amount The token amount to send
    function withdrawToken(IERC20 _token, address _to, uint256 _amount) external onlyOwner {
        if (address(_token) == address(0)) _sendNative(_to, _amount);
        else _token.safeTransfer(_to, _amount);
    }

    /// @notice Set the address of the operator
    /// @param _newOperator The address of the new operator
    function setOperator(address _newOperator) external onlyOwner {
        operator = _newOperator;
    }

    /// @notice Set whether the direct request is unlocked or not
    /// @param _unlockedRequest The address of the new operator
    function setUnlockedRequest(bool _unlockedRequest) external onlyOwner {
        unlockedRequest = _unlockedRequest;
    }

    /// @notice Private function to send faucet tokens to the user
    /// @dev Will only send tokens if the faucet has a sufficient balance
    /// @param _to The address that will receive the tokens
    function _request(address _to) private {
        uint256 len = faucetTokens.length;

        FaucetToken memory token = faucetTokens[0];

        if (token.amountPerRequest > 0 && address(this).balance >= token.amountPerRequest) {
            _sendNative(_to, token.amountPerRequest);
        }

        for (uint256 i = 1; i < len; ++i) {
            token = faucetTokens[i];

            if (token.amountPerRequest > 0 && token.ERC20.balanceOf(address(this)) >= token.amountPerRequest) {
                token.ERC20.safeTransfer(_to, token.amountPerRequest);
            }
        }
    }

    /// @notice Private function to add a token to the faucet
    /// @dev Token needs to be not added to the set yet
    /// @param _token The token to add, using the FaucetToken structure
    function _addFaucetToken(FaucetToken memory _token) private {
        require(tokenToIndices[_token.ERC20] == 0, "Already a faucet token");

        faucetTokens.push(_token);
        tokenToIndices[_token.ERC20] = faucetTokens.length;
    }

    /// @notice Private function to set the request cooldown for every users
    /// @dev The new cooldown needs to be greater than 1 hour
    /// @param _requestCooldown The new cooldown
    function _setRequestCooldown(uint256 _requestCooldown) private {
        require(_requestCooldown >= 1 hours, "Unsafe request cooldown");

        requestCooldown = _requestCooldown;
    }

    /// @notice Private function to set the amount per request of a specific token, designated by its symbol
    /// @param _token The address of the token
    /// @param _amountPerRequest The new amount per request
    function _setAmountPerRequest(IERC20 _token, uint96 _amountPerRequest) private {
        uint256 index = tokenToIndices[_token];

        require(index != 0, "Not a faucet token");

        faucetTokens[index - 1].amountPerRequest = _amountPerRequest;
    }

    /// @notice Private function to send `amount` NATIVE to `to`
    /// @param _to The recipient address
    /// @param _amount The NATIVE amount to send
    function _sendNative(address _to, uint256 _amount) private {
        (bool success,) = _to.call{value: _amount}("");
        require(success, "NATIVE transfer failed");
    }
}
