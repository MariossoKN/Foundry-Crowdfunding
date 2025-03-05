// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.18;

import {Crowdfunding} from "../src/Crowdfunding.sol";
import {CrowdfundingProject} from "../src/CrowdfundingProject.sol";
import {DeployCrowdfunding} from "../script/DeployCrowdfunding.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {console} from "forge-std/console.sol";

contract TestCrowdfundingProject is Test {
    Crowdfunding public crowdfunding;
    HelperConfig public helperConfig;

    uint256 crowdfundFeeInPrecent;
    uint256 minDeadlineInDays;
    uint256 deployerKey;

    uint256 initialFeesToBePaid;

    address PROJECT_OWNER = makeAddr("projectOwner");
    address PROJECT_OWNER2 = makeAddr("projectOwner2");
    address INVESTOR = makeAddr("investor");
    address INVESTOR2 = makeAddr("investor2");
    address INVESTOR3 = makeAddr("investor3");
    uint256 STARTING_BALANCE = 100 ether;

    string PROJECT_NAME = "Grand Resort Crowdfund Project";
    uint256 CROWDFUNDING_AMOUNT = 150 ether;
    uint256 INTEREST_RATE = 10; // SHOULD BE IN WEI
    uint256 MIN_INVESTMENT = 5 ether;
    uint256 MAX_INVESTMENT = 50 ether;
    uint256 DEADLINE_IN_DAYS = 25;
    uint256 INVESTMENT_PERIOD_IN_DAYS = 30;
    uint256 private constant ONE_DAY_IN_SECONDS = 86400;

    uint256 CORRECT_INVESTMENT_AMOUNT = 10 ether;
    uint256 INCORRECT_INVESTMENT_AMOUNT = 2 ether;

    function setUp() external {
        DeployCrowdfunding deployCrowdfunding = new DeployCrowdfunding();
        (crowdfunding, helperConfig) = deployCrowdfunding.run();
        (crowdfundFeeInPrecent, minDeadlineInDays, deployerKey) = helperConfig
            .activeNetworkConfig();

        initialFeesToBePaid = crowdfunding.calculateInitialFee(
            CROWDFUNDING_AMOUNT
        );

        vm.deal(PROJECT_OWNER, STARTING_BALANCE * 5);
        vm.deal(PROJECT_OWNER2, STARTING_BALANCE * 5);
        vm.deal(INVESTOR, STARTING_BALANCE);
        vm.deal(INVESTOR2, STARTING_BALANCE);
        vm.deal(INVESTOR3, STARTING_BALANCE);
    }

    //////////////////////
    // helper functions //
    //////////////////////

    function createProject() public returns (CrowdfundingProject) {
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
        return project;
    }

    function createProjectFullyFundItAndPerformUpkeep()
        public
        returns (CrowdfundingProject)
    {
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

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);

        vm.warp(
            block.timestamp +
                (INVESTMENT_PERIOD_IN_DAYS * ONE_DAY_IN_SECONDS) +
                1
        );
        vm.roll(block.number + 1);
        project.performUpkeep("");
        return project;
    }

    function createProjectFullyFundItAndPerformUpkeepAndFinish() public {
        createProjectFullyFundItAndPerformUpkeep();

        vm.prank(PROJECT_OWNER);
        crowdfunding.ownerFundProject{value: 4 * MAX_INVESTMENT}(0);
        vm.prank(PROJECT_OWNER);
        crowdfunding.finishProject(0);
    }

    //////////////////////
    // constructor TEST //
    //////////////////////
    function testConstructorParametersShouldBeInitializedCorrectly() public {
        CrowdfundingProject project = createProject();

        assertEq(project.getProjectName(), PROJECT_NAME);
        assertEq(project.getOwner(), PROJECT_OWNER);
        assertEq(project.getCrowdfundingAmount(), CROWDFUNDING_AMOUNT);
        assertEq(project.getCurrentFundedAmount(), 0);
        assertEq(project.getProjectInterestRateInPercent(), INTEREST_RATE);
        assertEq(project.getProjectMinInvestment(), MIN_INVESTMENT);
        assertEq(project.getProjectMaxInvestment(), MAX_INVESTMENT);
        assertEq(project.getProjectDeadlineInDays(), DEADLINE_IN_DAYS);
        assertEq(
            project.getProjectInvestmentPeriod(),
            INVESTMENT_PERIOD_IN_DAYS
        );
        assertEq(uint256(project.getProjectStatus()), 1);
        assertEq(project.getProjectStartTimestamp(), block.timestamp);
        assertEq(
            project.getCrowdfundingContractAddress(),
            address(crowdfunding)
        );
    }

    ///////////////
    // fund TEST //
    ///////////////
    function testCanBeOnlyCalledByCrowdfundingContract() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__CanOnlyBeCalledByTheCrowdfundingContract
                    .selector
            )
        );
        project.fund{value: CORRECT_INVESTMENT_AMOUNT}(INVESTOR);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__CanOnlyBeCalledByTheCrowdfundingContract
                    .selector
            )
        );
        project.fund{value: CORRECT_INVESTMENT_AMOUNT}(PROJECT_OWNER);
    }

    function testShouldRevertIfCalledWhehNotInFundingState() public {
        createProjectFullyFundItAndPerformUpkeep();

        vm.prank(INVESTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__FundingIsNotActive
                    .selector
            )
        );
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);

        vm.prank(PROJECT_OWNER);
        crowdfunding.ownerFundProject{value: CROWDFUNDING_AMOUNT * 2}(0);
        vm.prank(PROJECT_OWNER);
        crowdfunding.finishProject(0);

        vm.prank(INVESTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__FundingIsNotActive
                    .selector
            )
        );
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
    }

    function testShouldRevertIfWrongAmountSent() public {
        createProject();

        vm.prank(INVESTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__NotEnoughEthSent
                    .selector
            )
        );
        crowdfunding.fundProject{value: MIN_INVESTMENT - 1}(0);

        vm.prank(INVESTOR2);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject.CrowdfundingProject__TooMuchEthSent.selector
            )
        );
        crowdfunding.fundProject{value: MAX_INVESTMENT + 1}(0);
    }

    function testShoulRevertIfTheSentAmountExceedsTheMaxFundAmount() public {
        CrowdfundingProject project = createProject();

        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        crowdfunding.fundProject{value: MAX_INVESTMENT - 1}(0);

        uint256 remainingAmountToFund = project.getRemainingFundingAmount();

        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__AmountEthSentIsGreaterThanTheRestCrowfundingNeeded
                    .selector,
                remainingAmountToFund
            )
        );
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);

        uint256 remainingAmountToFund2 = project.getRemainingFundingAmount();

        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__AmountEthSentIsGreaterThanTheRestCrowfundingNeeded
                    .selector,
                remainingAmountToFund2
            )
        );
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
    }

    function testShouldFundToTheContractAndUpdateInvestorArray() public {
        CrowdfundingProject project = createProject();

        uint256 investedAmountBefore = project.getInvestorInvestmentAmount(
            INVESTOR
        );
        uint256 investedAmountBefore2 = project.getInvestorInvestmentAmount(
            INVESTOR2
        );

        assertEq(investedAmountBefore, 0);
        assertEq(investedAmountBefore2, 0);

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);

        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);

        uint256 investedAmountAfter = project.getInvestorInvestmentAmount(
            INVESTOR
        );
        uint256 investedAmountAfter2 = project.getInvestorInvestmentAmount(
            INVESTOR2
        );

        assertEq(
            investedAmountAfter,
            CORRECT_INVESTMENT_AMOUNT + MIN_INVESTMENT
        );
        assertEq(investedAmountAfter2, MAX_INVESTMENT);
    }
}
