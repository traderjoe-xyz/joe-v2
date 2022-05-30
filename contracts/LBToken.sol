// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./interfaces/ILBToken.sol";

error LBToken__OperatorNotApproved(address from, address operator);
error LBToken__TransferFromOrToAddress0();
error LBToken__MintToAddress0();
error LBToken__MintTooLow(uint256 amount);
error LBToken__BurnFromAddress0();
error LBToken__BurnExceedsBalance(address from, int24 id, uint256 amount);
error LBToken__SelfApproval(address owner);
error LBToken__WrongId();
error LBToken__TransferExceedsBalance(address from, int24 id, uint256 amount);

/// @title Joe Liquidity Bin Provider Token
/// @author Trader Joe
/// @notice The LBToken is an implementation of a multi-token.
/// It allows to create multi-ERC20 represented by their IDs.
contract LBToken is ILBToken {
    // Mapping from token ID to account balances
    mapping(uint24 => mapping(address => uint256)) internal _balances;

    // Mapping from account to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    // Mapping from token ID to total supplies
    mapping(uint24 => uint256) internal _totalSupplies;

    string public constant name = "JLB Token";
    string public constant symbol = "JLB";

    uint24 private constant HALF_MAX_NUM_BINS = type(uint24).max / 2 + 1;

    /// @notice Returns the number of decimals used to get its user representation
    /// @return The number of decimals as uint8
    function decimals() external view virtual returns (uint8) {
        return 18;
    }

    /// @notice Returns the number of decimals used to get its user representation
    /// @param id The token ID
    /// @return The total supply of that token ID
    function totalSupply(int24 id)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _totalSupplies[_getInternalId(id)];
    }

    /// @notice Returns the amount of tokens of type `id` owned by `account`
    /// @param account The address of the owner
    /// @param id The token ID
    /// @return The amount of tokens of type `id` owned by `account`
    function balanceOf(address account, int24 id)
        external
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[_getInternalId(id)][account];
    }

    /// @notice Transfers `amount` tokens of type `id` from `msg.sender` to `to`
    /// @param to The address of the recipient
    /// @param id The token ID
    /// @param amount The amount to send
    function safeTransfer(
        address to,
        int24 id,
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
        int24 id,
        uint256 amount
    ) external virtual override {
        address operator = msg.sender;
        if (_isApprovedForAll(from, operator))
            revert LBToken__OperatorNotApproved(from, operator);
        _safeTransfer(from, to, id, amount);
        emit TransferFromSingle(msg.sender, from, to, id, amount);
    }

    /// @notice Returns the internal `id`, i.e., the natural one
    /// @param _id The public id
    /// @return The internal id
    function _getInternalId(int24 _id) internal pure returns (uint24) {
        if (_id < 0) {
            return HALF_MAX_NUM_BINS + uint24(-_id);
        }
        return HALF_MAX_NUM_BINS + uint24(_id);
    }

    /// @notice Returns the public `id`, i.e., the integer one
    /// @param _id The internal id
    /// @return The public id
    function _getPublicId(uint24 _id) internal pure returns (int24) {
        return int24(_id) - int24(HALF_MAX_NUM_BINS);
    }

    /// @dev Transfers `amount` tokens of type `id` from `from` to `to`
    /// @param from The address of the owner of the tokens
    /// @param to The address of the recipient
    /// @param id The token ID
    /// @param amount The amount to send
    function _safeTransfer(
        address from,
        address to,
        int24 id,
        uint256 amount
    ) internal virtual {
        if (from == address(0) || to == address(0))
            revert LBToken__TransferFromOrToAddress0();

        uint24 _id = _getInternalId(id);

        uint256 fromBalance = _balances[_id][from];
        if (fromBalance < amount)
            revert LBToken__TransferExceedsBalance(from, id, amount);
        unchecked {
            _balances[_id][from] = fromBalance - amount;
        }
        _balances[_id][to] += amount;
    }

    /// @dev Creates `amount` tokens of type `id`, and assigns them to `account`
    /// @param account The address of the recipient
    /// @param id The token ID
    /// @param amount The amount to create
    function _mint(
        address account,
        uint24 id,
        uint256 amount
    ) internal virtual {
        if (account == address(0)) revert LBToken__MintToAddress0();

        uint256 _totalSupply = _totalSupplies[id];
        _totalSupplies[id] = _totalSupply + amount;
        if (_totalSupply == 0) {
            if (amount < 10_000) revert LBToken__MintTooLow(amount); // Do we check that ? or only > 1000 ?
            unchecked {
                amount -= 1000;
                _balances[id][address(0)] = 1000;
                emit TransferSingle(
                    address(0),
                    address(0),
                    _getPublicId(id),
                    1000
                );
            }
        }
        _balances[id][account] += amount;
        emit TransferSingle(address(0), account, _getPublicId(id), amount);
    }

    /// @dev Destroys `amount` tokens of type `id` from `account`
    /// @param account The address of the owner
    /// @param id The token ID
    /// @param amount The amount to destroy
    function _burn(
        address account,
        uint24 id,
        uint256 amount
    ) internal virtual {
        if (account == address(0)) revert LBToken__BurnFromAddress0();

        uint256 accountBalance = _balances[id][account];
        if (accountBalance < amount)
            revert LBToken__BurnExceedsBalance(
                account,
                _getPublicId(id),
                amount
            );
        unchecked {
            _balances[id][account] = accountBalance - amount;
        }
        _totalSupplies[id] -= amount;

        emit TransferSingle(account, address(0), _getPublicId(id), amount);
    }

    /// @notice Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`
    /// @param operator The address of the operator
    /// @param approved The boolean value to grant or revoke permission
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        if (owner == operator) {
            revert LBToken__SelfApproval(owner);
        }
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
