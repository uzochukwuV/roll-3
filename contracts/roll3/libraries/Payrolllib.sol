// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

/// @title PayrollLibrary - A reusable library for payroll calculations and job management
library PayrollLibrary {
    struct Job {
        uint256 id;
        address employer;
        bytes jobDescription;
        address freelancer;
        address token;
        uint256 depositAmount;
        uint256 amountPerMileStone;
        uint256 numOfMileStone;
        uint256 currentMileStone;
        uint256 amountReleased;
        // case should we do it by mile stone or by timeframe
        uint256 remainingBalance;
        uint256 lastUpdate;
        bool isActive;
        bool staked;
    }

    


    
    /// @notice Calculates the amount owed to a freelancer based on milestones completed
    /// @param job Job struct
    /// @return amountOwed The amount owed to the freelancer
    function calculateOwed(Job storage job) internal view returns (uint256) {
        // require(job.active, "Job is not active");
        require(job.currentMileStone > 1, "No milestones completed");
        return (job.depositAmount * job.currentMileStone) / job.numOfMileStone;
    }
    
    /// @notice Updates job last paid timestamp and milestone completion
    /// @param job Job struct
    function updateLastPaid(Job storage job) internal {
        job.lastUpdate = block.timestamp;
        job.currentMileStone++;
    }
}