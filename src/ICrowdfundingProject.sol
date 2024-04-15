// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.18;

interface ICrowdfundingProject {
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

    function fund(address _investor) external payable;

    function calculateAmountToBePaidToInvestor(
        uint256 _investedValue,
        uint256 _interestRateInPercent
    ) external pure returns (uint256);

    function checkUpkeep(
        bytes calldata checkData
    ) external view returns (bool upkeepNeeded, bytes memory performData);

    function performUpkeep(bytes calldata performData) external;

    function cancel() external;

    function ownerFund() external view;

    function finish() external;

    function calculateFullAmountToBePaidOutToInvestorsWithoutGasFees()
        external
        view
        returns (uint256);

    function getOwner() external view returns (address);

    function getProjectMaxCrowdfundingAmount() external view returns (uint256);

    function getProjectFundedAmount() external view returns (uint256);

    function getProjectInterestRateInPercent() external view returns (uint256);

    function getProjectMinInvestment() external view returns (uint256);

    function getProjectMaxInvestment() external view returns (uint256);

    function getProjectDeadlineInDays() external view returns (uint256);

    function getProjectInvestmentPeriod() external view returns (uint256);

    function getProjectStatus() external view returns (ProjectState);

    function getProjectStartTimestamp() external view returns (uint256);

    function getInvestorsCount() external view returns (uint256);

    function getInvestorAddress(uint256 _index) external view returns (address);

    function getInvestorsInvestmentAmount(
        uint256 _index
    ) external view returns (uint256);

    function getInvestorsPaidOutStatus(
        uint256 _index
    ) external view returns (bool);

    function getInvestorsAmountToBePaidOut(
        uint256 _index
    ) external view returns (uint256);

    function getCrowdfundingContractAddress() external view returns (address);
}
