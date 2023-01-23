// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "test/helpers/TestHelper.sol";

contract LiquidityBinRouterTest is TestHelper {
    event AVAXreceived();

    function setUp() public override {
        usdc = new ERC20Mock(6);
        weth = new ERC20Mock(18);
        wavax = new WAVAX();
        uint16 binStep = 100;
        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        factory.setPreset(
            binStep,
            uint16(Constants.BASIS_POINT_MAX),
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED / 6,
            DEFAULT_SAMPLE_LIFETIME
        );

        router = new LBRouter(factory, IJoeFactory(address(0)), IWAVAX(address(wavax)));

        pair = LBPair(address(factory.createLBPair(usdc, weth, ID_ONE, 100)));
    }

    function testFeeOnActiveBin() public {
        //setup pool with only Y liquidity
        uint16 binStep = 100;
        uint256 _amountYIn = 100e18;
        uint24 _numberBins = 1;
        int256[] memory _deltaIds;
        uint256[] memory _distributionX;
        uint256[] memory _distributionY;
        _deltaIds = new int256[](_numberBins);
        _distributionX = new uint256[](_numberBins);
        _distributionY = new uint256[](_numberBins);
        _deltaIds[0] = 0;
        _distributionX[0] = 0;
        _distributionY[0] = Constants.PRECISION;

        vm.prank(BOB);
        weth.approve(address(router), _amountYIn);

        weth.mint(BOB, _amountYIn);

        ILBRouter.LiquidityParameters memory _liquidityParameters = ILBRouter.LiquidityParameters(
            usdc,
            weth,
            binStep,
            0,
            _amountYIn,
            0,
            _amountYIn,
            ID_ONE,
            ID_ONE,
            _deltaIds,
            _distributionX,
            _distributionY,
            BOB,
            block.timestamp
        );
        vm.prank(BOB);
        router.addLiquidity(_liquidityParameters);

        //setup liquidity add with only tokenX
        uint256 amountXIn = 100e18;
        _distributionX[0] = Constants.PRECISION;
        _distributionY[0] = 0;

        usdc.mint(ALICE, amountXIn);
        vm.prank(ALICE);
        usdc.approve(address(router), amountXIn);

        uint256 feesXTotal;
        (feesXTotal,,,) = pair.getGlobalFees();
        assertEq(feesXTotal, 0);

        _liquidityParameters = ILBRouter.LiquidityParameters(
            usdc,
            weth,
            binStep,
            amountXIn,
            0,
            0,
            0,
            ID_ONE,
            ID_ONE,
            _deltaIds,
            _distributionX,
            _distributionY,
            ALICE,
            block.timestamp
        );

        vm.prank(ALICE);
        router.addLiquidity(_liquidityParameters);

        uint256[] memory amounts = new uint256[](_numberBins);
        uint256[] memory ids = new uint256[](_numberBins);
        for (uint256 i; i < _numberBins; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            amounts[i] = pair.balanceOf(ALICE, ids[i]);
        }

        vm.prank(ALICE);
        pair.setApprovalForAll(address(router), true);
        vm.prank(ALICE);
        router.removeLiquidity(usdc, weth, binStep, 0, 0, ids, amounts, ALICE, block.timestamp);

        (feesXTotal,,,) = pair.getGlobalFees();
        assertGt(feesXTotal, amountXIn / 199);

        //remove BOB's liquidity to ALICE account
        for (uint256 i; i < _numberBins; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            amounts[i] = pair.balanceOf(BOB, ids[i]);
        }
        vm.prank(BOB);
        pair.setApprovalForAll(address(router), true);
        vm.prank(BOB);
        router.removeLiquidity(usdc, weth, binStep, 0, 0, ids, amounts, ALICE, block.timestamp);

        uint256 ALICE6DbalanceAfterSecondRemove = usdc.balanceOf(ALICE);

        assertEq(ALICE6DbalanceAfterSecondRemove + feesXTotal, amountXIn);
    }

    function testFeeOnActiveBinReverse() public {
        //setup pool with only X liquidity
        uint16 binStep = 100;
        uint256 _amountXIn = 100e18;
        uint24 _numberBins = 1;
        int256[] memory _deltaIds;
        uint256[] memory _distributionX;
        uint256[] memory _distributionY;
        _deltaIds = new int256[](_numberBins);
        _distributionX = new uint256[](_numberBins);
        _distributionY = new uint256[](_numberBins);
        _deltaIds[0] = 0;
        _distributionX[0] = Constants.PRECISION;
        _distributionY[0] = 0;

        vm.prank(BOB);
        usdc.approve(address(router), _amountXIn);

        usdc.mint(BOB, _amountXIn);

        ILBRouter.LiquidityParameters memory _liquidityParameters = ILBRouter.LiquidityParameters(
            usdc,
            weth,
            binStep,
            _amountXIn,
            0,
            _amountXIn,
            0,
            ID_ONE,
            ID_ONE,
            _deltaIds,
            _distributionX,
            _distributionY,
            BOB,
            block.timestamp
        );
        vm.prank(BOB);
        router.addLiquidity(_liquidityParameters);

        //setup liquidity add with only tokenX
        uint256 amountYIn = 100e18;
        _distributionX[0] = 0;
        _distributionY[0] = Constants.PRECISION;

        weth.mint(ALICE, amountYIn);
        vm.prank(ALICE);
        weth.approve(address(router), amountYIn);

        uint256 feesYTotal;
        (, feesYTotal,,) = pair.getGlobalFees();
        assertEq(feesYTotal, 0);

        _liquidityParameters = ILBRouter.LiquidityParameters(
            usdc,
            weth,
            binStep,
            0,
            amountYIn,
            0,
            0,
            ID_ONE,
            ID_ONE,
            _deltaIds,
            _distributionX,
            _distributionY,
            ALICE,
            block.timestamp
        );

        vm.prank(ALICE);
        router.addLiquidity(_liquidityParameters);

        uint256[] memory amounts = new uint256[](_numberBins);
        uint256[] memory ids = new uint256[](_numberBins);
        for (uint256 i; i < _numberBins; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            amounts[i] = pair.balanceOf(ALICE, ids[i]);
        }

        vm.prank(ALICE);
        pair.setApprovalForAll(address(router), true);
        vm.prank(ALICE);
        router.removeLiquidity(usdc, weth, binStep, 0, 0, ids, amounts, ALICE, block.timestamp);

        //remove BOB's liquidity to ALICE account
        for (uint256 i; i < _numberBins; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            amounts[i] = pair.balanceOf(BOB, ids[i]);
        }
        vm.prank(BOB);
        pair.setApprovalForAll(address(router), true);
        vm.prank(BOB);
        router.removeLiquidity(usdc, weth, binStep, 0, 0, ids, amounts, ALICE, block.timestamp);

        uint256 ALICE6DbalanceAfterSecondRemove = weth.balanceOf(ALICE);

        (, feesYTotal,,) = pair.getGlobalFees();
        assertGt(feesYTotal, amountYIn / 199);
        assertEq(ALICE6DbalanceAfterSecondRemove + feesYTotal, amountYIn);
    }
}
