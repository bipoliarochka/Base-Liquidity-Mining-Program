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
        // Добавить структуры:
struct NFTMiningTier {
    string tierName;
    uint256 minStake;
    uint256 rewardMultiplier;
    uint256 bonusPercentage;
    uint256 maxStake;
    bool enabled;
    uint256 maxUsers;
    uint256 currentUsers;
    uint256 maxRewardsPerDay;
    uint256 dailyRewards;
    uint256 lastResetTime;
}

struct NFTMiningPosition {
    uint256 tokenId;
    address staker;
    address nftContract;
    uint256 stakeTime;
    uint256 miningDuration;
    bool isMining;
    string miningTier;
    uint256 rewardMultiplier;
    uint256 miningPower;
    uint256 lastRewardTime;
    uint256 totalRewardsEarned;
    uint256 stakedAmount;
    uint256 dailyStake;
    uint256 lastDailyReset;
}

// Добавить маппинги:
mapping(string => NFTMiningTier) public nftMiningTiers;
mapping(address => mapping(uint256 => NFTMiningPosition)) public nftMiningPositions;
mapping(address => uint256[]) public userNFTMiningPositions;

// Добавить события:
event NFTMiningTierCreated(
    string indexed tierName,
    uint256 minStake,
    uint256 rewardMultiplier,
    uint256 bonusPercentage,
    uint256 maxStake
);

event NFTMiningStarted(
    address indexed staker,
    address indexed nftContract,
    uint256 tokenId,
    string miningTier,
    uint256 miningPower,
    uint256 timestamp
);

event NFTMiningEnded(
    address indexed staker,
    address indexed nftContract,
    uint256 tokenId,
    uint256 rewards,
    uint256 timestamp
);

event NFTMiningTierUpdated(
    string indexed tierName,
    uint256 minStake,
    uint256 rewardMultiplier,
    uint256 bonusPercentage
);

// Добавить функции:
function createNFTMiningTier(
    string memory tierName,
    uint256 minStake,
    uint256 rewardMultiplier,
    uint256 bonusPercentage,
    uint256 maxStake,
    uint256 maxUsers,
    uint256 maxRewardsPerDay
) external onlyOwner {
    require(bytes(tierName).length > 0, "Tier name cannot be empty");
    require(minStake <= maxStake, "Invalid stake limits");
    require(rewardMultiplier >= 1000, "Reward multiplier too low");
    require(bonusPercentage <= 10000, "Bonus percentage too high");
    
    nftMiningTiers[tierName] = NFTMiningTier({
        tierName: tierName,
        minStake: minStake,
        rewardMultiplier: rewardMultiplier,
        bonusPercentage: bonusPercentage,
        maxStake: maxStake,
        enabled: true,
        maxUsers: maxUsers,
        currentUsers: 0,
        maxRewardsPerDay: maxRewardsPerDay,
        dailyRewards: 0,
        lastResetTime: block.timestamp
    });
    
    emit NFTMiningTierCreated(tierName, minStake, rewardMultiplier, bonusPercentage, maxStake);
}

function updateNFTMiningTier(
    string memory tierName,
    uint256 minStake,
    uint256 rewardMultiplier,
    uint256 bonusPercentage
) external onlyOwner {
    require(nftMiningTiers[tierName].tierName.length > 0, "Tier not found");
    require(minStake <= nftMiningTiers[tierName].maxStake, "Invalid stake limits");
    require(rewardMultiplier >= 1000, "Reward multiplier too low");
    require(bonusPercentage <= 10000, "Bonus percentage too high");
    
    NFTMiningTier storage tier = nftMiningTiers[tierName];
    tier.minStake = minStake;
    tier.rewardMultiplier = rewardMultiplier;
    tier.bonusPercentage = bonusPercentage;
    
    emit NFTMiningTierUpdated(tierName, minStake, rewardMultiplier, bonusPercentage);
}

function startNFTMining(
    address nftContract,
    uint256 tokenId,
    string memory miningTier,
    uint256 miningPower
) external {
    require(nftMiningTiers[miningTier].tierName.length > 0, "Invalid mining tier");
    require(nftMiningTiers[miningTier].enabled, "Tier not enabled");
    require(ownerOf(nftContract, tokenId) == msg.sender, "Not owner");
    require(miningPower > 0, "Mining power must be greater than 0");
    
    // Check tier limits
    NFTMiningTier storage tier = nftMiningTiers[miningTier];
    require(tier.currentUsers < tier.maxUsers, "Tier full");
    
    // Check daily rewards
    if (block.timestamp >= tier.lastResetTime + 86400) {
        tier.dailyRewards = 0;
        tier.lastResetTime = block.timestamp;
    }
    

    uint256 positionId = uint256(keccak256(abi.encodePacked(nftContract, tokenId, block.timestamp)));
    
    nftMiningPositions[nftContract][tokenId] = NFTMiningPosition({
        tokenId: tokenId,
        staker: msg.sender,
        nftContract: nftContract,
        stakeTime: block.timestamp,
        miningDuration: 0,
        isMining: true,
        miningTier: miningTier,
        rewardMultiplier: tier.rewardMultiplier,
        miningPower: miningPower,
        lastRewardTime: block.timestamp,
        totalRewardsEarned: 0,
        stakedAmount: 0,
        dailyStake: 0,
        lastDailyReset: block.timestamp
    });
    
    // Update tier stats
    tier.currentUsers++;
    
    // Transfer NFT to contract
    transferFrom(msg.sender, address(this), nftContract, tokenId);
    
    userNFTMiningPositions[msg.sender].push(tokenId);
    
    emit NFTMiningStarted(msg.sender, nftContract, tokenId, miningTier, miningPower, block.timestamp);
}

function endNFTMining(
    address nftContract,
    uint256 tokenId
) external {
    NFTMiningPosition storage position = nftMiningPositions[nftContract][tokenId];
    require(position.isMining, "NFT not mining");
    require(position.staker == msg.sender, "Not staker");
    
    // Calculate rewards
    uint256 rewards = calculateNFTMiningRewards(position);
    
    // Return NFT to user
    transferFrom(address(this), msg.sender, nftContract, tokenId);
    
    // Transfer rewards
    if (rewards > 0) {
        // Transfer reward tokens
    }
    
    // Update stats
    position.isMining = false;
    position.totalRewardsEarned += rewards;
    
    // Update tier stats
    NFTMiningTier storage tier = nftMiningTiers[position.miningTier];
    tier.currentUsers--;
    
    emit NFTMiningEnded(msg.sender, nftContract, tokenId, rewards, block.timestamp);
}

function calculateNFTMiningRewards(NFTMiningPosition memory position) internal view returns (uint256) {
    // Simplified reward calculation
    uint256 timeElapsed = block.timestamp - position.lastRewardTime;
    uint256 baseReward = position.miningPower * position.rewardMultiplier / 1000;
    uint256 timeBonus = timeElapsed / 3600; // Bonus per hour
    uint256 totalReward = baseReward + (timeBonus * 100000000000000000); // 0.1 ETH per hour
    
    return totalReward;
}

function getNFTMiningTierInfo(string memory tierName) external view returns (NFTMiningTier memory) {
    return nftMiningTiers[tierName];
}

function getNFTMiningPosition(address nftContract, uint256 tokenId) external view returns (NFTMiningPosition memory) {
    return nftMiningPositions[nftContract][tokenId];
}

function getNFTMiningTiers() external view returns (string[] memory) {
    // Implementation would return all tier names
    return new string[](0);
}

function getNFTMiningStats() external view returns (
    uint256 totalPositions,
    uint256 activePositions,
    uint256 totalRewards,
    uint256 totalUsers
) {
    // Implementation would return mining statistics
    return (0, 0, 0, 0);
}
