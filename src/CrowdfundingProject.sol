// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * @title Crowdfunding Project
 * @author Mariosso
 * @notice This contract is a child of the Crowdfunding manager contract. It handles the logic for determining if a project is successfully funded and manages payouts to investors.
 * @dev The contract uses Chainlink Automation to check if the funding goal is met after the deadline. It has five main states:
 * 1. FUNDING_ACTIVE:
 *    - The initial state after project creation.
 *    - During this state:
 *      a) Investors can fund the project.
 *      b) The project owner can cancel the project.
 * 2. CLOSED:
 *    - The project transitions to this state automatically if the funding goal is not met by the deadline.
 *    - During this state:
 *      a) Investors can withdraw their contributions.
 *      b) The project owner can withdraw the initial fees paid during project creation.
 * 3. INVESTING_ACTIVE:
 *    - The project transitions to this state automatically if the funding goal is met by the deadline.
 *    - During this state:
 *      a) The crowdfunded amount is sent to the project owner.
 *      b) The crowdfunding fees are sent to the manager contract.
 *      c) The project owner can fund the project contract to repay investors and finish the project.
 * 4. FINISHED:
 *    - The project transitions to this state when the project owner calls the `finish` function and the contract has sufficient balance to repay investors.
 *    - This is the final state of the project.
 * 5. CANCELED:
 *    - The project transitions to this state if the project owner cancels the project.
 *    - During this state:
 *      a) Investors can withdraw their contributions.
 *      b) The project owner can withdraw the initial fees paid during project creation.
 * @dev IMPORTANT: After a project is successfully funded, the full funded amount is sent to the project owner.
 *      There is no mechanism to enforce repayment to investors. Investors must trust the project owner to repay them.
 *      Investors should only fund projects from known and trusted addresses.
 */

import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

contract CrowdfundingProject is AutomationCompatibleInterface {
    error CrowdfundingProject__NotEnoughEthSent();
    error CrowdfundingProject__TooMuchEthSent();
    error CrowdfundingProject__MinInvestmentGreaterOrEqualToMaxInvestment();
    error CrowdfundingProject__AmountCrowfundedCantBeLessThanMaxInvestment();
    error CrowdfundingProject__AmountEthSentIsGreaterThanTheRestCrowfundingNeeded(
        uint256
    );
    error CrowdfundingProject__FundingIsNotActive();
    error CrowdfundingProject__InvestingIsNotActive();
    error CrowdfundingProject__PayOutsNotActive();
    error CrowdfundingProject__CanOnlyBeCalledByTheCrowdfundingContract();
    error CrowdfundingProject__UpkeepNotNeeded();
    error CrowdfundingProject__AlreadyWithdrawed();
    error CrowdfundingProject__RateHasToBeBetweenOneAndTenThousand();

    modifier onlyCrowdfundingContract() {
        if (msg.sender != s_crowdfundingContractAddress) {
            revert CrowdfundingProject__CanOnlyBeCalledByTheCrowdfundingContract();
        }
        _;
    }

    address payable private s_crowdfundingContractAddress;

    string private s_projectName;
    address payable private immutable i_owner;
    uint256 private immutable i_maxCrowdfundingAmount;
    uint256 private s_currentFundedAmount;
    uint256 private immutable i_interestRate;
    uint256 private immutable i_minInvestment;
    uint256 private immutable i_maxInvestment;
    uint256 private immutable i_deadlineInDays;
    uint256 private immutable i_investmentPeriod;
    ProjectState private s_projectState;
    uint256 private s_projectFundingIntervalStart;
    uint256 private constant ONE_DAY_IN_SECONDS = 86400;
    uint256 private s_projectInvestmentIntervalStart;

    enum ProjectState {
        CLOSED,
        FUNDING_ACTIVE,
        INVESTING_ACTIVE,
        FINISHED,
        CANCELED
    }

    struct Investor {
        uint256 amountInvested;
        uint256 amountInvestedPlusInterest;
        uint256 amountToPayOut;
        bool paidOut;
    }

    mapping(address investorAddress => Investor investor) private s_investor;
    address[] s_investors;

    /**
     * @dev Initializes a new crowdfunding project with the provided details. The project state is set to FUNDING_ACTIVE, and the start timestamp is recorded.
     * @param _projectName The name of the project.
     * @param _projectOwner The address of the project owner.
     * @param _maxCrowfundingAmount The total amount to be raised. Must be greater than or equal to the maximum investment.
     * @param _interestRate The interest rate (in basis points) to be paid to investors. Must be between 1 and 10000 (0.01% to 100%).
     * @param _minInvestment The minimum amount an investor can contribute. Must be less than the maximum investment.
     * @param _maxInvestment The maximum amount an investor can contribute.
     * @param _deadlineInDays The deadline (in days) by which the funding goal must be reached.
     * @param _investmentPeriod The period (in days) during which the raised funds will be invested.
     * @param _crowdfundingContractAddress The address of the main crowdfunding manager contract.
     */
    constructor(
        string memory _projectName,
        address payable _projectOwner,
        uint256 _maxCrowfundingAmount,
        uint256 _interestRate,
        uint256 _minInvestment,
        uint256 _maxInvestment,
        uint256 _deadlineInDays,
        uint256 _investmentPeriod,
        address payable _crowdfundingContractAddress
    ) payable {
        if (_maxCrowfundingAmount < _maxInvestment) {
            revert CrowdfundingProject__AmountCrowfundedCantBeLessThanMaxInvestment();
        }
        if (_minInvestment >= _maxInvestment) {
            revert CrowdfundingProject__MinInvestmentGreaterOrEqualToMaxInvestment();
        }
        if (_interestRate < 1 || _interestRate > 10000) {
            revert CrowdfundingProject__RateHasToBeBetweenOneAndTenThousand();
        }
        s_projectName = _projectName;
        i_owner = _projectOwner;
        i_maxCrowdfundingAmount = _maxCrowfundingAmount;
        s_currentFundedAmount = 0;
        i_interestRate = _interestRate;
        i_minInvestment = _minInvestment;
        i_maxInvestment = _maxInvestment;
        i_deadlineInDays = _deadlineInDays;
        i_investmentPeriod = _investmentPeriod;
        s_projectState = ProjectState.FUNDING_ACTIVE;
        s_projectFundingIntervalStart = block.timestamp;
        s_crowdfundingContractAddress = _crowdfundingContractAddress;
    }

    /**
     * @dev Allows an investor to fund the project. Only callable by the Crowdfunding manager contract.
     * @dev Can only be called during the FUNDING_ACTIVE state.
     * @dev The funded amount must:
     *      - Be greater than or equal to the minimum investment.
     *      - Be less than or equal to the maximum investment.
     *      - Not exceed the remaining funding amount.
     * @dev The investor's funded amount and payout amount are calculated based on whether they have previously invested.
     * @param _investorAddress The address of the investor.
     */
    function fund(
        address _investorAddress
    ) external payable onlyCrowdfundingContract {
        if (s_projectState != ProjectState.FUNDING_ACTIVE) {
            revert CrowdfundingProject__FundingIsNotActive();
        }
        if (msg.value < i_minInvestment) {
            revert CrowdfundingProject__NotEnoughEthSent();
        }
        if (msg.value > i_maxInvestment) {
            revert CrowdfundingProject__TooMuchEthSent();
        }
        uint256 remainingFundingAmount = getRemainingFundingAmount();
        if (msg.value > remainingFundingAmount) {
            revert CrowdfundingProject__AmountEthSentIsGreaterThanTheRestCrowfundingNeeded(
                remainingFundingAmount
            );
        }

        uint256 amountInvestedPlusInterest = calculateInvestedPlusInterest(
            msg.value,
            i_interestRate
        );

        uint256 amountAlreadyInvested = s_investor[_investorAddress]
            .amountInvested;

        if (amountAlreadyInvested == 0) {
            s_investor[_investorAddress] = Investor(
                msg.value,
                amountInvestedPlusInterest,
                0,
                false
            );
            s_investors.push() = payable(_investorAddress);
            s_currentFundedAmount += msg.value;
        } else {
            s_investor[_investorAddress].amountInvested =
                amountAlreadyInvested +
                msg.value;
            uint256 amountAlreadyInvestedPlusInterest = s_investor[
                _investorAddress
            ].amountInvestedPlusInterest;
            s_investor[_investorAddress].amountInvestedPlusInterest =
                amountAlreadyInvestedPlusInterest +
                amountInvestedPlusInterest;
            s_currentFundedAmount += msg.value;
        }
    }

    /**
     * @dev Function used by Chainlink Automation to check if the funding deadline has passed.
     * @return upkeepNeeded True if the deadline has passed, otherwise false.
     * @return performData Additional data (not used in this implementation).
     */
    function checkUpkeep(
        bytes memory /* checkData */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        upkeepNeeded =
            (block.timestamp - s_projectFundingIntervalStart) >
            (i_deadlineInDays * ONE_DAY_IN_SECONDS);
    }

    /**
     * @dev Function used by Chainlink Automation to determine if the funding goal was met after the deadline.
     * @dev Can only be called during the FUNDING_ACTIVE state.
     * @dev Transitions the project to:
     *      - CLOSED state if the funding goal was not met.
     *      - INVESTING_ACTIVE state if the funding goal was met.
     */
    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert CrowdfundingProject__UpkeepNotNeeded();
        }
        if (s_projectState != ProjectState.FUNDING_ACTIVE) {
            revert CrowdfundingProject__FundingIsNotActive();
        }
        if (
            (block.timestamp - s_projectFundingIntervalStart) >
            (i_deadlineInDays * ONE_DAY_IN_SECONDS)
        ) {
            if (s_currentFundedAmount < i_maxCrowdfundingAmount) {
                s_projectState = ProjectState.CLOSED;
                setPayOuts();
            } else {
                s_projectInvestmentIntervalStart = block.timestamp;
                s_projectState = ProjectState.INVESTING_ACTIVE;
                withdrawFunds();
            }
        }
    }

    /**
     * @dev Cancels the crowdfunding project and sets payouts to investors and the project owner. Only callable by the Crowdfunding manager contract.
     * @dev Can only be called during the FUNDING_ACTIVE state.
     * @dev After cancellation:
     *      - Investors can withdraw their contributions.
     *      - The project owner can withdraw the initial fees paid during project creation.
     */
    function cancel() external onlyCrowdfundingContract {
        if (s_projectState != ProjectState.FUNDING_ACTIVE) {
            revert CrowdfundingProject__FundingIsNotActive();
        }
        s_projectState = ProjectState.CANCELED;
        setPayOuts();
    }

    /**
     * @dev Sets payouts to investors and the project owner based on the current project state.
     * @dev Only callable internally.
     * @dev Payout logic:
     *      - CLOSED/CANCELED: Investors receive their invested amount; the project owner receives the remaining balance.
     *      - FINISHED: Investors receive their invested amount plus interest; the project owner receives the remaining balance.
     */
    function setPayOuts() internal {
        address[] memory temporaryInvestorsAddresses = s_investors;

        if (
            s_projectState == ProjectState.CLOSED ||
            s_projectState == ProjectState.CANCELED
        ) {
            for (uint256 i = 0; i < temporaryInvestorsAddresses.length; i++) {
                address investorAddress = temporaryInvestorsAddresses[i];
                if (getInvestorPaidOutStatus(investorAddress) == false) {
                    s_investor[investorAddress].amountToPayOut += s_investor[
                        investorAddress
                    ].amountInvested;
                }
            }
        } else if (s_projectState == ProjectState.FINISHED) {
            for (uint256 i = 0; i < temporaryInvestorsAddresses.length; i++) {
                address investorAddress = temporaryInvestorsAddresses[i];
                if (getInvestorPaidOutStatus(investorAddress) == false) {
                    s_investor[investorAddress].amountToPayOut += s_investor[
                        investorAddress
                    ].amountInvestedPlusInterest;
                }
            }
        }

        uint256 amountInvestedOfAllInvestors = getInvestedAmountForAllInvestors();

        s_investor[i_owner].amountToPayOut = (address(this).balance -
            amountInvestedOfAllInvestors);
    }

    /**
     * @dev Allows investors and the project owner to withdraw their payouts.
     * @dev Cannot be called if the caller has already withdrawn or if the payout has not been set.
     */
    function withdrawPayOuts() external payable {
        if (s_investor[msg.sender].paidOut == true) {
            revert CrowdfundingProject__AlreadyWithdrawed();
        }
        uint256 amountToPayOut = s_investor[msg.sender].amountToPayOut;
        if (amountToPayOut == 0) {
            revert CrowdfundingProject__PayOutsNotActive();
        }
        s_investor[msg.sender].paidOut = true;

        (bool success, ) = payable(msg.sender).call{value: amountToPayOut}("");
        require(success, "Withdraw failed");
    }

    /**
     * @dev Called automatically by the `performUpkeep` function. Withdraws the funded amount to the project owner and the remaining balance to the crowdfunding manager contract.
     * @dev Only callable during the INVESTING_ACTIVE state. Only callable internally.
     */
    function withdrawFunds() internal {
        if (s_projectState != ProjectState.INVESTING_ACTIVE) {
            revert CrowdfundingProject__InvestingIsNotActive();
        }
        uint256 fundedAmount = s_currentFundedAmount;
        s_currentFundedAmount = 0;

        (bool success, ) = (i_owner).call{value: fundedAmount}("");
        require(success, "Withdraw to owner failed");

        (bool success2, ) = (s_crowdfundingContractAddress).call{
            value: address(this).balance
        }("");
        require(success2, "Fees withdraw failed");
    }

    /**
     * @dev Owner fund to the project contract in oreder to pay out investors.
     * @dev Only callable during INVESTING_ACTIVE state. Only callable by the crowdfunding manager contract.
     */
    function ownerFund() external payable onlyCrowdfundingContract {
        if (s_projectState != ProjectState.INVESTING_ACTIVE) {
            revert CrowdfundingProject__InvestingIsNotActive();
        }
    }

    /**
     * @dev Finishes the crowdfunding project and sets payouts to investors. The contract must have sufficient balance to cover all investor payouts.
     * @dev Can only be called during the INVESTING_ACTIVE state. Only callable by the Crowdfunding manager contract.
     * @dev After finishing:
     *      - Investors can withdraw their contributions plus interest.
     *      - The project owner can withdraw any remaining balance.
     */
    function finish() external onlyCrowdfundingContract {
        if (s_projectState != ProjectState.INVESTING_ACTIVE) {
            revert CrowdfundingProject__InvestingIsNotActive();
        }

        s_projectState = ProjectState.FINISHED;
        setPayOuts();
    }

    /**
     * @dev Calculates the total payout for an investor (investment amount + interest) when the project is finished.
     * @param _amountInvested The amount invested by the investor.
     * @param _interestRateInPercent The interest rate (in basis points) of the project.
     * @return The total payout amount.
     */
    function calculateInvestedPlusInterest(
        uint256 _amountInvested,
        uint256 _interestRateInPercent
    ) public pure returns (uint256) {
        uint256 interest = (_amountInvested * _interestRateInPercent) / 10000;
        return _amountInvested + interest;
    }

    ///////////////////////////
    // VIEW GETTER FUNCTIONS //
    ///////////////////////////

    // PUBLIC //
    function getInvestedAmountForAllInvestors() public view returns (uint256) {
        address[] memory temporaryInvestorsAddresses = s_investors;
        uint256 amountInvestedAll = 0;

        for (uint256 i = 0; i < temporaryInvestorsAddresses.length; i++) {
            address investorAddress = temporaryInvestorsAddresses[i];
            if (getInvestorPaidOutStatus(investorAddress) == false) {
                amountInvestedAll += s_investor[investorAddress].amountInvested;
            }
        }
        return amountInvestedAll;
    }

    function getInvestedPlusInteresOfAllInvestorsWithoutGasFees()
        public
        view
        returns (uint256)
    {
        address[] memory temporaryInvestorsAddresses = s_investors;
        uint256 amountInvestedPlusInterestAll = 0;

        for (uint256 i = 0; i < temporaryInvestorsAddresses.length; i++) {
            address investorAddress = temporaryInvestorsAddresses[i];
            if (getInvestorPaidOutStatus(investorAddress) == false) {
                amountInvestedPlusInterestAll += s_investor[investorAddress]
                    .amountInvestedPlusInterest;
            }
        }
        return amountInvestedPlusInterestAll;
    }

    function getRemainingFundingAmount() public view returns (uint256) {
        return i_maxCrowdfundingAmount - s_currentFundedAmount;
    }

    function getInvestorPaidOutStatus(
        address _investorAddress
    ) public view returns (bool) {
        return s_investor[_investorAddress].paidOut;
    }

    function getInvestorAddress(uint256 _index) public view returns (address) {
        return s_investors[_index];
    }

    // EXTERNAL //
    function getProjectName() external view returns (string memory) {
        return s_projectName;
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }

    function getCrowdfundingAmount() external view returns (uint256) {
        return i_maxCrowdfundingAmount;
    }

    function getCurrentFundedAmount() external view returns (uint256) {
        return s_currentFundedAmount;
    }

    function getProjectInterestRate() external view returns (uint256) {
        return i_interestRate;
    }

    function getProjectMinInvestment() external view returns (uint256) {
        return i_minInvestment;
    }

    function getProjectMaxInvestment() external view returns (uint256) {
        return i_maxInvestment;
    }

    function getProjectDeadlineInDays() external view returns (uint256) {
        return i_deadlineInDays;
    }

    function getProjectInvestmentPeriod() external view returns (uint256) {
        return i_investmentPeriod;
    }

    function getProjectStatus() external view returns (ProjectState) {
        return s_projectState;
    }

    function getProjectStartTimestamp() external view returns (uint256) {
        return s_projectFundingIntervalStart;
    }

    function getInvestorsCount() external view returns (uint256) {
        return s_investors.length;
    }

    function getInvestorInvestmentAmount(
        address _investorAddress
    ) external view returns (uint256) {
        return s_investor[_investorAddress].amountInvested;
    }

    function getInvestedPlusInterest(
        address _investorAddress
    ) external view returns (uint256) {
        return s_investor[_investorAddress].amountInvestedPlusInterest;
    }

    function getAmountToBePaidOut(
        address _investorAddress
    ) external view returns (uint256) {
        return s_investor[_investorAddress].amountToPayOut;
    }

    function getCrowdfundingContractAddress() external view returns (address) {
        return s_crowdfundingContractAddress;
    }

    //////////////////////
    // FALLBACK RECEIVE //
    //////////////////////
    /**
     * @dev Fallback function to handle incoming ETH transfers. Reverts to prevent accidental ETH transfers.
     */
    fallback() external payable {
        revert("Direct ETH transfers not allowed");
    }

    /**
     * @dev Receive function to handle incoming ETH transfers. Reverts to prevent accidental ETH transfers.
     */
    receive() external payable {
        revert("Direct ETH transfers not allowed");
    }
}
