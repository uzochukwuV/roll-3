// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Uncomment this line to use console.log
// import "hardhat/console.sol";


// will contain all functions in payroll contract
interface IPayrollStaking {
    function deposit(uint256 amount, address _depositToken) external payable;
    function withdraw(uint256 amount, address _depositToken) external;
    function getStake(address _user) external view returns (uint256);
}