// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "../src/libraries/Hooks.sol";
import "../src/interfaces/ILBHooks.sol";

import "./mocks/MockHooks.sol";

contract HooksTest is Test {
    error HooksTest__CustomRevert();

    uint256 fallbackType;

    MockHooks public hooks;
    MockHooksCaller public hooksCaller;
    bytes32 hooksParameters;

    function setUp() public {
        hooks = new MockHooks();
        hooksCaller = new MockHooksCaller();

        vm.label(address(hooks), "hooks");
        vm.label(address(hooksCaller), "hooksCaller");
    }

    function test_EncodeHooks(Hooks.Parameters memory parameters) public {
        hooksParameters = Hooks.encode(parameters);

        assertEq(parameters.hooks, Hooks.decode(hooksParameters).hooks, "test_EncodeHooks::1");
        assertEq(parameters.beforeSwap, Hooks.decode(hooksParameters).beforeSwap, "test_EncodeHooks::2");
        assertEq(parameters.afterSwap, Hooks.decode(hooksParameters).afterSwap, "test_EncodeHooks::3");
        assertEq(parameters.beforeFlashLoan, Hooks.decode(hooksParameters).beforeFlashLoan, "test_EncodeHooks::4");
        assertEq(parameters.afterFlashLoan, Hooks.decode(hooksParameters).afterFlashLoan, "test_EncodeHooks::5");
        assertEq(parameters.beforeMint, Hooks.decode(hooksParameters).beforeMint, "test_EncodeHooks::6");
        assertEq(parameters.afterMint, Hooks.decode(hooksParameters).afterMint, "test_EncodeHooks::7");
        assertEq(parameters.beforeBurn, Hooks.decode(hooksParameters).beforeBurn, "test_EncodeHooks::8");
        assertEq(parameters.afterBurn, Hooks.decode(hooksParameters).afterBurn, "test_EncodeHooks::9");
        assertEq(
            parameters.beforeBatchTransferFrom,
            Hooks.decode(hooksParameters).beforeBatchTransferFrom,
            "test_EncodeHooks::10"
        );
        assertEq(
            parameters.afterBatchTransferFrom,
            Hooks.decode(hooksParameters).afterBatchTransferFrom,
            "test_EncodeHooks::11"
        );
        assertEq(parameters.hooks, Hooks.getHooks(hooksParameters), "test_EncodeHooks::12");
        assertEq(
            hooksParameters & ~bytes32(uint256(type(uint160).max)),
            Hooks.getFlags(hooksParameters),
            "test_EncodeHooks::13"
        );

        bytes32 expectedFlags = 0;
        if (parameters.beforeSwap) expectedFlags |= Hooks.BEFORE_SWAP_FLAG;
        if (parameters.afterSwap) expectedFlags |= Hooks.AFTER_SWAP_FLAG;
        if (parameters.beforeFlashLoan) expectedFlags |= Hooks.BEFORE_FLASH_LOAN_FLAG;
        if (parameters.afterFlashLoan) expectedFlags |= Hooks.AFTER_FLASH_LOAN_FLAG;
        if (parameters.beforeMint) expectedFlags |= Hooks.BEFORE_MINT_FLAG;
        if (parameters.afterMint) expectedFlags |= Hooks.AFTER_MINT_FLAG;
        if (parameters.beforeBurn) expectedFlags |= Hooks.BEFORE_BURN_FLAG;
        if (parameters.afterBurn) expectedFlags |= Hooks.AFTER_BURN_FLAG;
        if (parameters.beforeBatchTransferFrom) expectedFlags |= Hooks.BEFORE_TRANSFER_FLAG;
        if (parameters.afterBatchTransferFrom) expectedFlags |= Hooks.AFTER_TRANSFER_FLAG;

        assertEq(bytes32(expectedFlags), Hooks.getFlags(hooksParameters), "test_EncodeHooks::14");
    }

    function test_CallHooks(
        Hooks.Parameters memory parameters,
        address account,
        bytes32[] calldata liquidityConfigs,
        uint256[] calldata ids,
        bytes calldata data
    ) public {
        hooks.setPair(address(this));

        bytes32 oldHooksParameters = Hooks.encode(parameters);

        parameters.hooks = address(hooks);

        hooksParameters = Hooks.encode(parameters);

        assertEq(Hooks.setHooks(oldHooksParameters, address(hooks)), hooksParameters, "test_CallHooks::1");

        hooks.reset();
        Hooks.onHooksSet(hooksParameters, data);

        assertEq(
            keccak256(hooks.beforeData()),
            keccak256(abi.encodeWithSelector(ILBHooks.onHooksSet.selector, hooksParameters, data)),
            "test_CallHooks::2"
        );

        hooks.reset();
        Hooks.beforeSwap(hooksParameters, account, account, false, bytes32(0));

        if (parameters.beforeSwap) {
            assertEq(
                keccak256(hooks.beforeData()),
                keccak256(abi.encodeWithSelector(ILBHooks.beforeSwap.selector, account, account, false, bytes32(0))),
                "test_CallHooks::3"
            );
        } else {
            assertEq(hooks.beforeData().length, 0, "test_CallHooks::4");
        }

        hooks.reset();
        Hooks.afterSwap(hooksParameters, account, account, false, bytes32(0));

        if (parameters.afterSwap) {
            assertEq(
                keccak256(hooks.afterData()),
                keccak256(abi.encodeWithSelector(ILBHooks.afterSwap.selector, account, account, false, bytes32(0))),
                "test_CallHooks::5"
            );
        } else {
            assertEq(hooks.afterData().length, 0, "test_CallHooks::6");
        }

        hooks.reset();
        Hooks.beforeFlashLoan(hooksParameters, account, account, bytes32(0));

        if (parameters.beforeFlashLoan) {
            assertEq(
                keccak256(hooks.beforeData()),
                keccak256(abi.encodeWithSelector(ILBHooks.beforeFlashLoan.selector, account, account, bytes32(0))),
                "test_CallHooks::7"
            );
        } else {
            assertEq(hooks.beforeData().length, 0, "test_CallHooks::8");
        }

        hooks.reset();
        Hooks.afterFlashLoan(hooksParameters, account, account, bytes32(0), bytes32(0));

        if (parameters.afterFlashLoan) {
            assertEq(
                keccak256(hooks.afterData()),
                keccak256(
                    abi.encodeWithSelector(ILBHooks.afterFlashLoan.selector, account, account, bytes32(0), bytes32(0))
                ),
                "test_CallHooks::9"
            );
        } else {
            assertEq(hooks.afterData().length, 0, "test_CallHooks::10");
        }

        hooks.reset();
        Hooks.beforeMint(hooksParameters, account, account, liquidityConfigs, bytes32(0));

        if (parameters.beforeMint) {
            assertEq(
                keccak256(hooks.beforeData()),
                keccak256(
                    abi.encodeWithSelector(ILBHooks.beforeMint.selector, account, account, liquidityConfigs, bytes32(0))
                ),
                "test_CallHooks::11"
            );
        } else {
            assertEq(hooks.beforeData().length, 0, "test_CallHooks::12");
        }

        hooks.reset();
        Hooks.afterMint(hooksParameters, account, account, liquidityConfigs, bytes32(0));

        if (parameters.afterMint) {
            assertEq(
                keccak256(hooks.afterData()),
                keccak256(
                    abi.encodeWithSelector(ILBHooks.afterMint.selector, account, account, liquidityConfigs, bytes32(0))
                ),
                "test_CallHooks::13"
            );
        } else {
            assertEq(hooks.afterData().length, 0, "test_CallHooks::14");
        }

        hooks.reset();
        Hooks.beforeBurn(hooksParameters, account, account, account, ids, ids);

        if (parameters.beforeBurn) {
            assertEq(
                keccak256(hooks.beforeData()),
                keccak256(abi.encodeWithSelector(ILBHooks.beforeBurn.selector, account, account, account, ids, ids)),
                "test_CallHooks::15"
            );
        } else {
            assertEq(hooks.beforeData().length, 0, "test_CallHooks::16");
        }

        hooks.reset();
        Hooks.afterBurn(hooksParameters, account, account, account, ids, ids);

        if (parameters.afterBurn) {
            assertEq(
                keccak256(hooks.afterData()),
                keccak256(abi.encodeWithSelector(ILBHooks.afterBurn.selector, account, account, account, ids, ids)),
                "test_CallHooks::17"
            );
        } else {
            assertEq(hooks.afterData().length, 0, "test_CallHooks::18");
        }

        hooks.reset();
        Hooks.beforeBatchTransferFrom(hooksParameters, account, account, account, ids, ids);

        if (parameters.beforeBatchTransferFrom) {
            assertEq(
                keccak256(hooks.beforeData()),
                keccak256(
                    abi.encodeWithSelector(
                        ILBHooks.beforeBatchTransferFrom.selector, account, account, account, ids, ids
                    )
                ),
                "test_CallHooks::19"
            );
        } else {
            assertEq(hooks.beforeData().length, 0, "test_CallHooks::20");
        }

        hooks.reset();
        Hooks.afterBatchTransferFrom(hooksParameters, account, account, account, ids, ids);

        if (parameters.afterBatchTransferFrom) {
            assertEq(
                keccak256(hooks.afterData()),
                keccak256(
                    abi.encodeWithSelector(
                        ILBHooks.afterBatchTransferFrom.selector, account, account, account, ids, ids
                    )
                ),
                "test_CallHooks::21"
            );
        } else {
            assertEq(hooks.afterData().length, 0, "test_CallHooks::22");
        }
    }

    function test_Revert_CallFailed() public {
        bytes32 parameters = Hooks.encode(
            Hooks.Parameters({
                hooks: address(this),
                beforeSwap: true,
                afterSwap: true,
                beforeFlashLoan: true,
                afterFlashLoan: true,
                beforeMint: true,
                afterMint: true,
                beforeBurn: true,
                afterBurn: true,
                beforeBatchTransferFrom: true,
                afterBatchTransferFrom: true
            })
        );

        hooksCaller.setHooksParameters(parameters);

        for (uint256 rev = 0; rev <= 4; rev++) {
            fallbackType = rev;

            bytes memory expectedRevertData = rev <= 2
                ? abi.encodeWithSelector(Hooks.Hooks__CallFailed.selector)
                : rev == 3
                    ? abi.encodePacked("HooksTest::fallback")
                    : abi.encodeWithSelector(HooksTest__CustomRevert.selector);

            vm.expectRevert(expectedRevertData);
            hooksCaller.onHooksSet(bytes32(0), new bytes(0));

            vm.expectRevert(expectedRevertData);
            hooksCaller.beforeSwap(address(0), address(0), false, bytes32(0));

            vm.expectRevert(expectedRevertData);
            hooksCaller.afterSwap(address(0), address(0), false, bytes32(0));

            vm.expectRevert(expectedRevertData);
            hooksCaller.beforeFlashLoan(address(0), address(0), bytes32(0));

            vm.expectRevert(expectedRevertData);
            hooksCaller.afterFlashLoan(address(0), address(0), bytes32(0), bytes32(0));

            vm.expectRevert(expectedRevertData);
            hooksCaller.beforeMint(address(0), address(0), new bytes32[](0), bytes32(0));

            vm.expectRevert(expectedRevertData);
            hooksCaller.afterMint(address(0), address(0), new bytes32[](0), bytes32(0));

            vm.expectRevert(expectedRevertData);
            hooksCaller.beforeBurn(address(0), address(0), address(0), new uint256[](0), new uint256[](0));

            vm.expectRevert(expectedRevertData);
            hooksCaller.afterBurn(address(0), address(0), address(0), new uint256[](0), new uint256[](0));

            vm.expectRevert(expectedRevertData);
            hooksCaller.beforeBatchTransferFrom(address(0), address(0), address(0), new uint256[](0), new uint256[](0));

            vm.expectRevert(expectedRevertData);
            hooksCaller.afterBatchTransferFrom(address(0), address(0), address(0), new uint256[](0), new uint256[](0));
        }
    }

    function getLBHooksParameters() external view returns (bytes32) {
        return hooksParameters;
    }

    fallback() external {
        if (fallbackType == 1) revert();
        if (fallbackType == 2) {
            assembly {
                mstore(0, 0x1234567890abcdef)
                return(0, 0x20)
            }
        }
        if (fallbackType == 3) revert("HooksTest::fallback");
        if (fallbackType == 4) revert HooksTest__CustomRevert();
    }
}

contract MockHooksCaller {
    bytes32 public hooksParameters;

    function setHooksParameters(bytes32 _hooksParameters) public {
        hooksParameters = _hooksParameters;
    }

    function onHooksSet(bytes32, bytes calldata data) public {
        Hooks.onHooksSet(hooksParameters, data);
    }

    function beforeSwap(address sender, address to, bool swapForY, bytes32 amountsIn) public {
        Hooks.beforeSwap(hooksParameters, sender, to, swapForY, amountsIn);
    }

    function afterSwap(address sender, address to, bool swapForY, bytes32 amountsOut) public {
        Hooks.afterSwap(hooksParameters, sender, to, swapForY, amountsOut);
    }

    function beforeFlashLoan(address sender, address to, bytes32 amounts) public {
        Hooks.beforeFlashLoan(hooksParameters, sender, to, amounts);
    }

    function afterFlashLoan(address sender, address to, bytes32 fees, bytes32 feesReceived) public {
        Hooks.afterFlashLoan(hooksParameters, sender, to, fees, feesReceived);
    }

    function beforeMint(address sender, address to, bytes32[] calldata liquidityConfigs, bytes32 amountsReceived)
        public
    {
        Hooks.beforeMint(hooksParameters, sender, to, liquidityConfigs, amountsReceived);
    }

    function afterMint(address sender, address to, bytes32[] calldata liquidityConfigs, bytes32 amountsReceived)
        public
    {
        Hooks.afterMint(hooksParameters, sender, to, liquidityConfigs, amountsReceived);
    }

    function beforeBurn(address sender, address from, address to, uint256[] calldata ids, uint256[] calldata amounts)
        public
    {
        Hooks.beforeBurn(hooksParameters, sender, from, to, ids, amounts);
    }

    function afterBurn(address sender, address from, address to, uint256[] calldata ids, uint256[] calldata amounts)
        public
    {
        Hooks.afterBurn(hooksParameters, sender, from, to, ids, amounts);
    }

    function beforeBatchTransferFrom(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) public {
        Hooks.beforeBatchTransferFrom(hooksParameters, sender, from, to, ids, amounts);
    }

    function afterBatchTransferFrom(
        address sender,
        address from,
        address,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) public {
        Hooks.afterBatchTransferFrom(hooksParameters, sender, from, address(0), ids, amounts);
    }
}
