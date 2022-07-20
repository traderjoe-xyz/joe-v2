// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinPairOracleTest is TestHelper {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV);
        new LBFactoryHelper(factory);
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

        assertEq(oracleSampleLifetime, 240);
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
        assertEq(newOracleSize, oracleSize + 100);
        assertEq(newOracleActiveSize, oracleActiveSize);
        assertEq(newOracleLastTimestamp, oracleLastTimestamp);
        assertEq(newOracleId, oracleId);
        assertEq(newMin, min);
        assertEq(newMax, max);
    }

    function testOracleSampleAtWith1Sample() public {
        uint256 tokenAmount = 100e18;
        token18D.mint(address(pair), tokenAmount);

        uint256[] memory _ids = new uint256[](1);
        _ids[0] = ID_ONE;

        uint256[] memory _liquidities = new uint256[](1);
        _liquidities[0] = SCALE;

        pair.mint(_ids, new uint256[](1), _liquidities, DEV);

        token6D.mint(address(pair), 5e18);
        vm.prank(DEV);
        pair.swap(true, DEV);

        vm.warp(block.timestamp + 250);

        token6D.mint(address(pair), 5e18);
        vm.prank(DEV);
        pair.swap(true, DEV);

        uint256 _ago = 130;
        uint256 _time = block.timestamp - _ago;

        (uint256 cumulativeId, uint256 cumulativeAccumulator, uint256 cumulativeBinCrossed) = pair.getOracleSampleFrom(
            _ago
        );
        assertEq(cumulativeId / _time, ID_ONE);
        assertEq(cumulativeAccumulator, 0);
        assertEq(cumulativeBinCrossed, 0);
    }
}
