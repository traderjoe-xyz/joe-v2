// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

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
    ) external {
        vm.assume(totalSupply > 0 && totalSupply >= amountToBurn);

        bytes32 binReserves = binReserveX.encode(binReserveY);

        bytes32 amountOut = binReserves.getAmountOutOfBin(amountToBurn, totalSupply);
        (uint128 amountOutX, uint128 amountOutY) = amountOut.decode();

        assertEq(amountOutX, amountToBurn.mulDivRoundDown(binReserveX, totalSupply), "test_GetAmountOutOfBin::1");
        assertEq(amountOutY, amountToBurn.mulDivRoundDown(binReserveY, totalSupply), "test_GetAmountOutOfBin::2");
    }

    function testFuzz_GetLiquidity(uint128 amountInX, uint128 amountInY, uint256 price) external {
        uint256 px = price.mulShiftRoundDown(amountInX, Constants.SCALE_OFFSET);

        bytes32 amountIn = amountInX.encode(amountInY);
        if (px > type(uint256).max - amountInY) {
            vm.expectRevert();
            amountIn.getLiquidity(price);
        } else {
            uint256 liquidity = amountIn.getLiquidity(price);
            assertEq(liquidity, px + amountInY, "test_GetLiquidity::1");
        }
    }

    function testFuzz_GetShareAndEffectiveAmountsIn(
        uint128 binReserveX,
        uint128 binReserveY,
        uint128 amountInX,
        uint128 amountInY,
        uint256 price,
        uint256 totalSupply
    ) external {
        bytes32 binReserves = binReserveX.encode(binReserveY);
        uint256 binLiquidity = binReserves.getLiquidity(price);

        vm.assume(price > 0 && totalSupply <= binLiquidity);

        bytes32 amountsIn = amountInX.encode(amountInY);

        (uint256 shares, bytes32 effectiveAmountsIn) =
            binReserves.getShareAndEffectiveAmountsIn(amountsIn, price, totalSupply);

        assertLe(uint256(effectiveAmountsIn), uint256(amountsIn), "test_GetShareAndEffectiveAmountsIn::1");

        uint256 userLiquidity = amountsIn.getLiquidity(price);
        uint256 expectedShares = binLiquidity == 0 || totalSupply == 0
            ? userLiquidity
            : userLiquidity.mulDivRoundDown(totalSupply, binLiquidity);

        assertEq(shares, expectedShares, "test_GetShareAndEffectiveAmountsIn::2");
    }

    function testFuzz_TryExploitShares(uint128 amountX, uint128 amountY, uint256 price) external {
        vm.assume(price > 0 && amountX > 0 && amountX < type(uint128).max && amountY > 0 && amountY < type(uint128).max);

        // exploiter front run the tx and mint 1 of liquidity
        uint256 totalSupply = 1;

        // exploiter increase the reserve to amounts added by user + 1
        bytes32 binReserves = uint128(amountX + 1).encode(uint128(amountY + 1));

        // user add liquidity
        (uint256 shares, bytes32 effectiveAmountsIn) =
            binReserves.getShareAndEffectiveAmountsIn(amountX.encode(amountY), price, totalSupply);

        assertEq(shares, 0, "test_TryExploitShares::1");

        (uint128 effectiveX, uint128 effectiveY) = effectiveAmountsIn.decode();
        assertEq(effectiveX, 0, "test_TryExploitShares::2");
        assertEq(effectiveY, 0, "test_TryExploitShares::3");

        // If user added liquidity with 1 wei more, he will get 1 share
        (shares, effectiveAmountsIn) =
            binReserves.getShareAndEffectiveAmountsIn((amountX + 1).encode(amountY + 1), price, totalSupply);

        assertEq(shares, 1, "test_TryExploitShares::3");
        assertEq(effectiveAmountsIn, (amountX + 1).encode(amountY + 1), "test_TryExploitShares::4");
    }

    function testFuzz_VerifyAmountsNeqIds(uint128 amountX, uint128 amountY, uint24 activeId, uint24 id) external {
        vm.assume(activeId != id);

        bytes32 amounts = amountX.encode(amountY);

        if (id < activeId && amountX > 0 || id > activeId && amountY > 0) {
            vm.expectRevert(abi.encodeWithSelector(BinHelper.BinMath__CompositionFactorFlawed.selector, id));
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
        uint8 binStep,
        uint128 amountXIn,
        uint128 amountYIn,
        uint256 price,
        uint256 totalSupply
    ) external {
        bytes32 binReserves = reserveX.encode(reserveY);
        uint256 binLiquidity = binReserves.getLiquidity(price);

        vm.assume(
            binStep <= 200 && price > 0 && totalSupply <= binLiquidity
                && (totalSupply == 0 && binReserves == 0 || totalSupply > 0 && binReserves > 0)
        );

        (uint256 shares, bytes32 amountsIn) =
            binReserves.getShareAndEffectiveAmountsIn(amountXIn.encode(amountYIn), price, totalSupply);

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
            assertGe(uint256(compositionFees) << 128, 0, "test_GetCompositionFees::1");
        } else {
            assertGe(uint128(uint256(compositionFees)), 0, "test_GetCompositionFees::2");
        }
    }

    function testFuzz_BinIsEmpty(uint128 binReserveX, uint128 binReserveY) external {
        bytes32 binReserves = binReserveX.encode(binReserveY);

        assertEq(binReserves.isEmpty(true), binReserveX == 0, "test_BinIsEmpty::1");
        assertEq(binReserves.isEmpty(false), binReserveY == 0, "test_BinIsEmpty::2");
    }

    function testFuzz_GetAmountsLessThanBin(
        uint128 binReserveX,
        uint128 binReserveY,
        bool swapForY,
        int16 deltaId,
        uint128 amountIn
    ) external {
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
        }

        bytes32 reserves = binReserveX.encode(binReserveY);

        (bytes32 amountsInToBin, bytes32 amountsOutOfBin, bytes32 totalFees) =
            reserves.getAmounts(parameters, DEFAULT_BIN_STEP, swapForY, activeId, amountIn.encode(swapForY));

        assertLe(amountsInToBin.decode(swapForY), amountIn, "test_GetAmounts::1");

        uint256 amountInWithoutFees = amountsInToBin.sub(totalFees).decode(swapForY);

        (uint256 amountOutWithNoFees, uint256 amountOut) = swapForY
            ? (
                price.mulShiftRoundDown(amountsInToBin.decodeFirst(), Constants.SCALE_OFFSET),
                amountsOutOfBin.decodeSecond()
            )
            : (
                uint256(amountsInToBin.decodeSecond()).shiftDivRoundDown(Constants.SCALE_OFFSET, price),
                amountsOutOfBin.decodeFirst()
            );

        assertGe(amountOutWithNoFees, amountOut, "test_GetAmounts::2");

        uint256 amountOutWithFees = swapForY
            ? price.mulShiftRoundDown(amountInWithoutFees, Constants.SCALE_OFFSET)
            : amountInWithoutFees.shiftDivRoundDown(Constants.SCALE_OFFSET, price);

        assertEq(amountOut, amountOutWithFees, "test_GetAmounts::3");
    }

    function testFuzz_getAmountsFullBin(
        uint128 binReserveX,
        uint128 binReserveY,
        bool swapForY,
        int16 deltaId,
        uint128 amountIn
    ) external {
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
        }

        bytes32 reserves = binReserveX.encode(binReserveY);

        (bytes32 amountsInToBin, bytes32 amountsOutOfBin, bytes32 totalFees) =
            reserves.getAmounts(parameters, DEFAULT_BIN_STEP, swapForY, activeId, amountIn.encode(swapForY));

        assertLe(amountsInToBin.decode(swapForY), amountIn, "test_GetAmounts::1");

        {
            uint256 amountInForSwap = amountsInToBin.decode(swapForY);

            (uint256 amountOutWithNoFees, uint256 amountOut) = swapForY
                ? (price.mulShiftRoundDown(amountInForSwap, Constants.SCALE_OFFSET), amountsOutOfBin.decodeSecond())
                : (uint256(amountInForSwap).shiftDivRoundDown(Constants.SCALE_OFFSET, price), amountsOutOfBin.decodeFirst());

            assertGe(amountOutWithNoFees, amountOut, "test_GetAmounts::2");
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

        assertLe(amountsOutOfBin.decode(!swapForY), amountOutWithFees, "test_GetAmounts::3");
        assertGe(amountsOutOfBin.decode(!swapForY), amountOutWithFeesAmountInSub1, "test_GetAmounts::4");
    }

    function testFuzz_Received(uint128 reserveX, uint128 reserveY, uint128 sentX, uint128 sentY) external {
        vm.assume(reserveX < type(uint128).max - sentX && reserveY < type(uint128).max - sentY);

        address pair = address(this);

        deal(address(usdc), pair, reserveX + sentX);
        deal(address(wavax), pair, reserveY + sentY);

        bytes32 reserves = reserveX.encode(reserveY);

        bytes32 received = reserves.received(IERC20(address(usdc)), IERC20(address(wavax)));

        (uint256 receivedX, uint256 receivedY) = received.decode();

        assertEq(receivedX, sentX, "test_Received::1");
        assertEq(receivedY, sentY, "test_Received::2");

        received = reserves.receivedX(IERC20(address(usdc)));
        receivedX = received.decodeFirst();

        assertEq(receivedX, sentX, "test_Received::3");

        received = reserves.receivedY(IERC20(address(wavax)));
        receivedY = received.decodeSecond();

        assertEq(receivedY, sentY, "test_Received::4");
    }

    function testFuzz_Transfer(uint128 amountX, uint128 amountY) external {
        address recipient = address(1);

        deal(address(usdc), address(this), amountX);
        deal(address(wavax), address(this), amountY);

        bytes32 amounts = amountX.encode(amountY);

        bytes32 firstHalf = amounts.sub((amountX / 2).encode((amountY / 2)));
        bytes32 secondHalf = amounts.sub(firstHalf);

        firstHalf.transfer(IERC20(address(usdc)), IERC20(address(wavax)), recipient);

        assertEq(usdc.balanceOf(recipient), firstHalf.decodeFirst(), "test_Transfer::1");
        assertEq(wavax.balanceOf(recipient), firstHalf.decodeSecond(), "test_Transfer::2");
        assertEq(usdc.balanceOf(address(this)), secondHalf.decodeFirst(), "test_Transfer::3");
        assertEq(wavax.balanceOf(address(this)), secondHalf.decodeSecond(), "test_Transfer::4");

        secondHalf.transferX(IERC20(address(usdc)), recipient);

        assertEq(usdc.balanceOf(recipient), amounts.decodeFirst(), "test_Transfer::5");
        assertEq(wavax.balanceOf(recipient), firstHalf.decodeSecond(), "test_Transfer::6");
        assertEq(usdc.balanceOf(address(this)), 0, "test_Transfer::7");
        assertEq(wavax.balanceOf(address(this)), secondHalf.decodeSecond(), "test_Transfer::8");

        secondHalf.transferY(IERC20(address(wavax)), recipient);

        assertEq(usdc.balanceOf(recipient), amounts.decodeFirst(), "test_Transfer::9");
        assertEq(wavax.balanceOf(recipient), amounts.decodeSecond(), "test_Transfer::10");
        assertEq(usdc.balanceOf(address(this)), 0, "test_Transfer::11");
        assertEq(wavax.balanceOf(address(this)), 0, "test_Transfer::12");
    }
}
