// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinPairSwapsTest is TestHelper {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV);
        new LBFactoryHelper(factory);
        router = new LBRouter(ILBFactory(DEV), IWAVAX(DEV));

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testSwapXtoYSingleBinFromGetSwapOut() public {
        uint112 tokenAmount = 100e18;
        token18D.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](2);
        _ids[0] = ID_ONE + 1;
        _ids[1] = ID_ONE;

        uint256[] memory _liquidities = new uint256[](2);
        _liquidities[0] = 0;
        _liquidities[1] = tokenAmount;

        pair.mint(_ids, _liquidities, DEV);

        uint256 amountXIn = 1e12;

        uint256 amountYOut = router.getSwapOut(pair, amountXIn, true);

        token6D.mint(address(pair), amountXIn);
        vm.prank(DEV);
        pair.swap(false, DEV);

        assertEq(token6D.balanceOf(DEV), 0);
        assertEq(token18D.balanceOf(DEV), amountYOut);

        (uint112 binReserveX, uint112 binReserveY) = pair.getBin(ID_ONE);

        LBPair.PairInformation memory pair = pair.pairInformation();

        assertEq(binReserveX, amountXIn - pair.feesX.total);
        assertEq(binReserveY, tokenAmount - amountYOut);
    }

    function testSwapYtoXSingleBinFromGetSwapOut() public {
        uint112 tokenAmount = 100e18;
        token6D.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](2);
        _ids[0] = ID_ONE;
        _ids[1] = ID_ONE + 1;

        uint256 price = router.getPriceFromId(pair, uint24(_ids[1]));

        uint256[] memory _liquidities = new uint256[](2);
        _liquidities[0] = 0;
        _liquidities[1] = (price * tokenAmount) / SCALE;

        pair.mint(_ids, _liquidities, DEV);

        uint256 amountYIn = 1e12;

        uint256 amountXOut = router.getSwapOut(pair, amountYIn, false);

        token18D.mint(address(pair), amountYIn);
        vm.prank(DEV);
        pair.swap(true, DEV);

        assertEq(token6D.balanceOf(DEV), amountXOut);
        assertEq(token18D.balanceOf(DEV), 0);

        (uint112 binReserveX, uint112 binReserveY) = pair.getBin(
            uint24(_ids[1])
        );

        LBPair.PairInformation memory pair = pair.pairInformation();

        assertEq(binReserveX, tokenAmount - amountXOut);
        assertEq(binReserveY, amountYIn - pair.feesY.total);
    }

    function testSwapXtoYSingleBinFromGetSwapIn() public {
        uint112 tokenAmount = 100e18;
        token18D.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](2);
        _ids[0] = ID_ONE + 1;
        _ids[1] = ID_ONE;

        uint256[] memory _liquidities = new uint256[](2);
        _liquidities[0] = 0;
        _liquidities[1] = tokenAmount;

        pair.mint(_ids, _liquidities, DEV);

        uint256 amountYOut = 1e12;

        uint256 amountXIn = router.getSwapIn(pair, amountYOut, true);

        token6D.mint(address(pair), amountXIn);
        vm.prank(DEV);
        pair.swap(false, DEV);

        assertEq(token6D.balanceOf(DEV), 0);
        assertEq(token18D.balanceOf(DEV), amountYOut);

        (uint112 binReserveX, uint112 binReserveY) = pair.getBin(ID_ONE);

        LBPair.PairInformation memory pair = pair.pairInformation();

        assertEq(binReserveX, amountXIn - pair.feesX.total);
        assertEq(binReserveY, tokenAmount - amountYOut);
    }

    function testSwapYtoXSingleBinFromGetSwapIn() public {
        uint112 tokenAmount = 100e18;
        token6D.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](2);
        _ids[0] = ID_ONE;
        _ids[1] = ID_ONE + 1;

        uint256 price = router.getPriceFromId(pair, uint24(_ids[1]));

        uint256[] memory _liquidities = new uint256[](2);
        _liquidities[0] = 0;
        _liquidities[1] = (price * tokenAmount) / SCALE;

        pair.mint(_ids, _liquidities, DEV);

        uint256 amountXOut = 1e12;

        uint256 amountYIn = router.getSwapIn(pair, amountXOut, false);

        token18D.mint(address(pair), amountYIn);
        vm.prank(DEV);
        pair.swap(true, DEV);

        assertEq(token6D.balanceOf(DEV), amountXOut);
        assertEq(token18D.balanceOf(DEV), 0);

        (uint112 binReserveX, uint112 binReserveY) = pair.getBin(
            uint24(_ids[1])
        );

        LBPair.PairInformation memory pair = pair.pairInformation();

        assertEq(binReserveX, tokenAmount - amountXOut);
        assertEq(binReserveY, amountYIn - pair.feesY.total);
    }

    function testSwapYtoXConsecutiveBinFromGetSwapIn() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 0);

        uint256 amountYInForSwap = router.getSwapIn(
            pair,
            amountXOutForSwap,
            false
        );

        token18D.mint(address(pair), amountYInForSwap);

        pair.swap(true, ALICE);

        assertGt(token6D.balanceOf(ALICE), amountXOutForSwap);
        assertApproxEqRel(token6D.balanceOf(ALICE), amountXOutForSwap, 1e14);
    }

    function testSwapXtoYConsecutiveBinFromGetSwapIn() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 0);

        uint256 amountXInForSwap = router.getSwapIn(
            pair,
            amountYOutForSwap,
            true
        );

        token6D.mint(address(pair), amountXInForSwap);

        pair.swap(false, ALICE);

        assertGt(token18D.balanceOf(ALICE), amountYOutForSwap);
        assertApproxEqRel(token18D.balanceOf(ALICE), amountYOutForSwap, 1e14);
    }

    function testSwapYtoXConsecutiveBinFromGetSwapOut() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYInForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 0);

        uint256 amountXOutForSwap = router.getSwapOut(
            pair,
            amountYInForSwap,
            false
        );

        token18D.mint(address(pair), amountYInForSwap);

        pair.swap(true, ALICE);

        assertApproxEqAbs(token6D.balanceOf(ALICE), amountXOutForSwap, 1);
    }

    function testSwapXtoYConsecutiveBinFromGetSwapOut() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXInForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 0);

        uint256 amountYOutForSwap = router.getSwapOut(
            pair,
            amountXInForSwap,
            true
        );

        token6D.mint(address(pair), amountXInForSwap);

        pair.swap(false, ALICE);

        assertEq(token18D.balanceOf(ALICE), amountYOutForSwap);
    }

    function testSwapYtoXDistantBinsFromGetSwapIn() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 100);

        uint256 amountYInForSwap = router.getSwapIn(
            pair,
            amountXOutForSwap,
            false
        );

        token18D.mint(address(pair), amountYInForSwap);

        pair.swap(true, ALICE);

        assertGt(token6D.balanceOf(ALICE), amountXOutForSwap);
        assertApproxEqRel(token6D.balanceOf(ALICE), amountXOutForSwap, 1e14);
    }

    function testSwapXtoYDistantBinsFromGetSwapIn() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 100);

        uint256 amountXInForSwap = router.getSwapIn(
            pair,
            amountYOutForSwap,
            true
        );

        token6D.mint(address(pair), amountXInForSwap);

        pair.swap(false, ALICE);

        assertGt(token18D.balanceOf(ALICE), amountYOutForSwap);
        assertApproxEqRel(token18D.balanceOf(ALICE), amountYOutForSwap, 1e14);
    }

    function testSwapYtoXDistantBinsFromGetSwapOut() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYInForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 100);

        uint256 amountXOutForSwap = router.getSwapOut(
            pair,
            amountYInForSwap,
            false
        );

        token18D.mint(address(pair), amountYInForSwap);

        pair.swap(true, ALICE);

        assertApproxEqAbs(token6D.balanceOf(ALICE), amountXOutForSwap, 1);
    }

    function testSwapXtoYDistantBinsFromGetSwapOut() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXInForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 100);

        uint256 amountYOutForSwap = router.getSwapOut(
            pair,
            amountXInForSwap,
            true
        );

        token6D.mint(address(pair), amountXInForSwap);

        pair.swap(false, ALICE);

        assertEq(token18D.balanceOf(ALICE), amountYOutForSwap);
    }
}
