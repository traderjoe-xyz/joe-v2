// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";

import "./helpers/TestHelper.sol";
import "./mocks/MockHooks.sol";

struct VolatilityParameters {
    uint24 volatilityAccumulator;
    uint24 volatilityReference;
    uint24 idReference;
    uint40 timeOfLastUpdate;
}

struct OracleParameters {
    uint8 sampleLifetime;
    uint16 size;
    uint16 activeSize;
    uint40 lastUpdated;
    uint40 firstTimestamp;
}

struct State {
    uint128 reserveX;
    uint128 reserveY;
    uint128 protocolFeeX;
    uint128 protocolFeeY;
    uint24 activeId;
    uint128 activeReserveX;
    uint128 activeReserveY;
    VolatilityParameters volatilityParameters;
    OracleParameters oracleParameters;
}

contract LBPairHooksTest is TestHelper {
    using SafeCast for uint256;

    MockLBHooks hooks;

    uint128 constant amount = 0.1e18;

    function setUp() public override {
        super.setUp();

        pairWnative = createLBPair(wnative, usdc);

        addLiquidity(DEV, DEV, pairWnative, ID_ONE, 1e18, 1e18, 50, 50);

        hooks = new MockLBHooks();
        hooks.setPair(address(pairWnative));

        factory.grantRole(factory.LB_HOOKS_MANAGER_ROLE(), address(this));

        Hooks.Parameters memory parameters = Hooks.Parameters({
            hooks: address(hooks),
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
        });

        factory.setLBHooksParametersOnPair(wnative, usdc, DEFAULT_BIN_STEP, Hooks.encode(parameters), new bytes(0));

        pairWnative.increaseOracleLength(1);
    }

    function test_GetLBHooksParameters() public view {
        bytes32 parameters = pairWnative.getLBHooksParameters();

        Hooks.Parameters memory hooksParameters = Hooks.decode(parameters);

        assertEq(hooksParameters.hooks, address(hooks), "test_GetLBHooksParameters::1");
        assertTrue(hooksParameters.beforeSwap, "test_GetLBHooksParameters::2");
        assertTrue(hooksParameters.afterSwap, "test_GetLBHooksParameters::3");
        assertTrue(hooksParameters.beforeFlashLoan, "test_GetLBHooksParameters::4");
        assertTrue(hooksParameters.afterFlashLoan, "test_GetLBHooksParameters::5");
        assertTrue(hooksParameters.beforeMint, "test_GetLBHooksParameters::6");
        assertTrue(hooksParameters.afterMint, "test_GetLBHooksParameters::7");
        assertTrue(hooksParameters.beforeBurn, "test_GetLBHooksParameters::8");
        assertTrue(hooksParameters.afterBurn, "test_GetLBHooksParameters::9");
        assertTrue(hooksParameters.beforeBatchTransferFrom, "test_GetLBHooksParameters::10");
        assertTrue(hooksParameters.afterBatchTransferFrom, "test_GetLBHooksParameters::11");
    }

    function test_BeforeAfterSwapHooksXtoY() public {
        (uint128 amountLeft, uint128 amountOut,) = pairWnative.getSwapOut(amount, true);

        vm.assume(amountOut > 0);

        assertEq(amountLeft, 0, "test_BeforeAfterSwapHooksXtoY::1");

        deal(address(wnative), ALICE, amount);

        State memory expectedBeforeState = hooks.getState();

        vm.startPrank(ALICE);
        wnative.transfer(address(pairWnative), amount);
        pairWnative.swap(true, ALICE);
        vm.stopPrank();

        State memory expectedAfterState = hooks.getState();

        assertEq(wnative.balanceOf(ALICE), 0, "test_BeforeAfterSwapHooksXtoY::2");
        assertEq(usdc.balanceOf(ALICE), amountOut, "test_BeforeAfterSwapHooksXtoY::3");

        assertEq(
            keccak256(hooks.beforeData()),
            keccak256(
                abi.encodeWithSelector(
                    ILBHooks.beforeSwap.selector, ALICE, ALICE, true, PackedUint128Math.encodeFirst(amount)
                )
            ),
            "test_BeforeAfterSwapHooksXtoY::4"
        );

        assertEq(
            keccak256(hooks.afterData()),
            keccak256(
                abi.encodeWithSelector(
                    ILBHooks.afterSwap.selector, ALICE, ALICE, true, PackedUint128Math.encodeSecond(amountOut)
                )
            ),
            "test_BeforeAfterSwapHooksXtoY::5"
        );

        State memory hooksBeforeState = hooks.getBeforeState();
        State memory hooksAfterState = hooks.getAfterState();

        _verifyStates(hooksBeforeState, expectedBeforeState);
        _verifyStates(hooksAfterState, expectedAfterState);
    }

    function test_BeforeAfterSwapHooksYtoX() public {
        (uint128 amountLeft, uint128 amountOut,) = pairWnative.getSwapOut(amount, false);

        vm.assume(amountOut > 0);

        assertEq(amountLeft, 0, "test_BeforeAfterSwapHooksYtoX::1");

        deal(address(usdc), ALICE, amount);

        State memory expectedBeforeState = hooks.getState();

        vm.startPrank(ALICE);
        usdc.transfer(address(pairWnative), amount);
        pairWnative.swap(false, ALICE);
        vm.stopPrank();

        State memory expectedAfterState = hooks.getState();

        assertEq(usdc.balanceOf(ALICE), 0, "test_BeforeAfterSwapHooksYtoX::2");
        assertEq(wnative.balanceOf(ALICE), amountOut, "test_BeforeAfterSwapHooksYtoX::3");

        assertEq(
            keccak256(hooks.beforeData()),
            keccak256(
                abi.encodeWithSelector(
                    ILBHooks.beforeSwap.selector, ALICE, ALICE, false, PackedUint128Math.encodeSecond(amount)
                )
            ),
            "test_BeforeAfterSwapHooksYtoX::4"
        );

        assertEq(
            keccak256(hooks.afterData()),
            keccak256(
                abi.encodeWithSelector(
                    ILBHooks.afterSwap.selector, ALICE, ALICE, false, PackedUint128Math.encodeFirst(amountOut)
                )
            ),
            "test_BeforeAfterSwapHooksYtoX::5"
        );

        State memory hooksBeforeState = hooks.getBeforeState();
        State memory hooksAfterState = hooks.getAfterState();

        _verifyStates(hooksBeforeState, expectedBeforeState);
        _verifyStates(hooksAfterState, expectedAfterState);
    }

    function test_BeforeAfterFlashLoanHooks() public {
        State memory expectedBeforeState = hooks.getState();

        bytes32 amounts = PackedUint128Math.encode(amount, amount);

        vm.prank(ALICE);
        pairWnative.flashLoan(ILBFlashLoanCallback(address(this)), amounts, new bytes(0));

        State memory expectedAfterState = hooks.getState();

        assertEq(
            keccak256(hooks.beforeData()),
            keccak256(abi.encodeWithSelector(ILBHooks.beforeFlashLoan.selector, ALICE, address(this), amounts)),
            "test_BeforeAfterFlashLoanHooks::1"
        );

        uint128 flashloanFee = uint128(factory.getFlashLoanFee() * amount / 1e18);

        bytes32 fees = PackedUint128Math.encode(flashloanFee, flashloanFee);

        assertEq(
            keccak256(hooks.afterData()),
            keccak256(
                abi.encodeWithSelector(
                    ILBHooks.afterFlashLoan.selector,
                    ALICE,
                    address(this),
                    fees,
                    PackedUint128Math.encode(amount, amount)
                )
            ),
            "test_BeforeAfterFlashLoanHooks::2"
        );

        State memory hooksBeforeState = hooks.getBeforeState();
        State memory hooksAfterState = hooks.getAfterState();

        _verifyStates(hooksBeforeState, expectedBeforeState);
        _verifyStates(hooksAfterState, expectedAfterState);
    }

    function test_BeforeAfterMintHooks() public {
        State memory expectedBeforeState = hooks.getState();

        bytes32[] memory liquidityConfigs = new bytes32[](1);
        liquidityConfigs[0] = LiquidityConfigurations.encodeParams(1e18, 1e18, expectedBeforeState.activeId);

        deal(address(wnative), ALICE, amount);
        deal(address(usdc), ALICE, amount);

        vm.startPrank(ALICE);
        wnative.transfer(address(pairWnative), amount);
        usdc.transfer(address(pairWnative), amount);
        pairWnative.mint(ALICE, liquidityConfigs, ALICE);
        vm.stopPrank();

        State memory expectedAfterState = hooks.getState();

        assertEq(
            keccak256(hooks.beforeData()),
            keccak256(
                abi.encodeWithSelector(
                    ILBHooks.beforeMint.selector,
                    ALICE,
                    ALICE,
                    liquidityConfigs,
                    PackedUint128Math.encode(amount, amount)
                )
            ),
            "test_BeforeAfterMintHooks::1"
        );

        assertEq(
            keccak256(hooks.afterData()),
            keccak256(
                abi.encodeWithSelector(
                    ILBHooks.afterMint.selector,
                    ALICE,
                    ALICE,
                    liquidityConfigs,
                    PackedUint128Math.encode(amount, amount)
                )
            ),
            "test_BeforeAfterMintHooks::2"
        );

        State memory hooksBeforeState = hooks.getBeforeState();
        State memory hooksAfterState = hooks.getAfterState();

        _verifyStates(hooksBeforeState, expectedBeforeState);
        _verifyStates(hooksAfterState, expectedAfterState);
    }

    function test_BeforeAfterBurnHooks() public {
        uint24 activeId = pairWnative.getActiveId();

        bytes32[] memory liquidityConfigs = new bytes32[](1);
        liquidityConfigs[0] = LiquidityConfigurations.encodeParams(1e18, 1e18, activeId);

        deal(address(wnative), ALICE, amount);
        deal(address(usdc), ALICE, amount);

        vm.startPrank(ALICE);
        wnative.transfer(address(pairWnative), amount);
        usdc.transfer(address(pairWnative), amount);
        pairWnative.mint(ALICE, liquidityConfigs, ALICE);

        State memory expectedBeforeState = hooks.getState();

        uint256[] memory ids = new uint256[](1);
        ids[0] = activeId;

        uint256[] memory amountsToBurn = new uint256[](1);
        amountsToBurn[0] = amount;

        pairWnative.burn(ALICE, ALICE, ids, amountsToBurn);
        vm.stopPrank();

        State memory expectedAfterState = hooks.getState();

        assertEq(
            keccak256(hooks.beforeData()),
            keccak256(abi.encodeWithSelector(ILBHooks.beforeBurn.selector, ALICE, ALICE, ALICE, ids, amountsToBurn)),
            "test_BeforeAfterBurnHooks::1"
        );

        assertEq(
            keccak256(hooks.afterData()),
            keccak256(abi.encodeWithSelector(ILBHooks.afterBurn.selector, ALICE, ALICE, ALICE, ids, amountsToBurn)),
            "test_BeforeAfterBurnHooks::2"
        );

        State memory hooksBeforeState = hooks.getBeforeState();
        State memory hooksAfterState = hooks.getAfterState();

        _verifyStates(hooksBeforeState, expectedBeforeState);
        _verifyStates(hooksAfterState, expectedAfterState);
    }

    function test_BeforeAfterBatchTransferFromHooks() public {
        uint24 activeId = pairWnative.getActiveId();

        bytes32[] memory liquidityConfigs = new bytes32[](1);
        liquidityConfigs[0] = LiquidityConfigurations.encodeParams(1e18, 1e18, activeId);

        deal(address(wnative), ALICE, amount);
        deal(address(usdc), ALICE, amount);

        vm.startPrank(ALICE);
        wnative.transfer(address(pairWnative), amount);
        usdc.transfer(address(pairWnative), amount);
        pairWnative.mint(ALICE, liquidityConfigs, ALICE);

        State memory expectedBeforeState = hooks.getState();

        uint256[] memory ids = new uint256[](1);
        ids[0] = activeId;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        pairWnative.batchTransferFrom(ALICE, BOB, ids, amounts);
        vm.stopPrank();

        State memory expectedAfterState = hooks.getState();

        assertEq(
            keccak256(hooks.beforeData()),
            keccak256(
                abi.encodeWithSelector(ILBHooks.beforeBatchTransferFrom.selector, ALICE, ALICE, BOB, ids, amounts)
            ),
            "test_BeforeAfterBatchTransferFromHooks::1"
        );

        assertEq(
            keccak256(hooks.afterData()),
            keccak256(abi.encodeWithSelector(ILBHooks.afterBatchTransferFrom.selector, ALICE, ALICE, BOB, ids, amounts)),
            "test_BeforeAfterBatchTransferFromHooks::2"
        );

        State memory hooksBeforeState = hooks.getBeforeState();
        State memory hooksAfterState = hooks.getAfterState();

        _verifyStates(hooksBeforeState, expectedBeforeState);
        _verifyStates(hooksAfterState, expectedAfterState);
    }

    fallback() external {
        deal(address(wnative), address(pairWnative), wnative.balanceOf(address(pairWnative)) + 2 * amount);
        deal(address(usdc), address(pairWnative), usdc.balanceOf(address(pairWnative)) + 2 * amount);

        bytes32 callback_success = Constants.CALLBACK_SUCCESS;
        assembly {
            mstore(0, callback_success)
            return(0, 32)
        }
    }

    function _verifyStates(State memory hooksState, State memory expectedState) internal pure {
        assertEq(hooksState.reserveX, expectedState.reserveX, "_verifyStates::1");
        assertEq(hooksState.reserveY, expectedState.reserveY, "_verifyStates::2");
        assertEq(hooksState.protocolFeeX, expectedState.protocolFeeX, "_verifyStates::3");
        assertEq(hooksState.protocolFeeY, expectedState.protocolFeeY, "_verifyStates::4");
        assertEq(hooksState.activeId, expectedState.activeId, "_verifyStates::5");
        assertEq(hooksState.activeReserveX, expectedState.activeReserveX, "_verifyStates::6");
        assertEq(hooksState.activeReserveY, expectedState.activeReserveY, "_verifyStates::7");

        VolatilityParameters memory vp = hooksState.volatilityParameters;
        VolatilityParameters memory evp = expectedState.volatilityParameters;

        assertEq(vp.volatilityAccumulator, evp.volatilityAccumulator, "_verifyStates::8");
        assertEq(vp.volatilityReference, evp.volatilityReference, "_verifyStates::9");
        assertEq(vp.idReference, evp.idReference, "_verifyStates::10");
        assertEq(vp.timeOfLastUpdate, evp.timeOfLastUpdate, "_verifyStates::11");

        OracleParameters memory op = hooksState.oracleParameters;
        OracleParameters memory eop = expectedState.oracleParameters;

        assertEq(op.sampleLifetime, eop.sampleLifetime, "_verifyStates::12");
        assertEq(op.size, eop.size, "_verifyStates::13");
        assertEq(op.activeSize, eop.activeSize, "_verifyStates::14");
        assertEq(op.lastUpdated, eop.lastUpdated, "_verifyStates::15");
        assertEq(op.firstTimestamp, eop.firstTimestamp, "_verifyStates::16");
    }

    function test_SwapReentrancy() public {
        deal(address(wnative), address(pairWnative), wnative.balanceOf(address(pairWnative)) + amount);

        hooks.setBefore(address(pairWnative), abi.encodeWithSelector(ILBPair.swap.selector, true, ALICE));

        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        vm.prank(ALICE);
        pairWnative.swap(true, ALICE);

        hooks.setBefore(address(0), new bytes(0));

        hooks.setAfter(address(pairWnative), abi.encodeWithSelector(ILBPair.swap.selector, false, ALICE));

        assertEq(wnative.balanceOf(ALICE), 0, "test_SwapReentrancy::1");

        vm.prank(ALICE);
        pairWnative.swap(true, address(pairWnative));

        assertGt(wnative.balanceOf(ALICE), 0, "test_SwapReentrancy::2");
    }

    function test_FlashLoanReentrancy() public {
        hooks.setBefore(
            address(pairWnative),
            abi.encodeWithSelector(
                ILBPair.flashLoan.selector, address(this), PackedUint128Math.encode(amount, amount), new bytes(0)
            )
        );

        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        vm.prank(ALICE);
        pairWnative.flashLoan(
            ILBFlashLoanCallback(address(this)), PackedUint128Math.encode(amount, amount), new bytes(0)
        );

        hooks.setBefore(address(0), new bytes(0));

        hooks.setAfter(
            address(pairWnative),
            abi.encodeWithSelector(
                ILBPair.flashLoan.selector, address(this), PackedUint128Math.encode(amount, amount), new bytes(0)
            )
        );

        uint256 beforeBalanceWnative = wnative.balanceOf(address(pairWnative));
        uint256 beforeBalanceUsdc = usdc.balanceOf(address(pairWnative));

        vm.prank(ALICE);
        pairWnative.flashLoan(
            ILBFlashLoanCallback(address(this)), PackedUint128Math.encode(amount, amount), new bytes(0)
        );

        // Should have triggered the fallback twice
        assertEq(
            wnative.balanceOf(address(pairWnative)), beforeBalanceWnative + 2 * amount, "test_FlashLoanReentrancy::1"
        );
        assertEq(usdc.balanceOf(address(pairWnative)), beforeBalanceUsdc + 2 * amount, "test_FlashLoanReentrancy::2");

        assertEq(wnative.balanceOf(address(this)), 2 * amount, "test_FlashLoanReentrancy::3");
        assertEq(usdc.balanceOf(address(this)), 2 * amount, "test_FlashLoanReentrancy::4");
    }

    function test_MintReentrancy() public {
        bytes32[] memory liquidityConfigs = new bytes32[](1);
        liquidityConfigs[0] = LiquidityConfigurations.encodeParams(0.5e18, 0.5e18, 2 ** 23);

        hooks.setBefore(
            address(pairWnative), abi.encodeWithSelector(ILBPair.mint.selector, ALICE, liquidityConfigs, ALICE)
        );

        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        vm.prank(ALICE);
        pairWnative.mint(ALICE, liquidityConfigs, ALICE);

        hooks.setBefore(address(0), new bytes(0));

        hooks.setAfter(
            address(pairWnative), abi.encodeWithSelector(ILBPair.mint.selector, ALICE, liquidityConfigs, ALICE)
        );

        uint256 beforeBalanceWnative = wnative.balanceOf(address(pairWnative));
        uint256 beforeBalanceUsdc = usdc.balanceOf(address(pairWnative));

        deal(address(wnative), address(pairWnative), wnative.balanceOf(address(pairWnative)) + amount);
        deal(address(usdc), address(pairWnative), usdc.balanceOf(address(pairWnative)) + amount);

        vm.prank(ALICE);
        pairWnative.mint(ALICE, liquidityConfigs, address(pairWnative));

        // Should have added twice 50% of the amount, so 75% of the amount
        assertEq(
            wnative.balanceOf(address(pairWnative)), beforeBalanceWnative + 75 * amount / 100, "test_MintReentrancy::1"
        );
        assertEq(usdc.balanceOf(address(pairWnative)), beforeBalanceUsdc + 75 * amount / 100, "test_MintReentrancy::2");

        assertEq(wnative.balanceOf(ALICE), 25 * amount / 100, "test_MintReentrancy::3");
        assertEq(usdc.balanceOf(ALICE), 25 * amount / 100, "test_MintReentrancy::4");
    }

    function test_BurnReentrancy() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = pairWnative.getActiveId();

        uint256[] memory amountsToBurn = new uint256[](1);
        amountsToBurn[0] = pairWnative.balanceOf(DEV, ids[0]) / 2;

        vm.prank(DEV);
        pairWnative.approveForAll(address(hooks), true);

        hooks.setBefore(
            address(pairWnative), abi.encodeWithSelector(ILBPair.burn.selector, DEV, ALICE, ids, amountsToBurn)
        );

        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        vm.prank(DEV);
        pairWnative.burn(DEV, ALICE, ids, amountsToBurn);

        hooks.setBefore(address(0), new bytes(0));

        hooks.setAfter(
            address(pairWnative), abi.encodeWithSelector(ILBPair.burn.selector, DEV, ALICE, ids, amountsToBurn)
        );

        assertEq(wnative.balanceOf(ALICE), 0, "test_BurnReentrancy::1");
        assertEq(usdc.balanceOf(ALICE), 0, "test_BurnReentrancy::2");

        vm.prank(DEV);
        pairWnative.burn(DEV, ALICE, ids, amountsToBurn);

        assertGt(wnative.balanceOf(ALICE), 0, "test_BurnReentrancy::3");
        assertGt(usdc.balanceOf(ALICE), 0, "test_BurnReentrancy::4");

        (uint256 binReserveX, uint256 binReserveY) = pairWnative.getBin(uint24(ids[0]));

        assertEq(binReserveX, 0, "test_BurnReentrancy::5");
        assertEq(binReserveY, 0, "test_BurnReentrancy::6");
    }

    function test_BatchTransferFromReentrancy() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = pairWnative.getActiveId();

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = pairWnative.balanceOf(DEV, ids[0]) / 2;

        vm.prank(DEV);
        pairWnative.approveForAll(address(hooks), true);

        hooks.setBefore(
            address(pairWnative), abi.encodeWithSelector(ILBToken.batchTransferFrom.selector, DEV, ALICE, ids, amounts)
        );

        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        vm.prank(DEV);
        pairWnative.batchTransferFrom(DEV, ALICE, ids, amounts);

        hooks.setBefore(address(0), new bytes(0));

        hooks.setAfter(
            address(pairWnative), abi.encodeWithSelector(ILBToken.batchTransferFrom.selector, DEV, ALICE, ids, amounts)
        );

        assertEq(pairWnative.balanceOf(ALICE, ids[0]), 0, "test_BatchTransferFromReentrancy::1");
        assertGt(pairWnative.balanceOf(DEV, ids[0]), 0, "test_BatchTransferFromReentrancy::2");

        vm.prank(DEV);
        pairWnative.batchTransferFrom(DEV, ALICE, ids, amounts);

        assertGt(pairWnative.balanceOf(ALICE, ids[0]), 0, "test_BatchTransferFromReentrancy::3");
        assertEq(pairWnative.balanceOf(DEV, ids[0]), 0, "test_BatchTransferFromReentrancy::4");
    }
}

contract MockLBHooks is MockHooks {
    State private _beforeState;
    State private _afterState;

    address public beforeTarget;
    bytes public beforeTargetData;

    address public afterTarget;
    bytes public afterTargetData;

    function getBeforeState() public view returns (State memory) {
        return _beforeState;
    }

    function getAfterState() public view returns (State memory) {
        return _afterState;
    }

    function reset() public override {
        super.reset();

        delete _beforeState;
        delete _afterState;
    }

    function setBefore(address target, bytes calldata data) public {
        beforeTarget = target;
        beforeTargetData = data;
    }

    function setAfter(address target, bytes calldata data) public {
        afterTarget = target;
        afterTargetData = data;
    }

    function _onHooksSet(bytes32 hooksParameters, bytes calldata onHooksSetData) internal override {
        super._onHooksSet(hooksParameters, onHooksSetData);

        _beforeState = getState();
    }

    function _beforeSwap(address sender, address to, bool swapForY, bytes32 amountsIn) internal override {
        if (sender == address(this)) return;

        super._beforeSwap(sender, to, swapForY, amountsIn);

        _beforeState = getState();

        _beforeCall();
    }

    function _afterSwap(address sender, address to, bool swapForY, bytes32 amountsOut) internal override {
        if (sender == address(this)) return;

        super._afterSwap(sender, to, swapForY, amountsOut);

        _afterState = getState();

        _afterCall();
    }

    function _beforeFlashLoan(address sender, address to, bytes32 amounts) internal override {
        if (sender == address(this)) return;

        super._beforeFlashLoan(sender, to, amounts);

        _beforeState = getState();

        _beforeCall();
    }

    function _afterFlashLoan(address sender, address to, bytes32 fees, bytes32 feesReceived) internal override {
        if (sender == address(this)) return;

        super._afterFlashLoan(sender, to, fees, feesReceived);

        _afterState = getState();

        _afterCall();
    }

    function _beforeMint(address sender, address to, bytes32[] calldata liquidityConfigs, bytes32 amountsReceived)
        internal
        override
    {
        if (sender == address(this)) return;

        super._beforeMint(sender, to, liquidityConfigs, amountsReceived);

        _beforeState = getState();

        _beforeCall();
    }

    function _afterMint(address sender, address to, bytes32[] calldata liquidityConfigs, bytes32 amountsIn)
        internal
        override
    {
        if (sender == address(this)) return;

        super._afterMint(sender, to, liquidityConfigs, amountsIn);

        _afterState = getState();

        _afterCall();
    }

    function _beforeBurn(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amountsToBurn
    ) internal override {
        if (sender == address(this)) return;

        super._beforeBurn(sender, from, to, ids, amountsToBurn);

        _beforeState = getState();

        _beforeCall();
    }

    function _afterBurn(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amountsToBurn
    ) internal override {
        if (sender == address(this)) return;

        super._afterBurn(sender, from, to, ids, amountsToBurn);

        _afterState = getState();

        _afterCall();
    }

    function _beforeBatchTransferFrom(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) internal override {
        if (sender == address(this)) return;

        super._beforeBatchTransferFrom(sender, from, to, ids, amounts);

        _beforeState = getState();

        _beforeCall();
    }

    function _afterBatchTransferFrom(
        address sender,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) internal override {
        if (sender == address(this)) return;

        super._afterBatchTransferFrom(sender, from, to, ids, amounts);

        _afterState = getState();

        _afterCall();
    }

    function getState() public view returns (State memory state) {
        ILBPair lbPair = _getLBPair();

        (state.reserveX, state.reserveY) = lbPair.getReserves();
        (state.protocolFeeX, state.protocolFeeY) = lbPair.getProtocolFees();
        uint24 activeId = (state.activeId = lbPair.getActiveId());
        (state.activeReserveX, state.activeReserveY) = lbPair.getBin(activeId);

        VolatilityParameters memory vp = state.volatilityParameters;
        (vp.volatilityAccumulator, vp.volatilityReference, vp.idReference, vp.timeOfLastUpdate) =
            lbPair.getVariableFeeParameters();

        OracleParameters memory op = state.oracleParameters;
        (op.sampleLifetime, op.size, op.activeSize, op.lastUpdated, op.firstTimestamp) = lbPair.getOracleParameters();
    }

    function _beforeCall() internal {
        if (beforeTarget == address(0)) return;

        Address.functionCall(beforeTarget, beforeTargetData);

        delete beforeTarget;
        delete beforeTargetData;
    }

    function _afterCall() internal {
        if (afterTarget == address(0)) return;

        Address.functionCall(afterTarget, afterTargetData);

        delete afterTarget;
        delete afterTargetData;
    }
}
