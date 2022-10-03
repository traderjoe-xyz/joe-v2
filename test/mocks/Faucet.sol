// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20MockDecimalsOwnable.sol";
import "../../src/libraries/PendingOwnable.sol";

/// @title Faucet contract
/// @author Trader Joe
/// @dev This contract should only be used for testnet
/// @notice Create a faucet contract that create test tokens and allow user to request for tokens.
/// This faucet will also provide AVAX if avax were sent to the contract (either during the construction or after).
/// This contract will not fail if its avax balance becomes too low, it will just not send AVAX but will mint the different tokens.
contract Faucet is PendingOwnable {
    struct FaucetTokenParameter {
        string name;
        string symbol;
        uint8 decimals;
        uint96 amountPerRequest;
    }

    struct FaucetToken {
        address ERC20;
        uint96 amountPerRequest;
    }

    uint256 public requestCoolDown;

    FaucetToken[] public faucetTokens;
    mapping(address => uint256) public lastRequest;

    mapping(string => uint256) symbolToIndices;

    /// @notice Creates the different test tokens and their respective amount per request
    /// @param tokens The different parameters to create a test token
    /// @param _avaxPerRequest The avax received per request
    /// @param _requestCoolDown The request cool down
    constructor(
        FaucetTokenParameter[] memory tokens,
        uint96 _avaxPerRequest,
        uint256 _requestCoolDown
    ) payable {
        _setRequestCoolDown(_requestCoolDown);

        faucetTokens.push(FaucetToken({ERC20: address(0), amountPerRequest: _avaxPerRequest}));
        symbolToIndices["AVAX"] = 1;

        for (uint256 i; i < tokens.length; ++i) {
            FaucetTokenParameter memory parameters = tokens[i];

            require(symbolToIndices[parameters.symbol] == 0, "only unique symbol");
            require(parameters.decimals > 0, "wrong decimals");

            symbolToIndices[parameters.symbol] = i + 2;

            faucetTokens.push(
                FaucetToken({
                    ERC20: address(
                        new ERC20MockDecimalsOwnable(parameters.name, parameters.symbol, parameters.decimals)
                    ),
                    amountPerRequest: parameters.amountPerRequest
                })
            );
        }
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

            if (token.amountPerRequest > 0)
                ERC20MockDecimalsOwnable(token.ERC20).mint(msg.sender, token.amountPerRequest);
        }
    }

    /// @notice Set the request cool down for every users
    /// @dev This function needs to be called bu the owner
    /// @param _requestCoolDown The new cool down
    function setRequestCoolDown(uint256 _requestCoolDown) external onlyOwner {
        _setRequestCoolDown(_requestCoolDown);
    }

    /// @notice Set the amount per request of a specific token, designated by its symbol
    /// @dev This function needs to be called bu the owner
    /// @param symbol the symbol of the token
    /// @param amountPerRequest The new amount per request
    function setAmountPerRequest(string calldata symbol, uint96 amountPerRequest) external onlyOwner {
        _setAmountPerRequest(symbol, amountPerRequest);
    }

    /// @notice Mint amount tokens directly to the recipient address, designated by its symbol
    /// @dev This function needs to be called bu the owner
    /// @param symbol The token's symbol
    /// @param recipient The address of the recipient
    /// @param amount The amount of token to mint
    function mint(
        string calldata symbol,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        uint256 index = symbolToIndices[symbol];

        require(index >= 2, "Wrong faucet symbol");

        ERC20MockDecimalsOwnable(faucetTokens[index - 1].ERC20).mint(recipient, amount);
    }

    /// @notice Withdraw `amount` AVAX to `to`
    /// @dev This function needs to be called bu the owner
    function withdrawAVAX(address to, uint256 amount) external onlyOwner {
        _sendAvax(to, amount);
    }

    /// @notice Private function to set the request cool down for every users
    /// @dev The new cool down needs to be greater than 1 hour
    /// @param _requestCoolDown The new cool down
    function _setRequestCoolDown(uint256 _requestCoolDown) private {
        require(_requestCoolDown >= 1 hours, "unsafe request cool down");

        requestCoolDown = _requestCoolDown;
    }

    /// @notice Private function to set the amount per request of a specific token, designated by its symbol
    /// @param symbol the symbol of the token
    /// @param amountPerRequest The new amount per request
    function _setAmountPerRequest(string calldata symbol, uint96 amountPerRequest) private {
        uint256 index = symbolToIndices[symbol];

        require(index != 0, "Wrong faucet symbol");

        faucetTokens[index - 1].amountPerRequest = amountPerRequest;
    }

    function _sendAvax(address to, uint256 amount) private {
        (bool success, ) = to.call{value: amount}("");
        require(success, "AVAX transfer failed");
    }
}
