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

        assertEq(accumulatedYfees, fees.tokenY);

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

        console2.log(token18D.balanceOf(address(pair)));

        (uint256[] memory _ids, uint256[] memory _liquidities, , ) = addLiquidity(amountYInLiquidity, startId, 5, 0);

        console2.log(token18D.balanceOf(address(pair)));

        token18D.mint(address(pair), amountYForSwap);

        console2.log(token18D.balanceOf(address(pair)));
        pair.swap(true, ALICE);

        pair.safeBatchTransferFrom(DEV, BOB, _ids, _liquidities);

        token18D.mint(address(pair), amountYForSwap);
        pair.swap(true, ALICE);

        uint256[] memory orderedIds = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            orderedIds[i] = startId - 2 + i;
        }
        ILBPair.UnclaimedFees memory feesForDev = pair.pendingFees(DEV, orderedIds);
        ILBPair.UnclaimedFees memory feesForBob = pair.pendingFees(BOB, orderedIds);

        assertGt(feesForDev.tokenY, 0);
        assertGt(feesForBob.tokenY, 0);

        LBPair.PairInformation memory pairInfo = pair.pairInformation();

        uint256 accumulatedYfees = pairInfo.feesY.total - pairInfo.feesY.protocol;

        assertEq(feesForDev.tokenY + feesForBob.tokenY, accumulatedYfees);

        pair.collectFees(DEV, orderedIds);
        assertEq(feesForDev.tokenY, token18D.balanceOf(DEV));
        pair.collectFees(BOB, orderedIds);
        assertEq(feesForBob.tokenY, token18D.balanceOf(BOB));
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
