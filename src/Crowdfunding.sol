// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * @title Crowdfunding
 * @author Mariosso
 * @notice This contract facilitates crowdfunding campaigns where project owners can raise funds and repay investors with interest. It acts as a manager crowdfunding projects.
 * @dev The contract involves three main roles:
 * 1. CROWDFUNDING CONTRACT OWNER:
 *    - Sets the crowdfunding fee and minimum funding deadline during contract creation.
 *    - Can withdraw fees collected from successful projects.
 * 2. PROJECT OWNER:
 *    - Creates and manages crowdfunding projects.
 *    - Defines the funding goal, interest rate, and deadlines during project creation.
 *    - Can cancel or finish projects, and fund the project contract to repay investors.
 *    - After the funding deadline, Chainlink Automation determines if the funding goal was met:
 *      a) If the goal is met, the funds are sent to the project owner, and the crowdfunding fee is sent to the manager contract.
 *      b) If the goal is not met, investors can withdraw their investments.
 * 3. INVESTORS:
 *    - Fund projects within the specified investment limits.
 *    - Can withdraw:
 *      - their investments if the project is canceled/closed;
 *      - their investment plus interest after the project is completed.
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

    event ProjectCanceled(
        address indexed _owner,
        uint256 indexed _projectIndex
    );

    event ProjectFundedOwner(
        address indexed _owner,
        uint256 indexed _projectIndex
    );

    modifier onlyProjectOwner(uint256 _projectId) {
        address owner = s_crowdfundingProjectArray[_projectId].owner;
        if (msg.sender != owner) {
            revert Crowdfunding__CanBeCalledOnlyByProjectOwner();
        }
        _;
    }

    struct Project {
        CrowdfundingProject projectContract;
        string name;
        uint256 crowdfundedAmount;
        uint256 interestRate;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint256 deadlineInDays;
        uint256 investmentPeriodDays;
        address owner;
    }

    error Crowdfunding__DeadlineIsTooShort(uint256);
    error Crowdfunding__YouAreNotAllowedToCancelThisProject();
    error Crowdfunding__YouHaveToSendTheExactAmountForInitialFees(uint256);
    error Crowdfunding__CanBeCalledOnlyByOwner();
    error Crowdfunding__CanBeCalledOnlyByProjectOwner();
    error Crowdfunding__NotEnoughEthInTheProjectContract();
    error Crowdfunding__ValueSentCantBeZero();
    error Crowdfunding__NameCantBeEmpty();

    Project[] private s_crowdfundingProjectArray;

    uint256 private immutable i_crowfundFeeInPercent;
    uint256 private immutable i_minDeadlineInDays;
    address private immutable i_owner;

    /**
     * @dev Initializes the crowdfunding contract with the crowdfunding fee and minimum deadline.
     * @param _crowdfundFeeInPercent The crowdfunding fee is a percentage of the total funding goal.
     *        Expressed in wei (e.g., 10000000000000000 = 1%, 1000000000000000 = 0.1%).
     * @param _minDeadlineInDays The minimum deadline (in days) that project owners must set for their projects.
     */
    constructor(uint256 _crowdfundFeeInPercent, uint256 _minDeadlineInDays) {
        i_crowfundFeeInPercent = _crowdfundFeeInPercent;
        i_minDeadlineInDays = _minDeadlineInDays;
        i_owner = payable(msg.sender);
    }

    /**
     * @dev Allows a project owner to create a new crowdfunding project. The project owner must pay an initial fee, which is a percentage of the funding goal.
     * If the project is successful, the fee is sent to the crowdfunding contract. If the project fails, the fee can be withdrawn by the project owner.
     * @param _projectName The name of the project.
     * @param _crowdfundedAmount The total amount the project owner aims to raise.
     * @param _interestRate The interest rate (in basis points) to be paid to investors. (e.g., 10000 = 1%, 1000 = 10%).
     * @param _minInvestment The minimum amount an investor can contribute.
     * @param _maxInvestment The maximum amount an investor can contribute.
     * @param _deadlineInDays The duration (in days) for which the project will be active. After this period:
     *   - If the funding goal is met, the project transitions to INVESTING_ACTIVE, and the funds are sent to the project owner.
     *   - If the funding goal is not met, the project is CLOSED, and investors can withdraw their contributions.
     * @param _investmentPeriodDays The duration (in days) for which the raised funds will be invested. After this period, investors must be repaid their investment plus interest.
     * @return The address of the newly created CrowdfundingProject contract.
     */
    function createProject(
        string memory _projectName,
        uint256 _crowdfundedAmount,
        uint256 _interestRate,
        uint256 _minInvestment,
        uint256 _maxInvestment,
        uint256 _deadlineInDays,
        uint256 _investmentPeriodDays
    ) external payable returns (CrowdfundingProject) {
        uint256 initialFees = calculateInitialFee(_crowdfundedAmount);
        if (msg.value != initialFees) {
            revert Crowdfunding__YouHaveToSendTheExactAmountForInitialFees(
                initialFees
            );
        }
        if (bytes(_projectName).length == 0) {
            revert Crowdfunding__NameCantBeEmpty();
        }
        if (_deadlineInDays < i_minDeadlineInDays) {
            revert Crowdfunding__DeadlineIsTooShort(i_minDeadlineInDays);
        }
        CrowdfundingProject crowdfundingProject = new CrowdfundingProject{
            value: msg.value
        }(
            _projectName,
            payable(msg.sender),
            _crowdfundedAmount,
            _interestRate,
            _minInvestment,
            _maxInvestment,
            _deadlineInDays,
            _investmentPeriodDays,
            payable(address(this))
        );
        s_crowdfundingProjectArray.push() = Project(
            crowdfundingProject,
            _projectName,
            _crowdfundedAmount,
            _interestRate,
            _minInvestment,
            _maxInvestment,
            _deadlineInDays,
            _investmentPeriodDays,
            payable(msg.sender)
        );
        emit ProjectCreated(
            msg.sender,
            crowdfundingProject,
            s_crowdfundingProjectArray.length - 1
        );
        return crowdfundingProject;
    }

    /**
     * @dev Allows an investor to fund a project. The investment amount must be:
     * - Greater than or equal to the minimum investment.
     * - Less than or equal to the maximum investment.
     * - Not zero.
     * - Not exceed the remaining funding amount (checkable via `getRemainingFundAmount`).
     * @dev The project must be in the FUNDING_ACTIVE state.
     * @param _projectId The ID of the project to fund.
     */
    function fundProject(uint256 _projectId) external payable {
        if (msg.value == 0) {
            revert Crowdfunding__ValueSentCantBeZero();
        }
        CrowdfundingProject projectContract = s_crowdfundingProjectArray[
            _projectId
        ].projectContract;
        projectContract.fund{value: msg.value}(msg.sender);
        emit ProjectFunded(msg.sender, _projectId, msg.value);
    }

    /**
     * @dev Allows the project owner to cancel a project. After cancellation:
     * - Investors can withdraw their contributions.
     * - The project owner can withdraw the initial fees.
     * @dev Can only be called by the project owner. The project must be in the FUNDING_ACTIVE state.
     * @param _projectId The ID of the project to cancel.
     */
    function cancelProject(
        uint256 _projectId
    ) external onlyProjectOwner(_projectId) {
        CrowdfundingProject projectContract = s_crowdfundingProjectArray[
            _projectId
        ].projectContract;
        projectContract.cancel();
        emit ProjectCanceled(msg.sender, _projectId);
    }

    /**
     * @dev Allows the project owner to fund the project contract, enabling investors to withdraw their investments plus interest.
     * @dev Can only be called by the project owner. The project must be in the INVESTING_ACTIVE state.
     * @param _projectId The ID of the project to fund.
     */
    function ownerFundProject(
        uint256 _projectId
    ) external payable onlyProjectOwner(_projectId) {
        if (msg.value == 0) {
            revert Crowdfunding__ValueSentCantBeZero();
        }
        CrowdfundingProject projectContract = s_crowdfundingProjectArray[
            _projectId
        ].projectContract;
        projectContract.ownerFund{value: msg.value}();
        emit ProjectFundedOwner(msg.sender, _projectId);
    }

    /**
     * @dev Allows the project owner to finish the project. The project must first be funded via `ownerFundProject` with the correct amount.
     * @dev Can only be called by the project owner.
     * @param _projectId The ID of the project to finish.
     */
    function finishProject(
        uint256 _projectId
    ) external onlyProjectOwner(_projectId) {
        CrowdfundingProject projectContract = s_crowdfundingProjectArray[
            _projectId
        ].projectContract;
        if (
            getInvestedPlusInterestToAllInvestorsWithoutGasFees(_projectId) >=
            address(projectContract).balance
        ) {
            revert Crowdfunding__NotEnoughEthInTheProjectContract();
        }
        projectContract.finish();
    }

    /**
     * @dev Allows the crowdfunding contract owner to withdraw fees collected from successful projects.
     * @dev Can only be called by the crowdfunding contract owner.
     */
    function withdrawFees() external {
        if (msg.sender != i_owner) {
            revert Crowdfunding__CanBeCalledOnlyByOwner();
        }
        (bool success, ) = (i_owner).call{value: address(this).balance}("");
        require(success, "Withdraw failed");
    }

    /**
     * @dev Calculates the initial fee that the project owner must pay during project creation.
     * The fee is a percentage of the total funding goal.
     * @param _maxCrowdfundingAmount The total funding goal set by the project owner.
     * @return The initial fee amount in wei.
     */
    function calculateInitialFee(
        uint256 _maxCrowdfundingAmount
    ) public view returns (uint256) {
        uint256 initialFees = ((_maxCrowdfundingAmount *
            i_crowfundFeeInPercent) / 1e18);
        return initialFees;
    }

    ///////////////////////////
    // PUBLIC VIEW FUNCTIONS //
    ///////////////////////////
    function getInvestedPlusInterestToAllInvestorsWithoutGasFees(
        uint256 _projectId
    ) public view returns (uint256) {
        return
            (s_crowdfundingProjectArray[_projectId].projectContract)
                .getInvestedPlusInteresOfAllInvestorsWithoutGasFees();
    }

    /////////////////////////////
    // EXTERNAL VIEW FUNCTIONS //
    /////////////////////////////
    function getProjectName(
        uint256 _projectId
    ) external view returns (string memory) {
        return s_crowdfundingProjectArray[_projectId].name;
    }

    function getCrowdfundingAmount(
        uint256 _projectId
    ) external view returns (uint256) {
        return s_crowdfundingProjectArray[_projectId].crowdfundedAmount;
    }

    function getInterestRate(
        uint256 _projectId
    ) external view returns (uint256) {
        return s_crowdfundingProjectArray[_projectId].interestRate;
    }

    function getMinInvestmentAmount(
        uint256 _projectId
    ) external view returns (uint256) {
        return s_crowdfundingProjectArray[_projectId].minInvestment;
    }

    function getMaxInvestmentAmount(
        uint256 _projectId
    ) external view returns (uint256) {
        return s_crowdfundingProjectArray[_projectId].maxInvestment;
    }

    function getDeadlineInDays(
        uint256 _projectId
    ) external view returns (uint256) {
        return s_crowdfundingProjectArray[_projectId].deadlineInDays;
    }

    function getInvestmentPeriodDays(
        uint256 _projectId
    ) external view returns (uint256) {
        return s_crowdfundingProjectArray[_projectId].investmentPeriodDays;
    }

    function getProjectOwner(
        uint256 _projectId
    ) external view returns (address) {
        return s_crowdfundingProjectArray[_projectId].owner;
    }

    function getProjectIdBasedOnOwnerAddress(
        address _owner
    ) external view returns (uint256[] memory) {
        uint256 arrayLength = s_crowdfundingProjectArray.length;
        uint256[] memory projectIds = new uint256[](arrayLength);
        uint256 count = 0;
        for (uint256 i = 0; i < arrayLength; i++) {
            if (s_crowdfundingProjectArray[i].owner == _owner) {
                projectIds[count] = i;
                count++;
            }
        }
        uint256[] memory result = new uint256[](count);
        for (uint256 j = 0; j < count; j++) {
            result[j] = projectIds[j];
        }
        return result;
    }

    function getInitialFees(
        uint256 _maxCrowdfundingAmount
    ) external view returns (uint256) {
        return calculateInitialFee(_maxCrowdfundingAmount);
    }

    function getCrowdfundingFeeInPercent() external view returns (uint256) {
        return i_crowfundFeeInPercent;
    }

    function getMinDeadlineInDays() external view returns (uint256) {
        return i_minDeadlineInDays;
    }

    function getProjectsCount() external view returns (uint256) {
        return s_crowdfundingProjectArray.length;
    }

    function getCwOwner() external view returns (address) {
        return i_owner;
    }

    //////////////////////
    // FALLBACK RECEIVE //
    //////////////////////
    fallback() external payable {}

    receive() external payable {}
}
