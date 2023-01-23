// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "test/helpers/TestHelper.sol";

import {Addresses} from "./Addresses.sol";

contract LiquidityBinRouterForkTest is TestHelper {
    LBPair internal pair0;
    LBPair internal pair1;
    LBPair internal pair2;
    LBPair internal pair3;
    LBPair internal taxTokenPair;

    function setUp() public override {
        vm.createSelectFork(vm.rpcUrl("avalanche"), 19_358_000);
        super.setUp();
        // usdc = new ERC20Mock(6);
        // link = new ERC20Mock(10);
        // wbtc = new ERC20Mock(12);
        // weth = new ERC20Mock(18);
        // wbtc = new ERC20Mock(24);

        // taxToken = new ERC20TransferTaxMock();

        wavax = WAVAX(Addresses.WAVAX_AVALANCHE_ADDRESS);
        usdc = ERC20Mock(Addresses.USDC_AVALANCHE_ADDRESS);

        // factory = new LBFactory(DEV, 8e14);
        factory.addQuoteAsset(IERC20(address(wavax)));
        factory.addQuoteAsset(IERC20(address(usdc)));
        // ILBPair _LBPairImplementation = new LBPair(factory);
        // factory.setLBPairImplementation(address(_LBPairImplementation));
        // addAllAssetsToQuoteWhitelist(factory);
        // setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        router = new LBRouter(factory, IJoeFactory(Addresses.JOE_V1_FACTORY_ADDRESS), IWAVAX(address(wavax)));

        pair = createLBPairDefaultFees(usdc, weth);
        addLiquidityFromRouter(usdc, weth, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);

        pair0 = createLBPairDefaultFees(usdc, link);
        addLiquidityFromRouter(usdc, link, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair1 = createLBPairDefaultFees(link, wbtc);
        addLiquidityFromRouter(link, wbtc, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair2 = createLBPairDefaultFees(wbtc, weth);
        addLiquidityFromRouter(wbtc, weth, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
        pair3 = createLBPairDefaultFees(weth, bnb);
        addLiquidityFromRouter(weth, bnb, 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);

        taxTokenPair = createLBPairDefaultFees(taxToken, wavax);
        addLiquidityFromRouter(
            ERC20Mock(address(taxToken)), ERC20Mock(address(wavax)), 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP
        );

        pairWavax = createLBPairDefaultFees(usdc, wavax);
        addLiquidityFromRouter(usdc, ERC20Mock(address(wavax)), 100e18, ID_ONE, 9, 2, DEFAULT_BIN_STEP);
    }

    function testSwapExactTokensForTokensMultiplePairsWithV1() public {
        if (block.number < 1000) {
            console.log("fork mainnet for V1 testing support");
            return;
        }

        uint256 amountIn = 1e18;

        deal(address(usdc), DEV, amountIn);

        usdc.approve(address(router), amountIn);

        IERC20[] memory tokenList;
        uint256[] memory pairVersions;

        tokenList = new IERC20[](3);
        tokenList[0] = usdc;
        tokenList[1] = wavax;
        tokenList[2] = usdc;

        pairVersions = new uint256[](2);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = 0;

        router.swapExactTokensForTokens(amountIn, 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(usdc.balanceOf(DEV), 0);

        tokenList[0] = usdc;
        tokenList[1] = wavax;
        tokenList[2] = usdc;

        pairVersions[0] = 0;
        pairVersions[1] = DEFAULT_BIN_STEP;

        uint256 balanceBefore = usdc.balanceOf(DEV);

        usdc.approve(address(router), usdc.balanceOf(DEV));
        router.swapExactTokensForTokens(usdc.balanceOf(DEV), 0, pairVersions, tokenList, DEV, block.timestamp);

        assertGt(usdc.balanceOf(DEV) - balanceBefore, 0);
    }

    function testSwapTokensForExactTokensMultiplePairsWithV1() public {
        if (block.number < 1000) {
            console.log("fork mainnet for V1 testing support");
            return;
        }

        uint256 amountOut = 1e6;

        deal(address(usdc), DEV, 1e6);

        usdc.approve(address(router), 100e18);

        IERC20[] memory tokenList;
        uint256[] memory pairVersions;

        tokenList = new IERC20[](3);
        tokenList[0] = usdc;
        tokenList[1] = wavax;
        tokenList[2] = usdc;

        pairVersions = new uint256[](2);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = 0;

        router.swapTokensForExactTokens(amountOut, 100e18, pairVersions, tokenList, DEV, block.timestamp);

        assertEq(usdc.balanceOf(DEV), amountOut);

        tokenList[0] = usdc;
        tokenList[1] = wavax;
        tokenList[2] = usdc;

        pairVersions[0] = 0;
        pairVersions[1] = DEFAULT_BIN_STEP;

        uint256 balanceBefore = usdc.balanceOf(DEV);

        usdc.approve(address(router), usdc.balanceOf(DEV));
        router.swapTokensForExactTokens(amountOut, usdc.balanceOf(DEV), pairVersions, tokenList, DEV, block.timestamp);

        assertEq(usdc.balanceOf(DEV) - balanceBefore, amountOut);

        vm.stopPrank();
    }

    function testTaxTokenSwappedOnV1Pairs() public {
        if (block.number < 1000) {
            console.log("fork mainnet for V1 testing support");
            return;
        }
        uint256 amountIn = 100e18;

        IJoeFactory factoryv1 = IJoeFactory(Addresses.JOE_V1_FACTORY_ADDRESS);
        //create taxToken-AVAX pair in DEXv1
        address taxPairv11 = factoryv1.createPair(address(taxToken), address(wavax));
        taxToken.mint(taxPairv11, amountIn);
        vm.deal(DEV, amountIn);
        wavax.deposit{value: amountIn}();
        wavax.transfer(taxPairv11, amountIn);
        IJoePair(taxPairv11).mint(DEV);

        //create taxToken-usdc pair in DEXv1
        address taxPairv12 = factoryv1.createPair(address(taxToken), address(usdc));
        taxToken.mint(taxPairv12, amountIn);
        usdc.mint(taxPairv12, amountIn);
        IJoePair(taxPairv12).mint(DEV);

        usdc.mint(DEV, amountIn);
        usdc.approve(address(router), amountIn);

        IERC20[] memory tokenList;
        uint256[] memory pairVersions;

        tokenList = new IERC20[](3);
        tokenList[0] = usdc;
        tokenList[1] = taxToken;
        tokenList[2] = wavax;

        pairVersions = new uint256[](2);
        pairVersions[0] = 0;
        pairVersions[1] = 0;
        uint256 amountIn2 = 1e18;

        vm.expectRevert("Joe: K");
        router.swapExactTokensForTokens(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp
        );
        vm.deal(DEV, amountIn2);
        vm.expectRevert("Joe: K");
        router.swapExactTokensForAVAX(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp
        );

        tokenList[0] = wavax;
        tokenList[1] = taxToken;
        tokenList[2] = usdc;

        vm.deal(DEV, amountIn2);
        vm.expectRevert("Joe: K");
        router.swapExactAVAXForTokens{value: amountIn2}(0, pairVersions, tokenList, DEV, block.timestamp);
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn2}(
            0, pairVersions, tokenList, DEV, block.timestamp
        );
    }

    function testSwappingOnNotExistingV1PairReverts() public {
        IERC20[] memory tokenListAvaxIn;
        IERC20[] memory tokenList;
        uint256[] memory pairVersions;

        uint256 amountIn2 = 1e18;
        vm.deal(DEV, amountIn2);

        tokenList = new IERC20[](3);
        tokenList[0] = usdc;
        tokenList[1] = weth;
        tokenList[2] = wavax;

        pairVersions = new uint256[](2);
        pairVersions[0] = DEFAULT_BIN_STEP;
        pairVersions[1] = 0;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapExactTokensForTokens(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapExactTokensForAVAX(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapTokensForExactTokens(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapTokensForExactAVAX(amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp
        );

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, weth, wavax, pairVersions[1]));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountIn2, 0, pairVersions, tokenList, DEV, block.timestamp
        );

        tokenListAvaxIn = new IERC20[](3);
        tokenListAvaxIn[0] = wavax;
        tokenListAvaxIn[1] = usdc;
        tokenListAvaxIn[2] = weth;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, usdc, weth, pairVersions[1]));
        router.swapExactAVAXForTokens{value: amountIn2}(0, pairVersions, tokenListAvaxIn, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, usdc, weth, pairVersions[1]));
        router.swapAVAXForExactTokens{value: amountIn2}(0, pairVersions, tokenListAvaxIn, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__PairNotCreated.selector, usdc, weth, pairVersions[1]));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens{value: amountIn2}(
            0, pairVersions, tokenListAvaxIn, DEV, block.timestamp
        );
    }

    receive() external payable {}
}
