// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "forge-std/Script.sol";

import {ILBFactory, LBFactory} from "src/LBFactory.sol";
import {ILBRouter, IJoeFactory, ILBLegacyFactory, ILBLegacyRouter, IWNATIVE, LBRouter} from "src/LBRouter.sol";
import {IERC20, LBPair} from "src/LBPair.sol";
import {LBQuoter} from "src/LBQuoter.sol";

import {BipsConfig} from "./config/bips-config.sol";

contract CoreDeployer is Script {
    using stdJson for string;

    uint256 private constant FLASHLOAN_FEE = 5e12;

    struct Deployment {
        address factoryV1;
        address factoryV2;
        address multisig;
        address routerV1;
        address routerV2;
        address wNative;
    }

    string[] chains = ["avalanche_fuji", "arbitrum_one_goerli"];

    function setUp() public {
        _overwriteDefaultArbitrumRPC();
    }

    function run() public {
        string memory json = vm.readFile("script/config/deployments.json");
        address deployer = vm.rememberKey(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        console.log("Deployer address: %s", deployer);

        for (uint256 i = 0; i < chains.length; i++) {
            bytes memory rawDeploymentData = json.parseRaw(string(abi.encodePacked(".", chains[i])));
            Deployment memory deployment = abi.decode(rawDeploymentData, (Deployment));

            console.log("\nDeploying V2.1 on %s", chains[i]);

            vm.createSelectFork(StdChains.getChain(chains[i]).rpcUrl);

            vm.broadcast(deployer);
            LBFactory factory = new LBFactory(deployer, FLASHLOAN_FEE);
            console.log("LBFactory deployed -->", address(factory));

            vm.broadcast(deployer);
            LBPair pairImplementation = new LBPair(factory);
            console.log("LBPair implementation deployed -->", address(pairImplementation));

            vm.broadcast(deployer);
            LBRouter router = new LBRouter(
                factory, 
                IJoeFactory(deployment.factoryV1),
                ILBLegacyFactory(deployment.factoryV2),
                ILBLegacyRouter(deployment.routerV2), 
                IWNATIVE(deployment.wNative)
            );
            console.log("LBRouter deployed -->", address(router));

            vm.startBroadcast(deployer);
            LBQuoter quoter =
            new LBQuoter(deployment.factoryV1, deployment.factoryV2, address(factory),deployment.routerV2, address(router));
            console.log("LBQuoter deployed -->", address(quoter));

            factory.setLBPairImplementation(address(pairImplementation));
            console.log("LBPair implementation set on factory\n");

            uint256 quoteAssets = ILBLegacyFactory(deployment.factoryV2).getNumberOfQuoteAssets();
            for (uint256 j = 0; j < quoteAssets; j++) {
                IERC20 quoteAsset = ILBLegacyFactory(deployment.factoryV2).getQuoteAsset(j);
                factory.addQuoteAsset(quoteAsset);
                console.log("Quote asset whitelisted -->", address(quoteAsset));
            }

            uint256[] memory presetList = BipsConfig.getPresetList();
            for (uint256 j; j < presetList.length; j++) {
                BipsConfig.FactoryPreset memory preset = BipsConfig.getPreset(presetList[j]);
                factory.setPreset(
                    preset.binStep,
                    preset.baseFactor,
                    preset.filterPeriod,
                    preset.decayPeriod,
                    preset.reductionFactor,
                    preset.variableFeeControl,
                    preset.protocolShare,
                    preset.maxVolatilityAccumulated,
                    preset.isOpen
                );
            }

            factory.setPendingOwner(deployment.multisig);
            vm.stopBroadcast();
        }
    }

    function _overwriteDefaultArbitrumRPC() private {
        StdChains.setChain(
            "arbitrum_one_goerli",
            StdChains.ChainData({
                name: "Arbitrum One Goerli",
                chainId: 421613,
                rpcUrl: vm.envString("ARBITRUM_TESTNET_RPC_URL")
            })
        );
    }
}
