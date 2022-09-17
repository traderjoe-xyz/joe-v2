// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "forge-std/Script.sol";

import "src/interfaces/IJoeFactory.sol";
import "src/interfaces/IJoeRouter02.sol";
import "src/LBFactory.sol";
import "src/LBRouter.sol";

import "test/mocks/ERC20.sol";

import "test/mocks/WAVAX.sol";
import "test/mocks/ERC20MockDecimals.sol";

contract PlaygroundDeployer is Script {
    IJoeFactory private factory_V1;
    IJoeRouter02 private router_V1;
    LBFactory internal factory;
    LBRouter internal router;
    ERC20Mock internal usdc;
    ERC20Mock internal usdt;
    WAVAX internal wavax;
    uint24 internal constant ID_ONE = 2**23;
    address private constant FACTORY_V1_FUJI = 0xF5c7d9733e5f53abCC1695820c4818C59B457C2C;
    address private constant ROUTER_V1_FUJI = 0xd7f655E3376cE2D7A2b08fF01Eb3B1023191A901;
    address private constant WAVAX_FUJI = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;

    address private constant FACTORY_V2_FUJI = 0x2c2A4F4F0d5BABB0E501784F4D66a7131eff86F1;
    address private constant ROUTER_V2_FUJI = 0x88080086a243616008294725A4B0fD78B4d6a6c2;

    LBFactory.LBPairInformation internal pair;

    function run() external {
        // Addresses initialization
        factory_V1 = IJoeFactory(payable(FACTORY_V1_FUJI));
        router_V1 = IJoeRouter02(payable(ROUTER_V1_FUJI));
        factory = LBFactory(FACTORY_V2_FUJI);
        router = LBRouter(payable(ROUTER_V2_FUJI));
        wavax = WAVAX(WAVAX_FUJI);

        // Creating tokens
        vm.startBroadcast();
        usdc = new ERC20Mock("USDC", "USDC", 6);
        usdt = new ERC20Mock("USDT", "USDT", 6);
        vm.stopBroadcast();

        console.log("USDC ->", address(usdc));
        console.log("USDT ->", address(usdt));

        // Whitelisting tokens to be Y tokens
        vm.startBroadcast();
        factory.addQuoteAsset(IERC20(address(usdc)));
        factory.addQuoteAsset(IERC20(address(usdt)));
        vm.stopBroadcast();

        // Minting and giving approval
        vm.startBroadcast();
        wavax.approve(address(router_V1), type(uint256).max);
        wavax.approve(address(router), type(uint256).max);

        usdc.mint(msg.sender, 1000000e6);
        usdc.approve(address(router_V1), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        usdt.mint(msg.sender, 1000000e6);
        usdt.approve(address(router_V1), type(uint256).max);
        usdt.approve(address(router), type(uint256).max);
        vm.stopBroadcast();

        // Creating pairs
        vm.startBroadcast();
        createPairV1(address(usdc), address(usdt));
        console.log("V1 Pair USDC-USDT ->", factory_V1.getPair(address(usdc), address(usdt)));
        createPairV2(address(usdc), address(usdt), ID_ONE, 1);
        pair = factory.getLBPairInformation(IERC20(usdc), IERC20(usdt), 1);
        console.log("V2 Pair USDC-USDT ->", address(pair.LBPair));

        createPairV1(address(wavax), address(usdc));
        console.log("V1 Pair AVAX-USDC ->", factory_V1.getPair(address(wavax), address(usdc)));
        createPairV2(address(wavax), address(usdc), convertIdAvaxToUSD(20), 20);
        pair = factory.getLBPairInformation(IERC20(wavax), IERC20(usdc), 20);
        console.log("V2 Pair AVAX-USDC ->", address(pair.LBPair));

        vm.stopBroadcast();

        // Adding liquidity
        vm.startBroadcast();
        addLiquidityV1(address(usdc), address(usdt), 100e6, 100e6);
        addLiquidityV2(address(usdc), address(usdt), 100e6, ID_ONE, 1);
        addLiquidityV1(address(wavax), address(usdc), 1e18, 20e6);
        addLiquidityV2(address(wavax), address(usdc), 20e6, convertIdAvaxToUSD(20), 20);
        vm.stopBroadcast();
    }

    function createPairV1(address tokenA, address tokenB) internal {
        factory_V1.createPair(tokenA, tokenB);
    }

    function addLiquidityV1(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal {
        if (tokenA == WAVAX_FUJI) {
            router_V1.addLiquidityAVAX{value: amountA}(tokenB, amountB, 0, 0, msg.sender, block.timestamp + 120);
        } else if (tokenB == WAVAX_FUJI) {
            router_V1.addLiquidityAVAX{value: amountB}(tokenA, amountA, 0, 0, msg.sender, block.timestamp + 120);
        } else {
            router_V1.addLiquidity(tokenA, tokenB, amountA, amountB, 0, 0, msg.sender, block.timestamp + 120);
        }
    }

    function createPairV2(
        address tokenA,
        address tokenB,
        uint24 _currentId,
        uint16 _binStep
    ) internal {
        factory.createLBPair(IERC20(tokenA), IERC20(tokenB), _currentId, _binStep);
    }

    function addLiquidityV2(
        address tokenA,
        address tokenB,
        uint256 amount,
        uint24 _currentId,
        uint16 _binStep
    ) internal {
        addLiquidityFromRouter(
            ERC20MockDecimals(tokenA),
            ERC20MockDecimals(tokenB),
            amount,
            _currentId,
            9,
            2,
            _binStep
        );
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
            _gap,
            _binStep
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
            block.timestamp + 120
        );
        if (address(_tokenX) == address(wavax)) {
            router.addLiquidityAVAX{value: amountXIn}(_liquidityParameters);
        } else if (address(_tokenY) == address(wavax)) {
            router.addLiquidityAVAX{value: _amountYIn}(_liquidityParameters);
        } else {
            router.addLiquidity(_liquidityParameters);
        }
    }

    function spreadLiquidityForRouter(
        uint256 _amountYIn,
        uint24 _startId,
        uint24 _numberBins,
        uint24 _gap,
        uint16 _binStep
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
                    getPriceFromId(uint24(int24(_startId) + int24(_deltaIds[i])), _binStep);
            }
        }
    }

    function getPriceFromId(uint24 _id, uint16 _binStep) internal pure returns (uint256 price) {
        price = BinHelper.getPriceFromId(_id, _binStep);
    }

    function getIdFromPrice(uint256 _price, uint16 _binStep) internal pure returns (uint24 id) {
        id = BinHelper.getIdFromPrice(_price, _binStep);
    }

    function convertIdAvaxToUSD(uint16 _binStep) internal pure returns (uint24 id) {
        id = getIdFromPrice(50e26, _binStep);
    }
}
