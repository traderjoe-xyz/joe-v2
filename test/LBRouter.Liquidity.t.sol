// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract LiquidityBinRouterTest is TestHelper {
    event AVAXreceived();

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);
        wavax = new WAVAX();

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
        addAllAssetsToQuoteWhitelist(factory);
        router = new LBRouter(factory, IJoeFactory(JOE_V1_FACTORY_ADDRESS), IWAVAX(address(wavax)));

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testAddLiquidityNoSlippage() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        (int256[] memory _deltaIds, , , uint256 amountXIn) = addLiquidityFromRouter(
            token6D,
            token18D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

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

        pair.setApprovalForAll(address(router), true);

        router.removeLiquidity(
            token6D,
            token18D,
            DEFAULT_BIN_STEP,
            totalXbalance,
            totalYBalance,
            ids,
            amounts,
            DEV,
            block.timestamp
        );

        assertEq(token6D.balanceOf(DEV), amountXIn);
        assertEq(token18D.balanceOf(DEV), _amountYIn);
    }

    function testRemoveLiquidityReverseOrder() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        (int256[] memory _deltaIds, , , uint256 amountXIn) = addLiquidityFromRouter(
            token6D,
            token18D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

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

        pair.setApprovalForAll(address(router), true);

        router.removeLiquidity(
            token18D,
            token6D,
            DEFAULT_BIN_STEP,
            _amountYIn,
            totalXbalance,
            ids,
            amounts,
            DEV,
            block.timestamp
        );

        assertEq(token6D.balanceOf(DEV), amountXIn);
        assertEq(token18D.balanceOf(DEV), _amountYIn);
    }

    function testRemoveLiquiditySlippageReverts() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 23;
        uint24 _gap = 2;

        (int256[] memory _deltaIds, , , uint256 amountXIn) = addLiquidityFromRouter(
            token6D,
            token18D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

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

        pair.setApprovalForAll(address(router), true);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBRouter__AmountSlippageCaught.selector,
                totalXbalance + 1,
                totalXbalance,
                totalYBalance,
                totalYBalance
            )
        );
        router.removeLiquidity(
            token6D,
            token18D,
            DEFAULT_BIN_STEP,
            totalXbalance + 1,
            totalYBalance,
            ids,
            amounts,
            DEV,
            block.timestamp
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                LBRouter__AmountSlippageCaught.selector,
                totalXbalance,
                totalXbalance,
                totalYBalance + 1,
                totalYBalance
            )
        );
        router.removeLiquidity(
            token6D,
            token18D,
            DEFAULT_BIN_STEP,
            totalXbalance,
            totalYBalance + 1,
            ids,
            amounts,
            DEV,
            block.timestamp
        );
    }

    function testAddLiquidityAVAX() public {
        pair = createLBPairDefaultFees(token6D, wavax);
        uint24 _numberBins = 23;
        uint256 _amountYIn = 100e18; //AVAX
        uint24 _gap = 2;

        (int256[] memory _deltaIds, , , uint256 amountXIn) = addLiquidityFromRouter(
            token6D,
            ERC20MockDecimals(address(wavax)),
            _amountYIn,
            ID_ONE,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

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

        pair.setApprovalForAll(address(router), true);

        uint256 AVAXBalanceBefore = address(DEV).balance;
        {
            router.removeLiquidityAVAX(
                token6D,
                DEFAULT_BIN_STEP,
                totalXbalance,
                totalYBalance,
                ids,
                amounts,
                DEV,
                block.timestamp
            );
        }
        assertEq(token6D.balanceOf(DEV), amountXIn);
        assertEq(address(DEV).balance - AVAXBalanceBefore, totalYBalance);
    }

    function testAddLiquidityAVAXReversed() public {
        pair = createLBPairDefaultFees(wavax, token6D);
        uint24 _numberBins = 21;
        uint256 amountTokenIn = 100e18;
        uint24 _gap = 2;
        (int256[] memory _deltaIds, , , uint256 _amountAVAXIn) = addLiquidityFromRouter(
            ERC20MockDecimals(address(wavax)),
            token6D,
            amountTokenIn,
            ID_ONE,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );
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
        assertApproxEqAbs(totalXbalance, _amountAVAXIn, 1000);
        assertApproxEqAbs(totalYBalance, amountTokenIn, 1000);

        pair.setApprovalForAll(address(router), true);
        uint256 AVAXBalanceBefore = address(DEV).balance;
        {
            router.removeLiquidityAVAX(
                token6D,
                DEFAULT_BIN_STEP,
                totalYBalance,
                totalXbalance,
                ids,
                amounts,
                DEV,
                block.timestamp
            );
        }
        assertEq(token6D.balanceOf(DEV), amountTokenIn);
        assertEq(address(DEV).balance - AVAXBalanceBefore, totalXbalance);
    }

    function testAddLiquidityTaxToken() public {
        taxToken = new ERC20WithTransferTax();
        pair = createLBPairDefaultFees(taxToken, wavax);
        uint24 _numberBins = 9;
        uint256 _amountAVAXIn = 100e18;
        uint24 _gap = 2;

        (int256[] memory _deltaIds, , , uint256 amountTokenIn) = addLiquidityFromRouter(
            ERC20MockDecimals(address(taxToken)),
            ERC20MockDecimals(address(wavax)),
            _amountAVAXIn,
            ID_ONE,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

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

        pair.setApprovalForAll(address(router), true);

        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        router.removeLiquidityAVAX(
            taxToken,
            DEFAULT_BIN_STEP,
            totalXbalance,
            _amountAVAXIn,
            ids,
            amounts,
            DEV,
            block.timestamp
        );

        router.removeLiquidity(
            taxToken,
            wavax,
            DEFAULT_BIN_STEP,
            totalXbalance,
            _amountAVAXIn,
            ids,
            amounts,
            DEV,
            block.timestamp
        );

        assertEq(taxToken.balanceOf(DEV), amountTokenIn / 4 + 1); //2 transfers with 50% tax
        assertEq(wavax.balanceOf(DEV), _amountAVAXIn);
    }

    function testAddLiquidityIgnored() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        addLiquidityFromRouter(token6D, token18D, _amountYIn, _startId, _numberBins, _gap, DEFAULT_BIN_STEP);

        factory.setLBPairIgnored(token6D, token18D, DEFAULT_BIN_STEP, true);
        ILBRouter.LiquidityParameters memory _liquidityParameters = prepareLiquidityParameters(
            token6D,
            token18D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

        router.addLiquidity(_liquidityParameters);
    }

    function testForIdSlippageCaughtReverts() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        addLiquidityFromRouter(token6D, token18D, _amountYIn, _startId, _numberBins, _gap, DEFAULT_BIN_STEP);

        (, , , uint256 amountXIn) = spreadLiquidityForRouter(_amountYIn, _startId, _numberBins, _gap);

        ILBRouter.LiquidityParameters memory _liquidityParameters = prepareLiquidityParameters(
            token6D,
            token18D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );
        _liquidityParameters.amountXMin = 0;
        _liquidityParameters.amountYMin = 0;
        _liquidityParameters.idSlippage = 0;

        //_liq.activeIdDesired + _liq.idSlippage < _activeId
        token18D.mint(address(pair), _amountYIn);
        pair.swap(false, ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBRouter__IdSlippageCaught.selector,
                8388608,
                _liquidityParameters.idSlippage,
                8388620
            )
        );
        router.addLiquidity(_liquidityParameters);

        // _activeId + _liq.idSlippage < _liq.activeIdDesired
        token6D.mint(address(pair), 2 * amountXIn);
        pair.swap(true, ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(
                LBRouter__IdSlippageCaught.selector,
                8388608,
                _liquidityParameters.idSlippage,
                8388596
            )
        );
        router.addLiquidity(_liquidityParameters);
    }

    function testForAmountSlippageCaughtReverts() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;
        addLiquidityFromRouter(token6D, token18D, _amountYIn, _startId, _numberBins, _gap, DEFAULT_BIN_STEP);

        ILBRouter.LiquidityParameters memory _liquidityParameters = prepareLiquidityParameters(
            token6D,
            token18D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

        (, , , uint256 amountXIn) = spreadLiquidityForRouter(_amountYIn, _startId, _numberBins, _gap);

        token18D.mint(address(pair), _amountYIn / 3);
        pair.swap(false, ALICE);

        //no slippage allowed
        _liquidityParameters.amountXMin = amountXIn;
        _liquidityParameters.amountYMin = _amountYIn;

        //Amount slippage is low in every case - depends only on C [bin composition] change in active bin
        vm.expectRevert(
            abi.encodeWithSelector(
                LBRouter__AmountSlippageCaught.selector,
                98518565614280135938,
                98515492353722968299,
                100000000000000000000,
                100000000000000000000
            )
        );
        router.addLiquidity(_liquidityParameters);
    }

    function testForIdDesiredOverflowReverts() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;
        uint256 overflown24 = uint256(type(uint24).max) + 1;

        ILBRouter.LiquidityParameters memory _liquidityParameters = prepareLiquidityParameters(
            token6D,
            token18D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );
        //this will fail until n16 from audit will be fixed
        _liquidityParameters.activeIdDesired = overflown24;
        _liquidityParameters.idSlippage = 0;
        vm.expectRevert(abi.encodeWithSelector(LBRouter__IdDesiredOverflows.selector, overflown24, 0));
        router.addLiquidity(_liquidityParameters);

        _liquidityParameters.activeIdDesired = 0;
        _liquidityParameters.idSlippage = overflown24;
        vm.expectRevert(abi.encodeWithSelector(LBRouter__IdDesiredOverflows.selector, 0, overflown24));
        router.addLiquidity(_liquidityParameters);

        _liquidityParameters.activeIdDesired = overflown24;
        _liquidityParameters.idSlippage = overflown24;
        vm.expectRevert(abi.encodeWithSelector(LBRouter__IdDesiredOverflows.selector, overflown24, overflown24));
        router.addLiquidity(_liquidityParameters);
    }

    function testForLengthsMismatchReverts() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        ILBRouter.LiquidityParameters memory _liquidityParameters = prepareLiquidityParameters(
            token6D,
            token18D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

        int256[] memory _wrongLengthDeltaIds = new int256[](_numberBins - 1);

        _liquidityParameters.deltaIds = _wrongLengthDeltaIds;

        vm.expectRevert(LBRouter__LengthsMismatch.selector);
        router.addLiquidity(_liquidityParameters);
    }

    function testWrongTokenOrderReverts() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        ILBRouter.LiquidityParameters memory _liquidityParameters = prepareLiquidityParameters(
            token18D,
            token6D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

        vm.expectRevert(LBRouter__WrongTokenOrder.selector);
        router.addLiquidity(_liquidityParameters);
        vm.expectRevert(LBRouter__WrongTokenOrder.selector);
        router.addLiquidityAVAX(_liquidityParameters);
    }

    function testAddLiquidityAVAXnotAVAXReverts() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        ILBRouter.LiquidityParameters memory _liquidityParameters = prepareLiquidityParameters(
            token6D,
            token18D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                LBRouter__WrongAvaxLiquidityParameters.selector,
                _liquidityParameters.tokenX,
                _liquidityParameters.tokenY,
                _liquidityParameters.amountX,
                _liquidityParameters.amountY,
                0
            )
        );
        router.addLiquidityAVAX(_liquidityParameters);
    }

    receive() external payable {}
}
