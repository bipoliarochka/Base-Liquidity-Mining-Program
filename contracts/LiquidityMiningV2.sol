// base-liquidity-mining/contracts/LiquidityMiningV2.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract LiquidityMiningV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;

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
        uint256 poolType; // 0 = classic, 1 = concentrated, 2 = stable
        uint256 feeTier; // 0 = 0.3%, 1 = 0.5%, 2 = 1%
        uint256 priceImpact;
        uint256 minStake;
        uint256 maxStake;
        uint256 maxApr;
        uint256 minApr;
    }

    struct Staker {
        uint256 amountStaked;
        uint256 rewardDebt;
        uint256 lastUpdateTime;
        uint256[] stakedTokens;
        uint256 totalFeesEarned;
        uint256 rewardDebt;
        uint256 lastRewardClaim;
        uint256 totalRewardsClaimed;
    }

    struct RewardTier {
        uint256 minStake;
        uint256 multiplier;
        string tierName;
        uint256 bonusReward;
    }

    struct PoolConfig {
        uint256 minLiquidity;
        uint256 maxLiquidity;
        uint256 minFee;
        uint256 maxFee;
        uint256 maxPriceImpact;
        bool enableStablePools;
        uint256 minTradingVolume;
        uint256 maxStakePerUser;
        uint256 minStakePerUser;
    }

    struct UserPoolStats {
        uint256 totalStaked;
        uint256 totalRewards;
        uint256 lastStakeTime;
        uint256 firstStakeTime;
        uint256 totalFees;
    }

    struct PoolPerformance {
        uint256 totalVolume;
        uint256 totalTrades;
        uint256 avgTradeSize;
        uint256 liquidityDepth;
        uint256 tvl;
        uint256 apr;
        uint256 feeRate;
        uint256 performanceScore;
    }

    mapping(address => mapping(address => Pool)) public pools;
    mapping(address => mapping(address => Staker)) public liquidityPositions;
    mapping(address => mapping(address => UserPoolStats)) public userPoolStats;
    mapping(address => RewardTier[]) public rewardTiers;
    mapping(address => PoolPerformance) public poolPerformance;
    
    PoolConfig public poolConfig;
    IERC20 public rewardToken;
    uint256 public constant REWARD_PRECISION = 1e18;
    uint256 public constant MAX_POOL_TYPE = 2;
    uint256 public constant MAX_FEE_TIER = 2;
    uint256 public constant MAX_REWARD_MULTIPLIER = 1000000;
    uint256 public constant MIN_REWARD_MULTIPLIER = 1000;
    
    // События
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        uint256 fee,
        uint256 poolType,
        uint256 timestamp
    );
    
    event LiquidityAdded(
        address indexed user,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidityMinted,
        uint256 timestamp
    );
    
    event LiquidityRemoved(
        address indexed user,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidityBurned,
        uint256 timestamp
    );
    
    event RewardClaimed(
        address indexed user,
        address indexed token0,
        address indexed token1,
        uint256 rewardAmount,
        uint256 timestamp
    );
    
    event PoolUpdated(
        address indexed token0,
        address indexed token1,
        uint256 fee,
        uint256 poolType,
        uint256 feeTier,
        uint256 timestamp
    );
    
    event RewardTierAdded(
        address indexed token0,
        address indexed token1,
        uint256 minStake,
        uint256 multiplier,
        string tierName
    );
    
    event PoolConfigUpdated(
        uint256 minLiquidity,
        uint256 maxLiquidity,
        uint256 minFee,
        uint256 maxFee,
        uint256 maxPriceImpact
    );
    
    event PoolPerformanceUpdated(
        address indexed token0,
        address indexed token1,
        uint256 totalVolume,
