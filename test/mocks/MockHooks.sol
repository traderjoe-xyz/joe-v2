// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "../../src/LBBaseHooks.sol";

contract MockHooks is LBBaseHooks {
    bytes public beforeData;
    bytes public afterData;

    address public pair;

    function setPair(address _pair) public {
        pair = _pair;
    }

    function reset() public {
        delete beforeData;
        delete afterData;
    }

    function _getLBPair() internal view override returns (ILBPair) {
        if (pair != address(0)) return ILBPair(pair);

        return super._getLBPair();
    }

    function _onHooksSet(bytes32) internal override {
        beforeData = msg.data;
    }

    function _beforeSwap(address, address, bool, bytes32) internal override {
        beforeData = msg.data;
    }

    function _afterSwap(address, address, bool, bytes32) internal override {
        afterData = msg.data;
    }

    function _beforeFlashLoan(address, address, bytes32) internal override {
        beforeData = msg.data;
    }

    function _afterFlashLoan(address, address, bytes32) internal override {
        afterData = msg.data;
    }

    function _beforeMint(address, address, bytes32[] calldata, bytes32) internal override {
        beforeData = msg.data;
    }

    function _afterMint(address, address, bytes32[] calldata, bytes32) internal override {
        afterData = msg.data;
    }

    function _beforeBurn(address, address, address, uint256[] calldata, uint256[] calldata) internal override {
        beforeData = msg.data;
    }

    function _afterBurn(address, address, address, uint256[] calldata, uint256[] calldata) internal override {
        afterData = msg.data;
    }

    function _beforeBatchTransferFrom(address, address, address, uint256[] calldata, uint256[] calldata)
        internal
        override
    {
        beforeData = msg.data;
    }

    function _afterBatchTransferFrom(address, address, address, uint256[] calldata, uint256[] calldata)
        internal
        override
    {
        afterData = msg.data;
    }
}
