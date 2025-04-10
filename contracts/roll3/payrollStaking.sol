// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import {IPayrollStaking} from "./interfaces/IPayrollStaking.sol";
import {
  IPoolAddressesProvider
} from "https://github.com/aave/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import { IPool } from "https://github.com/aave/aave-v3-core/contracts/interfaces/IPool.sol";
import { IERC20 } from "https://github.com/aave/aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol";


/// @title Payroll Staking
/// @author Aave
contract PayrollStaking is IPayrollStaking {
    IPoolAddressesProvider public immutable  ADDRESSES_PROVIDER;
    IPool public immutable  POOL;
    mapping(address => uint256) public deposits;
    

    constructor(IPoolAddressesProvider provider) {
        ADDRESSES_PROVIDER = provider;
        POOL = IPool(provider.getPool());
    }

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    function deposit(uint256 amount, address _depositToken) external payable  {
        require(amount > 0, "Amount must be greater than 0");
        IERC20 depositToken = IERC20(_depositToken);
        depositToken.transferFrom(msg.sender, address(this), amount);
        depositToken.approve(address(POOL), amount);
        
        POOL.supply(address(depositToken), amount, msg.sender, 0);
        deposits[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount, address _depositToken) external {
        require(amount > 0 && amount <= deposits[msg.sender], "Invalid amount");
        POOL.withdraw(_depositToken, amount, msg.sender);
        deposits[msg.sender] -= amount;
        emit Withdrawn(msg.sender, amount);
    }

    function getStake(address _user) external view returns (uint256){
        return deposits[_user];
    }
}