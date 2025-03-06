// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AutomationBase, AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

contract CrowdfundingProject is AutomationCompatibleInterface, AutomationBase {
    error CrowdfundingProject__NotEnoughEthSent();
    error CrowdfundingProject__TooMuchEthSent();
    error CrowdfundingProject__MinInvestmentGreaterOrEqualToMaxInvestment();
    error CrowdfundingProject__AmountCrowfundedCantBeLessThanMaxInvestment();
    error CrowdfundingProject__AmountEthSentIsGreaterThanTheRestCrowfundingNeeded(
        uint256
    );
    error CrowdfundingProject__FundingIsNotActive();
    error CrowdfundingProject__InvestingIsNotActive();
    error CrowdfundingProject__CanOnlyBeCalledByTheCrowdfundingContract();
    error CrowdfundingProject__ContractHasLessEthThenNeededToPayOutAllInvestors(
        uint256
    );
    error CrowdfundingProject__UpkeepNotNeeded();
    error CrowdfundingProject__AlreadyWithdrawed();
    error CrowdfundingProject__ProjectAlreadyCanceled();
    error CrowdfundingProject__ProjectAlreadyFinished();

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
        uint256 amountInvested;
        uint256 amountInvestedPlusInterest;
        uint256 amountToPayOut;
        bool paidOut;
    }

    mapping(address investorAddress => Investor investor) private s_investor;
    address[] s_investors;

    // creates the project with information given by project owner
    constructor(
        string memory _projectName,
        address payable _projectOwner,
        uint256 _maxCrowfundingAmount,
        uint256 _interestRateInPercent,
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
        s_projectName = _projectName;
        i_owner = _projectOwner;
        i_maxCrowdfundingAmount = _maxCrowfundingAmount;
        s_currentFundedAmount = 0;
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
            i_interestRateInPercent
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
        // maybe add a check for a project state? can this be called again after this was automaticly called by chainlink?
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

    // pays back the investors and cancels the project
    function cancel() external onlyCrowdfundingContract {
        if (s_projectState != ProjectState.FUNDING_ACTIVE) {
            revert CrowdfundingProject__FundingIsNotActive();
        }
        if (s_projectState == ProjectState.CANCELED) {
            revert CrowdfundingProject__ProjectAlreadyCanceled();
        }
        s_projectState = ProjectState.CANCELED;
        setPayOuts();
    }

    function setPayOuts() internal {
        address[] memory temporaryInvestorsAddresses = s_investors;

        if (
            s_projectState == ProjectState.CLOSED ||
            s_projectState == ProjectState.CANCELED
        ) {
            for (uint256 i = 0; i < temporaryInvestorsAddresses.length; i++) {
                address investorAddress = temporaryInvestorsAddresses[i];
                if (s_investor[investorAddress].paidOut == false) {
                    s_investor[investorAddress].amountToPayOut += s_investor[
                        investorAddress
                    ].amountInvested;
                }
            }
        } else if (s_projectState == ProjectState.FINISHED) {
            for (uint256 i = 0; i < temporaryInvestorsAddresses.length; i++) {
                address investorAddress = temporaryInvestorsAddresses[i];
                if (s_investor[investorAddress].paidOut == false) {
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

    // lets the investors and owner withdraw if the project was CANCELED, CLOSED or FINISHED
    function withdrawPayOuts() external payable {
        if (s_investor[msg.sender].paidOut == true) {
            revert CrowdfundingProject__AlreadyWithdrawed();
        }
        uint256 amountToPayOut = s_investor[msg.sender].amountToPayOut;

        s_investor[msg.sender].paidOut == true;

        (bool success, ) = payable(msg.sender).call{value: amountToPayOut}("");
        require(success, "Withdraw failed");
    }

    // CALLED BY UPKEEP. withdraws the crowdfunded amount to project owner and sends the initial fees to crowdfunding contract
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

    function ownerFund() external payable onlyCrowdfundingContract {
        if (s_projectState != ProjectState.INVESTING_ACTIVE) {
            revert CrowdfundingProject__InvestingIsNotActive();
        }
    }

    // finishes the project; pays out the investors and send back the rest eth left in the contract to project owner
    function finish() external onlyCrowdfundingContract {
        if (s_projectState != ProjectState.INVESTING_ACTIVE) {
            revert CrowdfundingProject__InvestingIsNotActive();
        }
        if (s_projectState == ProjectState.FINISHED) {
            revert CrowdfundingProject__ProjectAlreadyFinished();
        }

        s_projectState = ProjectState.FINISHED;
        setPayOuts();
    }

    // calculates how much the investor should get (based on the investment amount and interest rate) if the project is fully funded
    function calculateInvestedPlusInterest(
        uint256 _amountInvested,
        uint256 _interestRateInPercent
    ) public pure returns (uint256) {
        return
            _amountInvested +
            ((_amountInvested * _interestRateInPercent) / 100);
    }

    ///////////////////////////
    // VIEW GETTER FUNCTIONS //
    ///////////////////////////
    function getInvestedAmountForAllInvestors() public view returns (uint256) {
        address[] memory temporaryInvestorsAddresses = s_investors;
        uint256 amountInvestedAll = 0;

        for (uint256 i = 0; i < temporaryInvestorsAddresses.length; i++) {
            address investorsAddress = temporaryInvestorsAddresses[i];
            if (s_investor[investorsAddress].paidOut == false) {
                amountInvestedAll += s_investor[investorsAddress]
                    .amountInvested;
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
            address investorsAddress = temporaryInvestorsAddresses[i];
            if (s_investor[investorsAddress].paidOut == false) {
                amountInvestedPlusInterestAll += s_investor[investorsAddress]
                    .amountInvestedPlusInterest;
            }
        }
        return amountInvestedPlusInterestAll;
    }

    function getRemainingFundingAmount() public view returns (uint256) {
        return i_maxCrowdfundingAmount - s_currentFundedAmount;
    }

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

    function getInvestorPaidOutStatus(
        address _investorAddress
    ) external view returns (bool) {
        return s_investor[_investorAddress].paidOut;
    }

    function getCrowdfundingContractAddress() external view returns (address) {
        return s_crowdfundingContractAddress;
    }
}
