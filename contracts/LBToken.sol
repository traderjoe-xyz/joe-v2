// SPDX-License-identifier: MIT

pragma solidity 0.8.9;

import "./interfaces/ILBToken.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

error LBToken__SpenderNotApproved(address owner, address spender);
error LBToken__TransferFromOrToAddress0();
error LBToken__MintToAddress0();
error LBToken__MintTooLow(uint256 amount);
error LBToken__BurnFromAddress0();
error LBToken__BurnExceedsBalance(address from, uint256 id, uint256 amount);
error LBToken__LengthMismatch(uint256 accountsLength, uint256 idsLength);
error LBToken__SelfApproval(address owner);
error LBToken__TransferExceedsBalance(address from, uint256 id, uint256 amount);

/// @title Joe Liquidity Bin Provider Token
/// @author Trader Joe
/// @notice The LBToken is an implementation of a multi-token.
/// It allows to create multi-ERC20 represented by their ids.
contract LBToken is ILBToken, ERC165 {
    // Mapping from token id to account balances
    mapping(uint256 => mapping(address => uint256)) private _balances;

    // Mapping from account to spender approvals
    mapping(address => mapping(address => bool)) private _spenderApprovals;

    // Mapping from token id to total supplies
    mapping(uint256 => uint256) private _totalSupplies;

    string private _name;
    string private _symbol;

    event Transfer();

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /// @notice Wether this contract implements the interface defined by `_interfaceId`.
    /// @param _interfaceId The interfaceId as a bytes4
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override(ERC165, IERC165)
        returns (bool)
    {
        return
            _interfaceId == type(ILBToken).interfaceId ||
            super.supportsInterface(_interfaceId);
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
    /// @param _id The token id
    /// @return The total supply of that token id
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
    /// @param _id The token id
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

    /// @notice Returns the list of balance of token of each (account, id) pair
    /// @param _accounts The list of address of the owners
    /// @param _ids The list of token ids
    /// @return batchBalances The list of balance of token of each (account, id) pair
    function balanceOfBatch(address[] memory _accounts, uint256[] memory _ids)
        public
        view
        virtual
        override
        returns (uint256[] memory batchBalances)
    {
        uint256 _len = _accounts.length;
        if (_len != _ids.length)
            revert LBToken__LengthMismatch(_len, _ids.length);

        batchBalances = new uint256[](_len);
        for (uint256 i; i < _len; ++i) {
            batchBalances[i] = balanceOf(_accounts[i], _ids[i]);
        }
    }

    /// @notice Returns true if `spender` is approved to transfer `_account`'s tokens
    /// @param _owner The address of the owner
    /// @param _spender The address of the spender
    /// @return True if `spender` is approved to transfer `_account`'s tokens
    function isApprovedForAll(address _owner, address _spender)
        public
        view
        virtual
        override
        returns (bool)
    {
        return _isApprovedForAll(_owner, _spender);
    }

    /// @notice Grants or revokes permission to `spender` to transfer the caller's tokens, according to `approved`
    /// @param _spender The address of the spender
    /// @param _approved The boolean value to grant or revoke permission
    function setApprovalForAll(address _spender, bool _approved)
        public
        virtual
        override
    {
        _setApprovalForAll(msg.sender, _spender, _approved);
    }

    /// @notice Transfers `_amount` tokens of type `_id` from `_from` to `_to`
    /// @param _from The address of the owner of the tokens
    /// @param _to The address of the recipient
    /// @param _id The token id
    /// @param _amount The amount to send
    function safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount
    ) public virtual override {
        address _spender = msg.sender;
        if (_isApprovedForAll(_from, _spender))
            revert LBToken__SpenderNotApproved(_from, _spender);
        _safeTransferFrom(_from, _to, _id, _amount);
        emit TransferSingle(_spender, _from, _to, _id, _amount);
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
        if (_isApprovedForAll(_from, _spender))
            revert LBToken__SpenderNotApproved(_from, _spender);
        _safeBatchTransferFrom(_from, _to, _ids, _amounts);
        emit TransferBatch(_spender, _from, _to, _ids, _amounts);
    }

    /// @dev Transfers `_amount` tokens of type `_id` from `_from` to `_to`
    /// @param _from The address of the owner of the tokens
    /// @param _to The address of the recipient
    /// @param _id The token id
    /// @param _amount The amount to send
    function _safeTransferFrom(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount
    ) internal virtual {
        if (_from == address(0) || _to == address(0))
            revert LBToken__TransferFromOrToAddress0();
        _safeTransferHelper(_from, _to, _id, _amount);
    }

    function _safeBatchTransferFrom(
        address _from,
        address _to,
        uint256[] memory _ids,
        uint256[] memory _amounts
    ) internal virtual {
        if (_from == address(0) || _to == address(0))
            revert LBToken__TransferFromOrToAddress0();
        uint256 _len = _ids.length;
        if (_len != _amounts.length)
            revert LBToken__LengthMismatch(_len, _amounts.length);

        for (uint256 i; i < _len; ++i) {
            uint256 _id = _ids[i];
            uint256 _amount = _amounts[i];

            _safeTransferHelper(_from, _to, _id, _amount);
        }
    }

    function _safeTransferHelper(
        address _from,
        address _to,
        uint256 _id,
        uint256 _amount
    ) private {
        uint256 _fromBalance = _balances[_id][_from];
        if (_fromBalance < _amount)
            revert LBToken__TransferExceedsBalance(_from, _id, _amount);

        _beforeTokenTransfer(_from, _to, _id, _amount);

        unchecked {
            _balances[_id][_from] = _fromBalance - _amount;
        }
        _balances[_id][_to] += _amount;
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
        unchecked {
            _balances[_id][_account] += _amount;
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
        if (_accountBalance < _amount)
            revert LBToken__BurnExceedsBalance(_account, _id, _amount);

        _beforeTokenTransfer(address(0), _account, _id, _amount);

        unchecked {
            _balances[_id][_account] = _accountBalance - _amount;
            _totalSupplies[_id] -= _amount;
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
        if (_owner == _spender) {
            revert LBToken__SelfApproval(_owner);
        }
        _spenderApprovals[_owner][_spender] = _approved;
        emit ApprovalForAll(_owner, _spender, _approved);
    }

    /// @notice Returns true if `spender` is approved to transfer `owner`'s tokens
    /// or if `sender` is the `owner`
    /// @param _owner The address of the owner
    /// @param _spender The address of the spender
    /// @return True if `spender` is approved to transfer `owner`'s tokens
    function _isApprovedForAll(address _owner, address _spender)
        internal
        view
        virtual
        returns (bool)
    {
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
