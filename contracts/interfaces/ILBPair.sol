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
        uint128 fees0;
        uint128 fees1;
    }

    /// @dev Structure to store the information of the pair such as:
    /// - reserve0: The sum of amounts of token0 across all bins
    /// - reserve1: The sum of amounts of token1 across all bins
    /// - id: The current id used for swaps, this is also linked with the price
    /// - fees0: The token0 fees, they will be distributed to users and to the protocol
    /// - fees1: The token1 fees, they will be distributed to users and to the protocol
    struct PairInformation {
        uint136 reserve0;
        uint136 reserve1;
        uint24 id;
        uint128 fees0;
        uint128 fees1;
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
        uint24 startId,
        uint112[] calldata amounts0,
        uint112[] calldata amounts1,
        address to
    ) external;

    function burn(uint24[] calldata ids, address to) external;
}
