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
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LiquidityMining is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    // Существующие структуры и функции...
    
    // Новые структуры для NFT-базированного майнинга
    struct NFTMiningTier {
        string tierName;
        uint256 minStake;
        uint256 maxStake;
        uint256 rewardMultiplier;
        uint256 bonusPercentage;
        uint256 maxStakers;
        uint256 currentStakers;
        uint256 maxRewardsPerDay;
        uint256 dailyRewards;
        uint256 lastResetTime;
        bool enabled;
        uint256 lockupPeriod;
        uint256 performanceFee;
        uint256 withdrawalFee;
        uint256[] requiredNFTs;
        uint256[] requiredNFTLevels;
        uint256[] requiredNFTTypes;
        string description;
        uint256 minStakingDuration;
        uint256 maxStakingDuration;
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
        uint256[] nftTokenIds;
        uint256[] nftLevels;
        uint256[] nftTypes;
        uint256 nftBonus;
        uint256 compoundCount;
        uint256[] rewardHistory;
        uint256[] nftStakeHistory;
        mapping(address => bool) isVerified;
        uint256 verificationLevel;
        uint256 lastVerificationTime;
        uint256[] stakeHistory;
    }
    
    struct NFTMiningStats {
        uint256 totalNFTsStaked;
        uint256 totalStakers;
        uint256 totalRewardsDistributed;
        uint256 averageMiningPower;
        uint256 totalValueLocked;
        uint256 totalStakingDuration;
        uint256 successRate;
        uint256[] topStakers;
        uint256[] topNFTs;
        mapping(address => uint256) stakerRewards;
        mapping(address => uint256) stakerNFTs;
        mapping(address => uint256) stakerMiningPower;
        mapping(string => uint256) tierStats;
        mapping(address => uint256) nftTypeStats;
    }
    
    struct NFTMiningConfig {
        address nftContract;
        string[] allowedTiers;
        uint256 minStakeAmount;
        uint256 maxStakeAmount;
        uint256 minStakingDuration;
        uint256 maxStakingDuration;
        uint256 performanceFee;
        uint256 withdrawalFee;
        uint256[] requiredNFTTypes;
        uint256[] requiredNFTLevels;
        uint256[] requiredNFTCollections;
        uint256[] requiredNFTRarities;
        bool enabled;
        uint256 maxStakersPerNFT;
        uint256 maxStakersTotal;
        uint256 lastUpdate;
    }
    
    struct NFTMiningReward {
        address staker;
        address nftContract;
        uint256 tokenId;
        uint256 amount;
        uint256 timestamp;
        string rewardType;
        uint256 nftBonus;
        uint256 tierBonus;
        uint256 compoundBonus;
        uint256[] relatedNFTs;
        uint256[] relatedRewards;
    }
    
    struct NFTMiningVerification {
        address staker;
        address nftContract;
        uint256 tokenId;
        uint256 verificationTime;
        uint256 verificationLevel;
        bool verified;
        string verificationMethod;
        uint256[] nftAttributes;
        uint256[] nftTraits;
        uint256[] nftMetadata;
    }
    
    // Новые маппинги
    mapping(string => NFTMiningTier) public nftMiningTiers;
    mapping(address => mapping(uint256 => NFTMiningPosition)) public nftMiningPositions;
    mapping(address => uint256[]) public userNFTMiningPositions;
    mapping(address => NFTMiningStats) public nftMiningStats;
    mapping(address => NFTMiningConfig) public nftMiningConfigs;
    mapping(address => mapping(uint256 => NFTMiningReward)) public nftMiningRewards;
    mapping(address => mapping(uint256 => NFTMiningVerification)) public nftMiningVerifications;
    mapping(address => mapping(uint256 => uint256[])) public nftStakeHistory;
    mapping(string => uint256[]) public tierNFTs;
    mapping(address => mapping(uint256 => uint256)) public nftStakeCounts;
    
    // Новые события
    event NFTMiningTierCreated(
        string indexed tierName,
        uint256 minStake,
        uint256 maxStake,
        uint256 rewardMultiplier,
        uint256 bonusPercentage,
        uint256 maxStakers,
        string description
    );
    
    event NFTMiningPositionStarted(
        address indexed staker,
        address indexed nftContract,
        uint256 indexed tokenId,
        string miningTier,
        uint256 miningPower,
        uint256 stakeTime,
        uint256 miningDuration,
        uint256[] nftTokenIds
    );
    
    event NFTMiningPositionEnded(
        address indexed staker,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 rewards,
        uint256 timestamp,
        uint256 nftBonus,
        uint256 tierBonus
    );
    
    event NFTMiningRewardsClaimed(
        address indexed staker,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 rewards,
        uint256 timestamp,
        string rewardType
    );
    
    event NFTMiningConfigUpdated(
        address indexed nftContract,
        uint256 minStake,
        uint256 maxStake,
        uint256 performanceFee,
        uint256 withdrawalFee,
        bool enabled
    );
    
    event NFTMiningTierUpdated(
        string indexed tierName,
        uint256 minStake,
        uint256 maxStake,
        uint256 rewardMultiplier,
        uint256 bonusPercentage
    );
    
    event NFTMiningVerified(
        address indexed staker,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 verificationLevel,
        uint256 timestamp,
        bool success
    );
    
    event NFTMiningRewardDistributed(
        address indexed staker,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 timestamp,
        string rewardType,
        uint256 nftBonus,
        uint256 tierBonus
    );
    
    event NFTMiningCompounded(
        address indexed staker,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 compoundCount,
        uint256 timestamp
    );
    
    // Новые функции для NFT-базированного майнинга
    function createNFTMiningTier(
        string memory tierName,
        uint256 minStake,
        uint256 maxStake,
        uint256 rewardMultiplier,
        uint256 bonusPercentage,
        uint256 maxStakers,
        uint256 lockupPeriod,
        uint256 performanceFee,
        uint256 withdrawalFee,
        uint256[] memory requiredNFTs,
        uint256[] memory requiredNFTLevels,
        uint256[] memory requiredNFTTypes,
        string memory description,
        uint256 minStakingDuration,
        uint256 maxStakingDuration
    ) external onlyOwner {
        require(bytes(tierName).length > 0, "Tier name cannot be empty");
        require(minStake <= maxStake, "Invalid stake limits");
        require(rewardMultiplier >= 1000, "Reward multiplier too low");
        require(bonusPercentage <= 10000, "Bonus percentage too high");
        require(maxStakers > 0, "Max stakers must be greater than 0");
        require(lockupPeriod > 0, "Lockup period must be greater than 0");
        require(performanceFee <= 10000, "Performance fee too high");
        require(withdrawalFee <= 10000, "Withdrawal fee too high");
        require(minStakingDuration <= maxStakingDuration, "Invalid staking duration limits");
        
        nftMiningTiers[tierName] = NFTMiningTier({
            tierName: tierName,
            minStake: minStake,
            maxStake: maxStake,
            rewardMultiplier: rewardMultiplier,
            bonusPercentage: bonusPercentage,
            maxStakers: maxStakers,
            currentStakers: 0,
            maxRewardsPerDay: 0,
            dailyRewards: 0,
            lastResetTime: block.timestamp,
            enabled: true,
            lockupPeriod: lockupPeriod,
            performanceFee: performanceFee,
            withdrawalFee: withdrawalFee,
            requiredNFTs: requiredNFTs,
            requiredNFTLevels: requiredNFTLevels,
            requiredNFTTypes: requiredNFTTypes,
            description: description,
            minStakingDuration: minStakingDuration,
            maxStakingDuration: maxStakingDuration
        });
        
        emit NFTMiningTierCreated(
            tierName,
            minStake,
            maxStake,
            rewardMultiplier,
            bonusPercentage,
            maxStakers,
            description
        );
    }
    
    function updateNFTMiningTier(
        string memory tierName,
        uint256 minStake,
        uint256 maxStake,
        uint256 rewardMultiplier,
        uint256 bonusPercentage,
        uint256 maxStakers,
        uint256 lockupPeriod,
        uint256 performanceFee,
        uint256 withdrawalFee
    ) external onlyOwner {
        require(bytes(tierName).length > 0, "Tier name cannot be empty");
        require(nftMiningTiers[tierName].tierName.length > 0, "Tier not found");
        require(minStake <= maxStake, "Invalid stake limits");
        require(rewardMultiplier >= 1000, "Reward multiplier too low");
        require(bonusPercentage <= 10000, "Bonus percentage too high");
        require(maxStakers > 0, "Max stakers must be greater than 0");
        require(lockupPeriod > 0, "Lockup period must be greater than 0");
        require(performanceFee <= 10000, "Performance fee too high");
        require(withdrawalFee <= 10000, "Withdrawal fee too high");
        
        NFTMiningTier storage tier = nftMiningTiers[tierName];
        tier.minStake = minStake;
        tier.maxStake = maxStake;
        tier.rewardMultiplier = rewardMultiplier;
        tier.bonusPercentage = bonusPercentage;
        tier.maxStakers = maxStakers;
        tier.lockupPeriod = lockupPeriod;
        tier.performanceFee = performanceFee;
        tier.withdrawalFee = withdrawalFee;
        
        emit NFTMiningTierUpdated(
            tierName,
            minStake,
            maxStake,
            rewardMultiplier,
            bonusPercentage
        );
    }
    
    function setNFTMiningConfig(
        address nftContract,
        string[] memory allowedTiers,
        uint256 minStakeAmount,
        uint256 maxStakeAmount,
        uint256 minStakingDuration,
        uint256 maxStakingDuration,
        uint256 performanceFee,
        uint256 withdrawalFee,
        uint256[] memory requiredNFTTypes,
        uint256[] memory requiredNFTLevels,
        uint256[] memory requiredNFTCollections,
        uint256[] memory requiredNFTRarities,
        bool enabled,
        uint256 maxStakersPerNFT,
        uint256 maxStakersTotal
    ) external onlyOwner {
        require(nftContract != address(0), "Invalid NFT contract");
        require(minStakeAmount <= maxStakeAmount, "Invalid stake limits");
        require(minStakingDuration <= maxStakingDuration, "Invalid staking duration limits");
        require(performanceFee <= 10000, "Performance fee too high");
        require(withdrawalFee <= 10000, "Withdrawal fee too high");
        require(maxStakersPerNFT > 0, "Max stakers per NFT must be greater than 0");
        require(maxStakersTotal > 0, "Max stakers total must be greater than 0");
        
        nftMiningConfigs[nftContract] = NFTMiningConfig({
            nftContract: nftContract,
            allowedTiers: allowedTiers,
            minStakeAmount: minStakeAmount,
            maxStakeAmount: maxStakeAmount,
            minStakingDuration: minStakingDuration,
            maxStakingDuration: maxStakingDuration,
            performanceFee: performanceFee,
            withdrawalFee: withdrawalFee,
            requiredNFTTypes: requiredNFTTypes,
            requiredNFTLevels: requiredNFTLevels,
            requiredNFTCollections: requiredNFTCollections,
            requiredNFTRarities: requiredNFTRarities,
            enabled: enabled,
            maxStakersPerNFT: maxStakersPerNFT,
            maxStakersTotal: maxStakersTotal,
            lastUpdate: block.timestamp
        });
        
        emit NFTMiningConfigUpdated(
            nftContract,
            minStakeAmount,
            maxStakeAmount,
            performanceFee,
            withdrawalFee,
            enabled
        );
    }
    
    function startNFTMining(
        address nftContract,
        uint256 tokenId,
        string memory miningTier,
        uint256 miningPower,
        uint256 miningDuration,
        uint256[] memory nftTokenIds,
        uint256[] memory nftLevels,
        uint256[] memory nftTypes
    ) external {
        require(nftMiningConfigs[nftContract].enabled, "NFT mining not enabled");
        require(nftMiningTiers[miningTier].tierName.length > 0, "Invalid mining tier");
        require(nftMiningTiers[miningTier].enabled, "Mining tier not enabled");
        require(miningPower > 0, "Mining power must be greater than 0");
        require(miningDuration > 0, "Mining duration must be greater than 0");
        require(nftTokenIds.length == nftLevels.length, "Array length mismatch");
        require(nftTokenIds.length == nftTypes.length, "Array length mismatch");
        
        // Проверка владельца NFT
        require(ERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not NFT owner");
        
        // Проверка тайера
        NFTMiningTier storage tier = nftMiningTiers[miningTier];
        require(tier.currentStakers < tier.maxStakers, "Tier full");
        
        // Проверка конфига
        NFTMiningConfig storage config = nftMiningConfigs[nftContract];
        require(miningDuration >= config.minStakingDuration, "Mining duration too short");
        require(miningDuration <= config.maxStakingDuration, "Mining duration too long");
        
        // Проверка NFT требований
        if (tier.requiredNFTs.length > 0) {
            // Проверка наличия требуемых NFT
        }
        
        // Проверка количества стейкеров
        require(nftStakeCounts[nftContract][tokenId] < config.maxStakersPerNFT, "NFT stake limit reached");
        require(nftMiningStats[nftContract].totalStakers < config.maxStakersTotal, "Total stake limit reached");
        
        // Создание позиции майнинга
        uint256 positionId = uint256(keccak256(abi.encodePacked(nftContract, tokenId, block.timestamp)));
        
        nftMiningPositions[nftContract][tokenId] = NFTMiningPosition({
            tokenId: tokenId,
            staker: msg.sender,
            nftContract: nftContract,
            stakeTime: block.timestamp,
            miningDuration: miningDuration,
            isMining: true,
            miningTier: miningTier,
            rewardMultiplier: tier.rewardMultiplier,
            miningPower: miningPower,
            lastRewardTime: block.timestamp,
            totalRewardsEarned: 0,
            stakedAmount: 0,
            dailyStake: 0,
            lastDailyReset: block.timestamp,
            nftTokenIds: nftTokenIds,
            nftLevels: nftLevels,
            nftTypes: nftTypes,
            nftBonus: 0,
            compoundCount: 0,
            rewardHistory: new uint256[](0),
            nftStakeHistory: new uint256[](0),
            isVerified: new mapping(address => bool),
            verificationLevel: 0,
            lastVerificationTime: 0,
            stakeHistory: new uint256[](0)
        });
        
        // Обновить статистику
        tier.currentStakers++;
        nftMiningStats[nftContract].totalNFTsStaked++;
        nftMiningStats[nftContract].totalStakers++;
        nftMiningStats[nftContract].totalValueLocked = nftMiningStats[nftContract].totalValueLocked.add(miningPower);
        nftMiningStats[nftContract].averageMiningPower = nftMiningStats[nftContract].averageMiningPower.add(miningPower);
        nftMiningStats[nftContract].tierStats[miningTier]++;
        nftStakeCounts[nftContract][tokenId]++;
        
        // Добавить в историю пользователя
        userNFTMiningPositions[msg.sender].push(tokenId);
        
        // Передача NFT в контракт
        ERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);
        
        // Обновить историю стейкинга
        nftMiningPositions[nftContract][tokenId].stakeHistory.push(block.timestamp);
        
        emit NFTMiningPositionStarted(
            msg.sender,
            nftContract,
            tokenId,
            miningTier,
            miningPower,
            block.timestamp,
            miningDuration,
            nftTokenIds
        );
    }
    
    function endNFTMining(
        address nftContract,
        uint256 tokenId
    ) external {
        NFTMiningPosition storage position = nftMiningPositions[nftContract][tokenId];
        require(position.isMining, "NFT not mining");
        require(position.staker == msg.sender, "Not staker");
        require(block.timestamp >= position.stakeTime + position.miningDuration, "Mining period not ended");
        
        // Расчет наград
        uint256 rewards = calculateNFTMiningRewards(nftContract, tokenId);
        
        // Применить комиссию
        uint256 feeAmount = rewards.mul(position.performanceFee).div(10000);
        uint256 amountAfterFee = rewards.sub(feeAmount);
        
        // Обновить статистику
        nftMiningStats[nftContract].totalRewardsDistributed = nftMiningStats[nftContract].totalRewardsDistributed.add(amountAfterFee);
        nftMiningStats[nftContract].stakerRewards[msg.sender] = nftMiningStats[nftContract].stakerRewards[msg.sender].add(amountAfterFee);
        nftMiningStats[nftContract].stakerRewards[msg.sender] = nftMiningStats[nftContract].stakerRewards[msg.sender].add(amountAfterFee);
        
        // Возврат NFT пользователю
        ERC721(nftContract).transferFrom(address(this), msg.sender, tokenId);
        
        // Передача награды
        if (amountAfterFee > 0) {
            // Передача награды (в реальной реализации токены)
        }
        
        // Деактивировать стейкинг
        position.isMining = false;
        position.totalRewardsEarned = position.totalRewardsEarned.add(amountAfterFee);
        position.lastRewardTime = block.timestamp;
        
        // Обновить историю наград
        position.rewardHistory.push(amountAfterFee);
        
        emit NFTMiningPositionEnded(
            msg.sender,
            nftContract,
            tokenId,
            amountAfterFee,
            block.timestamp,
            position.nftBonus,
            position.rewardMultiplier
        );
    }
    
    function claimNFTMiningRewards(
        address nftContract,
        uint256 tokenId
    ) external {
        NFTMiningPosition storage position = nftMiningPositions[nftContract][tokenId];
        require(position.isMining, "NFT not mining");
        require(position.staker == msg.sender, "Not staker");
        
        // Расчет наград
        uint256 rewards = calculateNFTMiningRewards(nftContract, tokenId);
        require(rewards > 0, "No rewards to claim");
        
        // Обновить позицию
        position.pendingRewards = position.pendingRewards.add(rewards);
        position.rewardDebt = position.rewardDebt.add(rewards);
        position.totalRewardsEarned = position.totalRewardsEarned.add(rewards);
        position.lastRewardTime = block.timestamp;
        
        // Передача награды
        if (rewards > 0) {
            // Передача награды (в реальной реализации токены)
        }
        
        // Обновить историю наград
        position.rewardHistory.push(rewards);
        
        emit NFTMiningRewardsClaimed(
            msg.sender,
            nftContract,
            tokenId,
            rewards,
            block.timestamp,
            "claimed"
        );
    }
    
    function calculateNFTMiningRewards(
        address nftContract,
        uint256 tokenId
    ) internal view returns (uint256) {
        NFTMiningPosition storage position = nftMiningPositions[nftContract][tokenId];
        if (!position.isMining) return 0;
        
        // Простая формула награды
        uint256 timeElapsed = block.timestamp.sub(position.lastRewardTime);
        uint256 baseReward = position.miningPower.mul(position.rewardMultiplier).div(10000);
        uint256 timeBonus = timeElapsed.div(3600).mul(100000000000000000); // 0.1 ETH за час
        uint256 nftBonus = position.nftBonus;
        uint256 tierBonus = position.rewardMultiplier;
        
        uint256 totalReward = baseReward.add(timeBonus).add(nftBonus).add(tierBonus);
        
        return totalReward;
    }
    
    function verifyNFTMining(
        address nftContract,
        uint256 tokenId,
        uint256 verificationLevel,
        string memory verificationMethod,
        uint256[] memory nftAttributes,
        uint256[] memory nftTraits
    ) external {
        NFTMiningPosition storage position = nftMiningPositions[nftContract][tokenId];
        require(position.isMining, "NFT not mining");
        require(position.staker == msg.sender, "Not staker");
        require(verificationLevel <= 10000, "Verification level too high");
        
        // Создать верификацию
        nftMiningVerifications[nftContract][tokenId] = NFTMiningVerification({
            staker: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            verificationTime: block.timestamp,
            verificationLevel: verificationLevel,
            verified: true,
            verificationMethod: verificationMethod,
            nftAttributes: nftAttributes,
            nftTraits: nftTraits,
            nftMetadata: new uint256[](0)
        });
        
        // Обновить бонусы
        position.verificationLevel = verificationLevel;
        position.lastVerificationTime = block.timestamp;
        position.nftBonus = verificationLevel.mul(100000000000000000); // 0.1 ETH за уровень
        
        // Обновить статистику
        nftMiningStats[nftContract].successRate = nftMiningStats[nftContract].successRate.add(verificationLevel);
        
        emit NFTMiningVerified(
            msg.sender,
            nftContract,
            tokenId,
            verificationLevel,
            block.timestamp,
            true
        );
    }
    
    function compoundNFTMiningRewards(
        address nftContract,
        uint256 tokenId
    ) external {
        NFTMiningPosition storage position = nftMiningPositions[nftContract][tokenId];
        require(position.isMining, "NFT not mining");
        require(position.staker == msg.sender, "Not staker");
        
        // Расчет наград
        uint256 rewards = calculateNFTMiningRewards(nftContract, tokenId);
        require(rewards > 0, "No rewards to compound");
        
        // Обновить позицию
        position.compoundCount++;
        position.rewardDebt = position.rewardDebt.add(rewards);
        position.totalRewardsEarned = position.totalRewardsEarned.add(rewards);
        position
