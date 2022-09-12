// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;

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
        vm.assume(_price < 2**239);
        // Avoids LBPair__BinReserveOverflows (very big x amounts)
        vm.assume(_price > 2**17);

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

        uint256 amountYIn = _price > 2**128 ? 2 * ((1 << 112) - 1) : 2;

        (, , , uint256 amountXIn) = addLiquidity(amountYIn, startId, 3, 0);

        console2.log("startId", startId);

        (uint256 currentBinReserveX, uint256 currentBinReserveY) = pair.getBin(startId);
        (uint256 binYReserve0, uint256 binYReserve1) = pair.getBin(startId - 1);
        (uint256 binXReserve0, uint256 binXReserve1) = pair.getBin(startId + 1);

        console2.log("bin0", currentBinReserveX, currentBinReserveY);
        console2.log("binY", binYReserve0, binYReserve1);
        console2.log("binX", binXReserve0, binXReserve1);

        assertApproxEqRel(currentBinReserveX, amountXIn / 2, 1e3, "currentBinReserveX");
        assertApproxEqRel(currentBinReserveY, amountYIn / 2, 1e3, "currentBinReserveY");

        assertEq(binYReserve0, 0, "binYReserve0");
        assertApproxEqRel(binYReserve1, amountYIn / 2, 1e3, "binYReserve1");

        assertEq(binXReserve1, 0, "binXReserve0");
        assertApproxEqRel(binXReserve0, amountXIn / 2, 1e3, "binXReserve1");
        assertEq(binXReserve1, 0, "binXReserve0");
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
}
