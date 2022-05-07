// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./interfaces/IJLBPToken.sol";

contract JLBPToken is IJLBPToken {
    // Mapping from token ID to account balances
    mapping(uint256 => mapping(address => uint256)) private _balances;

    // Mapping from account to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Mapping from token ID to total supplies
    mapping(uint256 => uint256) internal _totalSupplies;

    string public constant name = "JLBP Token";
    string public constant symbol = "JLBP";

    /// @notice Returns the number of decimals used to get its user representation
    /// @return The number of decimals as uint8
    function decimals() external pure virtual returns (uint8) {
        return 18;
    }

    /// @notice Returns the number of decimals used to get its user representation
    /// @param id The token ID
    /// @return The total supply of that token ID
    function totalSupply(uint256 id)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _totalSupplies[id];
    }

    /// @notice Returns the amount of tokens of type `id` owned by `account`
    /// @param account The address of the owner
    /// @param id The token ID
    /// @return The amount of tokens of type `id` owned by `account`
    function balanceOf(address account, uint256 id)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[id][account];
    }

    /// @notice Transfers `amount` tokens of type `id` from `msg.sender` to `to`
    /// @param to The address of the recipient
    /// @param id The token ID
    /// @param amount The amount to send
    function safeTransfer(
        address to,
        uint256 id,
        uint256 amount
    ) external virtual override {
        address owner = msg.sender;
        _safeTransfer(owner, to, id, amount);
        emit TransferSingle(owner, to, id, amount);
    }

    /// @notice Returns true if `operator` is approved to transfer `account`'s tokens
    /// @param owner The address of the owner
    /// @param spender The address of the spender
    /// @return True if `operator` is approved to transfer `account`'s tokens
    function isApprovedForAll(address owner, address spender)
        external
        view
        virtual
        override
        returns (bool)
    {
        return _isApprovedForAll(owner, spender);
    }

    /// @notice Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`
    /// @param operator The address of the operator
    /// @param approved The boolean value to grant or revoke permission
    function setApprovalForAll(address operator, bool approved)
        external
        virtual
        override
    {
        _setApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Transfers `amount` tokens of type `id` from `from` to `to`
    /// @param from The address of the owner of the tokens
    /// @param to The address of the recipient
    /// @param id The token ID
    /// @param amount The amount to send
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) external virtual override {
        address operator = msg.sender;
        require(
            _isApprovedForAll(from, operator),
            "JLBP: caller is not approved"
        );
        _safeTransfer(from, to, id, amount);
        emit TransferFromSingle(msg.sender, from, to, id, amount);
    }

    /// @dev Transfers `amount` tokens of type `id` from `from` to `to`
    /// @param from The address of the owner of the tokens
    /// @param to The address of the recipient
    /// @param id The token ID
    /// @param amount The amount to send
    function _safeTransfer(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "JLBP: transfer from the zero address");
        require(to != address(0), "JLBP: transfer to the zero address");

        uint256 fromBalance = _balances[id][from];
        require(fromBalance >= amount, "JLBP: transfer amount exceeds balance");
        unchecked {
            _balances[id][from] = fromBalance - amount;
        }
        _balances[id][to] += amount;
    }

    /// @dev Creates `amount` tokens of type `id`, and assigns them to `account`
    /// @param account The address of the recipient
    /// @param id The token ID
    /// @param amount The amount to create
    function _mint(
        address account,
        uint256 id,
        uint256 amount
    ) internal virtual {
        require(account != address(0), "JLBP: mint to the zero address");

        _totalSupplies[id] += amount;
        _balances[id][account] += amount;
        emit TransferSingle(address(0), account, id, amount);
    }

    /// @dev Destroys `amount` tokens of type `id` from `account`
    /// @param account The address of the owner
    /// @param id The token ID
    /// @param amount The amount to destroy
    function _burn(
        address account,
        uint256 id,
        uint256 amount
    ) internal virtual {
        require(account != address(0), "JLBP: burn from the zero address");

        uint256 accountBalance = _balances[id][account];
        require(accountBalance >= amount, "JLBP: burn amount exceeds balance");
        unchecked {
            _balances[id][account] = accountBalance - amount;
        }
        _totalSupplies[id] -= amount;

        emit TransferSingle(account, address(0), id, amount);
    }

    /// @notice Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`
    /// @param operator The address of the operator
    /// @param approved The boolean value to grant or revoke permission
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "JLBP: setting approval status for self");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /// @notice Returns true if `operator` is approved to transfer `account`'s tokens
    /// @param owner The address of the owner
    /// @param spender The address of the spender
    /// @return True if `operator` is approved to transfer `account`'s tokens
    function _isApprovedForAll(address owner, address spender)
        internal
        view
        virtual
        returns (bool)
    {
        return _operatorApprovals[owner][spender];
    }
}
