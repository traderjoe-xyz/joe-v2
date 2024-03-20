// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ILBRouter} from "../../src/interfaces/ILBRouter.sol";
import {ILBLegacyRouter} from "../../src/interfaces/ILBLegacyRouter.sol";

library Utils {
    function convertToAbsolute(int256[] memory relativeIds, uint24 startId)
        internal
        pure
        returns (uint256[] memory absoluteIds)
    {
        absoluteIds = new uint256[](relativeIds.length);
        for (uint256 i = 0; i < relativeIds.length; i++) {
            int256 id = int256(uint256(startId)) + relativeIds[i];
            require(id >= 0, "Id conversion: id must be positive");
            absoluteIds[i] = uint256(id);
        }
    }

    function convertToRelative(uint256[] memory absoluteIds, uint24 startId)
        internal
        pure
        returns (int256[] memory relativeIds)
    {
        relativeIds = new int256[](absoluteIds.length);
        for (uint256 i = 0; i < absoluteIds.length; i++) {
            relativeIds[i] = int256(absoluteIds[i]) - int256(uint256(startId));
        }
    }

    function toLegacy(ILBRouter.LiquidityParameters memory liquidityParameters)
        internal
        pure
        returns (ILBLegacyRouter.LiquidityParameters memory legacyLiquidityParameters)
    {
        legacyLiquidityParameters = ILBLegacyRouter.LiquidityParameters({
            tokenX: liquidityParameters.tokenX,
            tokenY: liquidityParameters.tokenY,
            binStep: liquidityParameters.binStep,
            amountX: liquidityParameters.amountX,
            amountY: liquidityParameters.amountY,
            amountXMin: liquidityParameters.amountXMin,
            amountYMin: liquidityParameters.amountYMin,
            activeIdDesired: liquidityParameters.activeIdDesired,
            idSlippage: liquidityParameters.idSlippage,
            deltaIds: liquidityParameters.deltaIds,
            distributionX: liquidityParameters.distributionX,
            distributionY: liquidityParameters.distributionY,
            to: liquidityParameters.to,
            deadline: liquidityParameters.deadline
        });
    }
}
