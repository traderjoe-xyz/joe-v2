// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";
import "src/libraries/Math512Bits.sol";

contract LiquidityBinPairFeesTest is TestHelper {
    using Math512Bits for uint256;

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV);
        new LBFactoryHelper(factory);
        router = new LBRouter(ILBFactory(DEV), IJoeFactory(DEV), IWAVAX(DEV));

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testClaimFees() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 1e18;
        uint24 startId = ID_ONE;

        (uint256[] memory _ids, , , ) = addLiquidity(amountYInLiquidity, startId, 5, 0);

        uint256 amountYInForSwap = router.getSwapIn(pair, amountXOutForSwap, false);

        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(true, DEV);

        LBPair.PairInformation memory pairInfo = pair.pairInformation();

        uint256 accumulatedYfees = pairInfo.feesY.total - pairInfo.feesY.protocol;

        uint256[] memory orderedIds = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            orderedIds[i] = startId - 2 + i;
        }
        ILBPair.UnclaimedFees memory fees = pair.pendingFees(DEV, orderedIds);

        assertApproxEqAbs(accumulatedYfees, fees.tokenY, 1);

        pair.collectFees(DEV, orderedIds);
        assertEq(fees.tokenY, token18D.balanceOf(DEV));

        // Trying to claim a second time
        uint256 balanceBefore = token18D.balanceOf(DEV);
        fees = pair.pendingFees(DEV, orderedIds);
        assertEq(fees.tokenY, 0);
        pair.collectFees(DEV, orderedIds);
        assertEq(token18D.balanceOf(DEV), balanceBefore);
    }

    function testFeesOnTokenTransfer() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYForSwap = 1e6;
        uint24 startId = ID_ONE;

        (uint256[] memory _ids, , , ) = addLiquidity(amountYInLiquidity, startId, 5, 0);

        token18D.mint(address(pair), amountYForSwap);

        pair.swap(true, ALICE);

        uint256[] memory amounts = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            amounts[i] = pair.balanceOf(DEV, _ids[i]);
        }

        pair.safeBatchTransferFrom(DEV, BOB, _ids, amounts);

        token18D.mint(address(pair), amountYForSwap);
        pair.swap(true, ALICE);

        ILBPair.UnclaimedFees memory feesForDev = pair.pendingFees(DEV, _ids);
        ILBPair.UnclaimedFees memory feesForBob = pair.pendingFees(BOB, _ids);

        assertGt(feesForDev.tokenY, 0, "DEV should have fees on token Y");
        assertGt(feesForBob.tokenY, 0, "BOB should also have fees on token Y");

        LBPair.PairInformation memory pairInfo = pair.pairInformation();

        uint256 accumulatedYfees = pairInfo.feesY.total - pairInfo.feesY.protocol;

        assertApproxEqAbs(
            feesForDev.tokenY + feesForBob.tokenY,
            accumulatedYfees,
            1,
            "Sum of users fees = accumulated fees"
        );

        pair.collectFees(DEV, _ids);
        assertEq(feesForDev.tokenY, token18D.balanceOf(DEV), "DEV gets the expected amount when withdrawing fees");
        pair.collectFees(BOB, _ids);
        assertEq(feesForBob.tokenY, token18D.balanceOf(BOB), "BOB gets the expected amount when withdrawing fees");
    }

    function testClaimProtocolFees() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 1e6;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 5, 0);

        uint256 amountYInForSwap = router.getSwapIn(pair, amountXOutForSwap, false);

        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(true, DEV);

        LBPair.PairInformation memory pairInfo = pair.pairInformation();

        address protocolFeesReceiver = factory.feeRecipient();
        pair.distributeProtocolFees();
        assertEq(token18D.balanceOf(protocolFeesReceiver), pairInfo.feesY.protocol - 1);

        // Claiming twice
        pair.distributeProtocolFees();
        assertEq(token18D.balanceOf(protocolFeesReceiver), pairInfo.feesY.protocol - 1);
    }
}
