// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "test/helpers/TestHelper.sol";

contract LiquidityBinPairSwapsTest is TestHelper {
    function setUp() public override {
        usdc = new ERC20Mock(6);
        weth = new ERC20Mock(18);

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
        addAllAssetsToQuoteWhitelist(factory);
        router = new LBRouter(ILBFactory(DEV), IJoeFactory(DEV), IWAVAX(DEV));

        pair = createLBPairDefaultFees(usdc, weth);
    }

    function testSwapInsufficientAmountReverts() public {
        vm.expectRevert(LBPair__InsufficientAmounts.selector);
        pair.swap(true, DEV);
        vm.expectRevert(LBPair__InsufficientAmounts.selector);
        pair.swap(false, DEV);
    }

    function testSwapXtoYSingleBinFromGetSwapOut() public {
        uint256 tokenAmount = 100e18;
        weth.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](1);
        _ids[0] = ID_ONE;

        uint256[] memory _liquidities = new uint256[](1);
        _liquidities[0] = Constants.PRECISION;

        pair.mint(_ids, new uint256[](1), _liquidities, DEV);

        uint256 amountXIn = 1e12;

        (uint256 amountYOut,) = router.getSwapOut(pair, amountXIn, true);

        usdc.mint(address(pair), amountXIn);

        pair.swap(true, DEV);

        assertEq(usdc.balanceOf(DEV), 0);
        assertEq(weth.balanceOf(DEV), amountYOut);

        (uint256 binReserveX, uint256 binReserveY) = pair.getBin(ID_ONE);

        (uint256 feesXTotal,,,) = pair.getGlobalFees();

        assertEq(binReserveX, amountXIn - feesXTotal);
        assertEq(binReserveY, tokenAmount - amountYOut);
    }

    function testSwapYtoXSingleBinFromGetSwapOut() public {
        uint256 tokenAmount = 100e18;
        usdc.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](1);
        _ids[0] = ID_ONE;

        // uint256 price = router.getPriceFromId(pair, uint24(_ids[0]));

        uint256[] memory _liquidities = new uint256[](1);
        _liquidities[0] = Constants.PRECISION;

        pair.mint(_ids, _liquidities, new uint256[](1), DEV);

        uint256 amountYIn = 1e12;

        (uint256 amountXOut,) = router.getSwapOut(pair, amountYIn, false);

        weth.mint(address(pair), amountYIn);

        pair.swap(false, DEV);

        assertEq(usdc.balanceOf(DEV), amountXOut);
        assertEq(weth.balanceOf(DEV), 0);

        (uint256 binReserveX, uint256 binReserveY) = pair.getBin(uint24(_ids[0]));

        (, uint256 feesYTotal,,) = pair.getGlobalFees();

        assertEq(binReserveX, tokenAmount - amountXOut);
        assertEq(binReserveY, amountYIn - feesYTotal);
    }

    function testSwapXtoYSingleBinFromGetSwapIn() public {
        uint256 tokenAmount = 100e18;
        weth.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](1);
        _ids[0] = ID_ONE;

        uint256[] memory _liquidities = new uint256[](1);
        _liquidities[0] = Constants.PRECISION;

        pair.mint(_ids, new uint256[](1), _liquidities, DEV);

        uint256 amountYOut = 1e12;

        (uint256 amountXIn,) = router.getSwapIn(pair, amountYOut, true);

        usdc.mint(address(pair), amountXIn);

        pair.swap(true, DEV);

        assertEq(usdc.balanceOf(DEV), 0);
        assertEq(weth.balanceOf(DEV), amountYOut);

        (uint256 binReserveX, uint256 binReserveY) = pair.getBin(ID_ONE);

        (uint256 feesXTotal,,,) = pair.getGlobalFees();

        assertEq(binReserveX, amountXIn - feesXTotal);
        assertEq(binReserveY, tokenAmount - amountYOut);
    }

    function testSwapYtoXSingleBinFromGetSwapIn() public {
        uint256 tokenAmount = 100e18;
        usdc.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](1);
        _ids[0] = ID_ONE + 1;

        uint256[] memory _liquidities = new uint256[](1);
        _liquidities[0] = Constants.PRECISION;

        pair.mint(_ids, _liquidities, new uint256[](1), DEV);

        uint256 amountXOut = 1e12;

        (uint256 amountYIn,) = router.getSwapIn(pair, amountXOut, false);

        weth.mint(address(pair), amountYIn);

        pair.swap(false, DEV);

        assertEq(usdc.balanceOf(DEV), amountXOut);
        assertEq(weth.balanceOf(DEV), 0);

        (uint256 binReserveX, uint256 binReserveY) = pair.getBin(uint24(_ids[0]));

        (, uint256 feesYTotal,,) = pair.getGlobalFees();

        assertEq(binReserveX, tokenAmount - amountXOut);
        assertEq(binReserveY, amountYIn - feesYTotal);
    }

    function testSwapYtoXConsecutiveBinFromGetSwapIn() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 0);

        (uint256 amountYInForSwap,) = router.getSwapIn(pair, amountXOutForSwap, false);

        weth.mint(address(pair), amountYInForSwap);

        pair.swap(false, ALICE);

        assertEq(usdc.balanceOf(ALICE), amountXOutForSwap);
    }

    function testSwapXtoYConsecutiveBinFromGetSwapIn() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 0);

        (uint256 amountXInForSwap,) = router.getSwapIn(pair, amountYOutForSwap, true);

        usdc.mint(address(pair), amountXInForSwap);

        pair.swap(true, ALICE);

        assertEq(weth.balanceOf(ALICE), amountYOutForSwap);
    }

    function testSwapYtoXConsecutiveBinFromGetSwapOut() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYInForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 0);

        (uint256 amountXOutForSwap,) = router.getSwapOut(pair, amountYInForSwap, false);

        weth.mint(address(pair), amountYInForSwap);

        pair.swap(false, ALICE);

        assertEq(usdc.balanceOf(ALICE), amountXOutForSwap);
    }

    function testSwapXtoYConsecutiveBinFromGetSwapOut() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXInForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 0);

        (uint256 amountYOutForSwap,) = router.getSwapOut(pair, amountXInForSwap, true);

        usdc.mint(address(pair), amountXInForSwap);

        pair.swap(true, ALICE);

        assertEq(weth.balanceOf(ALICE), amountYOutForSwap);
    }

    function testSwapYtoXDistantBinsFromGetSwapIn() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 100);

        (uint256 amountYInForSwap,) = router.getSwapIn(pair, amountXOutForSwap, false);

        weth.mint(address(pair), amountYInForSwap);

        pair.swap(false, ALICE);

        assertEq(usdc.balanceOf(ALICE), amountXOutForSwap);
    }

    function testSwapXtoYDistantBinsFromGetSwapIn() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYOutForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 100);

        (uint256 amountXInForSwap,) = router.getSwapIn(pair, amountYOutForSwap, true);

        usdc.mint(address(pair), amountXInForSwap);

        pair.swap(true, ALICE);

        assertEq(weth.balanceOf(ALICE), amountYOutForSwap);
    }

    function testSwapYtoXDistantBinsFromGetSwapOut() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountYInForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 100);

        (uint256 amountXOutForSwap,) = router.getSwapOut(pair, amountYInForSwap, false);

        weth.mint(address(pair), amountYInForSwap);

        pair.swap(false, ALICE);

        assertEq(usdc.balanceOf(ALICE), amountXOutForSwap);
    }

    function testSwapXtoYDistantBinsFromGetSwapOut() public {
        uint256 amountYInLiquidity = 100e18;
        uint256 amountXInForSwap = 30e18;
        uint24 startId = ID_ONE;

        addLiquidity(amountYInLiquidity, startId, 9, 100);

        (uint256 amountYOutForSwap,) = router.getSwapOut(pair, amountXInForSwap, true);

        usdc.mint(address(pair), amountXInForSwap);

        pair.swap(true, ALICE);

        assertEq(weth.balanceOf(ALICE), amountYOutForSwap);
    }

    function testInvalidTokenPathReverts() public {
        uint256 _amountIn = 10e18;
        uint256 _amountOutMinAVAX = 10e18;
        uint256[] memory _pairBinSteps = new uint256[](1);
        IERC20[] memory _tokenPath = new IERC20[](2);
        _tokenPath[0] = usdc;
        _tokenPath[1] = weth;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, _tokenPath[1]));
        router.swapExactTokensForAVAX(_amountIn, _amountOutMinAVAX, _pairBinSteps, _tokenPath, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, _tokenPath[1]));
        router.swapTokensForExactAVAX(_amountIn, _amountOutMinAVAX, _pairBinSteps, _tokenPath, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, _tokenPath[1]));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            _amountIn, _amountOutMinAVAX, _pairBinSteps, _tokenPath, DEV, block.timestamp
        );

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, _tokenPath[0]));
        router.swapAVAXForExactTokens(_amountIn, _pairBinSteps, _tokenPath, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, _tokenPath[0]));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens(
            _amountIn, _pairBinSteps, _tokenPath, DEV, block.timestamp
        );
    }
}
