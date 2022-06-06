// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./interfaces/ILBToken.sol";

error LBToken__OperatorNotApproved(address from, address operator);
error LBToken__TransferFromOrToAddress0();
error LBToken__MintToAddress0();
error LBToken__MintTooLow(uint256 amount);
error LBToken__BurnFromAddress0();
error LBToken__BurnExceedsBalance(address from, uint256 id, uint256 amount);
error LBToken__SelfApproval(address owner);
error LBToken__TransferExceedsBalance(address from, uint256 id, uint256 amount);

/// @title Joe Liquidity Bin Provider Token
/// @author Trader Joe
/// @notice The LBToken is an implementation of a multi-token.
/// It allows to create multi-ERC20 represented by their IDs.
contract LBToken is ILBToken {
    // Mapping from token ID to account balances
    mapping(uint256 => mapping(address => uint256)) private _balances;

    // Mapping from account to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Mapping from token ID to total supplies
    mapping(uint256 => uint256) private _totalSupplies;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /// @notice Returns the name of the token
    /// @return The name of the token
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token, usually a shorter version of the name
    /// @return The symbol of the token
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the number of decimals used to get its user representation
    /// @return The number of decimals as uint8
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /// @notice Returns the number of decimals used to get its user representation
    /// @param _id The token ID
    /// @return The total supply of that token ID
    function totalSupply(uint256 _id)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _totalSupplies[_id];
    }

    /// @notice Returns the amount of tokens of type `id` owned by `_account`
    /// @param _account The address of the owner
    /// @param _id The token ID
    /// @return The amount of tokens of type `id` owned by `_account`
    function balanceOf(address _account, uint256 _id)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[_id][_account];
    }

    /// @notice Transfers `_amount` tokens of type `_id` from `msg.sender` to `_to`
    /// @param _to The address of the recipient
    /// @param _id The token ID
    /// @param _amount The amount to send
    function safeTransfer(
        address _to,
        uint256 _id,
        uint256 _amount
    ) public virtual override {
        address _owner = msg.sender;
        _safeTransfer(_owner, _to, _id, _amount);
        emit TransferSingle(_owner, _to, _id, _amount);
    }

    /// @notice Returns true if `operator` is approved to transfer `_account`'s tokens
    /// @param _owner The address of the owner
    /// @param _spender The address of the spender
    /// @return True if `operator` is approved to transfer `_account`'s tokens
    function isApprovedForAll(address _owner, address _spender)
        public
        view
        virtual
        override
        returns (bool)
    {
        return _isApprovedForAll(_owner, _spender);
    }

    /// @notice Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`
    /// @param _operator The address of the operator
    /// @param _approved The boolean value to grant or revoke permission
    function setApprovalForAll(address _operator, bool _approved)
        public
        virtual
        override
    {
        _setApprovalForAll(msg.sender, _operator, _approved);
    }

    /// @notice Transfers `_amount` tokens of type `_id` from `_from` to `_to`
    /// @param _from The address of the owner of the tokens
    /// @param _to The address of the recipient
    /// @param _id The token ID
    /// @param _amount The amount to send
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount
    ) public virtual override {
        address operator = msg.sender;
        if (_isApprovedForAll(_from, operator))
            revert LBToken__OperatorNotApproved(_from, operator);
        _safeTransfer(_from, _to, _id, _amount);
        emit TransferFromSingle(msg.sender, _from, _to, _id, _amount);
    }

    /// @dev Transfers `_amount` tokens of type `_id` from `_from` to `_to`
    /// @param _from The address of the owner of the tokens
    /// @param _to The address of the recipient
    /// @param _id The token ID
    /// @param _amount The amount to send
    function _safeTransfer(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount
    ) internal virtual {
        if (_from == address(0) || _to == address(0))
            revert LBToken__TransferFromOrToAddress0();

        uint256 _fromBalance = _balances[_id][_from];
        if (_fromBalance < _amount)
            revert LBToken__TransferExceedsBalance(_from, _id, _amount);
        unchecked {
            _balances[_id][_from] = _fromBalance - _amount;
        }
        _balances[_id][_to] += _amount;
    }

    /// @dev Creates `_amount` tokens of type `_id`, and assigns them to `_account`
    /// @param _account The address of the recipient
    /// @param _id The token ID
    /// @param _amount The amount to create
    function _mint(
        address _account,
        uint256 _id,
        uint256 _amount
    ) internal virtual {
        if (_account == address(0)) revert LBToken__MintToAddress0();

        uint256 _totalSupply = _totalSupplies[_id];
        _totalSupplies[_id] = _totalSupply + _amount;
        if (_totalSupply == 0) {
            if (_amount < 10_000) revert LBToken__MintTooLow(_amount); // Do we check that ? or only > 1000 ?
            unchecked {
                _amount -= 1000;
                _balances[_id][address(0)] = 1000;
                emit TransferSingle(address(0), address(0), _id, 1000);
            }
        }
        _balances[_id][_account] += _amount;
        emit TransferSingle(address(0), _account, _id, _amount);
    }

    /// @dev Destroys `_amount` tokens of type `_id` from `_account`
    /// @param _account The address of the owner
    /// @param _id The token ID
    /// @param _amount The amount to destroy
    function _burn(
        address _account,
        uint256 _id,
        uint256 _amount
    ) internal virtual {
        if (_account == address(0)) revert LBToken__BurnFromAddress0();

        uint256 _accountBalance = _balances[_id][_account];
        if (_accountBalance < _amount)
            revert LBToken__BurnExceedsBalance(_account, _id, _amount);
        unchecked {
            _balances[_id][_account] = _accountBalance - _amount;
        }
        _totalSupplies[_id] -= _amount;

        emit TransferSingle(_account, address(0), _id, _amount);
    }

    /// @notice Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`
    /// @param _owner The address of the owner
    /// @param _operator The address of the operator
    /// @param _approved The boolean value to grant or revoke permission
    function _setApprovalForAll(
        address _owner,
        address _operator,
        bool _approved
    ) internal virtual {
        if (_owner == _operator) {
            revert LBToken__SelfApproval(_owner);
        }
        _operatorApprovals[_owner][_operator] = _approved;
        emit ApprovalForAll(_owner, _operator, _approved);
    }

    /// @notice Returns true if `operator` is approved to transfer `_account`'s tokens
    /// @param _owner The address of the owner
    /// @param _spender The address of the spender
    /// @return True if `operator` is approved to transfer `_account`'s tokens
    function _isApprovedForAll(address _owner, address _spender)
        internal
        view
        virtual
        returns (bool)
    {
        return _operatorApprovals[_owner][_spender];
    }
}
