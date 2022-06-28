// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "forge-std/Test.sol";

import "src/LBFactory.sol";
import "src/LBPair.sol";
import "src/LBRouter.sol";
import "src/LBToken.sol";
import "src/libraries/Math512Bits.sol";

import "test/mocks/WAVAX.sol";
import "test/mocks/ERC20MockDecimals.sol";
import "test/mocks/FlashloanBorrower.sol";

abstract contract TestHelper is Test {
    using Math512Bits for uint256;

    uint24 internal constant ID_ONE = 2**23;
    uint256 internal constant PRICE_PRECISION = 1e36;
    uint256 internal constant BASIS_POINT_MAX = 10_000;

    int256 internal constant DEFAULT_LOG2_VALUE =
        int256(0xB19A9E77AF6827457B6619208C48);

    uint168 internal constant DEFAULT_MAX_ACCUMULATOR = 5_000;
    uint16 internal constant DEFAULT_FILTER_PERIOD = 50;
    uint16 internal constant DEFAULT_DECAY_PERIOD = 100;
    uint16 internal constant DEFAULT_BIN_STEP = 25;
    uint16 internal constant DEFAULT_BASE_FACTOR = 5_000;
    uint16 internal constant DEFAULT_PROTOCOL_SHARE = 1_000;
    uint8 internal constant DEFAULT_VARIABLEFEE_STATE = 0;

    bytes32 internal constant DEFAULT_PACKED_FEES_PARAMETERS =
        bytes32(
            abi.encodePacked(
                DEFAULT_VARIABLEFEE_STATE,
                DEFAULT_PROTOCOL_SHARE,
                DEFAULT_BASE_FACTOR,
                DEFAULT_BIN_STEP,
                DEFAULT_DECAY_PERIOD,
                DEFAULT_FILTER_PERIOD,
                DEFAULT_MAX_ACCUMULATOR
            )
        );

    address internal constant DEV = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
    address internal constant ALICE =
        0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant BOB = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;

    WAVAX internal wavax;
    ERC20MockDecimals internal token6D;
    ERC20MockDecimals internal token12D;
    ERC20MockDecimals internal token18D;

    LBFactory internal factory;
    LBRouter internal router;
    LBPair internal pair;

    function getPriceFromId(uint24 _id) internal pure returns (uint256 price) {
        price = BinHelper.getPriceFromId(_id, DEFAULT_LOG2_VALUE);
    }

    function getIdFromPrice(uint256 _price) internal pure returns (uint24 id) {
        id = BinHelper.getIdFromPrice(_price, DEFAULT_LOG2_VALUE);
    }

    function createLBPairDefaultFees(IERC20 _token0, IERC20 _token1)
        internal
        returns (LBPair newPair)
    {
        newPair = LBPair(
            address(
                factory.createLBPair(
                    _token0,
                    _token1,
                    DEFAULT_MAX_ACCUMULATOR,
                    DEFAULT_FILTER_PERIOD,
                    DEFAULT_DECAY_PERIOD,
                    DEFAULT_BIN_STEP,
                    DEFAULT_BASE_FACTOR,
                    DEFAULT_PROTOCOL_SHARE
                )
            )
        );
    }

    function addLiquidity(
        uint256 _amount1In,
        uint24 _startId,
        uint24 _numberBins,
        uint24 _gap
    ) internal {
        (
            uint256[] memory _ids,
            uint256[] memory _liquidities,
            uint256 amountXInLiquidity
        ) = spreadLiquidityN(_amount1In * 2, _startId, _numberBins, _gap);

        token6D.mint(address(pair), amountXInLiquidity);
        token18D.mint(address(pair), _amount1In);

        pair.mint(_ids, _liquidities, DEV);
    }

    function spreadLiquidityN(
        uint256 _amount1In,
        uint24 _startId,
        uint24 _numberBins,
        uint24 _gap
    )
        internal
        pure
        returns (
            uint256[] memory _ids,
            uint256[] memory _liquidities,
            uint256 amount0In
        )
    {
        uint24 spread = _numberBins / 2;
        _ids = new uint256[](_numberBins);
        _ids[0] = _startId;
        for (uint24 i; i < spread; i++) {
            _ids[2 * i + 1] = _startId - i - 1 - _gap;
            _ids[2 * i + 2] = _startId + i + 1 + _gap;
        }

        _liquidities = new uint256[](_numberBins);
        uint256 binLiquidity = _amount1In / _numberBins;
        _liquidities[0] = binLiquidity;
        amount0In += binLiquidity.mulDivRoundUp(
            PRICE_PRECISION,
            2 * getPriceFromId(_startId)
        );

        for (uint24 i; i < spread; i++) {
            _liquidities[2 * i + 1] = binLiquidity;
            _liquidities[2 * i + 2] = binLiquidity;
            amount0In += binLiquidity.mulDivRoundUp(
                PRICE_PRECISION,
                getPriceFromId(_startId + i + 1)
            );
        }
    }
}
