// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LiquidityMiningV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    struct Pool {
        IERC20 token;
        uint256 totalStaked;
        uint256 rewardPerSecond;
        uint256 lastUpdateTime;
        uint256 rewardRate;
        uint256 periodFinish;
        uint256 allocPoint;
        uint256 lastRewardTime;
        bool enabled;
        uint256 apr;
        uint256 minimumStake;
        uint256 maximumStake;
        uint256 lockupPeriod;
        uint256 performanceFee;
        uint256 withdrawalFee;
    }

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 lastRewardTime;
        uint256 pendingRewards;
        uint256 totalRewardsReceived;
        uint256 firstStakeTime;
    }

    struct PoolInfo {
        address token;
        uint256 allocPoint;
        uint256 rewardRate;
        uint256 apr;
        uint256 totalStaked;
        bool enabled;
    }

    mapping(address => Pool) public pools;
    mapping(address => mapping(address => UserInfo)) public userInfo;
    mapping(address => uint256[]) public userPools;
    
    IERC20 public rewardToken;
    IERC20 public stakingToken;
    
    uint256 public totalAllocPoints;
    uint256 public rewardPerSecond;
    uint256 public constant MAX_ALLOC_POINTS = 100000;
    uint256 public constant MAX_REWARD_RATE = 1000000000000000000000; // 1000 tokens per second
    
    // Configuration
    uint256 public minimumStakeAmount;
    uint256 public maximumStakeAmount;
    uint256 public performanceFee;
    uint256 public withdrawalFee;
    uint256 public lockupPeriod;
    
    // Events
    event PoolCreated(address indexed token, uint256 allocPoint, uint256 rewardRate, uint256 apr);
    event Staked(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event RewardPaid(address indexed user, address indexed token, uint256 reward);
    event EmergencyWithdraw(address indexed user, address indexed token, uint256 amount);
    event PoolUpdated(address indexed token, uint256 allocPoint, uint256 rewardRate);
    event RewardRateUpdated(uint256 newRate);
    event FeeUpdated(uint256 performanceFee, uint256 withdrawalFee);
    event LockupPeriodUpdated(uint256 newPeriod);
    event PoolDisabled(address indexed token);
    event PoolEnabled(address indexed token);
    event WithdrawalLocked(address indexed user, address indexed token, uint256 unlockTime);

    constructor(
        address _rewardToken,
        address _stakingToken,
        uint256 _rewardPerSecond,
        uint256 _minimumStakeAmount,
        uint256 _maximumStakeAmount
    ) {
        rewardToken = IERC20(_rewardToken);
        stakingToken = IERC20(_stakingToken);
        rewardPerSecond = _rewardPerSecond;
        minimumStakeAmount = _minimumStakeAmount;
        maximumStakeAmount = _maximumStakeAmount;
        performanceFee = 50; // 0.5%
        withdrawalFee = 10; // 0.1%
        lockupPeriod = 30 days; // 30 days lockup
    }

    // Create new pool
    function createPool(
        address token,
        uint256 allocPoint,
        uint256 rewardRate,
        uint256 apr
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(allocPoint <= MAX_ALLOC_POINTS, "Too many alloc points");
        require(rewardRate <= MAX_REWARD_RATE, "Reward rate too high");
        require(apr <= 1000000, "APR too high"); // 10000% max APR
        
        Pool storage pool = pools[token];
        require(pool.token == address(0), "Pool already exists");
        
        pool.token = IERC20(token);
        pool.allocPoint = allocPoint;
        pool.rewardRate = rewardRate;
        pool.lastRewardTime = block.timestamp;
        pool.apr = apr;
        pool.enabled = true;
        
        totalAllocPoints = totalAllocPoints.add(allocPoint);
        
        emit PoolCreated(token, allocPoint, rewardRate, apr);
    }

    // Update pool parameters
    function updatePool(
        address token,
        uint256 allocPoint,
        uint256 rewardRate,
        uint256 apr
    ) external onlyOwner {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        require(allocPoint <= MAX_ALLOC_POINTS, "Too many alloc points");
        require(rewardRate <= MAX_REWARD_RATE, "Reward rate too high");
        require(apr <= 1000000, "APR too high");
        
        totalAllocPoints = totalAllocPoints.sub(pool.allocPoint).add(allocPoint);
        
        pool.allocPoint = allocPoint;
        pool.rewardRate = rewardRate;
        pool.apr = apr;
        
        emit PoolUpdated(token, allocPoint, rewardRate);
    }

    // Enable pool
    function enablePool(address token) external onlyOwner {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        pool.enabled = true;
        emit PoolEnabled(token);
    }

    // Disable pool
    function disablePool(address token) external onlyOwner {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        pool.enabled = false;
        emit PoolDisabled(token);
    }

    // Stake tokens
    function stake(
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        require(pool.enabled, "Pool disabled");
        require(amount >= minimumStakeAmount, "Amount below minimum");
        require(amount <= maximumStakeAmount, "Amount above maximum");
        require(amount > 0, "Amount must be greater than 0");
        require(pool.token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        updatePool(token);
        UserInfo storage user = userInfo[token][msg.sender];
        
        if (user.amount > 0) {
            uint256 pending = calculatePendingReward(token, msg.sender);
            if (pending > 0) {
                user.pendingRewards = user.pendingRewards.add(pending);
            }
        }
        
        user.amount = user.amount.add(amount);
        pool.totalStaked = pool.totalStaked.add(amount);
        
        if (user.firstStakeTime == 0) {
            user.firstStakeTime = block.timestamp;
        }
        
        pool.token.transferFrom(msg.sender, address(this), amount);
        user.lastRewardTime = block.timestamp;
        
        // Update user history
        userPools[msg.sender].push(token);
        
        emit Staked(msg.sender, token, amount);
    }

    // Withdraw tokens
    function withdraw(
        address token,
        uint256 amount
    ) external whenNotPaused nonReentrant {
        Pool storage pool = pools[token];
        require(pool.token != address(0), "Pool does not exist");
        require(pool.enabled, "Pool disabled");
        require(userInfo[token][msg.sender].amount >= amount, "Insufficient balance");
        
        updatePool(token);
        UserInfo storage user = userInfo[token][msg.sender];
        
        uint256 pending = calculatePendingReward(token, msg.sender);
        if (pending > 0) {
            user.pendingRewards = user.pendingRewards.add(pending);
        }
        
        // Check lockup period
        if (block.timestamp < user.firstStakeTime.add(lockupPeriod)) {
            uint256 feeAmount = amount.mul(withdrawalFee).div(10000);
            uint256 amountAfterFee = amount.sub(feeAmount);
            
            // Apply fee
            if (feeAmount > 0) {
                pool.token.transfer(owner(), feeAmount);
