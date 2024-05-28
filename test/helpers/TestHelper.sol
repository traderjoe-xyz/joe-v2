// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import "src/LBFactory.sol";
import "src/LBPair.sol";
import "src/LBRouter.sol";
import "src/LBQuoter.sol";
import "src/interfaces/ILBRouter.sol";
import "src/interfaces/IJoeRouter02.sol";
import "src/interfaces/ILBLegacyRouter.sol";
import "src/interfaces/ILBLegacyFactory.sol";
import "src/LBToken.sol";
import "src/libraries/math/Uint256x256Math.sol";
import "src/libraries/Constants.sol";

import {PriceHelper} from "src/libraries/PriceHelper.sol";

import "./Utils.sol";

import "test/mocks/WNATIVE.sol";
import "test/mocks/ERC20.sol";
import "test/mocks/FlashBorrower.sol";
import "test/mocks/ERC20TransferTax.sol";

import {AvalancheAddresses} from "../integration/Addresses.sol";

abstract contract TestHelper is Test {
    using Uint256x256Math for uint256;
    using Utils for uint256[];
    using Utils for int256[];
    using SafeCast for uint256;

    uint24 internal constant ID_ONE = 2 ** 23;
    uint256 internal constant BASIS_POINT_MAX = 10_000;

    // Avalanche market config for 10bps
    uint16 internal constant DEFAULT_BIN_STEP = 10;
    uint16 internal constant DEFAULT_BASE_FACTOR = 5_000;
    uint16 internal constant DEFAULT_FILTER_PERIOD = 30;
    uint16 internal constant DEFAULT_DECAY_PERIOD = 600;
    uint16 internal constant DEFAULT_REDUCTION_FACTOR = 5_000;
    uint24 internal constant DEFAULT_VARIABLE_FEE_CONTROL = 40_000;
    uint16 internal constant DEFAULT_PROTOCOL_SHARE = 1_000;
    uint24 internal constant DEFAULT_MAX_VOLATILITY_ACCUMULATOR = 350_000;
    bool internal constant DEFAULT_OPEN_STATE = false;
    uint256 internal constant DEFAULT_FLASHLOAN_FEE = 8e14;

    address payable immutable DEV = payable(address(this));
    address payable immutable ALICE = payable(makeAddr("alice"));
    address payable immutable BOB = payable(makeAddr("bob"));

    // Wrapped Native
    WNATIVE internal wnative;

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
    LBPair internal localPair;
    LBPair internal pairWnative;
    LBQuoter internal quoter;
    LBPair internal pairImplementation;

    // Forked contracts
    IJoeRouter02 internal routerV1;
    IJoeFactory internal factoryV1;
    ILBLegacyRouter internal legacyRouterV2;
    ILBLegacyFactory internal legacyFactoryV2;
    ILBRouter internal routerV2_1;
    ILBFactory internal factoryV2_1;

    function setUp() public virtual {
        wnative = WNATIVE(AvalancheAddresses.WNATIVE);
        // If not forking, deploy mock
        if (address(wnative).code.length == 0) {
            vm.etch(address(wnative), address(new WNATIVE()).code);
        }

        // Create mocks
        usdc = new ERC20Mock(6);
        usdt = new ERC20Mock(6);
        wbtc = new ERC20Mock(8);
        weth = new ERC20Mock(18);
        link = new ERC20Mock(18);
        bnb = new ERC20Mock(18);
        taxToken = new ERC20TransferTaxMock();

        // Label mocks
        vm.label(address(wnative), "wnative");
        vm.label(address(usdc), "usdc");
        vm.label(address(usdt), "usdt");
        vm.label(address(wbtc), "wbtc");
        vm.label(address(weth), "weth");
        vm.label(address(link), "link");
        vm.label(address(bnb), "bnb");
        vm.label(address(taxToken), "taxToken");

        // Get forked contracts
        routerV1 = IJoeRouter02(AvalancheAddresses.JOE_V1_ROUTER);
        factoryV1 = IJoeFactory(AvalancheAddresses.JOE_V1_FACTORY);
        legacyRouterV2 = ILBLegacyRouter(AvalancheAddresses.JOE_V2_ROUTER);
        legacyFactoryV2 = ILBLegacyFactory(AvalancheAddresses.JOE_V2_FACTORY);
        factoryV2_1 = ILBFactory(AvalancheAddresses.JOE_V2_1_FACTORY);
        routerV2_1 = ILBRouter(AvalancheAddresses.JOE_V2_1_ROUTER);

        // Create factory
        factory = new LBFactory(DEV, DEV, DEFAULT_FLASHLOAN_FEE);
        pairImplementation = new LBPair(factory);

        // Setup factory
        factory.setLBPairImplementation(address(pairImplementation));
        addAllAssetsToQuoteWhitelist();
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        // Create router
        router =
            new LBRouter(factory, factoryV1, legacyFactoryV2, legacyRouterV2, factoryV2_1, IWNATIVE(address(wnative)));

        // Create quoter
        quoter = new LBQuoter(
            address(factoryV1),
            address(legacyFactoryV2),
            address(factoryV2_1),
            address(factory),
            address(legacyRouterV2),
            address(routerV2_1),
            address(router)
        );

        // Label deployed contracts
        vm.label(address(router), "router");
        vm.label(address(quoter), "quoter");
        vm.label(address(factory), "factory");
        vm.label(address(pairImplementation), "pairImplementation");

        // Label forks
        vm.label(address(routerV1), "routerV1");
        vm.label(address(factoryV1), "factoryV1");
        vm.label(address(legacyRouterV2), "legacyRouterV2");
        vm.label(address(legacyFactoryV2), "legacyFactoryV2");

        // Give approvals to routers
        wnative.approve(address(routerV1), type(uint256).max);
        usdc.approve(address(routerV1), type(uint256).max);
        usdt.approve(address(routerV1), type(uint256).max);
        wbtc.approve(address(routerV1), type(uint256).max);
        weth.approve(address(routerV1), type(uint256).max);
        link.approve(address(routerV1), type(uint256).max);
        bnb.approve(address(routerV1), type(uint256).max);
        taxToken.approve(address(routerV1), type(uint256).max);

        wnative.approve(address(legacyRouterV2), type(uint256).max);
        usdc.approve(address(legacyRouterV2), type(uint256).max);
        usdt.approve(address(legacyRouterV2), type(uint256).max);
        wbtc.approve(address(legacyRouterV2), type(uint256).max);
        weth.approve(address(legacyRouterV2), type(uint256).max);
        link.approve(address(legacyRouterV2), type(uint256).max);
        bnb.approve(address(legacyRouterV2), type(uint256).max);
        taxToken.approve(address(legacyRouterV2), type(uint256).max);

        wnative.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        usdt.approve(address(router), type(uint256).max);
        wbtc.approve(address(router), type(uint256).max);
        weth.approve(address(router), type(uint256).max);
        link.approve(address(router), type(uint256).max);
        bnb.approve(address(router), type(uint256).max);
        taxToken.approve(address(router), type(uint256).max);
    }

    function supportsInterface(bytes4 interfaceId) external view virtual returns (bool) {
        return interfaceId == type(ILBToken).interfaceId;
    }

    function getPriceFromId(uint24 id) internal pure returns (uint256 price) {
        price = PriceHelper.getPriceFromId(id, DEFAULT_BIN_STEP);
    }

    function getIdFromPrice(uint256 price) internal pure returns (uint24 id) {
        id = PriceHelper.getIdFromPrice(price, DEFAULT_BIN_STEP);
    }

    function addAllAssetsToQuoteWhitelist() internal {
        if (address(wnative) != address(0)) factory.addQuoteAsset(wnative);
        if (address(usdc) != address(0)) factory.addQuoteAsset(usdc);
        if (address(usdt) != address(0)) factory.addQuoteAsset(usdt);
        if (address(wbtc) != address(0)) factory.addQuoteAsset(wbtc);
        if (address(weth) != address(0)) factory.addQuoteAsset(weth);
        if (address(link) != address(0)) factory.addQuoteAsset(link);
        if (address(bnb) != address(0)) factory.addQuoteAsset(bnb);
        if (address(taxToken) != address(0)) factory.addQuoteAsset(taxToken);
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
            DEFAULT_MAX_VOLATILITY_ACCUMULATOR,
            DEFAULT_OPEN_STATE
        );
    }

    function createLBPair(IERC20 tokenX, IERC20 tokenY) internal returns (LBPair newPair) {
        newPair = createLBPairFromStartId(tokenX, tokenY, ID_ONE);
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

    function getLiquidityParameters(
        IERC20 tokenX,
        IERC20 tokenY,
        uint256 amountYIn,
        uint24 startId,
        uint24 numberBins,
        uint24 gap
    ) internal view returns (ILBRouter.LiquidityParameters memory liquidityParameters) {
        (uint256[] memory ids, uint256[] memory distributionX, uint256[] memory distributionY, uint256 amountXIn) =
            spreadLiquidity(amountYIn, startId, numberBins, gap);

        liquidityParameters = ILBRouter.LiquidityParameters({
            tokenX: tokenX,
            tokenY: tokenY,
            binStep: DEFAULT_BIN_STEP,
            amountX: amountXIn,
            amountY: amountYIn,
            amountXMin: 0,
            amountYMin: 0,
            activeIdDesired: startId,
            idSlippage: 0,
            deltaIds: ids.convertToRelative(startId),
            distributionX: distributionX,
            distributionY: distributionY,
            to: DEV,
            refundTo: DEV,
            deadline: block.timestamp + 1000
        });
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
                amountXIn += binLiquidity > 0
                    ? binLiquidity.shiftDivRoundDown(Constants.SCALE_OFFSET, getPriceFromId(uint24(ids[i])))
                    : 0;
            }
        }
    }

    function addLiquidity(
        address from,
        address to,
        LBPair lbPair,
        uint24 activeId,
        uint256 amountX,
        uint256 amountY,
        uint8 nbBinX,
        uint8 nbBinY
    ) public {
        IERC20 tokenX = lbPair.getTokenX();
        IERC20 tokenY = lbPair.getTokenY();

        deal(address(tokenX), from, amountX);
        deal(address(tokenY), from, amountY);

        uint256 total = getTotalBins(nbBinX, nbBinY);

        bytes32[] memory liquidityConfigurations = new bytes32[](total);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);

            uint64 distribX = id >= activeId && nbBinX > 0 ? (Constants.PRECISION / nbBinX).safe64() : 0;
            uint64 distribY = id <= activeId && nbBinY > 0 ? (Constants.PRECISION / nbBinY).safe64() : 0;

            liquidityConfigurations[i] = LiquidityConfigurations.encodeParams(distribX, distribY, id);
        }

        vm.startPrank(from);
        tokenX.transfer(address(lbPair), amountX);
        tokenY.transfer(address(lbPair), amountY);
        vm.stopPrank();

        lbPair.mint(to, liquidityConfigurations, from);
    }

    function removeLiquidity(
        address from,
        address to,
        LBPair lbPair,
        uint24 activeId,
        uint256 percentToBurn,
        uint8 nbBinX,
        uint8 nbBinY
    ) public {
        require(percentToBurn <= Constants.PRECISION, "Percent to burn too high");

        uint256 total = getTotalBins(nbBinX, nbBinY);

        uint256[] memory ids = new uint256[](total);
        uint256[] memory amounts = new uint256[](total);

        for (uint256 i; i < total; ++i) {
            uint24 id = getId(activeId, i, nbBinY);
            uint256 b = lbPair.balanceOf(from, id);

            ids[i] = id;
            amounts[i] = b.mulDivRoundDown(percentToBurn, Constants.PRECISION);
        }

        vm.prank(from);
        lbPair.burn(from, to, ids, amounts);
    }

    function getTotalBins(uint8 nbBinX, uint8 nbBinY) public pure returns (uint256) {
        return nbBinX > 0 && nbBinY > 0 ? nbBinX + nbBinY - 1 : nbBinX + nbBinY;
    }

    function getId(uint24 activeId, uint256 i, uint8 nbBinY) public pure returns (uint24) {
        uint256 id = activeId + i;
        id = nbBinY > 0 ? id - nbBinY + 1 : id;

        return id.safe24();
    }

    function isPresetOpen(uint16 binStep) public view returns (bool isOpen) {
        (,,,,,,, isOpen) = factory.getPreset(binStep);
    }
}
