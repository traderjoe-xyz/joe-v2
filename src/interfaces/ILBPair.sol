// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/utils/introspection/IERC165.sol";

import "./ILBFactory.sol";
import "../libraries/FeeHelper.sol";

interface ILBPair is IERC165 {
    /// @dev Structure to store the reserves of bins:
    /// - reserveX: The current reserve of tokenX of the bin
    /// - reserveY: The current reserve of tokenY of the bin
    struct Bin {
        uint112 reserveX;
        uint112 reserveY;
        uint256 accTokenXPerShare;
        uint256 accTokenYPerShare;
    }

    /// @dev Structure to store the information of the pair such as:
    /// - reserveX: The sum of amounts of tokenX across all bins
    /// - reserveY: The sum of amounts of tokenY across all bins
    /// - id: The current id used for swaps, this is also linked with the price
    /// - feesX: The current amount of fees to distribute in tokenX (total, protocol)
    /// - feesY: The current amount of fees to distribute in tokenY (total, protocol)
    struct PairInformation {
        uint136 reserveX;
        uint136 reserveY;
        uint24 id;
        FeeHelper.FeesDistribution feesX;
        FeeHelper.FeesDistribution feesY;
    }

    struct Debts {
        uint256 debtX;
        uint256 debtY;
    }

    struct Amounts {
        uint128 tokenX;
        uint128 tokenY;
    }

    function tokenX() external view returns (IERC20);

    function tokenY() external view returns (IERC20);

    function factory() external view returns (ILBFactory);

    function pairInformation() external view returns (PairInformation memory);

    function feeParameters()
        external
        view
        returns (FeeHelper.FeeParameters memory);

    function findFirstBin(uint24 id, bool isSearchingRight)
        external
        view
        returns (uint256);

    function getBin(uint24 id)
        external
        view
        returns (uint112 reserveX, uint112 reserveY);

    function pendingFees(address _account, uint256[] memory _ids)
        external
        view
        returns (Amounts memory);

    function swap(bool sentTokenY, address to) external;

    function flashLoan(
        address to,
        uint256 amountXOut,
        uint256 amountYOut,
        bytes memory data
    ) external;

    function mint(
        uint256[] memory _ids,
        uint256[] memory _Ls,
        address _to
    ) external;

    function burn(
        uint256[] memory ids,
        uint256[] memory _amounts,
        address to
    ) external;

    function setFeesParameters(bytes32 packedFeeParameters) external;
}
