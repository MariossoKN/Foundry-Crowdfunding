// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "../lib/forge-std/src/Script.sol";
import {Crowdfunding} from "../src/Crowdfunding.sol";
import {CrowdfundingProject} from "../src/CrowdfundingProject.sol";

contract DeployCrowdfunding is Script {
    Crowdfunding public crowdfunding;
    CrowdfundingProject public projectOne;
    CrowdfundingProject public projectTwo;

    uint256 contractFeeInPercent = 50000000000000000; // 0.05%
    uint256 minDeadlineInDays = 2;

    function run() external returns (Crowdfunding) {
        vm.startBroadcast();
        crowdfunding = new Crowdfunding(
            contractFeeInPercent,
            minDeadlineInDays
        );
        uint256 projectOneFees = crowdfunding.calculateInitialFee(10 ether);
        uint256 projectTwoFees = crowdfunding.calculateInitialFee(20 ether);
        projectOne = crowdfunding.createProject{value: projectOneFees}(
            10 ether,
            10,
            1 ether,
            2 ether,
            10,
            15
        );

        projectTwo = crowdfunding.createProject{value: projectTwoFees}(
            20 ether,
            20,
            2 ether,
            4 ether,
            20,
            30
        );
        vm.stopBroadcast();
        return crowdfunding;
    }
}
