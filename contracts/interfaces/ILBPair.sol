// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import "./ILBFactory.sol";
import "../libraries/FeeHelper.sol";

interface ILBPair is IERC165 {
    /// @dev Structure to store the reserves of bins:
    /// - reserve0: The current reserve of token0 of the bin
    /// - reserve1: The current reserve of token1 of the bin
    struct Bin {
        uint112 reserve0;
        uint112 reserve1;
        uint256 accToken0PerShare;
        uint256 accToken1PerShare;
    }

    /// @dev Structure to store the information of the pair such as:
    /// - reserve0: The sum of amounts of token0 across all bins
    /// - reserve1: The sum of amounts of token1 across all bins
    /// - id: The current id used for swaps, this is also linked with the price
    /// - fees0: The current amount of fees to distribute in token0 (total, protocol)
    /// - fees1: The current amount of fees to distribute in token1 (total, protocol)
    struct PairInformation {
        uint136 reserve0;
        uint136 reserve1;
        uint24 id;
        FeeHelper.FeesDistribution fees0;
        FeeHelper.FeesDistribution fees1;
    }

    struct FeesOut {
        uint128 amount0;
        uint128 amount1;
    }

    struct UnclaimedFees {
        uint128 token0;
        uint128 token1;
    }

    struct Debts {
        uint256 debt0;
        uint256 debt1;
    }

    struct Amounts {
        uint128 token0;
        uint128 token1;
    }

    function PRICE_PRECISION() external pure returns (uint256);

    function token0() external view returns (IERC20);

    function token1() external view returns (IERC20);

    function factory() external view returns (ILBFactory);

    function log2Value() external view returns (int256);

    function pairInformation() external view returns (PairInformation memory);

    function feeParameters()
        external
        view
        returns (FeeHelper.FeeParameters memory);

    function getBin(uint24 id)
        external
        view
        returns (
            uint256 price,
            uint112 reserve0,
            uint112 reserve1
        );

    function getIdFromPrice(uint256 price) external view returns (uint24);

    function getPriceFromId(uint24 id) external view returns (uint256);

    function getSwapIn(uint256 amount0Out, uint256 amount1Out)
        external
        view
        returns (uint256 amount0In, uint256 amount1In);

    function getSwapOut(uint256 amount0In, uint256 amount1In)
        external
        view
        returns (uint256 amount0Out, uint256 amount1Out);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to
    ) external;

    function flashLoan(
        address to,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) external;

    function mint(
        uint256[] calldata _ids,
        uint256[] calldata _Ls,
        address _to
    ) external;

    function burn(
        uint256[] calldata ids,
        uint256[] calldata _amounts,
        address to
    ) external;
}
