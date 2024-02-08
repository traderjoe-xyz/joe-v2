// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "../../src/LBBaseHooks.sol";

contract MockHooks is LBBaseHooks {
    bytes public beforeData;
    bytes public afterData;

    address public pair;

    function setPair(address _pair) public virtual {
        pair = _pair;
    }

    function reset() public virtual {
        delete beforeData;
        delete afterData;
    }

    function _getLBPair() internal view virtual override returns (ILBPair) {
        if (pair != address(0)) return ILBPair(pair);

        return super._getLBPair();
    }

    function _onHooksSet(bytes32, bytes calldata) internal virtual override {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        beforeData = msg.data[0:offset];
    }

    function _beforeSwap(address, address, bool, bytes32) internal virtual override {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        beforeData = msg.data[0:offset];
    }

    function _afterSwap(address, address, bool, bytes32) internal virtual override {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        afterData = msg.data[0:offset];
    }

    function _beforeFlashLoan(address, address, bytes32) internal virtual override {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        beforeData = msg.data[0:offset];
    }

    function _afterFlashLoan(address, address, bytes32, bytes32) internal virtual override {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        afterData = msg.data[0:offset];
    }

    function _beforeMint(address, address, bytes32[] calldata, bytes32) internal virtual override {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        beforeData = msg.data[0:offset];
    }

    function _afterMint(address, address, bytes32[] calldata, bytes32) internal virtual override {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        afterData = msg.data[0:offset];
    }

    function _beforeBurn(address, address, address, uint256[] calldata, uint256[] calldata) internal virtual override {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        beforeData = msg.data[0:offset];
    }

    function _afterBurn(address, address, address, uint256[] calldata, uint256[] calldata) internal virtual override {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        afterData = msg.data[0:offset];
    }

    function _beforeBatchTransferFrom(address, address, address, uint256[] calldata, uint256[] calldata)
        internal
        virtual
        override
    {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        beforeData = msg.data[0:offset];
    }

    function _afterBatchTransferFrom(address, address, address, uint256[] calldata, uint256[] calldata)
        internal
        virtual
        override
    {
        uint256 offset = pair == address(0) ? _getImmutableArgsOffset() : msg.data.length;
        afterData = msg.data[0:offset];
    }
}
