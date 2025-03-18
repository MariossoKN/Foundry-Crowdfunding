// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.18;

import {Crowdfunding} from "../src/Crowdfunding.sol";
import {CrowdfundingProject} from "../src/CrowdfundingProject.sol";
import {DeployCrowdfunding} from "../script/DeployCrowdfunding.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";

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
    uint256 INTEREST_RATE = 1000; // 10%
    uint256 INTEREST_RATE2 = 1500; // 15%
    uint256 INTEREST_RATE3 = 550; // 5.5%
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

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");
        return project;
    }

    function createProjectFullyFundItAndPerformUpkeepAndFinish()
        public
        returns (CrowdfundingProject)
    {
        CrowdfundingProject project = createProjectFullyFundItAndPerformUpkeep();

        vm.prank(PROJECT_OWNER);
        crowdfunding.ownerFundProject{value: 4 * MAX_INVESTMENT}(0);
        vm.prank(PROJECT_OWNER);
        crowdfunding.finishProject(0);

        return project;
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
        assertEq(project.getProjectInterestRate(), INTEREST_RATE);
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

    function testShouldFundToTheContractAndUpdateInvestorMappingWithOneInvestor()
        public
    {
        CrowdfundingProject project = createProject();

        uint256 investedAmountBefore = project.getInvestorInvestmentAmount(
            INVESTOR
        );
        assertEq(investedAmountBefore, 0);

        // fund #1
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        uint256 investedAmountAfter = project.getInvestorInvestmentAmount(
            INVESTOR
        );
        assertEq(investedAmountAfter, CORRECT_INVESTMENT_AMOUNT);
        assertEq(
            project.getInvestedPlusInterest(INVESTOR),
            (CORRECT_INVESTMENT_AMOUNT / 10) + CORRECT_INVESTMENT_AMOUNT
        );
        assertEq(project.getInvestorPaidOutStatus(INVESTOR), false);
        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);

        // fund #2
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        uint256 investedAmountAfter2 = project.getInvestorInvestmentAmount(
            INVESTOR
        );
        assertEq(
            investedAmountAfter2,
            CORRECT_INVESTMENT_AMOUNT + MIN_INVESTMENT
        );
        assertEq(
            project.getInvestedPlusInterest(INVESTOR),
            ((CORRECT_INVESTMENT_AMOUNT + MIN_INVESTMENT) / 10) +
                (CORRECT_INVESTMENT_AMOUNT + MIN_INVESTMENT)
        );
        assertEq(project.getInvestorPaidOutStatus(INVESTOR), false);
        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);

        // fund #3
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        uint256 investedAmountAfter3 = project.getInvestorInvestmentAmount(
            INVESTOR
        );
        assertEq(
            investedAmountAfter3,
            CORRECT_INVESTMENT_AMOUNT + MIN_INVESTMENT + MAX_INVESTMENT
        );
        assertEq(
            project.getInvestedPlusInterest(INVESTOR),
            ((CORRECT_INVESTMENT_AMOUNT + MIN_INVESTMENT + MAX_INVESTMENT) /
                10 +
                (CORRECT_INVESTMENT_AMOUNT + MIN_INVESTMENT + MAX_INVESTMENT))
        );
        assertEq(project.getInvestorPaidOutStatus(INVESTOR), false);
        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);
    }

    function testShouldFundToTheContractAndUpdateInvestorMappingWithMultipleInvestors()
        public
    {
        CrowdfundingProject project = createProject();

        uint256 investedAmountBefore = project.getInvestorInvestmentAmount(
            INVESTOR
        );
        uint256 investedAmountBefore2 = project.getInvestorInvestmentAmount(
            INVESTOR2
        );

        assertEq(investedAmountBefore, 0);
        assertEq(investedAmountBefore2, 0);

        // investor #1
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        uint256 investedAmountAfter = project.getInvestorInvestmentAmount(
            INVESTOR
        );
        uint256 investedPlusInterestAmount = project.getInvestedPlusInterest(
            INVESTOR
        );
        assertEq(investedAmountAfter, CORRECT_INVESTMENT_AMOUNT);
        assertEq(
            investedPlusInterestAmount,
            (CORRECT_INVESTMENT_AMOUNT / 10) + CORRECT_INVESTMENT_AMOUNT
        );
        assertEq(project.getInvestorPaidOutStatus(INVESTOR), false);
        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);

        // investor #2
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        uint256 investedAmountAfter2 = project.getInvestorInvestmentAmount(
            INVESTOR2
        );
        uint256 investedPlusInterestAmount2 = project.getInvestedPlusInterest(
            INVESTOR2
        );
        assertEq(investedAmountAfter2, MIN_INVESTMENT);
        assertEq(
            investedPlusInterestAmount2,
            (MIN_INVESTMENT / 10) + MIN_INVESTMENT
        );
        assertEq(project.getInvestorPaidOutStatus(INVESTOR2), false);
        assertEq(project.getAmountToBePaidOut(INVESTOR2), 0);

        // investor #3
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        uint256 investedAmountAfter3 = project.getInvestorInvestmentAmount(
            INVESTOR3
        );
        uint256 investedPlusInterestAmount3 = project.getInvestedPlusInterest(
            INVESTOR3
        );
        assertEq(investedAmountAfter3, MAX_INVESTMENT);
        assertEq(
            investedPlusInterestAmount3,
            (MAX_INVESTMENT / 10) + MAX_INVESTMENT
        );
        assertEq(project.getInvestorPaidOutStatus(INVESTOR3), false);
        assertEq(project.getAmountToBePaidOut(INVESTOR3), 0);
    }

    function testShouldFundToTheContractAndUpdateTheCurrentFundingAmountWithOneInvestor()
        public
    {
        CrowdfundingProject project = createProject();

        uint256 contractBalanceBefore = address(project).balance;
        uint256 expectedContractBalanceBefore = project
            .getCurrentFundedAmount();

        assertEq(contractBalanceBefore, initialFeesToBePaid);
        assertEq(expectedContractBalanceBefore, 0);

        // fund #1
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        uint256 contractBalanceAfter = address(project).balance;
        uint256 expectedContractBalanceAfter = project.getCurrentFundedAmount();

        assertEq(
            contractBalanceAfter,
            contractBalanceBefore + CORRECT_INVESTMENT_AMOUNT
        );
        assertEq(expectedContractBalanceAfter, CORRECT_INVESTMENT_AMOUNT);

        // fund #2
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        uint256 contractBalanceAfter2 = address(project).balance;
        uint256 expectedContractBalanceAfter2 = project
            .getCurrentFundedAmount();

        assertEq(
            contractBalanceAfter2,
            contractBalanceBefore + CORRECT_INVESTMENT_AMOUNT + MIN_INVESTMENT
        );
        assertEq(
            expectedContractBalanceAfter2,
            CORRECT_INVESTMENT_AMOUNT + MIN_INVESTMENT
        );
    }

    function testShouldFundToTheContractAndUpdateTheCurrentFundingAmountWithMultipleInvestors()
        public
    {
        CrowdfundingProject project = createProject();

        uint256 contractBalanceBefore = address(project).balance;
        uint256 expectedContractBalanceBefore = project
            .getCurrentFundedAmount();

        assertEq(contractBalanceBefore, initialFeesToBePaid);
        assertEq(expectedContractBalanceBefore, 0);

        // investor #1
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        uint256 contractBalanceAfter = address(project).balance;
        uint256 expectedContractBalanceAfter = project.getCurrentFundedAmount();

        assertEq(
            contractBalanceAfter,
            contractBalanceBefore + CORRECT_INVESTMENT_AMOUNT
        );
        assertEq(expectedContractBalanceAfter, CORRECT_INVESTMENT_AMOUNT);

        // investor #2
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        uint256 contractBalanceAfter2 = address(project).balance;
        uint256 expectedContractBalanceAfter2 = project
            .getCurrentFundedAmount();

        assertEq(
            contractBalanceAfter2,
            contractBalanceBefore + CORRECT_INVESTMENT_AMOUNT + MAX_INVESTMENT
        );
        assertEq(
            expectedContractBalanceAfter2,
            CORRECT_INVESTMENT_AMOUNT + MAX_INVESTMENT
        );

        // investor #3
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        uint256 contractBalanceAfter3 = address(project).balance;
        uint256 expectedContractBalanceAfter3 = project
            .getCurrentFundedAmount();

        assertEq(
            contractBalanceAfter3,
            contractBalanceBefore +
                CORRECT_INVESTMENT_AMOUNT +
                MAX_INVESTMENT +
                MIN_INVESTMENT
        );
        assertEq(
            expectedContractBalanceAfter3,
            CORRECT_INVESTMENT_AMOUNT + MAX_INVESTMENT + MIN_INVESTMENT
        );
    }

    function testShouldFundToTheContractAndUpdateInvestorsArrayWithOneInvestor()
        public
    {
        CrowdfundingProject project = createProject();

        // fund #1
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        assertEq(project.getInvestorAddress(0), INVESTOR);

        // fund #2
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.expectRevert();
        project.getInvestorAddress(1);

        // fund #3
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        vm.expectRevert();
        project.getInvestorAddress(2);
    }

    function testShouldFundToTheContractAndUpdateInvestorsArrayWithMultipleInvestors()
        public
    {
        CrowdfundingProject project = createProject();

        // investor #1
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        assertEq(project.getInvestorAddress(0), INVESTOR);

        // investor #2
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        assertEq(project.getInvestorAddress(1), INVESTOR2);

        // investor #3
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        assertEq(project.getInvestorAddress(2), INVESTOR3);
    }

    //////////////////////
    // checkUpkeep TEST //
    //////////////////////
    function testFuzz_ShoulReturnFalseIfNotEnoughTimePassed(
        uint256 _amount
    ) public {
        uint256 amount = bound(
            _amount,
            ONE_DAY_IN_SECONDS,
            (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) - 1
        );

        CrowdfundingProject project = createProject();

        vm.warp(block.timestamp + (amount) + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = project.checkUpkeep("");
        assertEq(upkeepNeeded, false);
    }

    function testFuzz_ShoulReturnTrueIfEnoughTimePassed(
        uint256 _amount
    ) public {
        uint256 amount = bound(
            _amount,
            (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1,
            type(uint40).max
        );

        CrowdfundingProject project = createProject();

        vm.warp(block.timestamp + amount);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = project.checkUpkeep("");
        assertEq(upkeepNeeded, true);
    }

    ////////////////////////
    // performUpkeep TEST //
    ////////////////////////
    function testShouldRevertIfUpkeepNotNeeded() public {
        CrowdfundingProject project = createProject();

        // test #1
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__UpkeepNotNeeded
                    .selector
            )
        );
        project.performUpkeep("");

        // test #2
        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) - 5);
        vm.roll(block.number + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__UpkeepNotNeeded
                    .selector
            )
        );
        project.performUpkeep("");
    }

    function testRevertIfCalledInClosedState() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        assertEq(uint256(project.getProjectStatus()), 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__FundingIsNotActive
                    .selector
            )
        );
        project.performUpkeep("");
    }

    function testShouldRevertIfCalledInFinishedState() public {
        CrowdfundingProject project = createProjectFullyFundItAndPerformUpkeepAndFinish();

        assertEq(uint256(project.getProjectStatus()), 3);

        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__FundingIsNotActive
                    .selector
            )
        );
        project.performUpkeep("");
    }

    function testShouldRevertIfCalledInInvestingActiveState() public {
        CrowdfundingProject project = createProjectFullyFundItAndPerformUpkeep();

        assertEq(uint256(project.getProjectStatus()), 2);

        vm.prank(PROJECT_OWNER);
        crowdfunding.ownerFundProject{value: STARTING_BALANCE * 3}(0);

        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__FundingIsNotActive
                    .selector
            )
        );
        project.performUpkeep("");
    }

    function testShouldChangeProjectStateToClosedAndSetPayOutsWithOneInvestor()
        public
    {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);

        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);
        assertEq(uint256(project.getProjectStatus()), 1); // 1 = Funding

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        assertEq(
            project.getAmountToBePaidOut(INVESTOR),
            CORRECT_INVESTMENT_AMOUNT
        );
        assertEq(uint256(project.getProjectStatus()), 0); // 1 = Closed
    }

    function testShouldChangeProjectStateToClosedAndSetPayOutsWithMultipleInvestors()
        public
    {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);

        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);
        assertEq(project.getAmountToBePaidOut(INVESTOR2), 0);
        assertEq(project.getAmountToBePaidOut(INVESTOR3), 0);
        assertEq(uint256(project.getProjectStatus()), 1); // 1 = Funding

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        assertEq(
            project.getAmountToBePaidOut(INVESTOR),
            CORRECT_INVESTMENT_AMOUNT
        );
        assertEq(project.getAmountToBePaidOut(INVESTOR2), MIN_INVESTMENT);
        assertEq(project.getAmountToBePaidOut(INVESTOR3), MAX_INVESTMENT);
        assertEq(uint256(project.getProjectStatus()), 0); // 1 = Closed
    }

    function testShouldChangeTheStateToInvestingActiveAndWithdrawFundsToProjectOwnerAndCrowdfundingContract()
        public
    {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);

        uint256 projectOwnerBalanceBefore = address(PROJECT_OWNER).balance;
        uint256 projectContractBalanceBefore = address(project).balance;
        uint256 crowdfundingContractBalanceBefore = address(crowdfunding)
            .balance;

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        uint256 projectOwnerBalanceAfter = address(PROJECT_OWNER).balance;
        uint256 projectContractBalanceAfter = address(project).balance;
        uint256 crowdfundingContractBalanceAfter = address(crowdfunding)
            .balance;
        uint256 projectStatus = uint256(project.getProjectStatus());

        assertEq(
            projectOwnerBalanceAfter,
            projectOwnerBalanceBefore + (MAX_INVESTMENT * 3)
        );
        assertEq(
            projectContractBalanceAfter,
            projectContractBalanceBefore -
                (MAX_INVESTMENT * 3) -
                initialFeesToBePaid
        );
        assertEq(
            crowdfundingContractBalanceAfter,
            crowdfundingContractBalanceBefore + initialFeesToBePaid
        );
        assertEq(projectStatus, 2); // 1 = Investing Active
    }

    /////////////////
    // cancel TEST //
    /////////////////
    function testShoulRevertIfCalledByNotCrowdfundingContract() public {
        CrowdfundingProject project = createProject();

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__CanOnlyBeCalledByTheCrowdfundingContract
                    .selector
            )
        );
        project.cancel();
    }

    function testShoulRevertIfCalledInClosedState() public {
        CrowdfundingProject project = createProject();

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__FundingIsNotActive
                    .selector
            )
        );
        crowdfunding.cancelProject(0);
    }

    function testShoulRevertIfCalledInInvestingActiveState() public {
        createProjectFullyFundItAndPerformUpkeep();

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__FundingIsNotActive
                    .selector
            )
        );
        crowdfunding.cancelProject(0);
    }

    function testShoulRevertIfCalledInFinishedState() public {
        createProjectFullyFundItAndPerformUpkeepAndFinish();

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__FundingIsNotActive
                    .selector
            )
        );
        crowdfunding.cancelProject(0);
    }

    function testShoulRevertIfCalledAlreadyCanceled() public {
        createProject();

        vm.prank(PROJECT_OWNER);
        crowdfunding.cancelProject(0);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__FundingIsNotActive
                    .selector
            )
        );
        crowdfunding.cancelProject(0);
    }

    function testShouldChangeStateToCanceledAndSetPayOuts() public {
        CrowdfundingProject project = createProject();

        assertEq(uint256(project.getProjectStatus()), 1);
        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);
        assertEq(project.getAmountToBePaidOut(INVESTOR2), 0);
        assertEq(project.getAmountToBePaidOut(INVESTOR3), 0);
        assertEq(project.getAmountToBePaidOut(PROJECT_OWNER), 0);

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);

        vm.prank(PROJECT_OWNER);
        crowdfunding.cancelProject(0);

        assertEq(uint256(project.getProjectStatus()), 4);
        assertEq(project.getAmountToBePaidOut(INVESTOR), MAX_INVESTMENT);
        assertEq(project.getAmountToBePaidOut(INVESTOR2), MAX_INVESTMENT);
        assertEq(project.getAmountToBePaidOut(INVESTOR3), MIN_INVESTMENT);
        assertEq(
            project.getAmountToBePaidOut(PROJECT_OWNER),
            initialFeesToBePaid
        );
    }

    //////////////////////////
    // withdrawPayOuts TEST //
    //////////////////////////
    function testShoulRevertIfAlreadyWithdrawed() public {
        CrowdfundingProject project = createProjectFullyFundItAndPerformUpkeepAndFinish();

        vm.prank(INVESTOR);
        project.withdrawPayOuts();
        vm.prank(INVESTOR2);
        project.withdrawPayOuts();
        vm.prank(INVESTOR3);
        project.withdrawPayOuts();

        vm.prank(INVESTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__AlreadyWithdrawed
                    .selector
            )
        );
        project.withdrawPayOuts();

        vm.prank(INVESTOR2);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__AlreadyWithdrawed
                    .selector
            )
        );
        project.withdrawPayOuts();

        vm.prank(INVESTOR3);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__AlreadyWithdrawed
                    .selector
            )
        );
        project.withdrawPayOuts();
    }

    function testShoulRevertIfPayOutAmountIsZero() public {
        CrowdfundingProject project = createProject();

        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);

        vm.prank(INVESTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__PayOutsNotActive
                    .selector
            )
        );
        project.withdrawPayOuts();
    }

    function testShouldWithrawTheRightAmountAndChangeThePaidOutToTrue() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT * 3}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT * 2}(0);

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        uint256 investorBalanceBefore = address(INVESTOR).balance;
        uint256 investorBalanceBefore2 = address(INVESTOR2).balance;
        uint256 investorBalanceBefore3 = address(INVESTOR3).balance;

        vm.prank(PROJECT_OWNER);
        crowdfunding.ownerFundProject{value: STARTING_BALANCE * 3}(0);
        vm.prank(PROJECT_OWNER);
        crowdfunding.finishProject(0);

        vm.prank(INVESTOR);
        project.withdrawPayOuts();
        vm.prank(INVESTOR2);
        project.withdrawPayOuts();
        vm.prank(INVESTOR3);
        project.withdrawPayOuts();

        uint256 expectedPayOut = project.getAmountToBePaidOut(INVESTOR);
        uint256 expectedPayOut2 = project.getAmountToBePaidOut(INVESTOR2);
        uint256 expectedPayOut3 = project.getAmountToBePaidOut(INVESTOR3);

        uint256 investorBalanceAfter = address(INVESTOR).balance;
        uint256 investorBalanceAfter2 = address(INVESTOR2).balance;
        uint256 investorBalanceAfter3 = address(INVESTOR3).balance;

        assertEq(
            expectedPayOut,
            project.calculateInvestedPlusInterest(
                MAX_INVESTMENT * 2,
                INTEREST_RATE
            )
        );
        assertEq(
            expectedPayOut2,
            project.calculateInvestedPlusInterest(
                CORRECT_INVESTMENT_AMOUNT * 3,
                INTEREST_RATE
            )
        );
        assertEq(
            expectedPayOut3,
            project.calculateInvestedPlusInterest(
                CORRECT_INVESTMENT_AMOUNT * 2,
                INTEREST_RATE
            )
        );

        assertEq(investorBalanceAfter, investorBalanceBefore + expectedPayOut);
        assertEq(
            investorBalanceAfter2,
            investorBalanceBefore2 + expectedPayOut2
        );
        assertEq(
            investorBalanceAfter3,
            investorBalanceBefore3 + expectedPayOut3
        );

        assertEq(project.getInvestorPaidOutStatus(INVESTOR), true);
        assertEq(project.getInvestorPaidOutStatus(INVESTOR2), true);
        assertEq(project.getInvestorPaidOutStatus(INVESTOR3), true);
    }

    ////////////////////
    // ownerFund TEST //
    ////////////////////
    function testShouldRevertIfNotCalledByCrowdfundingContract() public {
        CrowdfundingProject project = createProject();

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__CanOnlyBeCalledByTheCrowdfundingContract
                    .selector
            )
        );
        project.ownerFund();
    }

    function testShouldRevertIfCalledInClosedState() public {
        CrowdfundingProject project = createProject();

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        assertEq(uint256(project.getProjectStatus()), 0);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__InvestingIsNotActive
                    .selector
            )
        );
        crowdfunding.ownerFundProject{value: MAX_INVESTMENT}(0);
    }

    function testShouldRevertIfCalledInFundingActiveState() public {
        CrowdfundingProject project = createProject();

        assertEq(uint256(project.getProjectStatus()), 1);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__InvestingIsNotActive
                    .selector
            )
        );
        crowdfunding.ownerFundProject{value: MAX_INVESTMENT}(0);
    }

    function testRevertsIfCalledInFinishedState() public {
        CrowdfundingProject project = createProjectFullyFundItAndPerformUpkeepAndFinish();

        assertEq(uint256(project.getProjectStatus()), 3);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__InvestingIsNotActive
                    .selector
            )
        );
        crowdfunding.ownerFundProject{value: MAX_INVESTMENT}(0);
    }

    function testShouldRevertIfCalledInCanceledState() public {
        CrowdfundingProject project = createProject();

        vm.prank(PROJECT_OWNER);
        crowdfunding.cancelProject(0);

        assertEq(uint256(project.getProjectStatus()), 4);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__InvestingIsNotActive
                    .selector
            )
        );
        crowdfunding.ownerFundProject{value: MAX_INVESTMENT}(0);
    }

    function testShouldFundToTheContract() public {
        CrowdfundingProject project = createProjectFullyFundItAndPerformUpkeep();

        uint256 projectContractBalanceBefore = address(project).balance;

        vm.prank(PROJECT_OWNER);
        crowdfunding.ownerFundProject{value: STARTING_BALANCE * 3}(0);

        uint256 projectContractBalanceAfter = address(project).balance;

        assertEq(
            projectContractBalanceBefore + (STARTING_BALANCE * 3),
            projectContractBalanceAfter
        );
    }

    /////////////////
    // finish TEST //
    /////////////////
    function testShouldRevertIfNotCalledByCrowdfunding() public {
        CrowdfundingProject project = createProject();

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__CanOnlyBeCalledByTheCrowdfundingContract
                    .selector
            )
        );
        project.finish();
    }

    function testRevertsIfCalledInClosedState() public {
        CrowdfundingProject project = createProject();

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        assertEq(uint256(project.getProjectStatus()), 0);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__InvestingIsNotActive
                    .selector
            )
        );
        crowdfunding.finishProject(0);
    }

    function testShouldRevertIfInFundingState() public {
        CrowdfundingProject project = createProject();

        assertEq(uint256(project.getProjectStatus()), 1);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__InvestingIsNotActive
                    .selector
            )
        );
        crowdfunding.finishProject(0);
    }

    function testShouldRevertIfInFinishedState() public {
        CrowdfundingProject project = createProjectFullyFundItAndPerformUpkeepAndFinish();

        assertEq(uint256(project.getProjectStatus()), 3);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__InvestingIsNotActive
                    .selector
            )
        );
        crowdfunding.finishProject(0);
    }

    function testShouldRevertIfInCanceledState() public {
        CrowdfundingProject project = createProject();

        vm.prank(PROJECT_OWNER);
        crowdfunding.cancelProject(0);

        assertEq(uint256(project.getProjectStatus()), 4);

        vm.prank(PROJECT_OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                CrowdfundingProject
                    .CrowdfundingProject__InvestingIsNotActive
                    .selector
            )
        );
        crowdfunding.finishProject(0);
    }

    function testShouldSetTheStateToFinishedAndSetPayOuts() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);

        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);
        assertEq(project.getAmountToBePaidOut(INVESTOR2), 0);
        assertEq(project.getAmountToBePaidOut(INVESTOR3), 0);

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        vm.prank(PROJECT_OWNER);
        crowdfunding.ownerFundProject{value: STARTING_BALANCE * 3}(0);
        vm.prank(PROJECT_OWNER);
        crowdfunding.finishProject(0);

        assertEq(
            project.getAmountToBePaidOut(INVESTOR),
            ((MAX_INVESTMENT * INTEREST_RATE) / 10000) + MAX_INVESTMENT
        );
        assertEq(
            project.getAmountToBePaidOut(INVESTOR2),
            ((MAX_INVESTMENT * INTEREST_RATE) / 10000) + MAX_INVESTMENT
        );
        assertEq(
            project.getAmountToBePaidOut(INVESTOR3),
            ((MAX_INVESTMENT * INTEREST_RATE) / 10000) + MAX_INVESTMENT
        );
        assertEq(uint256(project.getProjectStatus()), 3);
    }

    ////////////////////////////////////////
    // calculateInvestedPlusInterest TEST //
    ////////////////////////////////////////
    function testShouldCalculateAmountInvestedPlusInterest() public {
        uint256 expectedCalculatedAmount = ((MIN_INVESTMENT * INTEREST_RATE) /
            10000) + MIN_INVESTMENT;
        // 5500000000000000000 (5.5 ETH)
        uint256 expectedCalculatedAmount2 = ((MAX_INVESTMENT * INTEREST_RATE2) /
            10000) + MAX_INVESTMENT;
        // 57500000000000000000 (57.5 ETH)
        uint256 expectedCalculatedAmount3 = ((CORRECT_INVESTMENT_AMOUNT *
            INTEREST_RATE3) / 10000) + CORRECT_INVESTMENT_AMOUNT;
        // 10550000000000000000 (10.55 ETH)

        CrowdfundingProject project = createProject();

        assertEq(
            project.calculateInvestedPlusInterest(
                MIN_INVESTMENT,
                INTEREST_RATE
            ),
            expectedCalculatedAmount
        );
        assertEq(
            project.calculateInvestedPlusInterest(
                MAX_INVESTMENT,
                INTEREST_RATE2
            ),
            expectedCalculatedAmount2
        );
        assertEq(
            project.calculateInvestedPlusInterest(
                CORRECT_INVESTMENT_AMOUNT,
                INTEREST_RATE3
            ),
            expectedCalculatedAmount3
        );
    }

    ///////////////////////////
    // getter functions TEST //
    ///////////////////////////
    /**
     * @dev some getter functions are already tested in constructor/create project tests
     */

    ///////////////////////////////////////////
    // getInvestedAmountForAllInvestors TEST //
    ///////////////////////////////////////////
    function testShouldGetAmountInvestedOfAllInvestorsTogetherWithMultipleInvestors()
        public
    {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);

        uint256 expectedAmountInvested = MIN_INVESTMENT +
            CORRECT_INVESTMENT_AMOUNT +
            MIN_INVESTMENT +
            MAX_INVESTMENT +
            CORRECT_INVESTMENT_AMOUNT +
            MAX_INVESTMENT;

        assertEq(
            project.getInvestedAmountForAllInvestors(),
            expectedAmountInvested
        );
    }

    function testShouldGetAmountInvestedOfAllInvestorsTogetherWithOneInvestor()
        public
    {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MIN_INVESTMENT * 2}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);

        uint256 expectedAmountInvested = MIN_INVESTMENT +
            CORRECT_INVESTMENT_AMOUNT +
            (MIN_INVESTMENT * 2) +
            MAX_INVESTMENT;

        assertEq(
            project.getInvestedAmountForAllInvestors(),
            expectedAmountInvested
        );
    }

    /////////////////////////////////////////////////////////////
    // getInvestedPlusInteresOfAllInvestorsWithoutGasFees TEST //
    /////////////////////////////////////////////////////////////
    function testShouldGetAmountInvestedPlusInterestOfAll() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        // 15 ETH
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        // 55 ETH
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        // 60 ETH

        uint256 expectedAmountInvestor1 = project.getInvestedPlusInterest(
            INVESTOR
        );
        // 16,5 ETH
        uint256 expectedAmountInvestor2 = project.getInvestedPlusInterest(
            INVESTOR2
        );
        // 60,5 ETH
        uint256 expectedAmountInvestor3 = project.getInvestedPlusInterest(
            INVESTOR3
        );
        // 66 ETH

        assertEq(
            project.getInvestedPlusInteresOfAllInvestorsWithoutGasFees(),
            expectedAmountInvestor1 +
                expectedAmountInvestor2 +
                expectedAmountInvestor3
        );
        // 143 ETH
    }

    ////////////////////////////////////
    // getRemainingFundingAmount TEST //
    ////////////////////////////////////
    function testShouldGetRemainingFundingAmount() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);

        uint256 expectedRemainingAmount = CROWDFUNDING_AMOUNT -
            CORRECT_INVESTMENT_AMOUNT -
            MIN_INVESTMENT;

        assertEq(project.getRemainingFundingAmount(), expectedRemainingAmount);
        // 135 ETH

        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);

        uint256 expectedRemainingAmount2 = CROWDFUNDING_AMOUNT -
            CORRECT_INVESTMENT_AMOUNT -
            MIN_INVESTMENT -
            MAX_INVESTMENT;

        assertEq(project.getRemainingFundingAmount(), expectedRemainingAmount2);
        // 85 ETH
    }

    ///////////////////////////////////
    // getInvestorPaidOutStatus TEST //
    ///////////////////////////////////
    function testShouldGetPaidOutStatusIfClosed() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);

        assertEq(project.getInvestorPaidOutStatus(INVESTOR), false);
        assertEq(project.getInvestorPaidOutStatus(INVESTOR2), false);

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        assertEq(project.getInvestorPaidOutStatus(INVESTOR), false);
        assertEq(project.getInvestorPaidOutStatus(INVESTOR2), false);

        vm.prank(INVESTOR);
        project.withdrawPayOuts();
        vm.prank(INVESTOR2);
        project.withdrawPayOuts();

        assertEq(project.getInvestorPaidOutStatus(INVESTOR), true);
        assertEq(project.getInvestorPaidOutStatus(INVESTOR2), true);
    }

    function testShouldGetPaidOutStatusIfFinished() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);

        assertEq(project.getInvestorPaidOutStatus(INVESTOR), false);
        assertEq(project.getInvestorPaidOutStatus(INVESTOR2), false);

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        assertEq(project.getInvestorPaidOutStatus(INVESTOR), false);
        assertEq(project.getInvestorPaidOutStatus(INVESTOR2), false);

        vm.prank(PROJECT_OWNER);
        crowdfunding.ownerFundProject{value: STARTING_BALANCE * 3}(0);
        vm.prank(PROJECT_OWNER);
        crowdfunding.finishProject(0);

        vm.prank(INVESTOR);
        project.withdrawPayOuts();
        vm.prank(INVESTOR2);
        project.withdrawPayOuts();

        assertEq(project.getInvestorPaidOutStatus(INVESTOR), true);
        assertEq(project.getInvestorPaidOutStatus(INVESTOR2), true);
    }

    ////////////////////////////
    // getInvestorsCount TEST //
    ////////////////////////////
    function testShouldGetAmountOfInvestors() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);
        vm.prank(INVESTOR3);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);

        assertEq(project.getInvestorsCount(), 3);
    }

    //////////////////////////////////////
    // getInvestorInvestmentAmount TEST //
    //////////////////////////////////////
    function testShouldGetInvestorsInvestedAmount() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);

        assertEq(
            project.getInvestorInvestmentAmount(INVESTOR),
            CORRECT_INVESTMENT_AMOUNT + MAX_INVESTMENT
        );
        assertEq(
            project.getInvestorInvestmentAmount(INVESTOR2),
            MIN_INVESTMENT
        );
    }

    //////////////////////////////////
    // getInvestedPlusInterest TEST //
    //////////////////////////////////
    function testShouldGetInvestorsInvestedPlusInterestAmount() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);

        assertEq(
            project.getInvestedPlusInterest(INVESTOR),
            project.calculateInvestedPlusInterest(
                CORRECT_INVESTMENT_AMOUNT + MAX_INVESTMENT,
                INTEREST_RATE
            )
        );
        assertEq(
            project.getInvestedPlusInterest(INVESTOR2),
            project.calculateInvestedPlusInterest(MIN_INVESTMENT, INTEREST_RATE)
        );
    }

    ///////////////////////////////
    // getAmountToBePaidOut TEST //
    ///////////////////////////////
    function testShouldGetInvestorAmountToBePaidOutIfClosed() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MIN_INVESTMENT}(0);

        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);
        assertEq(project.getAmountToBePaidOut(INVESTOR2), 0);

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        assertEq(
            project.getAmountToBePaidOut(INVESTOR),
            CORRECT_INVESTMENT_AMOUNT + MAX_INVESTMENT
        );
        assertEq(project.getAmountToBePaidOut(INVESTOR2), MIN_INVESTMENT);
    }

    function testShouldGetInvestorAmountToBePaidOutIfFinished() public {
        CrowdfundingProject project = createProject();

        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);

        assertEq(project.getAmountToBePaidOut(INVESTOR), 0);
        assertEq(project.getAmountToBePaidOut(INVESTOR2), 0);

        vm.warp(block.timestamp + (DEADLINE_IN_DAYS * ONE_DAY_IN_SECONDS) + 1);
        vm.roll(block.number + 1);
        project.performUpkeep("");

        vm.prank(PROJECT_OWNER);
        crowdfunding.ownerFundProject{value: STARTING_BALANCE * 3}(0);
        vm.prank(PROJECT_OWNER);
        crowdfunding.finishProject(0);

        assertEq(
            project.getAmountToBePaidOut(INVESTOR),
            project.calculateInvestedPlusInterest(
                MAX_INVESTMENT + MAX_INVESTMENT,
                INTEREST_RATE
            )
        );
        assertEq(
            project.getAmountToBePaidOut(INVESTOR2),
            project.calculateInvestedPlusInterest(MAX_INVESTMENT, INTEREST_RATE)
        );
    }

    ///////////////////////////
    // FALLBACK RECEIVE TEST //
    ///////////////////////////
    function testShouldRevertReceive() public {
        CrowdfundingProject project = createProject();

        vm.expectRevert();
        (bool success, ) = address(project).call{value: 1 ether}("");
    }

    function testShouldRevertFallback() public {
        CrowdfundingProject project = createProject();

        vm.expectRevert();
        (bool success, ) = address(project).call{value: 1 ether}(
            abi.encodeWithSignature("invalidFunction()")
        );
    }
}
