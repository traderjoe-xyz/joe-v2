// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract LiquidityBinPairLiquidityTest is TestHelper {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        router = new LBRouter(ILBFactory(DEV), IJoeFactory(DEV), IWAVAX(DEV));
    }

    function testConstructor(
        uint16 _binStep,
        uint16 _baseFactor,
        uint16 _filterPeriod,
        uint16 _decayPeriod,
        uint16 _reductionFactor,
        uint24 _variableFeeControl,
        uint16 _protocolShare,
        uint24 _maxVolatilityAccumulated
    ) public {
        bytes32 _packedFeeParameters = bytes32(
            abi.encodePacked(
                uint136(_maxVolatilityAccumulated), // The first 112 bits are reserved for the dynamic parameters
                _protocolShare,
                _variableFeeControl,
                _reductionFactor,
                _decayPeriod,
                _filterPeriod,
                _baseFactor,
                _binStep
            )
        );

        pair = new LBPair(ILBFactory(DEV));
        pair.initialize(token6D, token18D, ID_ONE, DEFAULT_SAMPLE_LIFETIME, _packedFeeParameters);

        assertEq(address(pair.factory()), DEV);
        assertEq(address(pair.tokenX()), address(token6D));
        assertEq(address(pair.tokenY()), address(token18D));

        FeeHelper.FeeParameters memory feeParameters = pair.feeParameters();
        assertEq(feeParameters.volatilityAccumulated, 0, "volatilityAccumulated should be 0");
        assertEq(feeParameters.volatilityReference, 0, "volatilityReference should be 0");
        assertEq(feeParameters.indexRef, 0, "indexRef should be 0");
        assertEq(feeParameters.time, 0, "Time should be zero");
        assertEq(
            feeParameters.maxVolatilityAccumulated,
            _maxVolatilityAccumulated,
            "Max volatilityAccumulated should be correctly set"
        );
        assertEq(feeParameters.filterPeriod, _filterPeriod, "Filter Period should be correctly set");
        assertEq(feeParameters.decayPeriod, _decayPeriod, "Decay Period should be correctly set");
        assertEq(feeParameters.binStep, _binStep, "Bin Step should be correctly set");
        assertEq(feeParameters.baseFactor, _baseFactor, "Base Factor should be correctly set");
        assertEq(feeParameters.protocolShare, _protocolShare, "Protocol Share should be correctly set");
    }

    function testFuzzingAddLiquidity(uint256 _price) public {
        // Avoids Math__Exp2InputTooBig and very small x amounts
        vm.assume(_price < 2**238);
        // Avoids LBPair__BinReserveOverflows (very big x amounts)
        vm.assume(_price > 2**18);

        uint24 startId = getIdFromPrice(_price);

        uint256 _calculatedPrice = getPriceFromId(startId);

        // Can't use `assertApproxEqRel` as it overflow when multiplying by 1e18
        // Assert that price is at most `binStep`% away from the calculated price
        assertEq(
            (
                (((_price * (Constants.BASIS_POINT_MAX - DEFAULT_BIN_STEP)) / 10_000) <= _calculatedPrice &&
                    _calculatedPrice <= (_price * (Constants.BASIS_POINT_MAX + DEFAULT_BIN_STEP)) / 10_000)
            ),
            true,
            "Wrong log2"
        );

        pair = createLBPairDefaultFeesFromStartId(token6D, token18D, startId);

        uint256 amountYIn = _price < type(uint128).max ? 2**18 : type(uint112).max;
        uint256 amountXIn = (amountYIn << 112) / _price + 3;

        console.log(amountXIn, amountYIn);

        token6D.mint(address(pair), amountXIn);
        token18D.mint(address(pair), amountYIn);

        uint256[] memory ids = new uint256[](3);
        uint256[] memory distribX = new uint256[](3);
        uint256[] memory distribY = new uint256[](3);

        ids[0] = startId - 1;
        ids[1] = startId;
        ids[2] = startId + 1;

        distribY[0] = Constants.PRECISION / 2;
        distribX[1] = Constants.PRECISION / 2;

        distribY[1] = Constants.PRECISION / 2;
        distribX[2] = Constants.PRECISION / 2;

        pair.mint(ids, distribX, distribY, DEV);

        (uint256 binXReserve0, uint256 binYReserve0) = pair.getBin(uint24(ids[0]));
        (uint256 binXReserve1, uint256 binYReserve1) = pair.getBin(uint24(ids[1]));
        (uint256 binXReserve2, uint256 binYReserve2) = pair.getBin(uint24(ids[2]));

        assertEq(binXReserve0, 0, "binXReserve0");
        assertApproxEqRel(binYReserve0, amountYIn / 2, 1e3, "binYReserve0");

        assertApproxEqRel(binXReserve1, amountXIn / 2, 1e3, "currentBinReserveX");
        assertApproxEqRel(binYReserve1, amountYIn / 2, 1e3, "currentBinReserveY");

        assertEq(binYReserve2, 0, "binYReserve2");
        assertApproxEqRel(binXReserve2, amountXIn / 2, 1e3, "binXReserve2");
    }

    function testBurnLiquidity() public {
        pair = createLBPairDefaultFees(token6D, token18D);
        uint256 amount1In = 3e12;
        (
            uint256[] memory _ids,
            uint256[] memory _distributionX,
            uint256[] memory _distributionY,
            uint256 amount0In
        ) = spreadLiquidity(amount1In * 2, ID_ONE, 5, 0);

        token6D.mint(address(pair), amount0In);
        token18D.mint(address(pair), amount1In);

        pair.mint(_ids, _distributionX, _distributionY, ALICE);

        token6D.mint(address(pair), amount0In);
        token18D.mint(address(pair), amount1In);

        pair.mint(_ids, _distributionX, _distributionY, BOB);

        uint256[] memory amounts = new uint256[](5);
        for (uint256 i; i < 5; i++) {
            amounts[i] = pair.balanceOf(BOB, _ids[i]);
        }

        vm.startPrank(BOB);
        pair.safeBatchTransferFrom(BOB, address(pair), _ids, amounts);
        pair.burn(_ids, amounts, BOB);
        pair.collectFees(BOB, _ids); // the excess token were sent to fees, so they need to be claimed
        vm.stopPrank();

        assertEq(token6D.balanceOf(BOB), amount0In);
        assertEq(token18D.balanceOf(BOB), amount1In);
    }

    function testFlawedCompositionFactor() public {
        uint24 _numberBins = 5;
        uint24 startId = ID_ONE;
        uint256 amount0In = 3e12;
        uint256 amount1In = 3e12;
        pair = createLBPairDefaultFees(token6D, token18D);

        addLiquidity(amount1In, startId, _numberBins, 0);

        (uint256 reserveX, uint256 reserveY, uint256 activeId) = pair.getReservesAndId();

        uint256[] memory _ids = new uint256[](3);
        _ids[0] = activeId - 1;
        _ids[1] = activeId;
        _ids[2] = activeId + 1;
        uint256[] memory _distributionX = new uint256[](3);
        _distributionX[0] = Constants.PRECISION / 3;
        _distributionX[1] = Constants.PRECISION / 3;
        _distributionX[2] = Constants.PRECISION / 3;
        uint256[] memory _distributionY = new uint256[](3);

        token6D.mint(address(pair), amount0In);
        token18D.mint(address(pair), amount1In);

        vm.expectRevert(abi.encodeWithSelector(LBPair__CompositionFactorFlawed.selector, _ids[0]));
        pair.mint(_ids, _distributionX, _distributionY, ALICE);

        _distributionX[2] = 0;
        _distributionX[1] = 0;
        _distributionX[0] = 0;
        _distributionY[0] = Constants.PRECISION / 3;
        _distributionY[1] = Constants.PRECISION / 3;
        _distributionY[2] = Constants.PRECISION / 3;

        vm.expectRevert(abi.encodeWithSelector(LBPair__CompositionFactorFlawed.selector, _ids[2]));
        pair.mint(_ids, _distributionX, _distributionY, ALICE);

        uint256[] memory _ids2 = new uint256[](1);
        uint256[] memory _distributionX2 = new uint256[](1);
        uint256[] memory _distributionY2 = new uint256[](1);

        _ids2[0] = activeId - 1;
        _distributionX2[0] = Constants.PRECISION;
        vm.expectRevert(abi.encodeWithSelector(LBPair__CompositionFactorFlawed.selector, _ids2[0]));
        pair.mint(_ids2, _distributionX2, _distributionY2, ALICE);

        _ids2[0] = activeId + 1;
        _distributionY2[0] = Constants.PRECISION;
        _distributionX2[0] = 0;
        vm.expectRevert(abi.encodeWithSelector(LBPair__CompositionFactorFlawed.selector, _ids2[0]));
        pair.mint(_ids2, _distributionX2, _distributionY2, ALICE);
    }

    function testInsufficientLiquidityMinted() public {
        uint24 _numberBins = 5;
        uint24 startId = ID_ONE;
        uint256 amount0In = 3e12;
        uint256 amount1In = 3e12;
        pair = createLBPairDefaultFees(token6D, token18D);

        addLiquidity(amount1In, startId, _numberBins, 0);

        (uint256 reserveX, uint256 reserveY, uint256 activeId) = pair.getReservesAndId();

        uint256[] memory _ids = new uint256[](3);
        _ids[0] = activeId - 1;
        _ids[1] = activeId;
        _ids[2] = activeId + 1;
        uint256[] memory _distributionX = new uint256[](3);
        _distributionX[0] = 0;
        _distributionX[1] = Constants.PRECISION / 3;
        _distributionX[2] = Constants.PRECISION / 3;
        uint256[] memory _distributionY = new uint256[](3);

        token6D.mint(address(pair), amount0In);
        token18D.mint(address(pair), amount1In);

        vm.expectRevert(abi.encodeWithSelector(LBPair__InsufficientLiquidityMinted.selector, _ids[0]));
        pair.mint(_ids, _distributionX, _distributionY, ALICE);

        _distributionX[2] = 0;
        _distributionX[1] = 0;
        _distributionX[0] = 0;
        _distributionY[0] = Constants.PRECISION / 3;
        _distributionY[1] = Constants.PRECISION / 3;
        _distributionY[2] = 0;

        vm.expectRevert(abi.encodeWithSelector(LBPair__InsufficientLiquidityMinted.selector, _ids[2]));
        pair.mint(_ids, _distributionX, _distributionY, ALICE);
    }
}
