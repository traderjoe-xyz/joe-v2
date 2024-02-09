// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./helpers/TestHelper.sol";

import {LBFactory, LBFactory} from "src/LBFactory.sol";
import {ILBRouter, IJoeFactory, ILBLegacyFactory, ILBLegacyRouter, IWNATIVE, LBRouter} from "src/LBRouter.sol";
import {IERC20, LBPair} from "src/LBPair.sol";
import {LBQuoter} from "src/LBQuoter.sol";

contract GetOracleLengthTest is Test {
    LBFactory public constant factoryAvax = LBFactory(0x8e42f2F4101563bF679975178e880FD87d3eFd4e);
    LBFactory public constant factoryArbitrum = LBFactory(0x8e42f2F4101563bF679975178e880FD87d3eFd4e);
    LBFactory public constant factoryBsc = LBFactory(0x8e42f2F4101563bF679975178e880FD87d3eFd4e);
    LBFactory public constant factoryEth = LBFactory(0xDC8d77b69155c7E68A95a4fb0f06a71FF90B943a);

    string[] chains = ["avalanche", "arbitrum_one", "bnb_smart_chain", "mainnet"];
    mapping(string => uint256) public forks;

    function setUp() public {
        for (uint256 i = 0; i < chains.length; i++) {
            string memory chain = chains[i];

            forks[chain] = vm.createFork(_getRPC(chain));
        }
    }

    // function test_size_avalanche() public {
    //     get_size("avalanche");
    // }

    // function test_size_arbitrum() public {
    //     get_size("arbitrum_one");
    // }

    // function test_size_bsc() public {
    //     get_size("bnb_smart_chain");
    // }

    // function test_size_eth() public {
    //     get_size("mainnet");
    // }

    function get_size(string memory chain) public {
        vm.selectFork(forks[chain]);

        LBFactory factory = _getLBFactories(chain);

        GetAllSizeAndAddress s = new GetAllSizeAndAddress();

        (address[] memory pairs, uint256[] memory sizes) = s.getAllSizeAndAddress(factory);

        uint256 atRisk = 0;

        for (uint256 j = 0; j < pairs.length; j++) {
            address pair = pairs[j];
            uint256 size = sizes[j];

            if (size > 0) {
                atRisk++;
                console.log("Pair %s has size %s", pair, size);
            }
        }

        console.log("There are %s/%s pairs at risk on %s", atRisk, pairs.length, chain);
    }

    function _getRPC(string memory chain) internal returns (string memory) {
        // if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("avalanche"))) {
        //     return "https://rpc.ankr.com/avalanche";
        // } else if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("arbitrum_one"))) {
        //     return "https://rpc.ankr.com/arbitrum";
        // } else if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("bnb_smart_chain"))) {
        //     return "https://rpc.ankr.com/bsc";
        // } else if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("mainnet"))) {
        //     return "https://rpc.ankr.com/eth";
        // }
        return StdChains.getChain(chain).rpcUrl;
    }

    function _getLBFactories(string memory chain) internal pure returns (LBFactory) {
        if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("avalanche"))) {
            return factoryAvax;
        } else if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("arbitrum_one"))) {
            return factoryArbitrum;
        } else if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("bnb_smart_chain"))) {
            return factoryBsc;
        } else if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("mainnet"))) {
            return factoryEth;
        } else {
            revert("Invalid chain");
        }
    }
}

contract GetAllSizeAndAddress {
    function getAllSizeAndAddress(LBFactory factory)
        external
        view
        returns (address[] memory pairs, uint256[] memory size)
    {
        uint256 nbPairs = factory.getNumberOfLBPairs();

        pairs = new address[](nbPairs);
        size = new uint256[](nbPairs);

        for (uint256 i = 0; i < nbPairs; i++) {
            LBPair pair = LBPair(address(factory.getLBPairAtIndex(i)));

            (, uint16 _size,,,) = pair.getOracleParameters();

            pairs[i] = address(pair);
            size[i] = _size;
        }
    }
}
