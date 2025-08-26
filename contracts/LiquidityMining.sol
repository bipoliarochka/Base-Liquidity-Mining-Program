# base-liquidity-mining/contracts/LiquidityMining.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LiquidityMining is Ownable, ReentrancyGuard {
    struct Pool {
        IERC20 token0;
        IERC20 token1;
        uint256 totalStaked;
        uint256 rewardPerSecond;
        uint256 lastUpdateTime;
        uint256 accRewardPerShare;
        uint256 poolStartTime;
        uint256 poolEndTime;
        bool isActive;
    }
    
    struct Staker {
        uint256 amountStaked;
        uint256 rewardDebt;
        uint256 lastUpdateTime;
        uint256[] stakedTokens;
    }
    
    struct RewardTier {
        uint256 minStake;
        uint256 multiplier;
    }
    
    mapping(address => Pool) public pools;
    mapping(address => Staker) public stakers;
    mapping(address => uint256[]) public stakerPools;
    
    IERC20 public rewardToken;
    uint256 public totalRewardTokens;
    uint256 public constant REWARD_PRECISION = 1e18;
    
    RewardTier[] public rewardTiers;
    
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint256 rewardPerSecond,
        uint256 startTime,
        uint256 endTime
    );
    
    event Staked(
        address indexed user,
        address indexed token0,
        address indexed token1,
        uint256 amount,
        uint256 rewardMultiplier
    );
    
    event Unstaked(
        address indexed user,
        address indexed token0,
        address indexed token1,
        uint256 amount
    );
    
    event RewardClaimed(
        address indexed user,
        uint256 rewardAmount
    );
    
    constructor(
        address _rewardToken,
        uint256 _totalRewardTokens
    ) {
        rewardToken = IERC20(_rewardToken);
        totalRewardTokens = _totalRewardTokens;
    }
    
    function createPool(
        address token0,
        address token1,
        uint256 rewardPerSecond,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner {
        require(token0 != token1, "Same tokens");
        require(startTime > block.timestamp, "Invalid start time");
        require(endTime > startTime, "Invalid end time");
        
        pools[token0] = Pool({
            token0: IERC20(token0),
            token1: IERC20(token1),
            totalStaked: 0,
            rewardPerSecond: rewardPerSecond,
            lastUpdateTime: startTime,
            accRewardPerShare: 0,
            poolStartTime: startTime,
            poolEndTime: endTime,
            isActive: true
        });
        
        emit PoolCreated(token0, token1, rewardPerSecond, startTime, endTime);
    }
    
    function addRewardTier(
        uint256 minStake,
        uint256 multiplier
    ) external onlyOwner {
        rewardTiers.push(RewardTier({
            minStake: minStake,
            multiplier: multiplier
        }));
    }
    
    function stake(
        address token0,
        address token1,
        uint256 amount
    ) external nonReentrant {
        Pool storage pool = pools[token0];
        require(pool.isActive, "Pool inactive");
        require(block.timestamp >= pool.poolStartTime, "Pool not started");
        require(block.timestamp <= pool.poolEndTime, "Pool ended");
        require(amount > 0, "Amount must be greater than 0");
        
        // Update pool rewards
        updatePool(token0);
        
        // Calculate reward multiplier
        uint256 rewardMultiplier = calculateRewardMultiplier(amount);
        
        // Transfer tokens to contract
        pool.token0.transferFrom(msg.sender, address(this), amount);
        pool.token1.transferFrom(msg.sender, address(this), amount);
        
        // Update staker
        stakers[msg.sender].amountStaked += amount;
        stakers[msg.sender].lastUpdateTime = block.timestamp;
        stakers[msg.sender].stakedTokens.push(amount);
        
        // Update pool
        pool.totalStaked += amount;
        
        emit Staked(msg.sender, token0, token1, amount, rewardMultiplier);
    }
    
    function unstake(
        address token0,
        address token1,
        uint256 amount
    ) external nonReentrant {
        Pool storage pool = pools[token0];
        require(pool.isActive, "Pool inactive");
        require(stakers[msg.sender].amountStaked >= amount, "Insufficient stake");
        
        // Update pool rewards
        updatePool(token0);
        
        // Transfer tokens back to user
        pool.token0.transfer(msg.sender, amount);
        pool.token1.transfer(msg.sender, amount);
        
        // Update staker
        stakers[msg.sender].amountStaked -= amount;
        stakers[msg.sender].lastUpdateTime = block.timestamp;
        
        // Update pool
        pool.totalStaked -= amount;
        
        emit Unstaked(msg.sender, token0, token1, amount);
    }
    
    function claimReward() external nonReentrant {
        updatePool(address(0)); // Placeholder for general update
        
        uint256 reward = calculatePendingReward(msg.sender);
        require(reward > 0, "No rewards to claim");
        
        // Transfer rewards
        rewardToken.transfer(msg.sender, reward);
        
        // Update reward debt
        stakers[msg.sender].rewardDebt += reward;
        
        emit RewardClaimed(msg.sender, reward);
    }
    
    function updatePool(address token0) internal {
        Pool storage pool = pools[token0];
        if (block.timestamp <= pool.lastUpdateTime) return;
        
        uint256 timePassed = block.timestamp - pool.lastUpdateTime;
        uint256 rewards = timePassed * pool.rewardPerSecond;
        
        if (pool.totalStaked > 0) {
            pool.accRewardPerShare += (rewards * REWARD_PRECISION) / pool.totalStaked;
        }
        
        pool.lastUpdateTime = block.timestamp;
    }
    
    function calculateRewardMultiplier(uint256 stakeAmount) internal view returns (uint256) {
        for (uint256 i = rewardTiers.length; i > 0; i--) {
            if (stakeAmount >= rewardTiers[i - 1].minStake) {
                return rewardTiers[i - 1].multiplier;
            }
        }
        return 1e18; // Default multiplier
    }
    
    function calculatePendingReward(address user) internal view returns (uint256) {
        Staker storage staker = stakers[user];
        uint256 pending = (staker.amountStaked * staker.rewardDebt) / REWARD_PRECISION;
        return pending;
    }
    
    function getPoolInfo(address token0) external view returns (Pool memory) {
        return pools[token0];
    }
    
    function getUserStake(address user) external view returns (uint256) {
        return stakers[user].amountStaked;
    }
}
