// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "forge-std/Script.sol";
import "openzeppelin/utils/Strings.sol";

import "src/interfaces/IJoeFactory.sol";
import "src/interfaces/IJoeRouter02.sol";
import "src/Quoter.sol";
import "src/LBFactory.sol";
import "src/LBFactoryHelper.sol";
import "src/LBRouter.sol";

import "test/mocks/ERC20.sol";
import "test/mocks/WAVAX.sol";
import "test/mocks/ERC20MockDecimals.sol";

contract PlaygroundDeployer is Script {
    IJoeFactory private factory_V1;
    IJoeRouter02 private router_V1;
    Quoter private quoter;
    LBFactory internal factory;
    LBRouter internal router;

    ERC20Mock internal usdc;
    ERC20Mock internal usdt;
    WAVAX internal wavax;

    uint24 internal constant ID_ONE = 2**23;
    uint256 internal constant BASIS_POINT_MAX = 10_000;
    uint64 internal constant DEFAULT_MAX_ACCUMULATOR = 1_248_999;
    uint16 internal constant DEFAULT_FILTER_PERIOD = 50;
    uint16 internal constant DEFAULT_DECAY_PERIOD = 100;
    uint8 internal constant DEFAULT_BIN_STEP = 25;
    uint8 internal constant DEFAULT_BASE_FACTOR = 50;
    uint8 internal constant DEFAULT_PROTOCOL_SHARE = 10;
    uint8 internal constant DEFAULT_SAMPLE_LIFETIME = 240;
    uint8 internal constant DEFAULT_REDUCTION_FACTOR = 50;
    uint8 internal constant DEFAULT_VARIABLE_FEE_CONTROL = 50;

    address private constant FACTORY_V1_FUJI = 0xF5c7d9733e5f53abCC1695820c4818C59B457C2C;
    address private constant ROUTER_V1_FUJI = 0xd7f655E3376cE2D7A2b08fF01Eb3B1023191A901;
    address private constant WAVAX_FUJI = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;

    uint256 private constant NUMBER_OF_TOKENS = 3;
    uint256 private constant AMOUNT_IN_PAIRS = 1e18;

    function run() external {
        wavax = WAVAX(WAVAX_FUJI);
        factory_V1 = IJoeFactory(payable(FACTORY_V1_FUJI));
        router_V1 = IJoeRouter02(payable(ROUTER_V1_FUJI));

        vm.broadcast();
        factory = new LBFactory(msg.sender);

        vm.broadcast();
        new LBFactoryHelper(factory);

        vm.broadcast();
        router = new LBRouter(factory, IJoeFactory(address(factory_V1)), IWAVAX(address(wavax)));

        vm.broadcast();
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        vm.broadcast();
        quoter = new Quoter(address(router), address(factory_V1), address(factory), WAVAX_FUJI);

        address[] memory tokens = new address[](NUMBER_OF_TOKENS);

        // Creating tokens
        vm.startBroadcast();
        for (uint256 i; i < NUMBER_OF_TOKENS; i++) {
            ERC20Mock token = new ERC20Mock(
                string(abi.encodePacked("Token ", Strings.toString(i))),
                string(abi.encodePacked("TK ", Strings.toString(i))),
                18
            );
            tokens[i] = address(token);
            console.log("Token ", i + 1, ":", tokens[i]);
        }
        usdc = new ERC20Mock("USDC", "USDC", 6);
        usdt = new ERC20Mock("USDT", "USDT", 6);
        vm.stopBroadcast();

        // Minting and giving approval
        vm.startBroadcast();
        wavax.approve(address(router_V1), type(uint256).max);
        wavax.approve(address(router), type(uint256).max);
        for (uint256 i; i < NUMBER_OF_TOKENS; i++) {
            ERC20Mock(tokens[i]).mint(msg.sender, 1000000e18);
            ERC20Mock(tokens[i]).approve(address(router_V1), type(uint256).max);
            ERC20Mock(tokens[i]).approve(address(router), type(uint256).max);
        }
        ERC20Mock(usdc).mint(msg.sender, 1000000e6);
        ERC20Mock(usdc).approve(address(router_V1), type(uint256).max);
        ERC20Mock(usdc).approve(address(router), type(uint256).max);

        ERC20Mock(usdt).mint(msg.sender, 1000000e6);
        ERC20Mock(usdt).approve(address(router_V1), type(uint256).max);
        ERC20Mock(usdt).approve(address(router), type(uint256).max);
        vm.stopBroadcast();

        // Creating pairs
        vm.startBroadcast();
        for (uint256 i; i < NUMBER_OF_TOKENS; i++) {
            // createPairV1(address(tokens[i]), address(wavax));
            // createPairV2(address(tokens[i]), address(wavax), ID_ONE);
            // createPairV1(address(tokens[i]), address(usdc));
            // createPairV2(address(tokens[i]), address(usdc), ID_ONE);
            // createPairV1(address(tokens[i]), address(usdt));
            // createPairV2(address(tokens[i]), address(usdt), ID_ONE);
            // for (uint256 j; j < i; j++) {
            //     createPairV1(address(tokens[i]), address(tokens[j]));
            //     createPairV2(address(tokens[i]), address(tokens[j]), ID_ONE);
            // }
        }
        createPairV1(address(usdc), address(usdt));
        createPairV2(address(usdc), address(usdt), ID_ONE);
        // createPairV1(address(usdc), address(wavax));
        createPairV2(address(usdc), address(wavax), convertIdAvaxToUSD());
        // createPairV1(address(usdt), address(wavax));
        createPairV2(address(usdt), address(wavax), convertIdAvaxToUSD());
        vm.stopBroadcast();

        // Adding liquidity
        vm.startBroadcast();
        for (uint256 i; i < NUMBER_OF_TOKENS; i++) {
            // addLiquidityV1(address(tokens[i]), address(wavax));
            // addLiquidityV2(address(tokens[i]), address(wavax), ID_ONE);
            // addLiquidityV1(address(tokens[i]), address(usdc));
            // addLiquidityV2(address(tokens[i]), address(usdc), ID_ONE);
            // addLiquidityV1(address(tokens[i]), address(usdt));
            // addLiquidityV2(address(tokens[i]), address(usdt), ID_ONE);
            // for (uint256 j; j < i; j++) {
            //     addLiquidityV1(address(tokens[i]), address(tokens[j]));
            //     addLiquidityV2(address(tokens[i]), address(tokens[j]), ID_ONE);
            // }
        }
        addLiquidityV1(address(usdc), address(usdt), AMOUNT_IN_PAIRS / 1e10);
        addLiquidityV2(address(usdc), address(usdt), AMOUNT_IN_PAIRS / 1e10, ID_ONE);
        // createPairV1(address(usdc), address(wavax));
        addLiquidityV2(address(usdc), address(wavax), AMOUNT_IN_PAIRS, convertIdAvaxToUSD());
        // addLiquidityV1(address(usdt), address(wavax));
        addLiquidityV2(address(usdt), address(wavax), AMOUNT_IN_PAIRS, convertIdAvaxToUSD());
        vm.stopBroadcast();

        console.log("Router V1:", address(router_V1));
        console.log("Factory V1:", address(factory_V1));
        console.log("Router V2:", address(router));
        console.log("Factory V2:", address(factory));
        console.log("Quoter:", address(quoter));
        console.log("WAVAX:", address(wavax));
        console.log("USDC:", address(usdc));
        console.log("USDT:", address(usdt));
    }

    function createPairV1(address tokenA, address tokenB) internal {
        factory_V1.createPair(tokenA, tokenB);
    }

    function addLiquidityV1(
        address tokenA,
        address tokenB,
        uint256 amount
    ) internal {
        uint256 randomPriceDeviation = 9_800 + (block.number % 400);

        if (tokenB == WAVAX_FUJI) {
            router_V1.addLiquidityAVAX{value: amount}(
                tokenA,
                (amount * randomPriceDeviation) / 10_000,
                0,
                0,
                msg.sender,
                block.timestamp + 12_000
            );
        } else {
            router_V1.addLiquidity(
                tokenA,
                tokenB,
                (amount * randomPriceDeviation) / 10_000,
                amount,
                0,
                0,
                msg.sender,
                block.timestamp + 12_000
            );
        }
    }

    function createPairV2(
        address tokenA,
        address tokenB,
        uint24 _currentId
    ) internal {
        // uint16 binStep = uint16(block.number % 200) + 1;
        // uint24 startId = ID_ONE - 1200 + uint24(block.number % 1200);
        factory.createLBPair(IERC20(tokenA), IERC20(tokenB), _currentId, DEFAULT_BIN_STEP);
    }

    function addLiquidityV2(
        address tokenA,
        address tokenB,
        uint256 amount,
        uint24 _currentId
    ) internal {
        addLiquidityFromRouter(
            ERC20MockDecimals(tokenA),
            ERC20MockDecimals(tokenB),
            amount,
            _currentId,
            9,
            2,
            DEFAULT_BIN_STEP
        );
    }

    function addLiquidityFromRouter(
        ERC20MockDecimals _tokenX,
        ERC20MockDecimals _tokenY,
        uint256 _amountYIn,
        uint24 _startId,
        uint24 _numberBins,
        uint24 _gap,
        uint8 _binStep
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
            msg.sender,
            block.timestamp + 12_000
        );

        if (address(_tokenY) == address(wavax)) {
            _liquidityParameters.tokenY = IERC20(address(0));
            router.addLiquidityAVAX{value: _amountYIn}(_liquidityParameters);
        } else {
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

    function getPriceFromId(uint24 _id) internal pure returns (uint256 price) {
        price = BinHelper.getPriceFromId(_id, DEFAULT_BIN_STEP);
    }

    function getIdFromPrice(uint256 _price) internal pure returns (uint24 id) {
        id = BinHelper.getIdFromPrice(_price, DEFAULT_BIN_STEP);
    }

    function setDefaultFactoryPresets(uint8 _binStep) internal {
        factory.setPreset(
            _binStep,
            DEFAULT_BASE_FACTOR,
            DEFAULT_FILTER_PERIOD,
            DEFAULT_DECAY_PERIOD,
            DEFAULT_REDUCTION_FACTOR,
            DEFAULT_VARIABLE_FEE_CONTROL,
            DEFAULT_PROTOCOL_SHARE,
            DEFAULT_MAX_ACCUMULATOR,
            DEFAULT_SAMPLE_LIFETIME
        );
    }

    function convertIdAvaxToUSD() internal pure returns (uint24) {
        return getIdFromPrice((getPriceFromId(ID_ONE) * 1e12) / 20);
    }

    receive() external payable {}
}
