// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.18;

/**
 * @title
 * @author
 * @notice
 */

import {CrowdfundingProject} from "./CrowdfundingProject.sol";

contract Crowdfunding {
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

    error CrowdfundingProject__DeadlineIsTooShort(uint256);
    error Crowdfunding__YouAreNotAllowedToCancelThisProject();
    error Crowdfunding__YouHaveToSendTheExactAmountForInitialFees(uint256);
    error Crowdfunding__CanBeCalledOnlyByOwner();
    error Crowdfunding__CanBeCalledOnlyByProjectOwner();
    error Crowdfunding__NotEnoughEthInTheProjectContract();
    error Crowdfunding__ValueSentCantBeZero();

    CrowdfundingProject[] private s_crowdfundingProjectArray;

    uint256 private immutable i_crowfundFeeInPercent;
    uint256 private immutable i_minDeadlineInDays;
    address private immutable i_owner;

    /**
     * @param _crowdfundFeeInPrecent fee in % which is taken by the contract if the project is successful; has to be paid by the project owner at project creation; has to be set in wei so it can be for example 0,05%
     * @param _minDeadlineInDays minimum deadline which can be set by the project owner at project creation
     */
    constructor(uint256 _crowdfundFeeInPrecent, uint256 _minDeadlineInDays) {
        i_crowfundFeeInPercent = _crowdfundFeeInPrecent;
        i_minDeadlineInDays = _minDeadlineInDays;
        i_owner = payable(msg.sender);
    }

    /**
     * @dev lets the crowdfunding project owner to create a new project (new contract); project owner has to pay the initial fee which is % from the crowdfunded amount. If projects funding will be successful, fees will be sent back to this contract; if the project will be canceled, the initial fees will be returned to project owner (minus gas fees)
     * @param _crowdfundedAmount the amount the project owner wants to crowdfund
     * @param _interestRateInPercent interest rates which should be paid to investors after vesting time
     * @param _minInvestment minimum investment which can be invested by investors
     * @param _maxInvestment maximum investment which can be invested by investors
     * @param _deadlineInDays for how long the project should be active. When the deadline is reached and:
     * 1. crowdfunding amount is reached, project will be set to INVESTING_ACITVE status and the project owner can withdraw the crowdfunded amount
     * 2. crowdfunding amount is not reached, project will be set to CANCELLED status and the investors will be paid back the invested amount
     * @param _investmentPeriodDays for how long the crowdfunded amount will be invested. After this time, investors have to be paid out the invested amount + interest
     */
    function createProject(
        string memory _projectName,
        uint256 _crowdfundedAmount,
        uint256 _interestRateInPercent,
        uint256 _minInvestment,
        uint256 _maxInvestment,
        uint256 _deadlineInDays,
        uint256 _investmentPeriodDays
    ) external payable returns (CrowdfundingProject) {
        uint256 initialFees = calculateInitialFee(_crowdfundedAmount);
        // q should there be a chek for min. msg.value, so if the project is canceled the investors pay back doesnt fail
        if (msg.value != initialFees) {
            revert Crowdfunding__YouHaveToSendTheExactAmountForInitialFees(
                initialFees
            );
        }
        // should add a check for the project name
        if (_deadlineInDays < i_minDeadlineInDays) {
            revert CrowdfundingProject__DeadlineIsTooShort(i_minDeadlineInDays);
        }
        // q does this array need a project name?
        // q should we check for the minDeadline here?
        CrowdfundingProject crowdfundingProject = new CrowdfundingProject{
            value: msg.value
        }(
            _projectName,
            payable(msg.sender),
            _crowdfundedAmount,
            _interestRateInPercent,
            _minInvestment,
            _maxInvestment,
            _deadlineInDays,
            _investmentPeriodDays,
            // i_minDeadlineInDays,
            payable(address(this))
        );
        // q should we use mapping instead of array?
        s_crowdfundingProjectArray.push(crowdfundingProject);
        emit ProjectCreated(
            msg.sender,
            crowdfundingProject,
            s_crowdfundingProjectArray.length - 1
        );
        return crowdfundingProject;
    }

    // lets the investor to fund the project, the investment cant be less than the minInvestment and more than the maxInvestment
    function fundProject(uint256 _projectId) external payable {
        s_crowdfundingProjectArray[_projectId].fund{value: msg.value}(
            msg.sender
        );
        emit ProjectFunded(msg.sender, _projectId, msg.value);
    }

    // lets the project owner to cancel the project; investors will get their investment back and the project owner will get the back the = initial fees - gas fees
    function cancelProject(uint256 _projectId) external {
        address owner = s_crowdfundingProjectArray[_projectId].getOwner();
        if (msg.sender != owner) {
            revert Crowdfunding__YouAreNotAllowedToCancelThisProject();
        }
        s_crowdfundingProjectArray[_projectId].cancel();
    }

    // lets the project owner to fund the project contract to be able to pay out the investors (cant forget the gas fees to sent eth to investors), the rest eth will be sent back with the same transaction
    function ownerFundProject(uint256 _projectId) external payable {
        if (msg.sender != s_crowdfundingProjectArray[_projectId].getOwner()) {
            revert Crowdfunding__CanBeCalledOnlyByProjectOwner();
        }
        if (msg.value == 0) {
            revert Crowdfunding__ValueSentCantBeZero();
        }
        s_crowdfundingProjectArray[_projectId].ownerFund{value: msg.value}();
    }

    // ??? add a function to pay out a single investor ??? just in case the finish function doest work properly

    // lets the project owner to finish the project and pay out the investors; project owner has to first fund the project with the ownerFundProject function
    function finishProject(uint256 _projectId) external {
        if (msg.sender != s_crowdfundingProjectArray[_projectId].getOwner()) {
            revert Crowdfunding__CanBeCalledOnlyByProjectOwner();
        }
        if (
            getFullAmountToBePaidOutToInvestorsWithoutGasFees(_projectId) >=
            address(s_crowdfundingProjectArray[_projectId]).balance
        ) {
            revert Crowdfunding__NotEnoughEthInTheProjectContract();
        }
        s_crowdfundingProjectArray[_projectId].finish();
    }

    // lets the crowdfunding owner to withdraw the fees paid by project owner
    function withdrawFees() external {
        if (msg.sender != i_owner) {
            revert Crowdfunding__CanBeCalledOnlyByOwner();
        }
        (bool success, ) = (i_owner).call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    // calculates the initial fees paid by project owner
    // 1500000000000000000000 (1500 ETH) * 50000000000000000 (0.05%) / 1e18 = 75000000000000000000
    // 75000000000000000000 / 100
    // 750000000000000000 (0,75 ETH) which is 0,05% from 1500 ETH
    function calculateInitialFee(
        uint256 _maxCrowdfundingAmount
    ) public view returns (uint256) {
        uint256 initialFees = ((_maxCrowdfundingAmount *
            i_crowfundFeeInPercent) / 1e18) / 100;
        return initialFees;
    }

    //////////////////////
    // Getter Functions //
    //////////////////////

    function getProjectAddress(
        uint256 _projectId
    ) public view returns (CrowdfundingProject) {
        return s_crowdfundingProjectArray[_projectId];
    }

    function getInitialFees(
        uint256 _maxCrowdfundingAmount
    ) public view returns (uint256) {
        return calculateInitialFee(_maxCrowdfundingAmount);
    }

    function getCrowdfundingFeeInPercent() public view returns (uint256) {
        return i_crowfundFeeInPercent;
    }

    function getMinDeadlineInDays() public view returns (uint256) {
        return i_minDeadlineInDays;
    }

    function getProjectsCount() public view returns (uint256) {
        return s_crowdfundingProjectArray.length;
    }

    function getProjectStatus(
        uint256 _projectId
    ) public view returns (CrowdfundingProject.ProjectState) {
        return s_crowdfundingProjectArray[_projectId].getProjectStatus();
    }

    function getProjectAmountFunded(
        uint256 _projectId
    ) public view returns (uint256) {
        return s_crowdfundingProjectArray[_projectId].getProjectFundedAmount();
    }

    function getFullAmountToBePaidOutToInvestorsWithoutGasFees(
        uint256 _projectId
    ) public view returns (uint256) {
        return
            s_crowdfundingProjectArray[_projectId]
                .calculateFullAmountToBePaidOutToInvestorsWithoutGasFees();
    }

    fallback() external {}

    receive() external payable {}
}
