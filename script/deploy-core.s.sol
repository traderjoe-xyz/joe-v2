// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Script.sol";

import "src/LBFactory.sol";
import "src/LBRouter.sol";
import "src/LBPair.sol";
import "src/LBQuoter.sol";

import "./config/bips-config.sol";

contract CoreDeployer is Script {
    address private constant WAVAX_AVALANCHE = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address private constant WAVAX_FUJI = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;

    address private constant FACTORY_V1_AVALANCHE = 0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10;
    address private constant FACTORY_V1_FUJI = 0xF5c7d9733e5f53abCC1695820c4818C59B457C2C;

    address private wavax;
    address private factoryV1;

    uint256 private constant FLASHLOAN_FEE = 5e12;

    function run() external {
        if (block.chainid == 43114) {
            wavax = WAVAX_AVALANCHE;
            factoryV1 = FACTORY_V1_AVALANCHE;
        } else {
            wavax = WAVAX_FUJI;
            factoryV1 = FACTORY_V1_FUJI;
        }

        vm.broadcast();
        LBFactory factory = new LBFactory(msg.sender, FLASHLOAN_FEE);
        console.log("LBFactory deployed -->", address(factory));

        vm.broadcast();
        LBPair pairImplementation = new LBPair(factory);
        console.log("LBPair implementation deployed -->", address(pairImplementation));

        vm.broadcast();
        LBRouter router = new LBRouter(factory, IJoeFactory(factoryV1), IWAVAX(wavax));
        console.log("LBRouter deployed -->", address(router));

        vm.startBroadcast();
        LBQuoter quoter = new LBQuoter(address(router), address(factoryV1), address(factory));
        console.log("LBQuoter deployed -->", address(quoter));

        factory.setLBPairImplementation(address(pairImplementation));
        console.log("LBPair implementation set on factory");

        factory.addQuoteAsset(IERC20(wavax));
        console.log("Wavax whitelisted as quote asset");
        vm.stopBroadcast();

        vm.startBroadcast();
        uint256[] memory presetList = BipsConfig.getPresetList();
        for (uint256 i; i < presetList.length; i++) {
            BipsConfig.FactoryPreset memory preset = BipsConfig.getPreset(presetList[i]);
            factory.setPreset(
                preset.binStep,
                preset.baseFactor,
                preset.filterPeriod,
                preset.decayPeriod,
                preset.reductionFactor,
                preset.variableFeeControl,
                preset.protocolShare,
                preset.maxVolatilityAccumulated,
                preset.sampleLifetime
            );
        }
        vm.stopBroadcast();
    }
}
