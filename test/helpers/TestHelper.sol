// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Test.sol";

import "src/LBFactory.sol";
import "src/LBPair.sol";
import "src/LBRouter.sol";
import "src/LBQuoter.sol";
import "src/interfaces/ILBRouter.sol";
import "src/interfaces/IJoeRouter02.sol";
import "src/LBToken.sol";
import "src/libraries/math/Uint256x256Math.sol";
import "src/libraries/Constants.sol";

import "test/mocks/WAVAX.sol";
import "test/mocks/ERC20.sol";
import "test/mocks/FlashloanBorrower.sol";
import "test/mocks/ERC20TransferTax.sol";

abstract contract TestHelper is Test, IERC165 {
    using Uint256x256Math for uint256;

    uint24 internal constant ID_ONE = 2 ** 23;
    uint256 internal constant BASIS_POINT_MAX = 10_000;

    // Avalanche market config for 10bps
    uint16 internal constant DEFAULT_BIN_STEP = 10;
    uint16 internal constant DEFAULT_BASE_FACTOR = 1000;
    uint16 internal constant DEFAULT_FILTER_PERIOD = 30;
    uint16 internal constant DEFAULT_DECAY_PERIOD = 600;
    uint16 internal constant DEFAULT_REDUCTION_FACTOR = 5_000;
    uint24 internal constant DEFAULT_VARIABLE_FEE_CONTROL = 40_000;
    uint16 internal constant DEFAULT_PROTOCOL_SHARE = 1_000;
    uint24 internal constant DEFAULT_MAX_VOLATILITY_ACCUMULATED = 350_000;
    uint16 internal constant DEFAULT_SAMPLE_LIFETIME = 120;
    uint256 internal constant DEFAULT_FLASHLOAN_FEE = 8e14;

    address payable immutable DEV = payable(address(this));
    address payable immutable ALICE = payable(makeAddr("alice"));
    address payable immutable BOB = payable(makeAddr("bob"));

    // Wrapped Native
    WAVAX internal wavax;

    // 6 decimals
    ERC20Mock internal usdc;
    ERC20Mock internal usdt;

    // 8 decimals
    ERC20Mock internal wbtc;

    // 18 decimals
    ERC20Mock internal link;
    ERC20Mock internal bnb;
    ERC20Mock internal weth;

    // Tax tokens (18 decimals)
    ERC20TransferTaxMock internal taxToken;

    LBFactory internal factory;
    LBRouter internal router;
    LBPair internal pair;
    LBPair internal pairWavax;
    LBQuoter internal quoter;

    function setUp() public virtual {
        // Create mocks
        wavax = new WAVAX();
        usdc = new ERC20Mock(6);
        usdt = new ERC20Mock(6);
        wbtc = new ERC20Mock(8);
        weth = new ERC20Mock(18);
        link = new ERC20Mock(18);
        bnb = new ERC20Mock(18);
        taxToken = new ERC20TransferTaxMock();

        // Label mocks
        vm.label(address(wavax), "wavax");
        vm.label(address(usdc), "usdc");
        vm.label(address(usdt), "usdt");
        vm.label(address(wbtc), "wbtc");
        vm.label(address(weth), "weth");
        vm.label(address(link), "link");
        vm.label(address(bnb), "bnb");
        vm.label(address(taxToken), "taxToken");

        // Create factory
        factory = new LBFactory(DEV, DEFAULT_FLASHLOAN_FEE);
        ILBPair LBPairImplementation = new LBPair(factory);

        // Setup factory
        factory.setLBPairImplementation(address(LBPairImplementation));
        addAllAssetsToQuoteWhitelist();
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        // Create router
        router = new LBRouter(factory, IJoeFactory(address(0)), IWAVAX(address(0)));

        // Label deployed contracts
        vm.label(address(factory), "factory");
        vm.label(address(router), "router");
        vm.label(address(LBPairImplementation), "LBPairImplementation");
    }

    function supportsInterface(bytes4 interfaceId) external view virtual returns (bool) {
        return interfaceId == type(ILBToken).interfaceId;
    }

    function getPriceFromId(uint24 id) internal pure returns (uint256 price) {
        price = BinHelper.getPriceFromId(id, DEFAULT_BIN_STEP);
    }

    function getIdFromPrice(uint256 price) internal pure returns (uint24 id) {
        id = BinHelper.getIdFromPrice(price, DEFAULT_BIN_STEP);
    }

    function createLBPair(IERC20 tokenX, IERC20 tokenY) internal returns (LBPair newPair) {
        newPair = createLBPairFromStartId(tokenX, tokenY, ID_ONE);
    }

    function setDefaultFactoryPresets(uint16 binStep) internal {
        factory.setPreset(
            binStep,
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

    function createLBPairFromStartId(IERC20 tokenX, IERC20 tokenY, uint24 startId) internal returns (LBPair newPair) {
        newPair = createLBPairFromStartIdAndBinStep(tokenX, tokenY, startId, DEFAULT_BIN_STEP);
    }

    function createLBPairFromStartIdAndBinStep(IERC20 tokenX, IERC20 tokenY, uint24 startId, uint16 binStep)
        internal
        returns (LBPair newPair)
    {
        newPair = LBPair(address(factory.createLBPair(tokenX, tokenY, startId, binStep)));
    }

    function convertRelativeIdsToAbsolute(int256[] memory relativeIds, uint24 startId)
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

    function convertAbsoluteIdsToRelative(uint256[] memory absoluteIds, uint24 startId)
        internal
        pure
        returns (int256[] memory relativeIds)
    {
        relativeIds = new int256[](absoluteIds.length);
        for (uint256 i = 0; i < absoluteIds.length; i++) {
            relativeIds[i] = int256(absoluteIds[i]) - int256(uint256(startId));
        }
    }

    function addLiquidityAndReturnAbsoluteIds(
        ERC20Mock tokenX,
        ERC20Mock tokenY,
        uint256 amountYIn,
        uint24 startId,
        uint24 numberBins,
        uint24 gap
    )
        internal
        returns (
            uint256[] memory ids,
            uint256[] memory distributionX,
            uint256[] memory distributionY,
            uint256 amountXIn
        )
    {
        (ids, distributionX, distributionY, amountXIn) =
            addLiquidity(tokenX, tokenY, amountYIn, startId, numberBins, gap);
    }

    function addLiquidityAndReturnRelativeIds(
        ERC20Mock tokenX,
        ERC20Mock tokenY,
        uint256 amountYIn,
        uint24 startId,
        uint24 numberBins,
        uint24 gap
    )
        internal
        returns (int256[] memory ids, uint256[] memory distributionX, uint256[] memory distributionY, uint256 amountXIn)
    {
        uint256[] memory absoluteIds;
        (absoluteIds, distributionX, distributionY, amountXIn) =
            addLiquidity(tokenX, tokenY, amountYIn, startId, numberBins, gap);
        ids = convertAbsoluteIdsToRelative(absoluteIds, startId);
    }

    function addLiquidity(
        ERC20Mock tokenX,
        ERC20Mock tokenY,
        uint256 amountYIn,
        uint24 startId,
        uint24 numberBins,
        uint24 gap
    )
        internal
        returns (
            uint256[] memory ids,
            uint256[] memory distributionX,
            uint256[] memory distributionY,
            uint256 amountXIn
        )
    {
        (ids, distributionX, distributionY, amountXIn) = spreadLiquidity(amountYIn, startId, numberBins, gap);

        tokenX.mint(address(pair), amountXIn);
        tokenY.mint(address(pair), amountYIn);

        pair.mint(ids, distributionX, distributionY, DEV);
    }

    function spreadLiquidity(uint256 amountYIn, uint24 startId, uint24 numberBins, uint24 gap)
        internal
        pure
        returns (
            uint256[] memory ids,
            uint256[] memory distributionX,
            uint256[] memory distributionY,
            uint256 amountXIn
        )
    {
        if (numberBins % 2 == 0) {
            revert("Pls put an uneven number of bins");
        }

        uint24 spread = numberBins / 2;
        ids = new uint256[](numberBins);

        distributionX = new uint256[](numberBins);
        distributionY = new uint256[](numberBins);
        uint256 binDistribution = Constants.PRECISION / (spread + 1);
        uint256 binLiquidity = amountYIn / (spread + 1);

        for (uint256 i; i < numberBins; i++) {
            ids[i] = startId - spread * (1 + gap) + i * (1 + gap);

            if (i <= spread) {
                distributionY[i] = binDistribution;
            }
            if (i >= spread) {
                distributionX[i] = binDistribution;
                amountXIn +=
                    binLiquidity > 0 ? (binLiquidity * Constants.SCALE - 1) / getPriceFromId(uint24(ids[i])) + 1 : 0;
            }
        }
    }

    function addAllAssetsToQuoteWhitelist() internal {
        if (address(wavax) != address(0)) factory.addQuoteAsset(wavax);
        if (address(usdc) != address(0)) factory.addQuoteAsset(usdc);
        if (address(usdt) != address(0)) factory.addQuoteAsset(usdt);
        if (address(wbtc) != address(0)) factory.addQuoteAsset(wbtc);
        if (address(weth) != address(0)) factory.addQuoteAsset(weth);
        if (address(link) != address(0)) factory.addQuoteAsset(link);
        if (address(bnb) != address(0)) factory.addQuoteAsset(bnb);
        if (address(taxToken) != address(0)) factory.addQuoteAsset(taxToken);
    }
}
