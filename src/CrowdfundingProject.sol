// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.18;

import {AutomationBase, AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

contract CrowdfundingProject is AutomationCompatibleInterface, AutomationBase {
    error CrowdfundingProject__NotEnoughEthSent();
    error CrowdfundingProject__TooMuchEthSent();
    error CrowdfundingProject__MinInvestmentGreaterThanMaxInvestment();
    error CrowdfundingProject__DeadlineIsTooShort(uint256);
    error CrowdfundingProject__AmountCrowfundedCantBeLessThanMaxInvestment();
    error CrowdfundingProject__AmountEthSentIsGreaterThanTheRestCrowfundingNeeded(
        uint256
    );
    error CrowdfundingProject__FundingIsNotActive();
    error CrowdfundingProject__CanOnlyBeCalledByTheCrowdfundingContract();
    error CrowdfundingProject__ContractHasLessEthThenNeededToPayOutAllInvestors(
        uint256
    );
    error CrowdfundingProject__ProjectHasTobeInInvestmentActiveState();
    error CrowdfundingProject__CantWithdrawUntilMaxFundAmountIsReached();
    error CrowdfundingProject__InvestingIsNotActive();
    error CrowdfundingProject__InvestorsCantBePaidBackIfTheProjectIsActive();
    error CrowdfundingProject__UpkeepNotNeeded();

    modifier onlyCrowdfundingContract() {
        if (msg.sender != s_crowdfundingContractAddress) {
            revert CrowdfundingProject__CanOnlyBeCalledByTheCrowdfundingContract();
        }
        _;
    }

    address payable private s_crowdfundingContractAddress;

    address payable private immutable i_owner;
    uint256 private immutable i_crowdfundingAmountNeeded;
    uint256 private s_fundedAmount;
    uint256 private immutable i_interestRateInPercent;
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
        address payable investor;
        uint256 amountInvested;
        uint256 amountToBePaidOut;
        bool paidOut;
    }

    Investor[] private s_investors;

    // creates the project with information given by project owner
    constructor(
        address payable _projectOwner,
        uint256 _maxCrowfundingAmount,
        uint256 _interestRateInPercent,
        uint256 _minInvestment,
        uint256 _maxInvestment,
        uint256 _deadlineInDays,
        uint256 _investmentPeriod,
        uint256 minDeadlineInDays,
        address payable _crowdfundingContractAddress
    ) payable {
        if (_maxCrowfundingAmount < _maxInvestment) {
            revert CrowdfundingProject__AmountCrowfundedCantBeLessThanMaxInvestment();
        }
        if (_minInvestment > _maxInvestment) {
            revert CrowdfundingProject__MinInvestmentGreaterThanMaxInvestment();
        }
        if (_deadlineInDays < minDeadlineInDays) {
            revert CrowdfundingProject__DeadlineIsTooShort(minDeadlineInDays);
        }
        i_owner = _projectOwner;
        i_crowdfundingAmountNeeded = _maxCrowfundingAmount;
        s_fundedAmount = 0;
        i_interestRateInPercent = _interestRateInPercent;
        i_minInvestment = _minInvestment;
        i_maxInvestment = _maxInvestment;
        i_deadlineInDays = _deadlineInDays;
        i_investmentPeriod = _investmentPeriod;
        s_projectState = ProjectState.FUNDING_ACTIVE;
        s_projectFundingIntervalStart = block.timestamp;
        s_crowdfundingContractAddress = _crowdfundingContractAddress;
    }

    // fund the project
    function fund(address _investor) external payable onlyCrowdfundingContract {
        // do we need to prevent the funder to fund again?
        if (s_projectState != ProjectState.FUNDING_ACTIVE) {
            revert CrowdfundingProject__FundingIsNotActive();
        }
        if (msg.value < i_minInvestment) {
            revert CrowdfundingProject__NotEnoughEthSent();
        }
        if (msg.value > i_maxInvestment) {
            revert CrowdfundingProject__TooMuchEthSent();
        }
        uint256 restFundingNeeded = i_crowdfundingAmountNeeded - s_fundedAmount;
        if (msg.value > restFundingNeeded) {
            revert CrowdfundingProject__AmountEthSentIsGreaterThanTheRestCrowfundingNeeded(
                restFundingNeeded
            );
        }
        uint256 amountToBePaid = calculateAmountToBePaidToInvestor(
            msg.value,
            i_interestRateInPercent
        );
        s_investors.push() = Investor(
            payable(_investor),
            msg.value,
            amountToBePaid,
            false
        );
        s_fundedAmount += msg.value;
    }

    // calculates how much the investor should get (based on the investment amount and interest rate) if the project is fully funded
    function calculateAmountToBePaidToInvestor(
        uint256 _amountInvested,
        uint256 _interestRateInPercent
    ) public pure returns (uint256) {
        return
            _amountInvested +
            ((_amountInvested * _interestRateInPercent) / 100);
    }

    // Chainlink automation to check if the project is fully funded after the time interval
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

    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert CrowdfundingProject__UpkeepNotNeeded();
        }
        if (
            (block.timestamp - s_projectFundingIntervalStart) >
            (i_deadlineInDays * ONE_DAY_IN_SECONDS)
        ) {
            if (s_fundedAmount < i_crowdfundingAmountNeeded) {
                s_projectState = ProjectState.CLOSED;
                payBackInvestorsAndOwner();
            } else {
                s_projectInvestmentIntervalStart = block.timestamp;
                s_projectState = ProjectState.INVESTING_ACTIVE;
                withdrawFunds();
            }
        }
    }

    // pays back the investors and cancels the project
    function cancel() external onlyCrowdfundingContract {
        s_projectState = ProjectState.CANCELED;
        payBackInvestorsAndOwner();
    }

    // pays back the investors and project owner; resets the investors array
    function payBackInvestorsAndOwner() internal {
        if (s_projectState == ProjectState.INVESTING_ACTIVE) {
            revert CrowdfundingProject__InvestorsCantBePaidBackIfTheProjectIsActive();
        }
        Investor[] memory temporaryInvestors = s_investors;
        // delete state variable due to possible Reentrancy attack
        delete s_investors;
        for (uint256 i = 0; i < temporaryInvestors.length; i++) {
            uint256 amountInvested = temporaryInvestors[i].amountInvested;
            (bool success, ) = (temporaryInvestors[i].investor).call{
                value: amountInvested
            }("");
            require(success, "Investors pay back failed");
        }
        // pay back the rest of initial fees to the owner
        (bool success2, ) = (i_owner).call{value: address(this).balance}("");
        require(success2, "Owner pay back failed");
    }

    function ownerFund() external payable onlyCrowdfundingContract {
        if (s_projectState != ProjectState.INVESTING_ACTIVE) {
            revert CrowdfundingProject__ProjectHasTobeInInvestmentActiveState();
        }
    }

    // withdraws the crowdfunded amount to project owner and the initial fees to crowdfunding contract
    function withdrawFunds() internal {
        if (s_projectState != ProjectState.INVESTING_ACTIVE) {
            revert CrowdfundingProject__InvestingIsNotActive();
        }
        if (s_fundedAmount < i_crowdfundingAmountNeeded) {
            revert CrowdfundingProject__CantWithdrawUntilMaxFundAmountIsReached();
        }
        uint256 fundedAmount = s_fundedAmount;
        s_fundedAmount = 0;
        (bool success, ) = (i_owner).call{value: fundedAmount}("");
        require(success, "Withdraw to owner failed");
        (bool success2, ) = (s_crowdfundingContractAddress).call{
            value: address(this).balance
        }("");
        require(success2, "Fees withdraw failed");
    }

    // finishes the project; pays out the investors and send back the rest eth left in the contract to project owner
    function finish() external onlyCrowdfundingContract {
        if (s_projectState != ProjectState.INVESTING_ACTIVE) {
            revert CrowdfundingProject__ProjectHasTobeInInvestmentActiveState();
        }
        s_projectState = ProjectState.FINISHED;
        Investor[] memory temporaryInvestors = s_investors;
        for (uint256 i = 0; i < temporaryInvestors.length; i++) {
            if (temporaryInvestors[i].paidOut == false) {
                uint256 amountToPayOut = temporaryInvestors[i]
                    .amountToBePaidOut;
                s_investors[i].paidOut = true;
                s_investors[i].amountToBePaidOut = 0;
                (bool success, ) = (temporaryInvestors[i].investor).call{
                    value: amountToPayOut
                }("");
                require(success, "Investor pay failed");
            }
        }
        (bool success2, ) = (i_owner).call{value: address(this).balance}("");
        require(success2, "Owner withdraw failed");
    }

    function calculateFullAmountToBePaidOutToInvestorsWithoutGasFees()
        public
        view
        returns (uint256)
    {
        uint256 fullAmountToBePaid = 0;
        Investor[] memory temporaryInvestors = s_investors;
        for (uint256 i = 0; i < temporaryInvestors.length; i++) {
            if (temporaryInvestors[i].paidOut == false) {
                fullAmountToBePaid += temporaryInvestors[i].amountToBePaidOut;
            }
        }
        return fullAmountToBePaid;
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }

    function getProjectMaxCrowdfundingAmount() external view returns (uint256) {
        return i_crowdfundingAmountNeeded;
    }

    function getProjectFundedAmount() external view returns (uint256) {
        return s_fundedAmount;
    }

    function getProjectInterestRateInPercent() external view returns (uint256) {
        return i_interestRateInPercent;
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

    function getInvestorAddress(
        uint256 _index
    ) external view returns (address) {
        return s_investors[_index].investor;
    }

    function getInvestorsInvestmentAmount(
        uint256 _index
    ) external view returns (uint256) {
        return s_investors[_index].amountInvested;
    }

    function getInvestorsAmountToBePaidOut(
        uint256 _index
    ) external view returns (uint256) {
        return s_investors[_index].amountToBePaidOut;
    }

    function getInvestorsPaidOutStatus(
        uint256 _index
    ) external view returns (bool) {
        return s_investors[_index].paidOut;
    }

    function getCrowdfundingContractAddress() external view returns (address) {
        return s_crowdfundingContractAddress;
    }

    // function getAmountToBePaidOutToInvestor(uint256 _index) external view returns (uint256) {
    //     return s_investors[_index].amountToBePaidOut;
    // }
}
