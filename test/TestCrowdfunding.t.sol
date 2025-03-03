// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.18;

import {Crowdfunding} from "../src/Crowdfunding.sol";
import {CrowdfundingProject} from "../src/CrowdfundingProject.sol";
import {DeployCrowdfunding} from "../script/DeployCrowdfunding.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Vm} from "../../lib/forge-std/src/Vm.sol";
import {Test, console} from "../../lib/forge-std/src/Test.sol";
import "forge-std/console.sol";

contract TestCrowdfunding is Test {
    event ProjectCreated(
        address indexed _owner,
        CrowdfundingProject indexed _projectAddress,
        uint256 indexed _projectIndex
    );

    event ProjectFunded(
        address indexed _funder,
        uint256 indexed _projectIndex,
        uint256 _fundAmount
    );

    event ProjectCanceled(
        address indexed _owner,
        uint256 indexed _projectIndex
    );

    event ProjectFundedOwner(
        address indexed _owner,
        uint256 indexed _projectIndex
    );

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

        vm.deal(PROJECT_OWNER, STARTING_BALANCE);
        vm.deal(PROJECT_OWNER2, STARTING_BALANCE);
        vm.deal(INVESTOR, STARTING_BALANCE);
        vm.deal(INVESTOR2, STARTING_BALANCE);
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
        crowdfunding.fundProject{value: MAX_INVESTMENT}(0);
        vm.prank(INVESTOR2);
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
    function testRevertIfTheAmountSentIsZero() public {
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

    function testFuzz_RevertIfTheAmountSentIsLessThanFeesToBePaid(
        uint256 _amount
    ) public {
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

    function testFuzz_RevertIfTheAmountSentIsMoreThanFeesToBePaid(
        uint256 _amount
    ) public {
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

    function testRevertsIfNameOfTheProjectIsEmpty() public {
        vm.expectRevert(Crowdfunding.Crowdfunding__NameCantBeEmpty.selector);
        crowdfunding.createProject{value: initialFeesToBePaid}(
            "",
            CROWDFUNDING_AMOUNT,
            INTEREST_RATE,
            MIN_INVESTMENT,
            MAX_INVESTMENT,
            DEADLINE_IN_DAYS,
            INVESTMENT_PERIOD_IN_DAYS
        );
    }

    function testFuzz_RevertIfDeadlineIsLessThanMinimum(
        uint256 _amount
    ) public {
        uint256 amount = bound(_amount, 0, minDeadlineInDays - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Crowdfunding.CrowdfundingProject__DeadlineIsTooShort.selector,
                minDeadlineInDays
            )
        );
        crowdfunding.createProject{value: initialFeesToBePaid}(
            PROJECT_NAME,
            CROWDFUNDING_AMOUNT,
            INTEREST_RATE,
            MIN_INVESTMENT,
            MAX_INVESTMENT,
            amount,
            INVESTMENT_PERIOD_IN_DAYS
        );
    }

    function testCreatesANewCrowdfundingProjectWithCorrectParameters() public {
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

    function testUpdatesTheProjectsStructWithCorrectData() public {
        createProject();

        string memory projectName = crowdfunding.getProjectName(0);
        uint256 crowdfundingAmount = crowdfunding.getCrowdfundingAmount(0);
        uint256 interestRate = crowdfunding.getInterestRate(0);
        uint256 minInvestment = crowdfunding.getMinInvestmentAmount(0);
        uint256 maxInvestment = crowdfunding.getMaxInvestmentAmount(0);
        uint256 deadline = crowdfunding.getDeadlineInDays(0);
        uint256 investmentPeriod = crowdfunding.getInvestmentPeriodDays(0);
        address owner = crowdfunding.getProjectOwner(0);
        uint256[] memory projectIdBasedOnOwnerAddress = crowdfunding
            .getProjectIdBasedOnOwnerAddress(PROJECT_OWNER);

        assertEq(projectName, PROJECT_NAME);
        assertEq(crowdfundingAmount, CROWDFUNDING_AMOUNT);
        assertEq(interestRate, INTEREST_RATE);
        assertEq(minInvestment, MIN_INVESTMENT);
        assertEq(maxInvestment, MAX_INVESTMENT);
        assertEq(deadline, DEADLINE_IN_DAYS);
        assertEq(investmentPeriod, INVESTMENT_PERIOD_IN_DAYS);
        assertEq(owner, PROJECT_OWNER);
        assertEq(projectIdBasedOnOwnerAddress.length, 1);
        assertEq(projectIdBasedOnOwnerAddress[0], 0);

        createProject();

        uint256[] memory projectIdsBasedOnOwnerAddress = crowdfunding
            .getProjectIdBasedOnOwnerAddress(PROJECT_OWNER);

        assertEq(projectIdsBasedOnOwnerAddress.length, 2);
        assertEq(projectIdsBasedOnOwnerAddress[1], 1);
    }

    function testShouldCreateAProjectsAndEmitEvent() public {
        uint256 projectId = 0;
        uint256 projectTwoId = 1;

        vm.prank(PROJECT_OWNER);
        vm.expectEmit(true, true, true, false);
        emit ProjectCreated(
            address(PROJECT_OWNER),
            CrowdfundingProject(0xa16E02E87b7454126E5E10d957A927A7F5B5d2be),
            projectId
        );

        crowdfunding.createProject{value: initialFeesToBePaid}(
            PROJECT_NAME,
            CROWDFUNDING_AMOUNT,
            INTEREST_RATE,
            MIN_INVESTMENT,
            MAX_INVESTMENT,
            DEADLINE_IN_DAYS,
            INVESTMENT_PERIOD_IN_DAYS
        );
        vm.stopPrank();

        vm.prank(PROJECT_OWNER);
        vm.expectEmit(true, true, true, false);
        emit ProjectCreated(
            address(PROJECT_OWNER),
            CrowdfundingProject(0xB7A5bd0345EF1Cc5E66bf61BdeC17D2461fBd968),
            projectTwoId
        );

        crowdfunding.createProject{value: initialFeesToBePaid}(
            PROJECT_NAME,
            CROWDFUNDING_AMOUNT,
            INTEREST_RATE,
            MIN_INVESTMENT,
            MAX_INVESTMENT,
            DEADLINE_IN_DAYS,
            INVESTMENT_PERIOD_IN_DAYS
        );

        vm.stopPrank();
    }

    //////////////////////
    // fundProject TEST //
    //////////////////////
    function testFuzz_RevertsIfTheProvidedIdDoesntExists(
        uint256 _amount
    ) public {
        uint256 amount = bound(_amount, 1, type(uint256).max);
        createProject();
        vm.expectRevert();
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(amount);
    }

    function testRevertsIfTheAmountFundedIsZero() public {
        createProject();
        vm.expectRevert();
        crowdfunding.fundProject{value: 0}(0);
    }

    function testShouldFundToTheContractAndEmitAnEvent() public {
        uint256 projectId = 0;
        CrowdfundingProject project = createProject();
        uint256 startingBalanceOfTheProject = address(project).balance;
        assertEq(startingBalanceOfTheProject, initialFeesToBePaid);

        vm.startPrank(INVESTOR);
        vm.expectEmit(true, true, true, false);
        emit ProjectFunded(
            address(INVESTOR),
            projectId,
            CORRECT_INVESTMENT_AMOUNT
        );
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(projectId);
        uint256 endingBalanceOfTheProject = address(project).balance;
        assertEq(
            endingBalanceOfTheProject,
            initialFeesToBePaid + CORRECT_INVESTMENT_AMOUNT
        );
        vm.stopPrank();
    }

    ///////////////////
    // cancelProject //
    ///////////////////
    function testFuzz_RevertsIfTheProjectIdNotExists(uint256 _amount) public {
        uint256 amount = bound(_amount, 1, type(uint256).max);
        createProject();
        vm.prank(PROJECT_OWNER);
        vm.expectRevert();
        crowdfunding.cancelProject(amount);
    }

    function testRevertsIfNotCalledByTheProjectOwner() public {
        createProject();
        vm.prank(PROJECT_OWNER2);
        vm.expectRevert();
        crowdfunding.cancelProject(0);
    }

    function testCancelsTheProjectAndPaysBackTheInvestorsAndOwnerAndEmitsAnEvent()
        public
    {
        uint256 startingProjectOwnerBalance = PROJECT_OWNER.balance;
        CrowdfundingProject project = createProject();
        uint256 startingInvestorBalance = INVESTOR.balance;
        vm.prank(INVESTOR);
        crowdfunding.fundProject{value: CORRECT_INVESTMENT_AMOUNT}(0);

        vm.expectEmit(true, true, false, false);
        emit ProjectCanceled(PROJECT_OWNER, 0);
        vm.prank(PROJECT_OWNER);
        crowdfunding.cancelProject(0);
        uint256 endingInvestorBalance = INVESTOR.balance;
        uint256 endingProjectOwnerBalance = PROJECT_OWNER.balance;

        assertEq(address(project).balance, 0);
        assertEq(endingInvestorBalance, startingInvestorBalance);
        // on real test net the project owner should get back (initialFees - fees payed for paying back investors)
        assertEq(endingProjectOwnerBalance, startingProjectOwnerBalance);
    }

    ///////////////////////////
    // ownerFundProject TEST //
    ///////////////////////////
    function testRevertsIfFundNotCalledByTheProjectOwner() public {
        uint256 fundAmount = 5 ether;
        createProject();
        vm.prank(PROJECT_OWNER2);
        vm.expectRevert();
        crowdfunding.ownerFundProject{value: fundAmount}(0);
    }

    function testRevertsIfTheAmountSentIsZero() public {
        createProject();
        vm.prank(PROJECT_OWNER);
        vm.expectRevert();
        crowdfunding.ownerFundProject{value: 0}(0);
    }

    function testShoudFundTheProjectContractWithFundedAmountAndEmitAnEvent()
        public
    {
        uint256 fundAmount = 5 ether;
        uint256 projectId = 0;
        CrowdfundingProject project = createProjectFullyFundItAndPerformUpkeep();
        uint256 startingBalanceOfTheProject = address(project).balance;

        vm.prank(PROJECT_OWNER);
        vm.expectEmit(true, true, false, false);
        emit ProjectFundedOwner(PROJECT_OWNER, 0);
        crowdfunding.ownerFundProject{value: fundAmount}(projectId);
        uint256 endingBalanceOfTheProject = address(project).balance;

        assertEq(
            endingBalanceOfTheProject,
            startingBalanceOfTheProject + fundAmount
        );
    }

    ////////////////////////
    // finishProject TEST //
    ////////////////////////

    ///////////////////////
    // withdrawFees TEST //
    ///////////////////////

    //////////////////////////////
    // calculateInitialFee TEST //
    //////////////////////////////

    function testFuzz_CalculatedInitialFeesShouldBeTheSameAsExpectedFees(
        uint256 _amount
    ) public {
        uint256 crowdfundingAmount = bound(_amount, 1 ether, 5000 ether);

        uint256 expectedFee = (crowdfundingAmount * 500000000000000) / 1e18;

        uint256 actualFee = crowdfunding.calculateInitialFee(
            crowdfundingAmount
        );

        vm.prank(PROJECT_OWNER);
        crowdfunding.createProject{value: expectedFee}(
            PROJECT_NAME,
            crowdfundingAmount,
            INTEREST_RATE,
            crowdfundingAmount / 2,
            crowdfundingAmount - 1,
            DEADLINE_IN_DAYS,
            INVESTMENT_PERIOD_IN_DAYS
        );

        assertEq(expectedFee, actualFee);
    }

    function testCalculateInitialFees() public {
        uint256 expectedValueSentInWei = (CROWDFUNDING_AMOUNT *
            500000000000000) / 1e18;

        vm.prank(PROJECT_OWNER);
        crowdfunding.createProject{value: expectedValueSentInWei}(
            PROJECT_NAME,
            CROWDFUNDING_AMOUNT,
            INTEREST_RATE,
            MIN_INVESTMENT,
            MAX_INVESTMENT,
            DEADLINE_IN_DAYS,
            INVESTMENT_PERIOD_IN_DAYS
        );

        initialFeesToBePaid = crowdfunding.calculateInitialFee(
            CROWDFUNDING_AMOUNT
        );
        assertEq(initialFeesToBePaid, expectedValueSentInWei);
    }
}
