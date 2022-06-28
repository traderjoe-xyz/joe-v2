// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinPairSwapsTest is TestHelper {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV);
        router = new LBRouter(ILBFactory(DEV), IWAVAX(DEV));

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testSwapYtoXSingleBin() public {
        uint256 tokenAmount = 100e6;
        token6D.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](2);
        _ids[0] = ID_ONE - 1;
        _ids[1] = ID_ONE;

        uint256[] memory _liquidities = new uint256[](2);
        _liquidities[0] = 0;
        _liquidities[1] =
            (tokenAmount * getPriceFromId(ID_ONE)) /
            PRICE_PRECISION;

        pair.mint(_ids, _liquidities, DEV);

        uint256 amount0Out = 1e6;
        (uint256 amount0In, uint256 amount1In) = router.getSwapIn(
            pair,
            amount0Out,
            0
        );
        console2.log("Swap amount0In, amount1In", amount0In, amount1In);

        token18D.mint(address(pair), amount1In);
        vm.prank(DEV);
        pair.swap(true, DEV);

        assertEq(token6D.balanceOf(DEV), amount0Out);
        assertEq(token18D.balanceOf(DEV), 0);

        (, uint112 binReserveX, uint112 binReserveY) = pair.getBin(ID_ONE);

        LBPair.PairInformation memory pair = pair.pairInformation();


        assertEq(binReserveX, tokenAmount - amount0Out, "binReserveX");
        assertEq(binReserveY, amount1In - pair.feesY.total, "binReserveY");
    }

    function testSwapXtoYSingleBin() public {
        uint112 tokenAmount = 100e12;
        token18D.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](2);
        _ids[0] = ID_ONE + 1;
        _ids[1] = ID_ONE;

        uint256[] memory _liquidities = new uint256[](2);
        _liquidities[0] = 0;
        _liquidities[1] = tokenAmount;

        pair.mint(_ids, _liquidities, DEV);

        uint256 amount1Out = 1e12;

        (uint256 amount0In, ) = router.getSwapIn(pair, 0, amount1Out);

        console2.log("amount0In", amount0In);
        token6D.mint(address(pair), amount0In);
        vm.prank(DEV);
        pair.swap(false, DEV);

        assertEq(token6D.balanceOf(DEV), 0);
        assertEq(token18D.balanceOf(DEV), amount1Out);

        (, uint112 binReserveX, uint112 binReserveY) = pair.getBin(ID_ONE);

        LBPair.PairInformation memory pair = pair.pairInformation();

        assertApproxEqRel(binReserveX, amount0In - pair.feesX.total, 1e14);
        assertEq(binReserveY, tokenAmount - amount1Out);
    }

    function testSwapYtoXConsecutiveBin() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 0);

        (, uint256 amountYInForSwap) = router.getSwapIn(
            pair,
            amountXOutForSwap,
            0
        );

        token18D.mint(address(pair), amountYInForSwap);

        pair.swap(true, ALICE);

        assertEq(token6D.balanceOf(ALICE), amountXOutForSwap);
    }

    function testSwapXtoYConsecutiveBin() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 0);

        (uint256 amountXInForSwap, ) = router.getSwapIn(
            pair,
            0,
            amountYOutForSwap
        );

        token6D.mint(address(pair), amountXInForSwap);

        pair.swap(true, ALICE);

        assertEq(token18D.balanceOf(ALICE), amountYOutForSwap);
    }

    function testSwapYtoXDistantBins() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 100);

        (, uint256 amountYInForSwap) = router.getSwapIn(
            pair,
            amountXOutForSwap,
            0
        );

        token18D.mint(address(pair), amountYInForSwap);

        pair.swap(true, ALICE);

        assertEq(token6D.balanceOf(ALICE), amountXOutForSwap);
    }

    function testSwapXtoYDistantBins() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 100);

        (uint256 amountXInForSwap, ) = router.getSwapIn(
            pair,
            0,
            amountYOutForSwap
        );

        token6D.mint(address(pair), amountXInForSwap);

        pair.swap(true, ALICE);

        assertEq(token18D.balanceOf(ALICE), amountYOutForSwap);
    }
}
