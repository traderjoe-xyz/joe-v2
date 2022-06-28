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
            pair.PRICE_PRECISION();

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
        pair.swap(amount0Out, 0, DEV);

        assertEq(token6D.balanceOf(DEV), amount0Out);
        assertEq(token18D.balanceOf(DEV), 0);

        (, uint112 binReserve0, uint112 binReserve1) = pair.getBin(ID_ONE);

        LBPair.PairInformation memory pair = pair.pairInformation();

        console2.log("fees total", pair.fees1.total);

        assertEq(binReserve0, tokenAmount - amount0Out, "binReserve0");
        assertEq(binReserve1, amount1In - pair.fees1.total, "binReserve1");
    }

    function testSwapXToYSingleBin() public {
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
        pair.swap(0, amount1Out, DEV);

        assertEq(token6D.balanceOf(DEV), 0);
        assertEq(token18D.balanceOf(DEV), amount1Out);

        (, uint112 binReserve0, uint112 binReserve1) = pair.getBin(ID_ONE);

        LBPair.PairInformation memory pair = pair.pairInformation();

        assertApproxEqRel(binReserve0, amount0In - pair.fees0.total, 1e14);
        assertEq(binReserve1, tokenAmount - amount1Out);
    }

    function testSwapYtoXMultipleBin() public {
        uint112 tokenAmount = 100e6;
        token6D.mint(address(pair), tokenAmount);

        uint24 startId = ID_ONE;

        uint24 nb = 10;

        uint256[] memory _ids = new uint256[](nb + 1);
        uint256[] memory _liquidities = new uint256[](nb + 1);

        _ids[0] = startId;
        _liquidities[0] = 0;
        for (uint256 i; i < nb; i++) {
            _ids[i + 1] = startId + i + 1;
            _liquidities[i + 1] = tokenAmount / nb;
        }

        pair.mint(_ids, _liquidities, DEV);

        uint256 amount0Out = tokenAmount;

        token18D.mint(address(pair), 200e6);

        vm.prank(DEV);
        pair.swap(amount0Out, 0, DEV);

        assertEq(token6D.balanceOf(DEV), amount0Out);

        LBPair.PairInformation memory pairInformation = pair.pairInformation();

        assertEq(pairInformation.reserve0, 0);
    }

    function testSwapXtoYMultipleBin() public {
        uint112 tokenAmount = 100e12;
        token18D.mint(address(pair), tokenAmount);

        uint24 startId = ID_ONE;

        uint24 nb = 10;

        uint256[] memory _ids = new uint256[](nb + 1);
        uint256[] memory _liquidities = new uint256[](nb + 1);

        _ids[0] = startId;
        _liquidities[0] = 0;
        for (uint256 i; i < nb; i++) {
            _ids[i + 1] = startId - i - 1;
            _liquidities[i + 1] = tokenAmount / nb;
        }

        pair.mint(_ids, _liquidities, DEV);

        uint256 amount1Out = tokenAmount;

        token6D.mint(address(pair), 200e12);

        vm.prank(DEV);
        pair.swap(0, amount1Out, DEV);

        assertEq(token18D.balanceOf(DEV), amount1Out);

        LBPair.PairInformation memory pairInformation = pair.pairInformation();

        assertEq(pairInformation.reserve1, 0);
    }

    function testSwapYtoXDistantBins() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 50e18;
        uint24 startId = ID_ONE;

        (
            uint256[] memory _ids,
            uint256[] memory _liquidities,
            uint256 amountXIn
        ) = spreadLiquidityN(amountYInLiquidity * 2, startId, 9, 100);

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
        pair.swap(amountXOutForSwap, 0, ALICE);

        assertEq(token6D.balanceOf(ALICE), amountXOutForSwap);
    }

    function testSwapXtoYDistantBins() public {
        uint256 amountXInLiquidity = 100e6;
        uint256 amountYOutForSwap = 50e6;
        uint24 startId = ID_ONE;

        (
            uint256[] memory _ids,
            uint256[] memory _liquidities,
            uint256 amountYIn
        ) = spreadLiquidityN(amountXInLiquidity * 2, startId, 9, 100);

        token6D.mint(address(pair), amountYIn);
        token18D.mint(address(pair), amountXInLiquidity);

        pair.mint(_ids, _liquidities, DEV);

        (uint256 amountXInForSwap, ) = router.getSwapIn(
            pair,
            0,
            amountYOutForSwap
        );

        token6D.mint(address(pair), amountXInForSwap);
        vm.prank(ALICE);
        pair.swap(0, amountYOutForSwap, ALICE);

        assertEq(token18D.balanceOf(ALICE), amountYOutForSwap);
    }
}
