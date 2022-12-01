// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "src/LBFactory.sol";
import "src/LBPair.sol";
import "src/LBRouter.sol";
import "src/LBQuoter.sol";
import "src/LBErrors.sol";
import "src/interfaces/ILBRouter.sol";
import "src/interfaces/IJoeRouter02.sol";
import "src/LBToken.sol";
import "src/libraries/Math512Bits.sol";
import "src/libraries/Constants.sol";

import "test/mocks/WAVAX.sol";
import "test/mocks/ERC20MockDecimals.sol";
import "test/mocks/FlashloanBorrower.sol";
import "test/mocks/ERC20WithTransferTax.sol";

abstract contract TestHelper is Test, IERC165 {
    using Math512Bits for uint256;

    uint24 internal constant ID_ONE = 2**23;
    uint256 internal constant BASIS_POINT_MAX = 10_000;

    uint24 internal constant DEFAULT_MAX_VOLATILITY_ACCUMULATED = 1_777_638;
    uint16 internal constant DEFAULT_FILTER_PERIOD = 50;
    uint16 internal constant DEFAULT_DECAY_PERIOD = 100;
    uint16 internal constant DEFAULT_BIN_STEP = 25;
    uint16 internal constant DEFAULT_BASE_FACTOR = 5000;
    uint16 internal constant DEFAULT_PROTOCOL_SHARE = 1000;
    uint16 internal constant DEFAULT_SAMPLE_LIFETIME = 120;
    uint16 internal constant DEFAULT_REDUCTION_FACTOR = 5000;
    uint24 internal constant DEFAULT_VARIABLE_FEE_CONTROL = 5000;

    address payable internal immutable DEV = payable(address(this));
    address payable internal constant ALICE = payable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address payable internal constant BOB = payable(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);

    address internal constant JOE_V1_FACTORY_ADDRESS = 0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10;
    address internal constant JOE_V1_ROUTER_ADDRESS = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;
    address internal constant WAVAX_AVALANCHE_ADDRESS = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address internal constant USDC_AVALANCHE_ADDRESS = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    WAVAX internal wavax;
    ERC20MockDecimals internal usdc;
    ERC20MockDecimals internal usdt;

    ERC20MockDecimals internal token6D;
    ERC20MockDecimals internal token10D;
    ERC20MockDecimals internal token12D;
    ERC20MockDecimals internal token18D;
    ERC20MockDecimals internal token24D;

    ERC20WithTransferTax internal taxToken;

    LBFactory internal factory;
    LBRouter internal router;
    IJoeRouter02 internal routerV1 = IJoeRouter02(JOE_V1_ROUTER_ADDRESS);
    LBPair internal pair;
    LBPair internal pairWavax;
    LBQuoter internal quoter;

    function supportsInterface(bytes4 interfaceId) external view virtual returns (bool) {
        return interfaceId == type(ILBToken).interfaceId;
    }

    function getPriceFromId(uint24 _id) internal pure returns (uint256 price) {
        price = BinHelper.getPriceFromId(_id, DEFAULT_BIN_STEP);
    }

    function getIdFromPrice(uint256 _price) internal pure returns (uint24 id) {
        id = BinHelper.getIdFromPrice(_price, DEFAULT_BIN_STEP);
    }

    function createLBPairDefaultFees(IERC20 _tokenX, IERC20 _tokenY) internal returns (LBPair newPair) {
        newPair = createLBPairDefaultFeesFromStartId(_tokenX, _tokenY, ID_ONE);
    }

    function setDefaultFactoryPresets(uint16 _binStep) internal {
        factory.setPreset(
            _binStep,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_VOLATILITY_ACCUMULATED,
            DEFAULT_SAMPLE_LIFETIME
        );
    }

    function createLBPairDefaultFeesFromStartId(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint24 _startId
    ) internal returns (LBPair newPair) {
        newPair = createLBPairDefaultFeesFromStartIdAndBinStep(_tokenX, _tokenY, _startId, DEFAULT_BIN_STEP);
    }

    function createLBPairDefaultFeesFromStartIdAndBinStep(
        IERC20 _tokenX,
        IERC20 _tokenY,
        uint24 _startId,
        uint16 _binStep
    ) internal returns (LBPair newPair) {
        newPair = LBPair(address(factory.createLBPair(_tokenX, _tokenY, _startId, _binStep)));
    }

    function addLiquidity(
        uint256 _amountYIn,
        uint24 _startId,
        uint24 _numberBins,
        uint24 _gap
    )
        internal
        returns (
            uint256[] memory _ids,
            uint256[] memory _distributionX,
            uint256[] memory _distributionY,
            uint256 amountXIn
        )
    {
        (_ids, _distributionX, _distributionY, amountXIn) = spreadLiquidity(_amountYIn, _startId, _numberBins, _gap);

        token6D.mint(address(pair), amountXIn);
        token18D.mint(address(pair), _amountYIn);

        pair.mint(_ids, _distributionX, _distributionY, DEV);
    }

    function spreadLiquidity(
        uint256 _amountYIn,
        uint24 _startId,
        uint24 _numberBins,
        uint24 _gap
    )
        internal
        pure
        returns (
            uint256[] memory _ids,
            uint256[] memory _distributionX,
            uint256[] memory _distributionY,
            uint256 amountXIn
        )
    {
        if (_numberBins % 2 == 0) {
            revert("Pls put an uneven number of bins");
        }

        uint24 spread = _numberBins / 2;
        _ids = new uint256[](_numberBins);

        _distributionX = new uint256[](_numberBins);
        _distributionY = new uint256[](_numberBins);
        uint256 binDistribution = Constants.PRECISION / (spread + 1);
        uint256 binLiquidity = _amountYIn / (spread + 1);

        for (uint256 i; i < _numberBins; i++) {
            _ids[i] = _startId - spread * (1 + _gap) + i * (1 + _gap);

            if (i <= spread) {
                _distributionY[i] = binDistribution;
            }
            if (i >= spread) {
                _distributionX[i] = binDistribution;
                amountXIn += binLiquidity > 0
                    ? (binLiquidity * Constants.SCALE - 1) / getPriceFromId(uint24(_ids[i])) + 1
                    : 0;
            }
        }
    }

    function addLiquidityFromRouter(
        ERC20MockDecimals _tokenX,
        ERC20MockDecimals _tokenY,
        uint256 _amountYIn,
        uint24 _startId,
        uint24 _numberBins,
        uint24 _gap,
        uint16 _binStep
    )
        internal
        returns (
            int256[] memory _deltaIds,
            uint256[] memory _distributionX,
            uint256[] memory _distributionY,
            uint256 amountXIn
        )
    {
        (_deltaIds, _distributionX, _distributionY, amountXIn) = spreadLiquidityForRouter(
            _amountYIn,
            _startId,
            _numberBins,
            _gap
        );

        ILBRouter.LiquidityParameters memory _liquidityParameters = ILBRouter.LiquidityParameters(
            _tokenX,
            _tokenY,
            _binStep,
            amountXIn,
            _amountYIn,
            0,
            0,
            _startId,
            0,
            _deltaIds,
            _distributionX,
            _distributionY,
            DEV,
            block.timestamp
        );

        if (address(_tokenY) == address(wavax)) {
            vm.deal(DEV, _amountYIn);
            _tokenX.mint(DEV, amountXIn);
            _tokenX.approve(address(router), amountXIn);
            router.addLiquidityAVAX{value: _amountYIn}(_liquidityParameters);
        } else if (address(_tokenX) == address(wavax)) {
            vm.deal(DEV, amountXIn);
            _tokenY.mint(DEV, _amountYIn);
            _tokenY.approve(address(router), _amountYIn);
            router.addLiquidityAVAX{value: amountXIn}(_liquidityParameters);
        } else {
            _tokenX.approve(address(router), amountXIn);
            _tokenX.mint(DEV, amountXIn);
            _tokenY.approve(address(router), _amountYIn);
            _tokenY.mint(DEV, _amountYIn);
            router.addLiquidity(_liquidityParameters);
        }
    }

    function spreadLiquidityForRouter(
        uint256 _amountYIn,
        uint24 _startId,
        uint24 _numberBins,
        uint24 _gap
    )
        internal
        pure
        returns (
            int256[] memory _deltaIds,
            uint256[] memory _distributionX,
            uint256[] memory _distributionY,
            uint256 amountXIn
        )
    {
        if (_numberBins % 2 == 0) {
            revert("Pls put an uneven number of bins");
        }

        uint256 spread = _numberBins / 2;
        _deltaIds = new int256[](_numberBins);

        _distributionX = new uint256[](_numberBins);
        _distributionY = new uint256[](_numberBins);
        uint256 binDistribution = Constants.PRECISION / (spread + 1);
        uint256 binLiquidity = _amountYIn / (spread + 1);

        for (uint256 i; i < _numberBins; i++) {
            _deltaIds[i] = int256(i * (1 + _gap)) - int256(spread * (1 + _gap));

            if (i <= spread) {
                _distributionY[i] = binDistribution;
            }
            if (i >= spread) {
                _distributionX[i] = binDistribution;
                amountXIn +=
                    (binLiquidity * Constants.SCALE) /
                    getPriceFromId(uint24(int24(_startId) + int24(_deltaIds[i])));
            }
        }
    }

    function prepareLiquidityParameters(
        ERC20MockDecimals _tokenX,
        ERC20MockDecimals _tokenY,
        uint256 _amountYIn,
        uint24 _startId,
        uint24 _numberBins,
        uint24 _gap,
        uint16 _binStep
    ) internal returns (ILBRouter.LiquidityParameters memory) {
        int256[] memory _deltaIds;
        uint256[] memory _distributionX;
        uint256[] memory _distributionY;
        uint256 amountXIn;
        (_deltaIds, _distributionX, _distributionY, amountXIn) = spreadLiquidityForRouter(
            _amountYIn,
            _startId,
            _numberBins,
            _gap
        );

        _tokenX.mint(DEV, amountXIn);
        _tokenX.approve(address(router), amountXIn);

        if (address(_tokenY) == address(wavax)) {
            vm.deal(DEV, _amountYIn);
        } else {
            _tokenY.approve(address(router), _amountYIn);
            _tokenY.mint(DEV, _amountYIn);
        }

        return
            ILBRouter.LiquidityParameters(
                _tokenX,
                _tokenY,
                _binStep,
                amountXIn,
                _amountYIn,
                0, //possible slippage = max
                0, //possible slippage = max
                ID_ONE,
                ID_ONE, //possible slippage = max
                _deltaIds,
                _distributionX,
                _distributionY,
                DEV,
                block.timestamp
            );
    }

    function addAllAssetsToQuoteWhitelist(LBFactory _factory) internal {
        if (address(wavax) != address(0)) _factory.addQuoteAsset(wavax);
        if (address(usdc) != address(0)) _factory.addQuoteAsset(usdc);
        if (address(usdt) != address(0)) _factory.addQuoteAsset(usdt);
        if (address(taxToken) != address(0)) _factory.addQuoteAsset(taxToken);
        if (address(token6D) != address(0)) _factory.addQuoteAsset(token6D);
        if (address(token10D) != address(0)) _factory.addQuoteAsset(token10D);
        if (address(token12D) != address(0)) _factory.addQuoteAsset(token12D);
        if (address(token18D) != address(0)) _factory.addQuoteAsset(token18D);
        if (address(token24D) != address(0)) _factory.addQuoteAsset(token24D);
    }
}
