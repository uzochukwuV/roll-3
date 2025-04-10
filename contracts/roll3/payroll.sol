// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libraries/PayrollLib.sol";
import "./libraries/Freelancer.sol";
import {IPayrollStaking} from "./interfaces/IPayrollStaking.sol";

contract PayrollImproved is Ownable, ReentrancyGuard {
    mapping(uint256 => PayrollLibrary.Job) public jobs;
    mapping(uint256 => FreelancerLibrary.Freelancer) public freelancers;
    mapping(address => bool) public isFreelancerValid;
    mapping(address => uint256) public freelancerIds;
    uint256 public jobCounter;
    uint256 public freelancerCounter;
    IPayrollStaking public immutable staking;
    IERC20 public immutable bidCoin;

    // Errors
    error InvalidAddress();
    error InvalidAmount();
    error InvalidDuration();
    error InsufficientBalance();
    error JobNotFound();
    error JobDone();
    error Unauthorized();
    error JobNotActive();
    error AlreadyRegistered();
    error JobAlreadyAssigned();
    error MilestoneAlreadyCompleted();
    error InvalidMilestone();
    error NoFundsAvailable();
    error FreelancerNotFound();

    // Bid structure
    struct Bidder {
        address freelancer;
        uint256 amount;
    }

    struct Bid {
        address[] freelancers;
        mapping(address => uint256) freelancerBids;
    }
    mapping(uint256 => Bid) private bids;

    // Events
    event FreelancerCreated(uint256 indexed id, address indexed freelancer, string name);
    event JobPosted(uint256 indexed jobId, address indexed employer, uint256 amount, address token);
    event JobBid(uint256 indexed jobId, address indexed freelancer, uint256 bidAmount);
    event JobAssigned(uint256 indexed jobId, address indexed freelancer);
    event MilestoneCompleted(uint256 indexed jobId, address indexed completedBy, uint256 milestoneNumber);
    event PaymentReceived(uint256 indexed jobId, address indexed freelancer, uint256 amount);
    event PaymentStaked(uint256 indexed jobId, address indexed freelancer, uint256 amount);
    event PaymentUnstaked(uint256 indexed jobId, address indexed freelancer, uint256 amount);

    // Modifiers
    modifier onlyValidAddress(address _address) {
        if (_address == address(0) || _address == address(this)) {
            revert InvalidAddress();
        }
        _;
    }

    modifier onlyValidFreelancer(address _address) {
        if (!isFreelancerValid[_address]) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyJobEmployer(uint256 _jobId) {
        if (jobs[_jobId].employer != msg.sender) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyJobParticipant(uint256 _jobId) {
        PayrollLibrary.Job storage job = jobs[_jobId];
        if (job.employer != msg.sender && job.freelancer != msg.sender) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyValidJob(uint256 _jobId) {
        if (_jobId == 0 || _jobId > jobCounter) {
            revert JobNotFound();
        }
        _;
    }

    modifier onlyActiveJob(uint256 _jobId) {
        if (!jobs[_jobId].isActive) {
            revert JobNotActive();
        }
        _;
    }

    modifier onlyJobFreelancer(uint256 _jobId) {
        if (jobs[_jobId].freelancer != msg.sender) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyValidAmount(uint256 amount) {
        if (amount <= 0) {
            revert InvalidAmount();
        }
        _;
    }

    constructor(address _stakingContract, address _bidCoin) Ownable(msg.sender) {
        if (_stakingContract == address(0) || _bidCoin == address(0)) {
            revert InvalidAddress();
        }
        staking = IPayrollStaking(_stakingContract);
        bidCoin = IERC20(_bidCoin);
    }

    /**
     * @dev Register a new freelancer
     * @param _name Freelancer's name
     * @param _description Freelancer's description
     * @param _achievements Array of achievement IDs
     * @param _stacks Technical skills and stack information
     */
    function registerFreelancer(
        string memory _name,
        bytes memory _description,
        uint256[] memory _achievements,
        bytes calldata _stacks
    ) external onlyValidAddress(msg.sender) {
        if (isFreelancerValid[msg.sender]) {
            revert AlreadyRegistered();
        }
        
        freelancerCounter++;
        freelancers[freelancerCounter] = FreelancerLibrary.Freelancer(
            freelancerCounter,
            msg.sender,
            _name,
            _description,
            0,
            0,
            _stacks,
            _achievements
        );
        
        isFreelancerValid[msg.sender] = true;
        freelancerIds[msg.sender] = freelancerCounter;
        
        emit FreelancerCreated(freelancerCounter, msg.sender, _name);
    }

    /**
     * @dev Post a new job
     * @param _amount Total job amount
     * @param _preferredToken Token address for payment
     * @param _milestoneCount Number of milestones
     * @param _jobDescription Job description
     * @param stake Whether to stake the funds
     */
    function postJob(
        uint256 _amount,
        address _preferredToken,
        uint256 _milestoneCount,
        bytes memory _jobDescription,
        bool stake
    ) external onlyValidAddress(_preferredToken) onlyValidAmount(_amount) {
        if (_milestoneCount == 0) {
            revert InvalidAmount();
        }
        
        uint256 amountPerMilestone = _amount / _milestoneCount;
        if (amountPerMilestone == 0) {
            revert InvalidAmount();
        }
        
        jobCounter++;
        // error check if user has the amount
        // add job title and job tag
        
        // Transfer tokens first
        IERC20 token = IERC20(_preferredToken);
        bool success = token.transferFrom(msg.sender, address(this), _amount);
        require(success, "Token transfer failed");
        
        // Create job
        jobs[jobCounter] = PayrollLibrary.Job(
            jobCounter,
            msg.sender,
            _jobDescription,
            address(0),
            _preferredToken,
            _amount,
            amountPerMilestone,
            _milestoneCount,
            1,
            0,
            _amount,
            block.timestamp,
            true,
            stake
        );
        
        // Stake funds if requested
        if (stake) {
            token.approve(address(staking), _amount);
            staking.deposit(_amount, _preferredToken);
        }
        
        emit JobPosted(jobCounter, msg.sender, _amount, _preferredToken);
    }

    /**
     * @dev Bid on a job
     * @param _jobId Job ID
     * @param _bidAmount Amount of bidCoin to bid
     */
    function bidJob(
        uint256 _jobId,
        uint256 _bidAmount
    ) external 
        onlyValidJob(_jobId)
        onlyActiveJob(_jobId)
        onlyValidFreelancer(msg.sender)
        nonReentrant
    {
        PayrollLibrary.Job storage job = jobs[_jobId];
        if (job.freelancer != address(0)) {
            revert JobAlreadyAssigned();
        }
        
        Bid storage jobBid = bids[_jobId];
        
        // Check if freelancer has already bid
        for (uint256 i = 0; i < jobBid.freelancers.length; i++) {
            if (jobBid.freelancers[i] == msg.sender) {
                revert AlreadyRegistered();
            }
        }
        
        // Record bid
        jobBid.freelancers.push(msg.sender);
        jobBid.freelancerBids[msg.sender] = _bidAmount; // Fixed bid at job amount
        
        emit JobBid(_jobId, msg.sender, _bidAmount);
    }

    /**
     * @dev Assign a job to a freelancer
     * @param _jobId Job ID
     * @param _freelancer Freelancer address
     */
    function assignJob(
        uint256 _jobId,
        address _freelancer
    )
        external
        onlyValidJob(_jobId)
        onlyJobEmployer(_jobId)
        onlyValidFreelancer(_freelancer)
        onlyActiveJob(_jobId)
    {
        PayrollLibrary.Job storage job = jobs[_jobId];
        if (job.freelancer != address(0)) {
            revert JobAlreadyAssigned();
        }
        
        // Check if freelancer has bid on this job
        bool hasBid = false;
        Bid storage jobBid = bids[_jobId];
        for (uint256 i = 0; i < jobBid.freelancers.length; i++) {
            if (jobBid.freelancers[i] == _freelancer) {
                hasBid = true;
                break;
            }
        }
        require(hasBid, "Freelancer has not bid on this job");
        
        // Assign job
        job.freelancer = _freelancer;
        job.lastUpdate = block.timestamp;
        
        // Update freelancer stats
        uint256 freelancerId = freelancerIds[_freelancer];
        freelancers[freelancerId].numJobsDone++;
        
        emit JobAssigned(_jobId, _freelancer);
    }

    /**
     * @dev Mark a milestone as completed
     * @param _jobId Job ID
     * @param _milestone Milestone number
     */
    function completeMilestone(
        uint256 _jobId,
        uint256 _milestone
    )
        external
        onlyValidJob(_jobId)
        onlyJobEmployer(_jobId)
    {
        PayrollLibrary.Job storage job = jobs[_jobId];
        
        if (job.freelancer == address(0)) {
            revert Unauthorized();
        }
        
        if (_milestone != job.currentMileStone) {
            revert InvalidMilestone();
        }
        
        if (_milestone > job.numOfMileStone) {
            revert InvalidMilestone();
        }
        
        // Update milestone
        uint256 paymentAmount = job.amountPerMileStone;
        job.amountReleased += paymentAmount;
        job.remainingBalance = job.amountPerMileStone * ( job.numOfMileStone- job.currentMileStone);
        
        // Check if this is the last milestone
        if (job.currentMileStone == job.numOfMileStone) {
            job.isActive = false; // Job completed
        } else {
            job.currentMileStone++;
        }
        
        job.lastUpdate = block.timestamp;
        
        emit MilestoneCompleted(_jobId, msg.sender, _milestone);
    }

    /**
     * @dev Receive payment for completed milestones
     * @param _jobId Job ID
     */
    function receivePayment(
        uint256 _jobId
    )
        external
        onlyValidJob(_jobId)
        onlyJobFreelancer(_jobId)
        nonReentrant
    {
        PayrollLibrary.Job storage job = jobs[_jobId];
        uint256 amount = job.remainingBalance;
        
        if (amount == 0) {
            revert NoFundsAvailable();
        }
        
        // Update state before transfer
        job.remainingBalance = 0;
        job.lastUpdate = block.timestamp;
        
        // Transfer funds
        if (job.staked) {
            staking.withdraw(amount, job.token);
        }
        
        IERC20(job.token).transfer(msg.sender, amount);
        
        // Update freelancer stats
        uint256 freelancerId = freelancerIds[msg.sender];
        if (!job.isActive) {
            freelancers[freelancerId].numJobsDone++;
        }
        
        emit PaymentReceived(_jobId, msg.sender, amount);
    }

    /**
     * @dev Stake available payment
     * @param _jobId Job ID
     */
    function stakePayment(
        uint256 _jobId
    )
        external
        onlyValidJob(_jobId)
        onlyJobFreelancer(_jobId)
        nonReentrant
    {
        PayrollLibrary.Job storage job = jobs[_jobId];
        uint256 amount = job.remainingBalance;
        
        if (amount == 0) {
            revert NoFundsAvailable();
        }
        
        if (job.staked) {
            revert Unauthorized();
        }
        
        // Update state
        job.staked = true;
        
        // Stake funds
        IERC20(job.token).approve(address(staking), amount);
        staking.deposit(amount, job.token);
        
        emit PaymentStaked(_jobId, msg.sender, amount);
    }

    /**
     * @dev Unstake available payment
     * @param _jobId Job ID
     */
    function unstakePayment(
        uint256 _jobId
    )
        external
        onlyValidJob(_jobId)
        onlyJobFreelancer(_jobId)
        nonReentrant
    {
        PayrollLibrary.Job storage job = jobs[_jobId];
        uint256 amount = job.remainingBalance;
        
        if (amount == 0) {
            revert NoFundsAvailable();
        }
        
        if (!job.staked) {
            revert Unauthorized();
        }
        
        // Update state before transfer
        job.remainingBalance = 0;
        job.staked = false;
        
        // Unstake and transfer funds
        staking.withdraw(amount, job.token);
        IERC20(job.token).transfer(msg.sender, amount);
        
        emit PaymentUnstaked(_jobId, msg.sender, amount);
    }

    /**
     * @dev Get available jobs
     * @param limit Maximum number of jobs to return
     * @return availableJobs Array of available jobs
     */
    function getAvailableJobs(
        uint256 limit
    )
        external
        view
        returns (PayrollLibrary.Job[] memory availableJobs)
    {
        if (limit == 0) {
            limit = 10; // Default limit
        }
        
        // Count available jobs
        uint256 count = 0;
        for (uint256 i = 1; i <= jobCounter && count < limit; i++) {
            if (jobs[i].freelancer == address(0) && jobs[i].isActive) {
                count++;
            }
        }
        
        // Create result array
        availableJobs = new PayrollLibrary.Job[](count);
        
        // Fill array
        count = 0;
        for (uint256 i = 1; i <= jobCounter && count < limit; i++) {
            if (jobs[i].freelancer == address(0) && jobs[i].isActive) {
                availableJobs[count] = jobs[i];
                count++;
            }
        }
        
        return availableJobs;
    }

    /**
     * @dev Get bidders for a job
     * @param _jobId Job ID
     * @return bidders Array of bidders
     */
    function getBidders(
        uint256 _jobId
    )
        external
        view
        onlyValidJob(_jobId)
        returns (Bidder[] memory bidders)
    {
        Bid storage jobBid = bids[_jobId];
        uint256 bidderCount = jobBid.freelancers.length;
        
        bidders = new Bidder[](bidderCount);
        
        for (uint256 i = 0; i < bidderCount; i++) {
            address freelancerAddr = jobBid.freelancers[i];
            bidders[i] = Bidder(
                freelancerAddr,
                jobBid.freelancerBids[freelancerAddr]
            );
        }
        
        return bidders;
    }

    /**
     * @dev Get freelancers
     * @param limit Maximum number of freelancers to return
     * @param skip Number of freelancers to skip
     * @return allFreelancers Array of freelancers
     */
    function getFreelancers(
        uint256 limit,
        uint256 skip
    )
        external
        view
        returns (FreelancerLibrary.Freelancer[] memory allFreelancers)
    {
        if (limit == 0) {
            limit = 10; // Default limit
        }
        
        if (skip >= freelancerCounter) {
            return new FreelancerLibrary.Freelancer[](0);
        }
        
        uint256 count = 0;
        uint256 remaining = freelancerCounter - skip;
        uint256 resultSize = (remaining < limit) ? remaining : limit;
        
        allFreelancers = new FreelancerLibrary.Freelancer[](resultSize);
        
        for (uint256 i = skip + 1; i <= freelancerCounter && count < limit; i++) {
            allFreelancers[count] = freelancers[i];
            count++;
        }
        
        return allFreelancers;
    }

    /**
     * @dev Get job data
     * @param id Job ID
     */
    function getJobData(
        uint256 id
    )
        external
        view
        onlyValidJob(id)
        returns (
            uint256 jobId,
            address employer,
            bytes memory jobDescription,
            address freelancer,
            address token,
            uint256 amount,
            uint256 amountPerMileStone,
            uint256 numOfMileStone,
            uint256 currentMileStone,
            uint256 amountReleased,
            uint256 remainingBalance,
            uint256 lastUpdate,
            bool isActive,
            bool staked
        )
    {
        PayrollLibrary.Job memory job = jobs[id];
        return (
            job.id,
            job.employer,
            job.jobDescription,
            job.freelancer,
            job.token,
            job.depositAmount,
            job.amountPerMileStone,
            job.numOfMileStone,
            job.currentMileStone,
            job.amountReleased,
            job.remainingBalance,
            job.lastUpdate,
            job.isActive,
            job.staked
        );
    }

    /**
     * @dev Get freelancer details
     * @param id Freelancer ID
     */
    function getFreelancerDetail(
        uint256 id
    )
        external
        view
        returns (
            uint256 freelancerId,
            address freelancer,
            string memory name,
            bytes memory description,
            uint256 numJobsDone,
            uint256 rating,
            bytes memory skills,
            uint256[] memory achievements
        )
    {
        if (id == 0 || id > freelancerCounter) {
            revert FreelancerNotFound();
        }
        
        FreelancerLibrary.Freelancer storage f = freelancers[id];
        return (
            f.id,
            f.freelancer,
            f.name,
            f.description,
            f.numJobsDone,
            f.rating,
            f.stacks,
            f.achievements
        );
    }

    /**
     * @dev Get the balance of a specific token in this contract
     * @param _tokenAddress Token address
     * @return Token balance
     */
    function getBalance(
        address _tokenAddress
    )
        external
        view
        onlyValidAddress(_tokenAddress)
        returns (uint256)
    {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }
    
    /**
     * @dev Withdraw tokens in case of emergency
     * @param _tokenAddress Token address
     */
    function emergencyWithdraw(
        address _tokenAddress
    )
        external
        onlyOwner
        onlyValidAddress(_tokenAddress)
        nonReentrant
    {
        IERC20 token = IERC20(_tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        token.transfer(owner(), balance);
    }

    /**
     * @dev Fallback function to receive ETH payments
     */
    receive() external payable {}
}