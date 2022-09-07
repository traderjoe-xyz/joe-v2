// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "./LBErrors.sol";
import "./interfaces/ILBToken.sol";
import "openzeppelin/utils/structs/EnumerableSet.sol";

/// @title Liquidity Book Token
/// @author Trader Joe
/// @notice The LBToken is an implementation of a multi-token.
/// It allows to create multi-ERC20 represented by their ids
contract LBToken is ILBToken {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @dev Mapping from token id to account balances
    mapping(uint256 => mapping(address => uint256)) private _balances;

    /// @dev Mapping from account to spender approvals
    mapping(address => mapping(address => bool)) private _spenderApprovals;

    /// @dev Mapping from token id to total supplies
    mapping(uint256 => uint256) private _totalSupplies;

    /// @dev  Mapping from account to set of ids, where user currently have a non-zero balance
    mapping(address => EnumerableSet.UintSet) private _userIds;

    string private constant _name = "Liquidity Book Token";
    string private constant _symbol = "LBT";

    /// @notice Returns the name of the token
    /// @return The name of the token
    function name() public pure virtual override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token, usually a shorter version of the name
    /// @return The symbol of the token
    function symbol() public pure virtual override returns (string memory) {
        return _symbol;
    }

    /// @notice Returns the total supply of token of type `id`
    /// @dev This is the amount of token of type `id` minted minus the amount burned
    /// @param _id The token id
    /// @return The total supply of that token id
    function totalSupply(uint256 _id) public view virtual override returns (uint256) {
        return _totalSupplies[_id];
    }

    /// @notice Returns the amount of tokens of type `id` owned by `_account`
    /// @param _account The address of the owner
    /// @param _id The token id
    /// @return The amount of tokens of type `id` owned by `_account`
    function balanceOf(address _account, uint256 _id) public view virtual override returns (uint256) {
        return _balances[_id][_account];
    }

    /// @notice Returns the type id at index `_index` where `account` has a non-zero balance
    /// @param _account The address of the account
    /// @param _index The position index
    /// @return The `account` non-zero position at index `_index`
    function userPositionAt(address _account, uint256 _index) public view virtual override returns (uint256) {
        return _userIds[_account].at(_index);
    }

    /// @notice Returns the number of non-zero balances of `account`
    /// @param _account The address of the account
    /// @return The number of non-zero balances of `account`
    function userPositionNb(address _account) public view virtual override returns (uint256) {
        return _userIds[_account].length();
    }

    /// @notice Returns true if `spender` is approved to transfer `_account`'s tokens
    /// @param _owner The address of the owner
    /// @param _spender The address of the spender
    /// @return True if `spender` is approved to transfer `_account`'s tokens
    function isApprovedForAll(address _owner, address _spender) public view virtual override returns (bool) {
        return _isApprovedForAll(_owner, _spender);
    }

    /// @notice Grants or revokes permission to `spender` to transfer the caller's tokens, according to `approved`
    /// @param _spender The address of the spender
    /// @param _approved The boolean value to grant or revoke permission
    function setApprovalForAll(address _spender, bool _approved) public virtual override {
        _setApprovalForAll(msg.sender, _spender, _approved);
    }

    /// @notice Batch transfers `_amount` tokens of type `_id` from `_from` to `_to`
    /// @param _from The address of the owner of the tokens
    /// @param _to The address of the recipient
    /// @param _ids The list of token ids
    /// @param _amounts The list of amounts to send
    function safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] memory _ids,
        uint256[] memory _amounts
    ) public virtual override {
        address _spender = msg.sender;
        if (!_isApprovedForAll(_from, _spender)) revert LBToken__SpenderNotApproved(_from, _spender);

        if (_from == address(0) || _to == address(0)) revert LBToken__TransferFromOrToAddress0();
        if (_ids.length != _amounts.length) revert LBToken__LengthMismatch(_ids.length, _amounts.length);

        for (uint256 i; i < _ids.length; ++i) {
            uint256 _id = _ids[i];
            uint256 _amount = _amounts[i];

            uint256 _fromBalance = _balances[_id][_from];
            if (_fromBalance < _amount) revert LBToken__TransferExceedsBalance(_from, _id, _amount);

            _beforeTokenTransfer(_from, _to, _id, _amount);

            unchecked {
                _balances[_id][_from] = _fromBalance - _amount;
            }

            if (_fromBalance == _amount) {
                _userIds[_from].remove(_id);
            }

            uint256 _toBalance = _balances[_id][_to];
            _balances[_id][_to] = _toBalance + _amount;

            if (_toBalance == 0) {
                _userIds[_to].add(_id);
            }
        }

        emit TransferBatch(_spender, _from, _to, _ids, _amounts);
    }

    /// @dev Creates `_amount` tokens of type `_id`, and assigns them to `_account`
    /// @param _account The address of the recipient
    /// @param _id The token id
    /// @param _amount The amount to mint
    function _mint(
        address _account,
        uint256 _id,
        uint256 _amount
    ) internal virtual {
        if (_account == address(0)) revert LBToken__MintToAddress0();

        _beforeTokenTransfer(address(0), _account, _id, _amount);

        _totalSupplies[_id] += _amount;

        uint256 _fromBalance = _balances[_id][_account];
        unchecked {
            _balances[_id][_account] = _fromBalance + _amount;
        }
        if (_fromBalance == 0) {
            _userIds[_account].add(_id);
        }

        emit TransferSingle(msg.sender, address(0), _account, _id, _amount);
    }

    /// @dev Destroys `_amount` tokens of type `_id` from `_account`
    /// @param _account The address of the owner
    /// @param _id The token id
    /// @param _amount The amount to destroy
    function _burn(
        address _account,
        uint256 _id,
        uint256 _amount
    ) internal virtual {
        if (_account == address(0)) revert LBToken__BurnFromAddress0();

        uint256 _accountBalance = _balances[_id][_account];
        if (_accountBalance < _amount) revert LBToken__BurnExceedsBalance(_account, _id, _amount);

        _beforeTokenTransfer(address(0), _account, _id, _amount);

        unchecked {
            _balances[_id][_account] = _accountBalance - _amount;
            _totalSupplies[_id] -= _amount;
        }

        if (_accountBalance == _amount) {
            _userIds[_account].remove(_id);
        }

        emit TransferSingle(msg.sender, _account, address(0), _id, _amount);
    }

    /// @notice Grants or revokes permission to `spender` to transfer the caller's tokens, according to `approved`
    /// @param _owner The address of the owner
    /// @param _spender The address of the spender
    /// @param _approved The boolean value to grant or revoke permission
    function _setApprovalForAll(
        address _owner,
        address _spender,
        bool _approved
    ) internal virtual {
        if (_owner == _spender) revert LBToken__SelfApproval(_owner);

        _spenderApprovals[_owner][_spender] = _approved;
        emit ApprovalForAll(_owner, _spender, _approved);
    }

    /// @notice Returns true if `spender` is approved to transfer `owner`'s tokens
    /// or if `sender` is the `owner`
    /// @param _owner The address of the owner
    /// @param _spender The address of the spender
    /// @return True if `spender` is approved to transfer `owner`'s tokens
    function _isApprovedForAll(address _owner, address _spender) internal view virtual returns (bool) {
        return _owner == _spender || _spenderApprovals[_owner][_spender];
    }

    /// @notice Hook that is called before any token transfer. This includes minting
    /// and burning.
    ///
    /// Calling conditions (for each `id` and `amount` pair):
    ///
    /// - When `from` and `to` are both non-zero, `amount` of ``from``'s tokens
    /// of token type `id` will be  transferred to `to`.
    /// - When `from` is zero, `amount` tokens of token type `id` will be minted
    /// for `to`.
    /// - when `to` is zero, `amount` of ``from``'s tokens of token type `id`
    /// will be burned.
    /// - `from` and `to` are never both zero.
    /// @param from The address of the owner of the token
    /// @param to The address of the recipient of the  token
    /// @param id The id of the token
    /// @param amount The amount of token of type `id`
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) internal virtual {}
}
