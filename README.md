# Crowdfunding Smart Contracts

**This repository contains Solidity smart contracts for a decentralized crowdfunding platform. The platform allows project owners to create crowdfunding campaigns, investors to fund projects, and automated payouts based on project success or failure.**

## Table of Contents

[Overview](#overview)

[Contracts](#contracts)

- [Crowdfunding](#crowdfunding)

- [CrowdfundingProject](#crowdfundingproject)

[Features](#features)

[Setup](#setup)

[Testing](#testing)

[Deployment](#deployment)

[Interacting with the Contracts](#interacting-with-the-contracts)

[Security Considerations](#security-considerations)

[License](#license)

## Overview

The Crowdfunding platform consists of two main contracts:

-    **Crowdfunding:** The manager contract that handles project creation and manages the overall crowdfunding process.

-    **CrowdfundingProject:** A child contract created for each project. It handles funding, payouts, and state transitions.

The platform uses Chainlink Automation to check if a project's funding goal is met after the deadline. Based on the outcome, the project transitions to either the CLOSED or INVESTING_ACTIVE state.

## Contracts

### Crowdfunding

The main manager contract that allows project owners to create crowdfunding projects. It also handles fee collection and project management.
Key Functions:

-    **createProject:** Creates a new crowdfunding project.

-    **fundProject:** Allows investors to fund a project.

-    **cancelProject:** Allows the project owner to cancel a project.

-    **finishProject:** Allows the project owner to finish a project and distribute payouts.

-    **withdrawFees:** Allows the contract owner to withdraw collected fees.

### CrowdfundingProject

A child contract created for each crowdfunding project. It handles funding, payouts, and state transitions.
Key Functions:

-    **fund:** Allows investors to fund the project.

-    **cancel:** Cancels the project and sets payouts.

-    **finish:** Finishes the project and sets payouts.

-    **withdrawPayOuts:** Allows investors and the project owner to withdraw their payouts.

States of the Crowdfunding project:

- **FUNDING_ACTIVE**: The project is accepting funds.

- **CLOSED**: The project failed to meet its funding goal.

- **INVESTING_ACTIVE**: The project met its funding goal and is in the investment phase.

- **FINISHED**: The project is completed, and payouts are distributed.

- **CANCELED**: The project was canceled by the owner.


## Features

Decentralized Crowdfunding: Project owners can create campaigns, and investors can fund them directly on the blockchain.

Automated State Transitions: Chainlink Automation checks if the funding goal is met after the deadline and transitions the project to the appropriate state.

Flexible Funding: Investors can fund projects within specified minimum and maximum investment limits.

Payouts: Investors can withdraw their funds if the project fails or their investment plus interest if the project succeeds.

Fee Collection: The platform collects a fee from successful projects.

## Setup

### Prerequisites

    Foundry (for testing and deployment).

    Node.js (optional, for additional tooling).

### Installation

Clone the repository:

```shell
$ git clone https://github.com/MariossoKN/Foundry-Crowdfunding.git
$ cd crowdfunding
```

Install Foundry:

```shell
$ curl -L https://foundry.paradigm.xyz | bash
$ foundryup
```

Install dependencies:

```shell
$ forge install
```

## Testing

The project includes comprehensive tests written in Solidity using Foundry. To run the tests:

```shell
$ forge test
```

### Test Coverage

To generate a test coverage report:

```shell
$ forge coverage
```

## Deployment

Before deploying the Crowdfunding Contract update the constructor parameters in the deployment script `(script/HelperConfig.s.sol)`. Example:

```
uint256 crowdfundFeeInPrecent = 500; // 0.05% in wei
uint256 minDeadlineInDays = 7;
```

Run the deployment script:

```shell
$ forge script script/DeployCrowdfunding.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast
```

To deploy a CrowdfundingProject use the `createProject` function in the Crowdfunding contract to deploy a new CrowdfundingProject.

## Interacting with the Contracts

### Creating a Project

Call the `createProject` function on the Crowdfunding contract:

```
crowdfunding.createProject{value: initialFee}(
    "Project Name",
    100 ether, // Funding goal
    1000, // Interest rate (10%)
    1 ether, // Minimum investment
    10 ether, // Maximum investment
    30, // Deadline in days
    365 // Investment period in days
);
```

### Funding a Project

Call the `fundProject` function on the Crowdfunding contract:

```
crowdfunding.fundProject{value: 1 ether}(projectId);
```

### Canceling a Project

Call the `cancelProject` function on the Crowdfunding contract:

```
crowdfunding.cancelProject(projectId);
```

### Owner funding a Project

Call the `ownerFundProject` function on the Crowdfunding contract:

```
crowdfunding.ownerFundProject{value: fundAmount}(projectId);
```

### Finishing a Project

Call the `finishProject` function on the Crowdfunding contract:

```
crowdfunding.finishProject(projectId);
```

### *Withdrawing Payouts

Call the `withdrawPayOuts` function on the CrowdfundingProject contract:

```
crowdfundingProject.withdrawPayOuts();
```

## Security Considerations
> [!CAUTION]
> Trust Assumption: After a project is successfully funded, the full funded amount is sent to the project owner. There is no mechanism to enforce repayment to investors. Investors should only fund projects from known and trusted addresses.

Reentrancy: The contracts include checks to prevent reentrancy attacks.

Testing: The contracts have been thoroughly tested, but users should conduct their own audits before deploying to production.

## License

This project is licensed under the MIT License. See the LICENSE file for details.

## Acknowledgments

Foundry for the testing framework.

Chainlink for providing automation services.

Feel free to customize this README.md to better suit your project's needs. Let me know if you need further assistance!