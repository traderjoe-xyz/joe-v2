// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "test/helpers/TestHelper.sol";
import {Addresses} from "test/integration/Addresses.sol";

contract LiquidityBinRouterTest is TestHelper {
    function setUp() public override {
        super.setUp();
    }

    function testConstructor() public {
        assertEq(address(router.factory()), address(factory));
        assertEq(address(router.oldFactory()), Addresses.JOE_V1_FACTORY_ADDRESS);
        assertEq(address(router.wavax()), Addresses.WAVAX_AVALANCHE_ADDRESS);
    }

    function testCreateLBPair() public {
        factory.setFactoryLockedState(false);

        router.createLBPair(usdc, weth, ID_ONE, DEFAULT_BIN_STEP);

        assertEq(factory.getNumberOfLBPairs(), 1);
        pair = LBPair(address(factory.getLBPairInformation(usdc, weth, DEFAULT_BIN_STEP).LBPair));

        assertEq(address(pair.factory()), address(factory));
        assertEq(address(pair.tokenX()), address(usdc));
        assertEq(address(pair.tokenY()), address(weth));

        FeeHelper.FeeParameters memory feeParameters = pair.feeParameters();
        assertEq(feeParameters.volatilityAccumulated, 0);
        assertEq(feeParameters.time, 0);
        assertEq(feeParameters.maxVolatilityAccumulated, DEFAULT_MAX_VOLATILITY_ACCUMULATED);
        assertEq(feeParameters.filterPeriod, DEFAULT_FILTER_PERIOD);
        assertEq(feeParameters.decayPeriod, DEFAULT_DECAY_PERIOD);
        assertEq(feeParameters.binStep, DEFAULT_BIN_STEP);
        assertEq(feeParameters.baseFactor, DEFAULT_BASE_FACTOR);
        assertEq(feeParameters.protocolShare, DEFAULT_PROTOCOL_SHARE);
    }

    function testModifierEnsure() public {
        uint256[] memory defaultUintArray = new uint256[](2);
        IERC20[] memory defaultIERCArray = new IERC20[](2);

        uint256 wrongDeadline = block.timestamp - 1;

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.removeLiquidity(
            usdc, weth, DEFAULT_BIN_STEP, 1, 1, defaultUintArray, defaultUintArray, DEV, wrongDeadline
        );

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.removeLiquidityAVAX(usdc, DEFAULT_BIN_STEP, 1, 1, defaultUintArray, defaultUintArray, DEV, wrongDeadline);
        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.swapExactTokensForTokens(1, 1, defaultUintArray, defaultIERCArray, DEV, wrongDeadline);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.swapExactTokensForAVAX(1, 1, defaultUintArray, defaultIERCArray, DEV, wrongDeadline);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.swapExactAVAXForTokens(1, defaultUintArray, defaultIERCArray, DEV, wrongDeadline);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.swapTokensForExactTokens(1, 1, defaultUintArray, defaultIERCArray, DEV, wrongDeadline);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.swapTokensForExactAVAX(1, 1, defaultUintArray, defaultIERCArray, DEV, wrongDeadline);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.swapAVAXForExactTokens(1, defaultUintArray, defaultIERCArray, DEV, wrongDeadline);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            1, 1, defaultUintArray, defaultIERCArray, DEV, wrongDeadline
        );

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            1, 1, defaultUintArray, defaultIERCArray, DEV, wrongDeadline
        );

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens(
            1, defaultUintArray, defaultIERCArray, DEV, wrongDeadline
        );

        // _addLiquidity private
    }

    function testModifieronlyFactoryOwner() public {
        vm.prank(ALICE);
        vm.expectRevert(LBRouter__NotFactoryOwner.selector);
        router.sweep(usdc, address(0), 1);
    }

    function testModifierVerifyInputs() public {
        IERC20[] memory defaultIERCArray = new IERC20[](1);
        uint256[] memory pairBinStepsZeroLength = new uint256[](0);
        IERC20[] memory mismatchedIERCArray = new IERC20[](3);
        uint256[] memory mismatchedpairBinSteps = new uint256[](4);
        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactTokensForTokens(1, 1, pairBinStepsZeroLength, defaultIERCArray, DEV, block.timestamp);
        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactTokensForTokens(1, 1, mismatchedpairBinSteps, mismatchedIERCArray, DEV, block.timestamp);

        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactTokensForAVAX(1, 1, pairBinStepsZeroLength, defaultIERCArray, DEV, block.timestamp);
        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactTokensForAVAX(1, 1, mismatchedpairBinSteps, mismatchedIERCArray, DEV, block.timestamp);

        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactAVAXForTokens(1, pairBinStepsZeroLength, defaultIERCArray, DEV, block.timestamp);
        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactAVAXForTokens(1, mismatchedpairBinSteps, mismatchedIERCArray, DEV, block.timestamp);

        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapTokensForExactTokens(1, 1, pairBinStepsZeroLength, defaultIERCArray, DEV, block.timestamp);
        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapTokensForExactTokens(1, 1, mismatchedpairBinSteps, mismatchedIERCArray, DEV, block.timestamp);

        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapTokensForExactAVAX(1, 1, pairBinStepsZeroLength, defaultIERCArray, DEV, block.timestamp);
        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapTokensForExactAVAX(1, 1, mismatchedpairBinSteps, mismatchedIERCArray, DEV, block.timestamp);

        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapAVAXForExactTokens(1, pairBinStepsZeroLength, defaultIERCArray, DEV, block.timestamp);
        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapAVAXForExactTokens(1, mismatchedpairBinSteps, mismatchedIERCArray, DEV, block.timestamp);

        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            1, 1, pairBinStepsZeroLength, defaultIERCArray, DEV, block.timestamp
        );
        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            1, 1, mismatchedpairBinSteps, mismatchedIERCArray, DEV, block.timestamp
        );

        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            1, 1, pairBinStepsZeroLength, defaultIERCArray, DEV, block.timestamp
        );
        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            1, 1, mismatchedpairBinSteps, mismatchedIERCArray, DEV, block.timestamp
        );

        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens(
            1, pairBinStepsZeroLength, defaultIERCArray, DEV, block.timestamp
        );

        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens(
            1, mismatchedpairBinSteps, mismatchedIERCArray, DEV, block.timestamp
        );
    }

    function testEnsureModifierLiquidity() public {
        uint256 wrongDeadline = block.timestamp - 1;
        uint256 _amountYIn = 1e18;
        uint24 _numberBins = 11;
        uint24 _gap = 2;
        uint16 _binStep = DEFAULT_BIN_STEP;
        int256[] memory _deltaIds;
        uint256[] memory _distributionX;
        uint256[] memory _distributionY;
        uint256 amountXIn;
        factory.setFactoryLockedState(false);
        router.createLBPair(usdc, weth, ID_ONE, DEFAULT_BIN_STEP);
        router.createLBPair(usdc, wavax, ID_ONE, DEFAULT_BIN_STEP);

        (_deltaIds, _distributionX, _distributionY, amountXIn) =
            spreadLiquidityForRouter(_amountYIn, ID_ONE, _numberBins, _gap);

        usdc.mint(DEV, amountXIn);
        usdc.approve(address(router), amountXIn);
        weth.mint(DEV, _amountYIn);
        weth.approve(address(router), _amountYIn);

        ILBRouter.LiquidityParameters memory _liquidityParameters = ILBRouter.LiquidityParameters(
            usdc,
            weth,
            _binStep,
            amountXIn,
            _amountYIn,
            0,
            0,
            ID_ONE,
            ID_ONE,
            _deltaIds,
            _distributionX,
            _distributionY,
            DEV,
            wrongDeadline
        );

        vm.expectRevert(abi.encodeWithSelector(LBRouter__DeadlineExceeded.selector, wrongDeadline, block.timestamp));
        router.addLiquidity(_liquidityParameters);
    }

    function testGetPriceFromId() public {
        pair = createLBPairDefaultFees(usdc, weth);
        uint256 price;

        price = router.getPriceFromId(pair, ID_ONE);
        assertEq(price, 340282366920938463463374607431768211456);

        price = router.getPriceFromId(pair, ID_ONE - 10000);
        assertEq(price, 4875582648561453899431769403);

        price = router.getPriceFromId(pair, ID_ONE + 10000);
        assertEq(price, 23749384962529715407923990466761537977856189636583);
    }

    function testGetIdFromPrice() public {
        pair = createLBPairDefaultFees(usdc, weth);
        uint24 id;

        id = router.getIdFromPrice(pair, 340282366920938463463374607431768211456);
        assertEq(id, ID_ONE);

        id = router.getIdFromPrice(pair, 4875582648561453899431769403);
        assertEq(id, ID_ONE - 10000);

        id = router.getIdFromPrice(pair, 23749384962529715407923990466761537977856189636583);
        assertEq(id, ID_ONE + 10000);
    }

    function testGetSwapInWrongAmountsReverts() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;
        uint256 amountXIn;
        int256[] memory _deltaIds;
        pair = createLBPairDefaultFees(usdc, weth);
        (_deltaIds,,, amountXIn) =
            addLiquidityFromRouter(usdc, weth, _amountYIn, _startId, _numberBins, _gap, DEFAULT_BIN_STEP);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__WrongAmounts.selector, 0, _amountYIn));
        router.getSwapIn(pair, 0, true);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__WrongAmounts.selector, _amountYIn + 1, _amountYIn));
        router.getSwapIn(pair, _amountYIn + 1, true);

        uint256[] memory amounts = new uint256[](_numberBins);
        uint256[] memory ids = new uint256[](_numberBins);
        uint256 totalXbalance;
        uint256 totalYBalance;
        for (uint256 i; i < _numberBins; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            uint256 LBTokenAmount = pair.balanceOf(DEV, ids[i]);
            amounts[i] = LBTokenAmount;
            (uint256 reserveX, uint256 reserveY) = pair.getBin(uint24(ids[i]));
            bool hasXBalanceInBin = (LBTokenAmount != 0) && (reserveX != 0);
            bool hasYBalanceInBin = (LBTokenAmount != 0) && (reserveY != 0);
            totalXbalance += hasXBalanceInBin ? (LBTokenAmount * reserveX - 1) / pair.totalSupply(ids[i]) + 1 : 0;
            totalYBalance += hasYBalanceInBin ? (LBTokenAmount * reserveY - 1) / pair.totalSupply(ids[i]) + 1 : 0;
        }
        assertApproxEqAbs(totalXbalance, amountXIn, 1000);
        assertApproxEqAbs(totalYBalance, _amountYIn, 1000);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__WrongAmounts.selector, amountXIn + 1, totalXbalance));
        router.getSwapIn(pair, amountXIn + 1, false);
    }

    function testGetSwapInOverflowReverts() public {
        uint256 _amountYIn = type(uint112).max - 1;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 1;
        uint24 _gap = 2;
        uint256 amountXIn;
        pair = createLBPairDefaultFees(usdc, weth);
        (,,, amountXIn) = addLiquidity(_amountYIn, _startId, _numberBins, _gap);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__SwapOverflows.selector, _startId));
        router.getSwapIn(pair, _amountYIn, true);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__SwapOverflows.selector, _startId));
        router.getSwapIn(pair, amountXIn, false);
    }

    function testSweep() public {
        uint256 amountMinted = 100e6;
        usdc.mint(address(router), amountMinted);
        router.sweep(usdc, ALICE, amountMinted);
        assertEq(usdc.balanceOf(ALICE), amountMinted);
        assertEq(usdc.balanceOf(address(router)), 0);

        uint256 amountAvax = 10e18;
        vm.deal(address(router), amountAvax);
        router.sweep(IERC20(address(0)), ALICE, amountAvax);
        assertEq(ALICE.balance, amountAvax);
        assertEq(address(router).balance, 0);
    }

    function testSweepMax() public {
        uint256 amountMinted = 1000e6;
        usdc.mint(address(router), amountMinted);
        router.sweep(usdc, ALICE, type(uint256).max);
        assertEq(usdc.balanceOf(ALICE), amountMinted);
        assertEq(usdc.balanceOf(address(router)), 0);

        uint256 amountAvax = 100e18;
        vm.deal(address(router), amountAvax);
        router.sweep(IERC20(address(0)), ALICE, type(uint256).max);
        assertEq(ALICE.balance, amountAvax);
        assertEq(address(router).balance, 0);
    }

    function testGetSwapInMoreBins() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;
        uint256 amountXIn;
        pair = createLBPairDefaultFees(usdc, weth);
        (,,, amountXIn) = addLiquidity(_amountYIn, _startId, _numberBins, _gap);
        //getSwapIn goes through all bins with liquidity
        (uint256 amountIn,) = router.getSwapIn(pair, amountXIn - 100, false);
        (uint256 amountIn2,) = router.getSwapIn(pair, _amountYIn - 100, true);
    }

    function testWrongTokenWAVAXSwaps() public {
        IERC20[] memory IERCArray = new IERC20[](2);
        IERCArray[0] = usdc;
        IERCArray[1] = weth;
        uint256[] memory pairBinStepsArray = new uint256[](1);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, address(IERCArray[1])));
        router.swapExactTokensForAVAX(1, 1, pairBinStepsArray, IERCArray, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, address(IERCArray[0])));
        router.swapExactAVAXForTokens(1, pairBinStepsArray, IERCArray, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, address(IERCArray[1])));
        router.swapTokensForExactAVAX(1, 1, pairBinStepsArray, IERCArray, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, address(IERCArray[0])));
        router.swapAVAXForExactTokens(1, pairBinStepsArray, IERCArray, DEV, block.timestamp);

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, address(IERCArray[1])));
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            1, 1, pairBinStepsArray, IERCArray, DEV, block.timestamp
        );

        vm.expectRevert(abi.encodeWithSelector(LBRouter__InvalidTokenPath.selector, address(IERCArray[0])));
        router.swapExactAVAXForTokensSupportingFeeOnTransferTokens(
            1, pairBinStepsArray, IERCArray, DEV, block.timestamp
        );
    }

    function testSweepLBToken() public {
        uint256 amountIn = 1e18;

        pair = createLBPairDefaultFees(usdc, weth);
        (uint256[] memory _ids,,,) = addLiquidity(amountIn, ID_ONE, 5, 0);

        uint256[] memory amounts = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            amounts[i] = pair.balanceOf(DEV, _ids[i]);
        }

        assertEq(pair.balanceOf(DEV, ID_ONE - 1), amountIn / 3);

        pair.safeBatchTransferFrom(DEV, address(router), _ids, amounts);

        for (uint256 i; i < 5; i++) {
            assertEq(pair.balanceOf(address(router), _ids[i]), amounts[i]);
            assertEq(pair.balanceOf(DEV, _ids[i]), 0);
        }
        vm.prank(ALICE);
        vm.expectRevert(LBRouter__NotFactoryOwner.selector);
        router.sweepLBToken(pair, DEV, _ids, amounts);

        router.sweepLBToken(pair, DEV, _ids, amounts);

        for (uint256 i; i < 5; i++) {
            assertEq(pair.balanceOf(DEV, _ids[i]), amounts[i]);
            assertEq(pair.balanceOf(address(router), _ids[i]), 0);
        }
    }
}
