// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

contract JLBPToken {
    mapping(uint256 => mapping(address => uint256)) private _balances;

    mapping(address => mapping(address => bool)) private _operatorApprovals;

    mapping(uint256 => uint256) internal _totalSupply;

    string public constant name = "JLBP Token";
    string public constant symbol = "JLBP";

    event TransferSingle(
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    event TransferFromSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 amount
    );

    event ApprovalForAll(
        address indexed account,
        address indexed operator,
        bool approved
    );

    function decimals() external pure virtual returns (uint8) {
        return 18;
    }

    function totalSupply(uint256 id) external view virtual returns (uint256) {
        return _totalSupply[id];
    }

    function balanceOf(address account, uint256 id)
        external
        view
        virtual
        returns (uint256)
    {
        return _balances[id][account];
    }

    function safeTransfer(
        address to,
        uint256 id,
        uint256 amount
    ) external virtual {
        address owner = msg.sender;
        _safeTransfer(owner, to, id, amount);
        emit TransferSingle(owner, to, id, amount);
    }

    function isApprovedForAll(address owner, address spender)
        external
        view
        virtual
        returns (bool)
    {
        return _isApprovedForAll(owner, spender);
    }

    function setApprovalForAll(address operator, bool approved) external {
        _setApprovalForAll(msg.sender, operator, approved);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) external virtual {
        address operator = msg.sender;
        require(
            _isApprovedForAll(from, operator),
            "JLBP: caller is not approved"
        );
        _safeTransfer(from, to, id, amount);
        emit TransferFromSingle(msg.sender, from, to, id, amount);
    }

    function _safeTransfer(
        address from,
        address to,
        uint256 id,
        uint256 amount
    ) internal {
        require(from != address(0), "JLBP: transfer from the zero address");
        require(to != address(0), "JLBP: transfer to the zero address");

        uint256 fromBalance = _balances[id][from];
        require(fromBalance >= amount, "JLBP: transfer amount exceeds balance");
        unchecked {
            _balances[id][from] = fromBalance - amount;
        }
        _balances[id][to] += amount;
    }

    function _mint(
        address account,
        uint256 id,
        uint256 amount
    ) internal {
        require(account != address(0), "JLBP: mint to the zero address");

        _totalSupply[id] += amount;
        _balances[id][account] += amount;
        emit TransferSingle(address(0), account, id, amount);
    }

    function _burn(
        address account,
        uint256 id,
        uint256 amount
    ) internal {
        require(account != address(0), "JLBP: burn from the zero address");

        uint256 accountBalance = _balances[id][account];
        require(accountBalance >= amount, "JLBP: burn amount exceeds balance");
        unchecked {
            _balances[id][account] = accountBalance - amount;
        }
        _totalSupply[id] -= amount;

        emit TransferSingle(account, address(0), id, amount);
    }

    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal {
        require(owner != operator, "JLBP: setting approval status for self");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    function _isApprovedForAll(address owner, address spender)
        internal
        view
        returns (bool)
    {
        return _operatorApprovals[owner][spender];
    }
}
