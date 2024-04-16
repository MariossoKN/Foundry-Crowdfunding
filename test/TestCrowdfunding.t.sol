// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.18;

import {Crowdfunding} from "../src/Crowdfunding.sol";
import {CrowdfundingProject} from "../src/CrowdfundingProject.sol";
import {DeployCrowdfunding} from "../script/DeployCrowdfunding.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";

contract TestCrowdfunding is Test {
    Crowdfunding public crowdfunding;
    HelperConfig public helperConfig;

    uint256 crowdfundFeeInPrecent;
    uint256 minDeadlineInDays;
    uint256 deployerKey;

    address PROJECT_OWNER = makeAddr("projectOwner");
    address PROJECT_OWNER2 = makeAddr("projectOwner2");
    uint256 STARTING_BALANCE = 100 ether;

    string PROJECT_NAME = "Grand Resort Crowdfund Project";
    uint256 CROWDFUNDING_AMOUNT = 150 ether;
    uint256 INTEREST_RATE = 10; // SHOULD BE IN WEI
    uint256 MIN_INVESTMENT = 5 ether;
    uint256 MAX_INVESTMENT = 50 ether;
    uint256 DEADLINE_IN_DAYS = 25;
    uint256 INVESTMENT_PERIOD_IN_DAYS = 30;

    function setUp() external {
        DeployCrowdfunding deployCrowdfunding = new DeployCrowdfunding();
        (crowdfunding, helperConfig) = deployCrowdfunding.run();
        (crowdfundFeeInPrecent, minDeadlineInDays, deployerKey) = helperConfig
            .activeNetworkConfig();
        vm.deal(PROJECT_OWNER, STARTING_BALANCE);
        vm.deal(PROJECT_OWNER2, STARTING_BALANCE);
    }

    //////////////////////
    // constructor TEST //
    //////////////////////
    function testConstructorParametersShouldBeInitializedCorrectly()
        public
        view
    {
        uint256 crowdfundingFee = crowdfunding.getCrowdfundingFeeInPercent();
        assertEq(crowdfundingFee, crowdfundFeeInPrecent);
        uint256 minDeadline = crowdfunding.getMinDeadlineInDays();
        assertEq(minDeadline, minDeadlineInDays);
    }

    /////////////////////////
    // createProject TESTs //
    /////////////////////////
    function testShouldRevertIfTheAmountSentIsZero() public {
        uint256 initialFeesToBePaid = crowdfunding.calculateInitialFee(
            CROWDFUNDING_AMOUNT
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfunding
                    .Crowdfunding__YouHaveToSendTheExactAmountForInitialFees
                    .selector,
                initialFeesToBePaid
            )
        );
        // 0,075000000000000000
        crowdfunding.createProject{value: 0}(
            PROJECT_NAME,
            CROWDFUNDING_AMOUNT,
            INTEREST_RATE,
            MIN_INVESTMENT,
            MAX_INVESTMENT,
            DEADLINE_IN_DAYS,
            INVESTMENT_PERIOD_IN_DAYS
        );
    }

    function testFuzzShouldRevertIfTheAmountSentIsLessThanFeesToBePaid(
        uint256 _amount
    ) public {
        uint256 initialFeesToBePaid = crowdfunding.calculateInitialFee(
            CROWDFUNDING_AMOUNT
        );
        uint256 amount = bound(_amount, 1, initialFeesToBePaid - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfunding
                    .Crowdfunding__YouHaveToSendTheExactAmountForInitialFees
                    .selector,
                initialFeesToBePaid
            )
        );
        // 0,075000000000000000
        crowdfunding.createProject{value: amount}(
            PROJECT_NAME,
            CROWDFUNDING_AMOUNT,
            INTEREST_RATE,
            MIN_INVESTMENT,
            MAX_INVESTMENT,
            DEADLINE_IN_DAYS,
            INVESTMENT_PERIOD_IN_DAYS
        );
    }

    function testFuzzShouldRevertIfTheAmountSentIsMoreThanFeesToBePaid(
        uint256 _amount
    ) public {
        uint256 initialFeesToBePaid = crowdfunding.calculateInitialFee(
            CROWDFUNDING_AMOUNT
        );
        uint256 amount = bound(
            _amount,
            initialFeesToBePaid + 1,
            STARTING_BALANCE
        );
        console.log(initialFeesToBePaid);
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfunding
                    .Crowdfunding__YouHaveToSendTheExactAmountForInitialFees
                    .selector,
                initialFeesToBePaid
            )
        );
        // 0,075000000000000000
        crowdfunding.createProject{value: amount}(
            PROJECT_NAME,
            CROWDFUNDING_AMOUNT,
            INTEREST_RATE,
            MIN_INVESTMENT,
            MAX_INVESTMENT,
            DEADLINE_IN_DAYS,
            INVESTMENT_PERIOD_IN_DAYS
        );
    }

    function testShoulRevertIfDeadlineIsMoreThanMinimum() public {}

    function testShouldCreateANewCrowdfundingProjectWithCorrectParameters()
        public
    {
        uint256 initialFeesToBePaid = crowdfunding.calculateInitialFee(
            CROWDFUNDING_AMOUNT
        );
        vm.prank(PROJECT_OWNER);
        CrowdfundingProject project = crowdfunding.createProject{
            value: initialFeesToBePaid
        }(
            PROJECT_NAME,
            CROWDFUNDING_AMOUNT,
            INTEREST_RATE,
            MIN_INVESTMENT,
            MAX_INVESTMENT,
            DEADLINE_IN_DAYS,
            INVESTMENT_PERIOD_IN_DAYS
        );
        assertEq(project.getProjectName(), PROJECT_NAME);
        assertEq(project.getOwner(), PROJECT_OWNER);
        assertEq(project.getCrowdfundingAmount(), CROWDFUNDING_AMOUNT);
        assertEq(project.getProjectInterestRateInPercent(), INTEREST_RATE);
        assertEq(project.getProjectMinInvestment(), MIN_INVESTMENT);
        assertEq(project.getProjectMaxInvestment(), MAX_INVESTMENT);
        assertEq(project.getProjectDeadlineInDays(), DEADLINE_IN_DAYS);
        assertEq(
            project.getProjectInvestmentPeriod(),
            INVESTMENT_PERIOD_IN_DAYS
        );
        assertEq(
            project.getCrowdfundingContractAddress(),
            address(crowdfunding)
        );
    }
}
