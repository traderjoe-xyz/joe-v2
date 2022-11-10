// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./TestHelper.sol";
import "src/libraries/Oracle.sol";

contract LiquidityBinPairOracleTest is TestHelper {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        router = new LBRouter(ILBFactory(DEV), IJoeFactory(DEV), IWAVAX(DEV));

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testVerifyOracleInitialParams() public {
        (
            uint256 oracleSampleLifetime,
            uint256 oracleSize,
            uint256 oracleActiveSize,
            uint256 oracleLastTimestamp,
            uint256 oracleId,
            uint256 min,
            uint256 max
        ) = pair.getOracleParameters();

        assertEq(oracleSampleLifetime, 120);
        assertEq(oracleSize, 2);
        assertEq(oracleActiveSize, 0);
        assertEq(oracleLastTimestamp, 0);
        assertEq(oracleId, 0);
        assertEq(min, 0);
        assertEq(max, 0);
    }

    function testIncreaseOracleLength() public {
        (
            uint256 oracleSampleLifetime,
            uint256 oracleSize,
            uint256 oracleActiveSize,
            uint256 oracleLastTimestamp,
            uint256 oracleId,
            uint256 min,
            uint256 max
        ) = pair.getOracleParameters();

        pair.increaseOracleLength(100);

        (
            uint256 newOracleSampleLifetime,
            uint256 newOracleSize,
            uint256 newOracleActiveSize,
            uint256 newOracleLastTimestamp,
            uint256 newOracleId,
            uint256 newMin,
            uint256 newMax
        ) = pair.getOracleParameters();

        assertEq(newOracleSampleLifetime, oracleSampleLifetime);
        assertEq(newOracleSize, 100);
        assertEq(newOracleActiveSize, oracleActiveSize);
        assertEq(newOracleLastTimestamp, oracleLastTimestamp);
        assertEq(newOracleId, oracleId);
        assertEq(newMin, min);
        assertEq(newMax, max);
    }

    function testOracleSampleFromEdgeCases() public {
        uint256 tokenAmount = 100e18;
        token18D.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](1);
        _ids[0] = ID_ONE;

        uint256[] memory _liquidities = new uint256[](1);
        _liquidities[0] = Constants.PRECISION;

        pair.mint(_ids, new uint256[](1), _liquidities, DEV);

        token6D.mint(address(pair), 5e18);

        vm.expectRevert(Oracle__NotInitialized.selector);
        pair.getOracleSampleFrom(0);

        vm.warp(10_000);

        pair.swap(true, DEV);

        vm.expectRevert(abi.encodeWithSelector(Oracle__LookUpTimestampTooOld.selector, 10_000, 9_000));
        pair.getOracleSampleFrom(1_000);
    }

    function testOracleSampleFromWith2Samples() public {
        uint256 tokenAmount = 100e18;
        token18D.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](1);
        _ids[0] = ID_ONE;

        uint256[] memory _liquidities = new uint256[](1);
        _liquidities[0] = Constants.PRECISION;

        pair.mint(_ids, new uint256[](1), _liquidities, DEV);

        token6D.mint(address(pair), 5e18);

        pair.swap(true, DEV);

        vm.warp(block.timestamp + 250);

        token6D.mint(address(pair), 5e18);

        pair.swap(true, DEV);

        uint256 _ago = 130;
        uint256 _time = block.timestamp - _ago;

        (uint256 cumulativeId, uint256 cumulativeVolatilityAccumulated, uint256 cumulativeBinCrossed) = pair
            .getOracleSampleFrom(_ago);
        assertEq(cumulativeId / _time, ID_ONE);
        assertEq(cumulativeVolatilityAccumulated, 0);
        assertEq(cumulativeBinCrossed, 0);
    }

    function testOracleSampleFromWith100Samples() public {
        uint256 amount1In = 200e18;
        (
            uint256[] memory _ids,
            uint256[] memory _distributionX,
            uint256[] memory _distributionY,
            uint256 amount0In
        ) = spreadLiquidity(amount1In * 2, ID_ONE, 99, 100);

        token6D.mint(address(pair), amount0In);
        token18D.mint(address(pair), amount1In);

        pair.mint(_ids, _distributionX, _distributionY, DEV);
        pair.increaseOracleLength(100);

        uint256 startTimestamp;

        for (uint256 i; i < 200; ++i) {
            token6D.mint(address(pair), 1e18);

            vm.warp(1500 + 100 * i);
            pair.swap(true, DEV);

            if (i == 1) startTimestamp = block.timestamp;
        }

        (uint256 cId, uint256 cAcc, uint256 cBin) = pair.getOracleSampleFrom(0);

        for (uint256 i; i < 99; ++i) {
            uint256 _ago = ((block.timestamp - startTimestamp) * i) / 100;

            (uint256 cumulativeId, uint256 cumulativeVolatilityAccumulated, uint256 cumulativeBinCrossed) = pair
                .getOracleSampleFrom(_ago);
            assertGe(cId, cumulativeId);
            assertGe(cAcc, cumulativeVolatilityAccumulated);
            assertGe(cBin, cumulativeBinCrossed);

            (cId, cAcc, cBin) = (cumulativeId, cumulativeVolatilityAccumulated, cumulativeBinCrossed);
        }
    }

    function testOracleSampleFromWith100SamplesNotAllInitialized() public {
        uint256 amount1In = 101e18;
        (
            uint256[] memory _ids,
            uint256[] memory _distributionX,
            uint256[] memory _distributionY,
            uint256 amount0In
        ) = spreadLiquidity(amount1In * 2, ID_ONE, 99, 100);

        token6D.mint(address(pair), amount0In);
        token18D.mint(address(pair), amount1In);

        pair.mint(_ids, _distributionX, _distributionY, DEV);

        uint256 startTimestamp;

        uint16 newSize = 2;
        for (uint256 i; i < 50; ++i) {
            token6D.mint(address(pair), 1e18);

            newSize += 2;
            pair.increaseOracleLength(newSize);

            vm.warp(1500 + 100 * i);
            pair.swap(true, DEV);

            if (i == 1) startTimestamp = block.timestamp;
        }

        (uint256 cId, uint256 cAcc, uint256 cBin) = pair.getOracleSampleFrom(0);

        for (uint256 i; i < 49; ++i) {
            uint256 _ago = ((block.timestamp - startTimestamp) * i) / 50;

            (uint256 cumulativeId, uint256 cumulativeVolatilityAccumulated, uint256 cumulativeBinCrossed) = pair
                .getOracleSampleFrom(_ago);
            assertGe(cId, cumulativeId);
            assertGe(cAcc, cumulativeVolatilityAccumulated);
            assertGe(cBin, cumulativeBinCrossed);

            (cId, cAcc, cBin) = (cumulativeId, cumulativeVolatilityAccumulated, cumulativeBinCrossed);
        }
    }

    function testTLowerThanTimestamp() public {
        uint256 amountYInLiquidity = 100e18;
        uint24 startId = ID_ONE;

        FeeHelper.FeeParameters memory _feeParameters = pair.feeParameters();
        addLiquidity(amountYInLiquidity, startId, 51, 5);

        (uint256 amountYInForSwap, ) = router.getSwapIn(pair, amountYInLiquidity / 4, true);
        token6D.mint(address(pair), amountYInForSwap);
        vm.prank(ALICE);
        pair.swap(true, ALICE);

        (uint256 cumulativeId, uint256 cumulativeVolatilityAccumulated, uint256 cumulativeBinCrossed) = pair
            .getOracleSampleFrom(0);

        vm.warp(block.timestamp + 90);
        (
            uint256 cumulativeIdAfter,
            uint256 cumulativeVolatilityAccumulatedAfter,
            uint256 cumulativeBinCrossedAfter
        ) = pair.getOracleSampleFrom(0);

        assertEq(cumulativeId * block.timestamp, cumulativeIdAfter);
        assertLt(cumulativeVolatilityAccumulated, cumulativeVolatilityAccumulatedAfter);
        assertEq(cumulativeBinCrossed, cumulativeBinCrossedAfter);
    }

    function testTheSameOracleSizeReverts() public {
        (, uint256 currentOracleSize, , , , , ) = pair.getOracleParameters();
        vm.expectRevert(abi.encodeWithSelector(LBPair__OracleNewSizeTooSmall.selector, currentOracleSize, currentOracleSize));
        pair.increaseOracleLength(uint16(currentOracleSize));
        pair.increaseOracleLength(uint16(currentOracleSize + 22));
        (, currentOracleSize, , , , , ) = pair.getOracleParameters();
        vm.expectRevert(abi.encodeWithSelector(LBPair__OracleNewSizeTooSmall.selector, currentOracleSize, currentOracleSize));
        pair.increaseOracleLength(uint16(currentOracleSize));
    }
}
