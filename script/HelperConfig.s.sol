// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Crowdfunding} from "../src/Crowdfunding.sol";
import {CrowdfundingProject} from "../src/CrowdfundingProject.sol";
import {Script} from "../lib/forge-std/src/Script.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    struct NetworkConfig {
        uint256 crowdfundFeeInPrecent;
        uint256 minDeadlineInDays;
        uint256 deployerKey;
    }

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getMainNetEthConfig();
        } else {
            activeNetworkConfig = getAnvilEthConfig();
        }
    }

    function getMainNetEthConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory mainNetNetworkConfig = NetworkConfig({
            crowdfundFeeInPrecent: 50000000000000000, // 0.05%
            minDeadlineInDays: 15,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
        return mainNetNetworkConfig;
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaNetworkConfig = NetworkConfig({
            crowdfundFeeInPrecent: 50000000000000000, // 0.05%
            minDeadlineInDays: 15,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
        return sepoliaNetworkConfig;
    }

    function getAnvilEthConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory anvilNetworkConfig = NetworkConfig({
            crowdfundFeeInPrecent: 50000000000000000, // 0.05%
            minDeadlineInDays: 15,
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
        return anvilNetworkConfig;
    }
}
