// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import "../helpers/TestHelper.sol";

import "../../src/libraries/BinHelper.sol";
import "../../src/libraries/math/PackedUint128Math.sol";
import "../../src/libraries/math/Uint256x256Math.sol";
import "../../src/libraries/math/Uint128x128Math.sol";
import "../../src/libraries/PairParameterHelper.sol";

contract BinHelperTest is TestHelper {
    using BinHelper for bytes32;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using Uint128x128Math for uint256;
    using Uint256x256Math for uint256;
    using PairParameterHelper for bytes32;

    function testFuzz_GetAmountOutOfBin(
        uint128 binReserveX,
        uint128 binReserveY,
        uint256 amountToBurn,
        uint256 totalSupply
    ) external pure {
        vm.assume(totalSupply > 0 && totalSupply >= amountToBurn);

        bytes32 binReserves = binReserveX.encode(binReserveY);

        bytes32 amountOut = binReserves.getAmountOutOfBin(amountToBurn, totalSupply);
        (uint128 amountOutX, uint128 amountOutY) = amountOut.decode();

        assertEq(amountOutX, amountToBurn.mulDivRoundDown(binReserveX, totalSupply), "testFuzz_GetAmountOutOfBin::1");
        assertEq(amountOutY, amountToBurn.mulDivRoundDown(binReserveY, totalSupply), "testFuzz_GetAmountOutOfBin::2");
    }

    function testFuzz_GetLiquidity(uint128 amountInX, uint128 amountInY, uint256 price) external {
        bytes32 amountsIn = amountInX.encode(amountInY);

        (uint256 px, uint256 L) = (0, 0);

        unchecked {
            px = price * uint256(amountInX);
            L = px + (uint256(amountInY) << 128);
        }

        if (amountInX != 0 && px / amountInX != price || L < px) {
            vm.expectRevert(BinHelper.BinHelper__LiquidityOverflow.selector);
            amountsIn.getLiquidity(price);
        } else {
            uint256 liquidity = amountsIn.getLiquidity(price);
            assertEq(liquidity, price * amountInX + (uint256(amountInY) << 128), "testFuzz_GetLiquidity::1");
        }
    }

    function testFuzz_getSharesAndEffectiveAmountsIn(
        uint128 binReserveX,
        uint128 binReserveY,
        uint128 amountInX,
        uint128 amountInY,
        uint256 price,
        uint256 totalSupply
    ) external pure {
        vm.assume(
            price > 0 && uint256(binReserveX) + amountInX <= type(uint128).max
                && uint256(binReserveY) + amountInY <= type(uint128).max
                && (
                    (uint256(binReserveX) + amountInX) == 0
                        || price <= type(uint256).max / (uint256(binReserveX) + amountInX)
                )
                && price * (uint256(binReserveX) + amountInX)
                    <= type(uint256).max - ((uint256(binReserveY) + amountInY) << 128)
                && price * (uint256(binReserveX) + amountInX) + ((uint256(binReserveY) + amountInY) << 128)
                    <= Constants.MAX_LIQUIDITY_PER_BIN
        );

        bytes32 binReserves = binReserveX.encode(binReserveY);
        uint256 binLiquidity = binReserves.getLiquidity(price);

        vm.assume(price > 0 && totalSupply <= binLiquidity);

        bytes32 amountsIn = amountInX.encode(amountInY);

        (uint256 shares, bytes32 effectiveAmountsIn) =
            binReserves.getSharesAndEffectiveAmountsIn(amountsIn, price, totalSupply);

        assertLe(uint256(effectiveAmountsIn), uint256(amountsIn), "testFuzz_getSharesAndEffectiveAmountsIn::1");

        uint256 userLiquidity = amountsIn.getLiquidity(price);
        uint256 expectedShares = binLiquidity == 0 || totalSupply == 0
            ? userLiquidity.sqrt()
            : userLiquidity.mulDivRoundDown(totalSupply, binLiquidity);

        assertEq(shares, expectedShares, "testFuzz_getSharesAndEffectiveAmountsIn::2");
    }

    function testFuzz_TryExploitShares(
        uint128 amountX1,
        uint128 amountY1,
        uint128 amountX2,
        uint128 amountY2,
        uint256 price
    ) external pure {
        vm.assume(
            price > 0 && amountX1 > 0 && amountY1 > 0 && amountX2 > 0 && amountY2 > 0
                && uint256(amountX1) + amountX2 <= type(uint128).max && uint256(amountY1) + amountY2 <= type(uint128).max
                && price <= type(uint256).max / (uint256(amountX1) + amountX2)
                && uint256(amountY1) + amountY2 <= type(uint128).max
                && price * (uint256(amountX1) + amountX2) <= type(uint256).max - ((uint256(amountY1) + amountY2) << 128)
                && price * (uint256(amountX1) + amountX2) + ((uint256(amountY1) + amountY2) << 128)
                    <= Constants.MAX_LIQUIDITY_PER_BIN
        );

        // exploiter front run the tx and mint the min amount of shares, so the total supply is 2^128
        uint256 totalSupply = 1 << 128;
        bytes32 binReserves = amountX1.encode(amountY1);

        bytes32 amountsIn = amountX2.encode(amountY2);
        (uint256 shares, bytes32 effectiveAmountsIn) =
            binReserves.getSharesAndEffectiveAmountsIn(amountsIn, price, totalSupply);

        binReserves = binReserves.add(effectiveAmountsIn);
        totalSupply += shares;

        uint256 userReceivedX = shares.mulDivRoundDown(binReserves.decodeX(), totalSupply);
        uint256 userReceivedY = shares.mulDivRoundDown(binReserves.decodeY(), totalSupply);

        uint256 receivedInY = userReceivedX.mulShiftRoundDown(price, Constants.SCALE_OFFSET) + userReceivedY;
        uint256 sentInY =
            price.mulShiftRoundDown(effectiveAmountsIn.decodeX(), Constants.SCALE_OFFSET) + effectiveAmountsIn.decodeY();

        assertApproxEqAbs(receivedInY, sentInY, ((price - 1) >> 128) + 2, "testFuzz_TryExploitShares::1");
    }

    function testFuzz_VerifyAmountsNeqIds(uint128 amountX, uint128 amountY, uint24 activeId, uint24 id) external {
        vm.assume(activeId != id);

        bytes32 amounts = amountX.encode(amountY);

        if (id < activeId && amountX > 0 || id > activeId && amountY > 0) {
            vm.expectRevert(abi.encodeWithSelector(BinHelper.BinHelper__CompositionFactorFlawed.selector, id));
        }

        amounts.verifyAmounts(activeId, id);
    }

    function testFuzz_VerifyAmountsOnActiveId(uint128 amountX, uint128 amountY, uint24 activeId) external pure {
        bytes32 amounts = amountX.encode(amountY);
        amounts.verifyAmounts(activeId, activeId);
    }

    function testFuzz_GetCompositionFees(
        uint128 reserveX,
        uint128 reserveY,
        uint16 binStep,
        uint128 amountXIn,
        uint128 amountYIn,
        uint256 price,
        uint256 totalSupply
    ) external pure {
        // make sure p*x+y doesn't overflow
        vm.assume(
            price > 0 && amountXIn > 0 && amountYIn > 0 && uint256(reserveX) + amountXIn <= type(uint128).max
                && uint256(reserveY) + amountYIn <= type(uint128).max
                && uint256(reserveX) + amountXIn <= type(uint256).max / price
                && price * uint256(reserveX + amountXIn) <= type(uint256).max - (uint256(reserveY + amountYIn) << 128)
                && price * uint256(reserveX + amountXIn) + (uint256(reserveY + amountYIn) << 128)
                    <= Constants.MAX_LIQUIDITY_PER_BIN
        );

        bytes32 binReserves = reserveX.encode(reserveY);
        uint256 binLiquidity = binReserves.getLiquidity(price);

        vm.assume(
            binStep <= 200 && price > 0 && totalSupply <= binLiquidity
                && (totalSupply == 0 && binReserves == 0 || totalSupply > 0 && binReserves > 0)
        );

        (uint256 shares, bytes32 amountsIn) =
            binReserves.getSharesAndEffectiveAmountsIn(amountXIn.encode(amountYIn), price, totalSupply);

        vm.assume(
            !binReserves.gt(bytes32(type(uint256).max).sub(amountsIn)) && totalSupply <= type(uint256).max - shares
        );

        (amountXIn, amountYIn) = amountsIn.decode();

        bytes32 parameters = bytes32(0).setStaticFeeParameters(
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR
        );

        bytes32 compositionFees = binReserves.getCompositionFees(parameters, binStep, amountsIn, totalSupply, shares);

        uint256 binC = reserveX | reserveY == 0 ? 0 : (uint256(reserveY) << 128) / (uint256(reserveX) + reserveY);
        uint256 userC = amountXIn | amountYIn == 0 ? 0 : (uint256(amountYIn) << 128) / (uint256(amountXIn) + amountYIn);

        if (binC > userC) {
            assertGe(uint256(compositionFees) << 128, 0, "testFuzz_GetCompositionFees::1");
        } else {
            assertGe(uint128(uint256(compositionFees)), 0, "testFuzz_GetCompositionFees::2");
        }
    }

    function testFuzz_BinIsEmpty(uint128 binReserveX, uint128 binReserveY) external pure {
        bytes32 binReserves = binReserveX.encode(binReserveY);

        assertEq(binReserves.isEmpty(true), binReserveX == 0, "testFuzz_BinIsEmpty::1");
        assertEq(binReserves.isEmpty(false), binReserveY == 0, "testFuzz_BinIsEmpty::2");
    }

    function testFuzz_GetAmountsLessThanBin(
        uint128 binReserveX,
        uint128 binReserveY,
        bool swapForY,
        int16 deltaId,
        uint128 amountIn
    ) external view {
        bytes32 parameters = bytes32(0).setStaticFeeParameters(
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR
        );

        uint24 activeId = uint24(uint256(int256(uint256(ID_ONE)) + deltaId));
        uint256 price = PriceHelper.getPriceFromId(activeId, DEFAULT_BIN_STEP);

        {
            uint256 maxAmountIn = swapForY
                ? uint256(binReserveY).shiftDivRoundUp(Constants.SCALE_OFFSET, price)
                : uint256(binReserveX).mulShiftRoundUp(price, Constants.SCALE_OFFSET);
            vm.assume(maxAmountIn <= type(uint128).max);

            uint128 maxFee = FeeHelper.getFeeAmount(uint128(maxAmountIn), parameters.getTotalFee(DEFAULT_BIN_STEP));
            vm.assume(maxAmountIn <= type(uint128).max - maxFee && amountIn < maxAmountIn + maxFee);

            vm.assume(
                swapForY
                    ? uint256(binReserveX) + maxAmountIn + maxFee <= type(uint128).max
                    : uint256(binReserveY) + maxAmountIn + maxFee <= type(uint128).max
            );

            vm.assume(
                binReserveX <= type(uint256).max / price
                    && price * binReserveX <= type(uint256).max - (uint256(binReserveY) << 128)
                    && price * binReserveX + (uint256(binReserveY) << 128)
                        <= Constants.MAX_LIQUIDITY_PER_BIN / 1e18 * (1e18 - parameters.getTotalFee(DEFAULT_BIN_STEP))
            );
        }

        bytes32 reserves = binReserveX.encode(binReserveY);

        (bytes32 amountsInToBin, bytes32 amountsOutOfBin, bytes32 totalFees) =
            reserves.getAmounts(parameters, DEFAULT_BIN_STEP, swapForY, activeId, amountIn.encode(swapForY));

        assertLe(amountsInToBin.decode(swapForY), amountIn, "testFuzz_GetAmountsLessThanBin::1");

        uint256 amountInWithoutFees = amountsInToBin.sub(totalFees).decode(swapForY);

        (uint256 amountOutWithNoFees, uint256 amountOut) = swapForY
            ? (price.mulShiftRoundDown(amountsInToBin.decodeX(), Constants.SCALE_OFFSET), amountsOutOfBin.decodeY())
            : (
                uint256(amountsInToBin.decodeY()).shiftDivRoundDown(Constants.SCALE_OFFSET, price),
                amountsOutOfBin.decodeX()
            );

        assertGe(amountOutWithNoFees, amountOut, "testFuzz_GetAmountsLessThanBin::2");

        uint256 amountOutWithFees = swapForY
            ? price.mulShiftRoundDown(amountInWithoutFees, Constants.SCALE_OFFSET)
            : amountInWithoutFees.shiftDivRoundDown(Constants.SCALE_OFFSET, price);

        assertEq(amountOut, amountOutWithFees, "testFuzz_GetAmountsLessThanBin::3");
    }

    function testFuzz_getAmountsFullBin(
        uint128 binReserveX,
        uint128 binReserveY,
        bool swapForY,
        int16 deltaId,
        uint128 amountIn
    ) external pure {
        bytes32 parameters = bytes32(0).setStaticFeeParameters(
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR
        );

        uint24 activeId = uint24(uint256(int256(uint256(ID_ONE)) + deltaId));
        uint256 price = PriceHelper.getPriceFromId(activeId, DEFAULT_BIN_STEP);

        {
            uint256 maxAmountIn = swapForY
                ? uint256(binReserveY).shiftDivRoundUp(Constants.SCALE_OFFSET, price)
                : uint256(binReserveX).mulShiftRoundUp(price, Constants.SCALE_OFFSET);
            vm.assume(maxAmountIn <= type(uint128).max);

            uint128 maxFee = FeeHelper.getFeeAmount(uint128(maxAmountIn), parameters.getTotalFee(DEFAULT_BIN_STEP));
            vm.assume(maxAmountIn <= type(uint128).max - maxFee && amountIn >= maxAmountIn + maxFee);

            vm.assume(
                swapForY
                    ? uint256(binReserveX) + maxAmountIn + maxFee <= type(uint128).max
                    : uint256(binReserveY) + maxAmountIn + maxFee <= type(uint128).max
            );

            vm.assume(
                binReserveX <= type(uint256).max / price
                    && price * binReserveX <= type(uint256).max - (uint256(binReserveY) << 128)
                    && price * binReserveX + (uint256(binReserveY) << 128)
                        <= Constants.MAX_LIQUIDITY_PER_BIN / 1e18 * (1e18 - parameters.getTotalFee(DEFAULT_BIN_STEP))
            );
        }

        bytes32 reserves = binReserveX.encode(binReserveY);

        (bytes32 amountsInToBin, bytes32 amountsOutOfBin, bytes32 totalFees) =
            reserves.getAmounts(parameters, DEFAULT_BIN_STEP, swapForY, activeId, amountIn.encode(swapForY));

        assertLe(amountsInToBin.decode(swapForY), amountIn, "testFuzz_getAmountsFullBin::1");

        {
            uint256 amountInForSwap = amountsInToBin.decode(swapForY);

            (uint256 amountOutWithNoFees, uint256 amountOut) = swapForY
                ? (price.mulShiftRoundDown(amountInForSwap, Constants.SCALE_OFFSET), amountsOutOfBin.decodeY())
                : (uint256(amountInForSwap).shiftDivRoundDown(Constants.SCALE_OFFSET, price), amountsOutOfBin.decodeX());

            assertGe(amountOutWithNoFees, amountOut, "testFuzz_getAmountsFullBin::2");
        }

        uint128 amountInToBin = amountsInToBin.sub(totalFees).decode(swapForY);

        (uint256 amountOutWithFees, uint256 amountOutWithFeesAmountInSub1) = amountInToBin == 0
            ? (0, 0)
            : swapForY
                ? (
                    price.mulShiftRoundDown(amountInToBin, Constants.SCALE_OFFSET),
                    price.mulShiftRoundDown(amountInToBin - 1, Constants.SCALE_OFFSET)
                )
                : (
                    uint256(amountInToBin).shiftDivRoundDown(Constants.SCALE_OFFSET, price),
                    uint256(amountInToBin - 1).shiftDivRoundDown(Constants.SCALE_OFFSET, price)
                );

        assertLe(amountsOutOfBin.decode(!swapForY), amountOutWithFees, "testFuzz_getAmountsFullBin::3");
        assertGe(amountsOutOfBin.decode(!swapForY), amountOutWithFeesAmountInSub1, "testFuzz_getAmountsFullBin::4");
    }

    function testFuzz_Received(uint128 reserveX, uint128 reserveY, uint128 sentX, uint128 sentY) external {
        vm.assume(reserveX < type(uint128).max - sentX && reserveY < type(uint128).max - sentY);

        address pair = address(this);

        deal(address(usdc), pair, reserveX + sentX);
        deal(address(wnative), pair, reserveY + sentY);

        bytes32 reserves = reserveX.encode(reserveY);

        bytes32 received = reserves.received(IERC20(address(usdc)), IERC20(address(wnative)));

        (uint256 receivedX, uint256 receivedY) = received.decode();

        assertEq(receivedX, sentX, "testFuzz_Received::1");
        assertEq(receivedY, sentY, "testFuzz_Received::2");

        received = reserves.receivedX(IERC20(address(usdc)));
        receivedX = received.decodeX();

        assertEq(receivedX, sentX, "testFuzz_Received::3");

        received = reserves.receivedY(IERC20(address(wnative)));
        receivedY = received.decodeY();

        assertEq(receivedY, sentY, "testFuzz_Received::4");
    }

    function testFuzz_Transfer(uint128 amountX, uint128 amountY) external {
        address recipient = address(1);

        deal(address(usdc), address(this), amountX);
        deal(address(wnative), address(this), amountY);

        bytes32 amounts = amountX.encode(amountY);

        bytes32 firstHalf = amounts.sub((amountX / 2).encode((amountY / 2)));
        bytes32 secondHalf = amounts.sub(firstHalf);

        firstHalf.transfer(IERC20(address(usdc)), IERC20(address(wnative)), recipient);

        assertEq(usdc.balanceOf(recipient), firstHalf.decodeX(), "testFuzz_Transfer::1");
        assertEq(wnative.balanceOf(recipient), firstHalf.decodeY(), "testFuzz_Transfer::2");
        assertEq(usdc.balanceOf(address(this)), secondHalf.decodeX(), "testFuzz_Transfer::3");
        assertEq(wnative.balanceOf(address(this)), secondHalf.decodeY(), "testFuzz_Transfer::4");

        secondHalf.transferX(IERC20(address(usdc)), recipient);

        assertEq(usdc.balanceOf(recipient), amounts.decodeX(), "testFuzz_Transfer::5");
        assertEq(wnative.balanceOf(recipient), firstHalf.decodeY(), "testFuzz_Transfer::6");
        assertEq(usdc.balanceOf(address(this)), 0, "testFuzz_Transfer::7");
        assertEq(wnative.balanceOf(address(this)), secondHalf.decodeY(), "testFuzz_Transfer::8");

        secondHalf.transferY(IERC20(address(wnative)), recipient);

        assertEq(usdc.balanceOf(recipient), amounts.decodeX(), "testFuzz_Transfer::9");
        assertEq(wnative.balanceOf(recipient), amounts.decodeY(), "testFuzz_Transfer::10");
        assertEq(usdc.balanceOf(address(this)), 0, "testFuzz_Transfer::11");
        assertEq(wnative.balanceOf(address(this)), 0, "testFuzz_Transfer::12");
    }
}
