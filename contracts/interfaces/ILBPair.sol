// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "../libraries/FeeHelper.sol";

interface ILBPair {
    /// @dev Structure to store the reserves of bins:
    /// - reserve0: The current reserve of token0 of the bin
    /// - reserve1: The current reserve of token1 of the bin
    struct Bin {
        uint112 reserve0;
        uint112 reserve1;
    }

    /// @dev Structure to store the information of the pair such as:
    /// - reserve0: The sum of amounts of token0 across all bins
    /// - reserve1: The sum of amounts of token1 across all bins
    /// - id: The current id used for swaps, this is also linked with the price
    /// - protocolFees0: The protocol fees received in token0
    /// - protocolFees1: The protocol fees received in token1
    struct Pair {
        uint136 reserve0;
        uint136 reserve1;
        uint24 id;
        uint128 protocolFees0;
        uint128 protocolFees1;
    }

    function PRICE_PRECISION() external pure returns (uint256);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function factory() external view returns (address);

    function log2Value() external view returns (int256);

    function pair() external view returns (Pair memory);

    function feeParameters()
        external
        view
        returns (FeeHelper.FeeParameters memory);

    function getBin(uint24 _id)
        external
        view
        returns (
            uint256 price,
            uint112 reserve0,
            uint112 reserve1
        );

    function getIdFromPrice(uint256 _price) external view returns (uint24);

    function getPriceFromId(uint24 _id) external view returns (uint256);

    function getSwapIn(uint256 _amount0Out, uint256 _amount1Out)
        external
        view
        returns (uint256 amount0In, uint256 amount1In);

    function getSwapOut(uint256 _amount0In, uint256 _amount1In)
        external
        view
        returns (uint256 amount0Out, uint256 amount1Out);

    function swap(
        uint256 _amount0Out,
        uint256 _amount1Out,
        address _to,
        bytes calldata _data
    ) external;

    function mint(
        uint24 _startId,
        uint112[] calldata _amounts0,
        uint112[] calldata _amounts1,
        address _to
    ) external;

    function burn(uint24[] calldata _ids, address _to) external;

    function distributeProtocolFees() external;
}
