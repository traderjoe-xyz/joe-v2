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
        router = new LBRouter(ILBFactory(DEV), IWAVAX(DEV));

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testClaimFees() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 1e18;
        uint24 startId = ID_ONE;

        (uint256[] memory _ids, , ) = addLiquidity(
            amountYInLiquidity,
            startId,
            5,
            0
        );

        (, uint256 amountYInForSwap) = router.getSwapIn(
            pair,
            amountXOutForSwap,
            0
        );

        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(true, DEV);

        LBPair.PairInformation memory pairInfo = pair.pairInformation();

        uint256 accumulatedYfees = pairInfo.feesY.total -
            pairInfo.feesY.protocol;

        ILBPair.Amounts memory fees = pair.pendingFees(DEV, _ids);

        assertEq(accumulatedYfees, fees.tokenY);

        pair.collectFees(DEV, _ids);
        assertEq(fees.tokenY, token18D.balanceOf(DEV));

        // Trying to claim a second time
        uint256 balanceBefore = token18D.balanceOf(DEV);
        fees = pair.pendingFees(DEV, _ids);
        assertEq(fees.tokenY, 0);
        pair.collectFees(DEV, _ids);
        assertEq(token18D.balanceOf(DEV), balanceBefore);
    }

    function testFeesOnTokenTransfer() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYForSwap = 1e6;
        uint24 startId = ID_ONE;

        console2.log(token18D.balanceOf(address(pair)));

        (uint256[] memory _ids, uint256[] memory _liquidities, ) = addLiquidity(
            amountYInLiquidity,
            startId,
            5,
            0
        );

        console2.log(token18D.balanceOf(address(pair)));

        token18D.mint(address(pair), amountYForSwap);

        console2.log(token18D.balanceOf(address(pair)));
        pair.swap(true, ALICE);

        pair.safeBatchTransferFrom(DEV, BOB, _ids, _liquidities);

        token18D.mint(address(pair), amountYForSwap);
        pair.swap(true, ALICE);

        ILBPair.Amounts memory feesForDev = pair.pendingFees(DEV, _ids);
        ILBPair.Amounts memory feesForBob = pair.pendingFees(BOB, _ids);

        assertGt(feesForDev.tokenY, 0);
        assertGt(feesForBob.tokenY, 0);

        LBPair.PairInformation memory pairInfo = pair.pairInformation();

        uint256 accumulatedYfees = pairInfo.feesY.total -
            pairInfo.feesY.protocol;

        assertEq(feesForDev.tokenY + feesForBob.tokenY, accumulatedYfees);

        pair.collectFees(DEV, _ids);
        assertEq(feesForDev.tokenY, token18D.balanceOf(DEV));
        pair.collectFees(BOB, _ids);
        assertEq(feesForBob.tokenY, token18D.balanceOf(BOB));
    }

    function testClaimProtocolFees() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 1e6;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 5, 0);

        (, uint256 amountYInForSwap) = router.getSwapIn(
            pair,
            amountXOutForSwap,
            0
        );

        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(true, DEV);

        LBPair.PairInformation memory pairInfo = pair.pairInformation();

        address protocolFeesReceiver = factory.feeRecipient();
        pair.distributeProtocolFees();
        assertEq(
            token18D.balanceOf(protocolFeesReceiver),
            pairInfo.feesY.protocol - 1
        );

        // Claiming twice
        pair.distributeProtocolFees();
        assertEq(
            token18D.balanceOf(protocolFeesReceiver),
            pairInfo.feesY.protocol - 1
        );
    }
}
