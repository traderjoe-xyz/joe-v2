// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/access/Ownable.sol";

import "../../src/libraries/PendingOwnable.sol";

interface IERC20Mintable is IERC20Metadata {
    function mint(address to, uint256 amount) external;
}

/// @title Faucet contract
/// @author Trader Joe
/// @dev This contract should only be used for testnet
/// @notice Create a faucet contract that create test tokens and allow user to request for tokens.
/// This faucet will also provide AVAX if avax were sent to the contract (either during the construction or after).
/// This contract will not fail if its avax balance becomes too low, it will just not send AVAX but will mint the different tokens.
contract Faucet is PendingOwnable {
    /// @dev Structure for faucet token, use only 1 storage slot
    struct FaucetToken {
        address ERC20;
        uint96 amountPerRequest;
    }

    /// @notice The minimum time needed between 2 requests
    uint256 public requestCoolDown;

    /// @notice last time a user has requested tokens
    mapping(address => uint256) public lastRequest;

    /// @notice faucet tokens set, custom to be able to use structures
    FaucetToken[] public faucetTokens;
    mapping(address => uint256) tokenToIndices;

    /// @notice Constructor of the faucet.
    /// @param _avaxPerRequest The avax received per request
    /// @param _requestCoolDown The request cool down
    constructor(uint96 _avaxPerRequest, uint256 _requestCoolDown) payable {
        _setRequestCoolDown(_requestCoolDown);
        _addFaucetToken(FaucetToken({ERC20: address(0), amountPerRequest: _avaxPerRequest}));
    }

    /// @notice Allows to receive AVAX directly
    receive() external payable {}

    /// @notice Returns the number of tokens given by the faucet
    function numberOfFaucetTokens() external view returns (uint256) {
        return faucetTokens.length;
    }

    /// @notice User needs to call this function in order to receive test tokens and avax
    /// @dev If contract's avax balance is not enough, it won't revert and will only receive the different test tokens
    function request() external {
        require(block.timestamp >= lastRequest[msg.sender] + requestCoolDown, "Too many request");
        lastRequest[msg.sender] = block.timestamp;

        uint256 len = faucetTokens.length;

        FaucetToken memory token = faucetTokens[0];

        if (token.amountPerRequest > 0 && address(this).balance >= token.amountPerRequest) {
            _sendAvax(msg.sender, token.amountPerRequest);
        }

        for (uint256 i = 1; i < len; ++i) {
            token = faucetTokens[i];

            if (token.amountPerRequest > 0) IERC20Mintable(token.ERC20).mint(msg.sender, token.amountPerRequest);
        }
    }

    /// @notice Add a token to the faucet
    /// @dev Tokens need to be owned by the faucet, and only mintable by the owner
    /// @param _token The address of the token
    /// @param _amountPerRequest The amount per request
    function addFaucetToken(address _token, uint96 _amountPerRequest) external onlyOwner {
        require(Ownable(_token).owner() == address(this), "Faucet is not the owner of token");

        _addFaucetToken(FaucetToken({ERC20: _token, amountPerRequest: _amountPerRequest}));
    }

    /// @notice Remove a token from the faucet
    /// @dev Token needs to be in the set, and AVAX can't be removed
    /// @param _token The address of the token
    function removeFaucetToken(address _token) external onlyOwner {
        uint256 index = tokenToIndices[_token];

        require(index >= 2, "Not a faucet token");

        Ownable(_token).transferOwnership(owner());

        uint256 lastIndex = faucetTokens.length - 1;
        faucetTokens[index] = faucetTokens[lastIndex];

        delete faucetTokens[lastIndex];
        delete tokenToIndices[_token];
    }

    /// @notice Set the request cool down for every users
    /// @dev This function needs to be called bu the owner
    /// @param _requestCoolDown The new cool down
    function setRequestCoolDown(uint256 _requestCoolDown) external onlyOwner {
        _setRequestCoolDown(_requestCoolDown);
    }

    /// @notice Set the amount per request of a specific token, designated by its symbol
    /// @dev This function needs to be called bu the owner
    /// @param _token The address of the token
    /// @param _amountPerRequest The new amount per request
    function setAmountPerRequest(address _token, uint96 _amountPerRequest) external onlyOwner {
        _setAmountPerRequest(_token, _amountPerRequest);
    }

    /// @notice Mint amount tokens directly to the recipient address, designated by its symbol
    /// @dev This function needs to be called bu the owner
    /// @param _token The address of the token
    /// @param _recipient The address of the recipient
    /// @param _amount The amount of token to mint
    function mint(
        address _token,
        address _recipient,
        uint256 _amount
    ) external onlyOwner {
        require(tokenToIndices[_token] >= 2, "Not a faucet token");

        IERC20Mintable(_token).mint(_recipient, _amount);
    }

    /// @notice Withdraw `amount` AVAX to `to`
    /// @dev This function needs to be called bu the owner
    /// @param _to The recipient address
    /// @param _amount The AVAX amount to send
    function withdrawAVAX(address _to, uint256 _amount) external onlyOwner {
        _sendAvax(_to, _amount);
    }

    /// @notice Private function to add a token to the faucet
    /// @dev Token needs to be not added to the set yet
    /// @param _token The token to add, using the FaucetToken structure
    function _addFaucetToken(FaucetToken memory _token) private {
        require(tokenToIndices[_token.ERC20] == 0, "Already a faucet token");

        faucetTokens.push(_token);
        tokenToIndices[_token.ERC20] = faucetTokens.length;
    }

    /// @notice Private function to set the request cool down for every users
    /// @dev The new cool down needs to be greater than 1 hour
    /// @param _requestCoolDown The new cool down
    function _setRequestCoolDown(uint256 _requestCoolDown) private {
        require(_requestCoolDown >= 1 hours, "Unsafe request cool down");

        requestCoolDown = _requestCoolDown;
    }

    /// @notice Private function to set the amount per request of a specific token, designated by its symbol
    /// @param _token The address of the token
    /// @param _amountPerRequest The new amount per request
    function _setAmountPerRequest(address _token, uint96 _amountPerRequest) private {
        uint256 index = tokenToIndices[_token];

        require(index != 0, "Not a faucet token");

        faucetTokens[index - 1].amountPerRequest = _amountPerRequest;
    }

    /// @notice Private function to send `amount` AVAX to `to`
    /// @param _to The recipient address
    /// @param _amount The AVAX amount to send
    function _sendAvax(address _to, uint256 _amount) private {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "AVAX transfer failed");
    }
}
