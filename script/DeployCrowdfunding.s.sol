// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "../lib/forge-std/src/Script.sol";
import {Crowdfunding} from "../src/Crowdfunding.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract DeployCrowdfunding is Script {
    Crowdfunding public crowdfunding;
    HelperConfig public helperConfig;

    function run() external returns (Crowdfunding, HelperConfig) {
        helperConfig = new HelperConfig();
        (
            uint256 crowdfundFeeInPrecent,
            uint256 minDeadlineInDays,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        crowdfunding = new Crowdfunding(
            crowdfundFeeInPrecent,
            minDeadlineInDays
        );
        vm.stopBroadcast();
        return (crowdfunding, helperConfig);
    }
}
