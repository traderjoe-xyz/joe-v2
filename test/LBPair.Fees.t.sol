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
        uint256 amountXOutForSwap = 1e6;
        uint24 startId = ID_ONE;

        (
            uint256[] memory _ids,
            uint256[] memory _liquidities,
            uint256 amountXIn
        ) = spreadLiquidityN(amountYInLiquidity * 2, startId, 5, 0);

        token6D.mint(address(pair), amountXIn);
        token18D.mint(address(pair), amountYInLiquidity);

        pair.mint(_ids, _liquidities, DEV);

        (, uint256 amountYInForSwap) = router.getSwapIn(
            pair,
            amountXOutForSwap,
            0
        );

        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(amountXOutForSwap, 0, DEV);

        LBPair.PairInformation memory pairInfo = pair.pairInformation();

        uint256 accumulatedYfees = pairInfo.fees1.total -
            pairInfo.fees1.protocol;

        ILBPair.UnclaimedFees memory fees = pair.pendingFees(DEV, _ids);

        assertEq(accumulatedYfees, fees.token1);

        pair.collectFees(DEV, _ids);
        assertEq(fees.token1, token18D.balanceOf(DEV));

        // Trying to claim a second time
        uint256 balanceBefore = token18D.balanceOf(DEV);
        fees = pair.pendingFees(DEV, _ids);
        assertEq(fees.token1, 0);
        pair.collectFees(DEV, _ids);
        assertEq(token18D.balanceOf(DEV), balanceBefore);
    }

    function testFeesOnTokenTransfer() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 1e6;
        uint24 startId = ID_ONE;

        (
            uint256[] memory _ids,
            uint256[] memory _liquidities,
            uint256 amountXIn
        ) = spreadLiquidityN(amountYInLiquidity * 2, startId, 5, 0);

        token6D.mint(address(pair), amountXIn);
        token18D.mint(address(pair), amountYInLiquidity);

        pair.mint(_ids, _liquidities, DEV);

        (, uint256 amountYInForSwap) = router.getSwapIn(
            pair,
            amountXOutForSwap,
            0
        );

        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(amountXOutForSwap, 0, DEV);

        pair.safeBatchTransferFrom(DEV, BOB, _ids, _liquidities);

        ILBPair.Amounts memory feesForDev = pair.pendingFees(DEV, _ids);

        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(amountXOutForSwap, 0, DEV);

        ILBPair.Amounts memory feesForBob = pair.pendingFees(BOB, _ids);

        assertGt(feesForDev.token1, 0);
        assertGt(feesForBob.token1, 0);

        LBPair.PairInformation memory pairInfo = pair.pairInformation();

        uint256 accumulatedYfees = pairInfo.fees1.total -
            pairInfo.fees1.protocol;

        assertEq(feesForDev.token1 + feesForBob.token1, accumulatedYfees);

        pair.collectFees(DEV, _ids);
        assertEq(feesForDev.token1, token18D.balanceOf(DEV));
        pair.collectFees(BOB, _ids);
        assertEq(feesForBob.token1, token18D.balanceOf(BOB));
    }

    function testClaimProtocolFees() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 1e6;
        uint24 startId = ID_ONE;

        (
            uint256[] memory _ids,
            uint256[] memory _liquidities,
            uint256 amountXIn
        ) = spreadLiquidityN(amountYInLiquidity * 2, startId, 5, 0);

        token6D.mint(address(pair), amountXIn);
        token18D.mint(address(pair), amountYInLiquidity);

        pair.mint(_ids, _liquidities, DEV);

        (, uint256 amountYInForSwap) = router.getSwapIn(
            pair,
            amountXOutForSwap,
            0
        );

        token18D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(amountXOutForSwap, 0, DEV);

        LBPair.PairInformation memory pairInfo = pair.pairInformation();

        address protocolFeesReceiver = factory.feeRecipient();
        pair.distributeProtocolFees();
        assertEq(
            token18D.balanceOf(protocolFeesReceiver),
            pairInfo.fees1.protocol - 1
        );

        // Claiming twice
        pair.distributeProtocolFees();
        assertEq(
            token18D.balanceOf(protocolFeesReceiver),
            pairInfo.fees1.protocol - 1
        );
    }
}
