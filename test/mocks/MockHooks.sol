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
        return ILBPair(pair);
    }

    function _onHooksSet(bytes32, bytes calldata) internal virtual override {
        beforeData = msg.data;
    }

    function _beforeSwap(address, address, bool, bytes32) internal virtual override {
        beforeData = msg.data;
    }

    function _afterSwap(address, address, bool, bytes32) internal virtual override {
        afterData = msg.data;
    }

    function _beforeFlashLoan(address, address, bytes32) internal virtual override {
        beforeData = msg.data;
    }

    function _afterFlashLoan(address, address, bytes32, bytes32) internal virtual override {
        afterData = msg.data;
    }

    function _beforeMint(address, address, bytes32[] calldata, bytes32) internal virtual override {
        beforeData = msg.data;
    }

    function _afterMint(address, address, bytes32[] calldata, bytes32) internal virtual override {
        afterData = msg.data;
    }

    function _beforeBurn(address, address, address, uint256[] calldata, uint256[] calldata) internal virtual override {
        beforeData = msg.data;
    }

    function _afterBurn(address, address, address, uint256[] calldata, uint256[] calldata) internal virtual override {
        afterData = msg.data;
    }

    function _beforeBatchTransferFrom(address, address, address, uint256[] calldata, uint256[] calldata)
        internal
        virtual
        override
    {
        beforeData = msg.data;
    }

    function _afterBatchTransferFrom(address, address, address, uint256[] calldata, uint256[] calldata)
        internal
        virtual
        override
    {
        afterData = msg.data;
    }
}
