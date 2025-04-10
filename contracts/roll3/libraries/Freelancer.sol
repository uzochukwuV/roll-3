// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

/// @title PayrollLibrary - A reusable library for payroll calculations and job management
library FreelancerLibrary {
    struct Freelancer {
        uint256 id;
        address freelancer;
        string name;
        bytes description;
        uint256 rating;
        uint256 numJobsDone;
        bytes stacks;
        uint256[] achievements;
    }

    
    // /// @notice Calculates the amount owed to a freelancer based on milestones completed
    // /// @param job Job struct
    // /// @return amountOwed The amount owed to the freelancer
    // function calculateOwed(Job storage job) internal view returns (uint256) {
    //     require(job.active, "Job is not active");
    //     require(job.milestonesCompleted > 0, "No milestones completed");
    //     return (job.salary * job.milestonesCompleted) / job.milestoneCount;
    // }
    
    // /// @notice Updates job last paid timestamp and milestone completion
    // /// @param job Job struct
    // function updateLastPaid(Job storage job) internal {
    //     job.lastPaid = block.timestamp;
    //     job.milestonesCompleted++;
    // }
}