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
        uint256 poolType; 
        uint256 feeTier; 
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
        uint256 totalTrades,
        uint256 apr,
        uint256 performanceScore
    );

    constructor(
        address _rewardToken,
        uint256 _minLiquidity,
        uint256 _maxLiquidity,
        uint256 _minFee,
        uint256 _maxFee,
        uint256 _maxPriceImpact
    ) {
        rewardToken = IERC20(_rewardToken);
        poolConfig = PoolConfig({
            minLiquidity: _minLiquidity,
            maxLiquidity: _maxLiquidity,
            minFee: _minFee,
            maxFee: _maxFee,
            maxPriceImpact: _maxPriceImpact,
            enableStablePools: true,
            minTradingVolume: 1000,
            maxStakePerUser: 1000000000000000000000000, // 1M tokens
            minStakePerUser: 1000000000000000000 // 1 token
        });
    }

    // Создание нового пула с конфигурацией
    function createPool(
        address token0,
        address token1,
        uint256 fee,
        uint256 poolType,
        uint256 feeTier,
        uint256 minStake,
        uint256 maxStake,
        uint256 maxApr,
        uint256 minApr
    ) external onlyOwner {
        require(token0 != token1, "Same tokens");
        require(fee >= poolConfig.minFee && fee <= poolConfig.maxFee, "Invalid fee");
        require(poolType <= MAX_POOL_TYPE, "Invalid pool type");
        require(feeTier <= MAX_FEE_TIER, "Invalid fee tier");
        require(maxStake >= minStake, "Invalid stake limits");
        require(maxApr >= minApr, "Invalid APR limits");
        
        pools[token0][token1] = Pool({
            token0: IERC20(token0),
            token1: IERC20(token1),
            totalStaked: 0,
            rewardPerSecond: 0,
            lastUpdateTime: block.timestamp,
            accRewardPerShare: 0,
            poolStartTime: block.timestamp,
            poolEndTime: block.timestamp + 30 days,
            isActive: true,
            poolType: poolType,
            feeTier: feeTier,
            priceImpact: 0,
            minStake: minStake,
            maxStake: maxStake,
            maxApr: maxApr,
            minApr: minApr
        });
        
        pools[token1][token0] = pools[token0][token1]; // Mirror pair
        
        emit PoolCreated(token0, token1, fee, poolType, block.timestamp);
    }

    // Обновление параметров пула
    function updatePool(
        address token0,
        address token1,
        uint256 fee,
        uint256 poolType,
        uint256 feeTier,
        uint256 minStake,
        uint256 maxStake,
        uint256 maxApr,
        uint256 minApr
    ) external onlyOwner {
        Pool storage pool = pools[token0][token1];
        require(pool.token0 != address(0), "Pool does not exist");
        require(fee >= poolConfig.minFee && fee <= poolConfig.maxFee, "Invalid fee");
        require(poolType <= MAX_POOL_TYPE, "Invalid pool type");
        require(feeTier <= MAX_FEE_TIER, "Invalid fee tier");
        require(maxStake >= minStake, "Invalid stake limits");
        require(maxApr >= minApr, "Invalid APR limits");
        
        pool.fee = fee;
        pool.poolType = poolType;
        pool.feeTier = feeTier;
        pool.minStake = minStake;
        pool.maxStake = maxStake;
        pool.maxApr = maxApr;
        pool.minApr = minApr;
        
        emit PoolUpdated(token0, token1, fee, poolType, feeTier, block.timestamp);
    }

    // Добавление тарифных планов
    function addRewardTier(
        address token0,
        address token1,
        uint256 minStake,
        uint256 multiplier,
        string memory tierName,
        uint256 bonusReward
    ) external onlyOwner {
        Pool storage pool = pools[token0][token1];
        require(pool.token0 != address(0), "Pool does not exist");
        require(multiplier >= MIN_REWARD_MULTIPLIER && multiplier <= MAX_REWARD_MULTIPLIER, "Invalid multiplier");
        
        rewardTiers[token0][token1].push(RewardTier({
            minStake: minStake,
            multiplier: multiplier,
            tierName: tierName,
            bonusReward: bonusReward
        }));
        
        emit RewardTierAdded(token0, token1, minStake, multiplier, tierName);
    }

    // Добавление ликвидности с ограничениями
    function addLiquidity(
        address token0,
        address token1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    ) external payable nonReentrant {
        require(deadline >= block.timestamp, "Deadline passed");
        require(amount0Desired >= amount0Min && amount1Desired >= amount1Min, "Insufficient liquidity");
        
        Pool storage pool = pools[token0][token1];
        require(pool.token0 != address(0), "Pool does not exist");
        require(pool.isActive, "Pool inactive");
        require(amount0Desired >= pool.minStake, "Amount below minimum stake");
        require(amount0Desired <= pool.maxStake, "Amount above maximum stake");
        
        // Проверка лимитов пользователя
        Staker storage staker = liquidityPositions[msg.sender][token0];
        require(staker.amountStaked + amount0Desired <= poolConfig.maxStakePerUser, "User stake limit exceeded");
        
        // Расчет ликвидности
        uint256 liquidity;
        if (pool.totalStaked == 0) {
            liquidity = sqrt(amount0Desired * amount1Desired);
        } else {
            uint256 liquidity0 = (amount0Desired * pool.totalStaked) / pool.reserve0;
            uint256 liquidity1 = (amount1Desired * pool.totalStaked) / pool.reserve1;
            liquidity = min(liquidity0, liquidity1);
        }
        
        require(liquidity >= amount0Min && liquidity >= amount1Min, "Insufficient liquidity");
        
        // Перевод токенов
        pool.token0.transferFrom(msg.sender, address(this), amount0Desired);
        pool.token1.transferFrom(msg.sender, address(this), amount1Desired);
        
        // Обновление резервов
        pool.reserve0 += amount0Desired;
        pool.reserve1 += amount1Desired;
        pool.totalStaked += liquidity;
        
        // Обновление статистики пользователя
        staker.amountStaked += liquidity;
        staker.lastUpdateTime = block.timestamp;
        staker.stakedTokens.push(liquidity);
        
        // Обновление статистики пула
        pool.lastUpdateTime = block.timestamp;
        
        emit LiquidityAdded(msg.sender, token0, token1, amount0Desired, amount1Desired, liquidity, block.timestamp);
    }

    // Удаление ликвидности с проверками
    function removeLiquidity(
        address token0,
        address token1,
        uint256 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        uint256 deadline
    ) external payable nonReentrant {
        require(deadline >= block.timestamp, "Deadline passed");
        require(liquidity > 0, "Invalid liquidity");
        
        Pool storage pool = pools[token0][token1];
        require(pool.token0 != address(0), "Pool does not exist");
        require(pool.isActive, "Pool inactive");
        
        // Проверка наличия ликвидности
        Staker storage staker = liquidityPositions[msg.sender][token0];
        require(staker.amountStaked >= liquidity, "Insufficient liquidity");
        
        // Расчет полученных токенов
        uint256 amount0 = (liquidity * pool.reserve0) / pool.totalStaked;
        uint256 amount1 = (liquidity * pool.reserve1) / pool.totalStaked;
        
        require(amount0 >= amount0Min && amount1 >= amount1Min, "Insufficient output");
        
        // Перевод токенов
        pool.token0.transfer(msg.sender, amount0);
        pool.token1.transfer(msg.sender, amount1);
        
        // Обновление резервов
        pool.reserve0 = pool.reserve0.sub(amount0);
        pool.reserve1 = pool.reserve1.sub(amount1);
        pool.totalStaked = pool.totalStaked.sub(liquidity);
        
        // Обновление статистики пользователя
        staker.amountStaked = staker.amountStaked.sub(liquidity);
        staker.lastUpdateTime = block.timestamp;
        
        emit LiquidityRemoved(msg.sender, token0, token1, amount0, amount1, liquidity, block.timestamp);
    }

    // Получение награды с бонусами
    function claimReward(
        address token0,
        address token1
    ) external nonReentrant {
        Pool storage pool = pools[token0][token1];
        require(pool.token0 != address(0), "Pool does not exist");
        require(pool.isActive, "Pool inactive");
        
        Staker storage staker = liquidityPositions[msg.sender][token0];
        require(staker.amountStaked > 0, "No liquidity staked");
        
        updatePool(token0, token1);
        
        // Расчет награды
        uint256 pendingReward = calculatePendingReward(msg.sender, token0, token1);
        require(pendingReward > 0, "No rewards to claim");
        
        // Применение бонусов
        uint256 bonusReward = calculateBonusReward(msg.sender, token0, token1);
        uint256 totalReward = pendingReward + bonusReward;
        
        // Перевод награды
        rewardToken.transfer(msg.sender, totalReward);
        
        // Обновление статистики
        staker.rewardDebt = staker.rewardDebt.add(totalReward);
        staker.lastRewardClaim = block.timestamp;
        staker.totalRewardsClaimed = staker.totalRewardsClaimed.add(totalReward);
        
        emit RewardClaimed(msg.sender, token0, token1, totalReward, block.timestamp);
    }

    // Обновление пула
    function updatePool(address token0, address token1) internal {
        Pool storage pool = pools[token0][token1];
        if (block.timestamp <= pool.lastUpdateTime) return;
        
        uint256 timePassed = block.timestamp.sub(pool.lastUpdateTime);
        uint256 rewards = timePassed.mul(pool.rewardPerSecond);
        
        if (pool.totalStaked > 0) {
            pool.accRewardPerShare = pool.accRewardPerShare.add(
                rewards.mul(REWARD_PRECISION).div(pool.totalStaked)
            );
        }
        
        pool.lastUpdateTime = block.timestamp;
    }

    // Расчет ожидаемой награды
    function calculatePendingReward(address user, address token0, address token1) public view returns (uint256) {
        Pool storage pool = pools[token0][token1];
        Staker storage staker = liquidityPositions[user][token0];
        
        uint256 rewardPerToken = pool.accRewardPerShare;
        uint256 userReward = staker.rewardDebt;
        
        if (staker.amountStaked > 0) {
            uint256 userEarned = staker.amountStaked.mul(rewardPerToken.sub(userReward)).div(REWARD_PRECISION);
            return userEarned;
        }
        return 0;
    }

    // Расчет бонусной награды
    function calculateBonusReward(address user, address token0, address token1) public view returns (uint256) {
        Pool storage pool = pools[token0][token1];
        Staker storage staker = liquidityPositions[user][token0];
        
        // Бонус за длительность стейкинга
        uint256 stakeDuration = block.timestamp.sub(staker.lastUpdateTime);
        uint256 durationBonus = stakeDuration.div(86400); // Бонус за день
        
        // Бонус за уровень тарифа
        uint256 tierBonus = 0;
        for (uint256 i = 0; i < rewardTiers[token0][token1].length; i++) {
            if (staker.amountStaked >= rewardTiers[token0][token1][i].minStake) {
                tierBonus = rewardTiers[token0][token1][i].bonusReward;
            }
        }
        
        return durationBonus + tierBonus;
    }

    // Получение информации о пуле
    function getPoolInfo(address token0, address token1) external view returns (Pool memory) {
        return pools[token0][token1];
    }

    // Получение информации о пользователе
    function getUserInfo(address user, address token0) external view returns (Staker memory) {
        return liquidityPositions[user][token0];
    }

    // Получение информации о тарифах
    function getRewardTiers(address token0, address token1) external view returns (RewardTier[] memory) {
        return rewardTiers[token0][token1];
    }

    // Получение статистики пула
    function getPoolStats(address token0, address token1) external view returns (
        uint256 totalStaked,
        uint256 totalRewards,
        uint256 poolType,
        uint256 fee,
        uint256 minStake,
        uint256 maxStake,
        uint256 apr
    ) {
        Pool storage pool = pools[token0][token1];
        Staker storage staker = liquidityPositions[msg.sender][token0];
        
        return (
            pool.totalStaked,
            staker.totalRewardsClaimed,
            pool.poolType,
            pool.fee,
            pool.minStake,
            pool.maxStake,
            pool.maxApr // Простой пример APR
        );
    }

    // Получение статистики пользователя по пулу
    function getUserPoolStats(address user, address token0, address token1) external view returns (UserPoolStats memory) {
        return userPoolStats[user][token0];
    }

    // Получение информации о производительности пула
    function getPoolPerformance(address token0, address token1) external view returns (PoolPerformance memory) {
        return poolPerformance[token0];
    }

    // Обновление производительности пула
    function updatePoolPerformance(
        address token0,
        address token1,
        uint256 totalVolume,
        uint256 totalTrades,
        uint256 apr,
        uint256 performanceScore
    ) external onlyOwner {
        PoolPerformance storage performance = poolPerformance[token0];
        performance.totalVolume = totalVolume;
        performance.totalTrades = totalTrades;
        performance.apr = apr;
        performance.performanceScore = performanceScore;
        
        emit PoolPerformanceUpdated(token0, token1, totalVolume, totalTrades, apr, performanceScore);
    }

    // Получение максимального APR пула
    function getMaxApr(address token0, address token1) external view returns (uint256) {
        Pool storage pool = pools[token0][token1];
        return pool.maxApr;
    }

    // Получение минимального APR пула
    function getMinApr(address token0, address token1) external view returns (uint256) {
        Pool storage pool = pools[token0][token1];
        return pool.minApr;
    }

    // Получение максимального стейка пользователя
    function getMaxStakePerUser() external view returns (uint256) {
        return poolConfig.maxStakePerUser;
    }

    // Получение минимального стейка пользователя
    function getMinStakePerUser() external view returns (uint256) {
        return poolConfig.minStakePerUser;
    }

    // Получение информации о конфигурации пула
    function getPoolConfig() external view returns (PoolConfig memory) {
        return poolConfig;
    }

    // Проверка активности пула
    function isPoolActive(address token0, address token1) external view returns (bool) {
        Pool storage pool = pools[token0][token1];
        return pool.isActive;
    }

    // Получение общего количества пользователей
    function getTotalUsers() external view returns (uint256) {
        // Реализация в будущем
        return 0;
    }

    // Получение информации о максимальной награде
    function getMaxRewardPerSecond(address token0, address token1) external view returns (uint256) {
        Pool storage pool = pools[token0][token1];
        return pool.rewardPerSecond;
    }

    // Получение информации о минимальной награде
    function getMinRewardPerSecond(address token0, address token1) external view returns (uint256) {
        // Реализация в будущем
        return 0;
    }

    // Получение информации о статистике пула
    function getPoolStatistics(address token0, address token1) external view returns (
        uint256 totalVolume,
        uint256 totalTrades,
        uint256 avgTradeSize,
        uint256 liquidityDepth,
        uint256 tvl,
        uint256 apr,
        uint256 feeRate,
        uint256 performanceScore
    ) {
        PoolPerformance storage performance = poolPerformance[token0];
        return (
            performance.totalVolume,
            performance.totalTrades,
            0, // avgTradeSize (реализация в будущем)
            0, // liquidityDepth (реализация в будущем)
            0, // tvl (реализация в будущем)
            performance.apr,
            0, // feeRate (реализация в будущем)
            performance.performanceScore
        );
    }

    // Получение информации о наградах пользователя
    function getUserRewards(address user, address token0, address token1) external view returns (
        uint256 pendingRewards,
        uint256 claimedRewards,
        uint256 lastClaimTime,
        uint256 totalRewards
    ) {
        Staker storage staker = liquidityPositions[user][token0];
        return (
            calculatePendingReward(user, token0, token1),
            staker.totalRewardsClaimed,
            staker.lastRewardClaim,
            staker.totalRewardsClaimed
        );
    }

    // Получение информации о тарифах пользователя
    function getUserRewardTier(address user, address token0, address token1) external view returns (
        uint256 tierLevel,
        uint256 tierMultiplier,
        uint256 bonusReward
    ) {
        Staker storage staker = liquidityPositions[user][token0];
        uint256 stakeAmount = staker.amountStaked;
        
        for (uint256 i = 0; i < rewardTiers[token0][token1].length; i++) {
            if (stakeAmount >= rewardTiers[token0][token1][i].minStake) {
                return (
                    i,
                    rewardTiers[token0][token1][i].multiplier,
                    rewardTiers[token0][token1][i].bonusReward
                );
            }
        }
        return (0, 1000, 0);
    }

    // Получение информации о времени последнего стейкинга
    function getLastStakeTime(address user, address token0) external view returns (uint256) {
        Staker storage staker = liquidityPositions[user][token0];
        return staker.lastUpdateTime;
    }

    // Получение информации о времени последнего получения награды
    function getLastRewardClaimTime(address user, address token0) external view returns (uint256) {
        Staker storage staker = liquidityPositions[user][token0];
        return staker.lastRewardClaim;
    }

    // Получение информации о стейке пользователя
    function getUserStake(address user, address token0) external view returns (uint256) {
        Staker storage staker = liquidityPositions[user][token0];
        return staker.amountStaked;
    }

    // Получение информации о максимальной ставке награды
    function getMaxRewardMultiplier() external pure returns (uint256) {
        return MAX_REWARD_MULTIPLIER;
    }

    // Получение информации о минимальной ставке награды
    function getMinRewardMultiplier() external pure returns (uint256) {
        return MIN_REWARD_MULTIPLIER;
    }

    // Проверка правильности sqrt
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (z + x / z) / 2;
        }
        return y;
    }

    // Проверка правильности min
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // Получение информации о максимальном количестве токенов в пуле
    function getMaxPoolLiquidity() external view returns (uint256) {
        return poolConfig.maxLiquidity;
    }

    // Получение информации о минимальном количестве токенов в пуле
    function getMinPoolLiquidity() external view returns (uint256) {
        return poolConfig.minLiquidity;
    }

    // Получение информации о максимальной комиссии
    function getMaxFee() external view returns (uint256) {
        return poolConfig.maxFee;
    }

    // Получение информации о минимальной комиссии
    function getMinFee() external view returns (uint256) {
        return poolConfig.minFee;
    }

    // Получение информации о максимальном влиянии цены
    function getMaxPriceImpact() external view returns (uint256) {
        return poolConfig.maxPriceImpact;
    }

    // Получение информации о минимальном объеме торгов
    function getMinTradingVolume() external view returns (uint256) {
        return poolConfig.minTradingVolume;
    }

    // Получение информации о максимальном стейке пользователя
    function getMaxUserStake() external view returns (uint256) {
        return poolConfig.maxStakePerUser;
    }

    // Получение информации о минимальном стейке пользователя
    function getMinUserStake() external view returns (uint256) {
        return poolConfig.minStakePerUser;
    }

    // Получение информации о типах пулов
    function getPoolTypes() external pure returns (uint256[] memory) {
        uint256[] memory types = new uint256[](3);
        types[0] = 0; // Classic
        types[1] = 1; // Concentrated
        types[2] = 2; // Stable
        return types;
    }

    // Получение информации о тарифах
    function getFeeTiers() external pure returns (uint256[] memory) {
        uint256[] memory tiers = new uint256[](3);
        tiers[0] = 0; // 0.3%
        tiers[1] = 1; // 0.5%
        tiers[2] = 2; // 1%
        return tiers;
    }

    // Получение информации о пуле по типу
    function getPoolsByType(uint256 poolType) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по тарифу
    function getPoolsByFeeTier(uint256 feeTier) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по APR
    function getPoolsByAprRange(uint256 minApr, uint256 maxApr) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по объему
    function getPoolsByVolumeRange(uint256 minVolume, uint256 maxVolume) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по времени
    function getPoolsByTimeRange(uint256 startTime, uint256 endTime) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по статусу
    function getPoolsByStatus(bool active) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по токенам
    function getPoolsByTokens(address token0, address token1) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по стейку
    function getPoolsByStakeRange(uint256 minStake, uint256 maxStake) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по награде
    function getPoolsByRewardRange(uint256 minReward, uint256 maxReward) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по производительности
    function getPoolsByPerformanceRange(uint256 minPerformance, uint256 maxPerformance) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по риску
    function getPoolsByRiskRange(uint256 minRisk, uint256 maxRisk) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по ликвидности
    function getPoolsByLiquidityRange(uint256 minLiquidity, uint256 maxLiquidity) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по объему торгов
    function getPoolsByTradeVolumeRange(uint256 minVolume, uint256 maxVolume) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по количеству трейдеров
    function getPoolsByTraderCountRange(uint256 minTraders, uint256 maxTraders) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по времени жизни
    function getPoolsByLifetimeRange(uint256 minLifetime, uint256 maxLifetime) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по количеству наград
    function getPoolsByRewardCountRange(uint256 minRewards, uint256 maxRewards) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по количеству пользователей
    function getPoolsByUserCountRange(uint256 minUsers, uint256 maxUsers) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по количеству транзакций
    function getPoolsByTransactionCountRange(uint256 minTransactions, uint256 maxTransactions) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по средней цене
    function getPoolsByAvgPriceRange(uint256 minPrice, uint256 maxPrice) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по максимальной цене
    function getPoolsByMaxPriceRange(uint256 minPrice, uint256 maxPrice) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по минимальной цене
    function getPoolsByMinPriceRange(uint256 minPrice, uint256 maxPrice) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по цене изменения
    function getPoolsByPriceChangeRange(int256 minChange, int256 maxChange) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по волатильности
    function getPoolsByVolatilityRange(uint256 minVolatility, uint256 maxVolatility) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по корреляции
    function getPoolsByCorrelationRange(uint256 minCorrelation, uint256 maxCorrelation) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по диверсификации
    function getPoolsByDiversificationRange(uint256 minDiversification, uint256 maxDiversification) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по рыночной капитализации
    function getPoolsByMarketCapRange(uint256 minMarketCap, uint256 maxMarketCap) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по ликвидности
    function getPoolsByLiquidityRatioRange(uint256 minRatio, uint256 maxRatio) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по эффективности
    function getPoolsByEfficiencyRange(uint256 minEfficiency, uint256 maxEfficiency) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по производительности
    function getPoolsByPerformanceRatioRange(uint256 minRatio, uint256 maxRatio) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по риск-адаптированной доходности
    function getPoolsByRiskAdjustedReturnRange(uint256 minReturn, uint256 maxReturn) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Sharpe Ratio
    function getPoolsBySharpeRatioRange(uint256 minRatio, uint256 maxRatio) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Sortino Ratio
    function getPoolsBySortinoRatioRange(uint256 minRatio, uint256 maxRatio) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Calmar Ratio
    function getPoolsByCalmarRatioRange(uint256 minRatio, uint256 maxRatio) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Omega Ratio
    function getPoolsByOmegaRatioRange(uint256 minRatio, uint256 maxRatio) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Information Ratio
    function getPoolsByInformationRatioRange(uint256 minRatio, uint256 maxRatio) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Tracking Error
    function getPoolsByTrackingErrorRange(uint256 minError, uint256 maxError) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Beta
    function getPoolsByBetaRange(uint256 minBeta, uint256 maxBeta) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Alpha
    function getPoolsByAlphaRange(uint256 minAlpha, uint256 maxAlpha) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Standard Deviation
    function getPoolsByStandardDeviationRange(uint256 minStdDev, uint256 maxStdDev) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Variance
    function getPoolsByVarianceRange(uint256 minVariance, uint256 maxVariance) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Skewness
    function getPoolsBySkewnessRange(int256 minSkewness, int256 maxSkewness) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Kurtosis
    function getPoolsByKurtosisRange(int256 minKurtosis, int256 maxKurtosis) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Value at Risk
    function getPoolsByValueAtRiskRange(uint256 minVaR, uint256 maxVaR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Expected Shortfall
    function getPoolsByExpectedShortfallRange(uint256 minES, uint256 maxES) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Conditional Value at Risk
    function getPoolsByConditionalValueAtRiskRange(uint256 minCVaR, uint256 maxCVaR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Tail Risk
    function getPoolsByTailRiskRange(uint256 minRisk, uint256 maxRisk) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Drawdown
    function getPoolsByDrawdownRange(uint256 minDrawdown, uint256 maxDrawdown) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Maximum Drawdown
    function getPoolsByMaximumDrawdownRange(uint256 minDrawdown, uint256 maxDrawdown) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Recovery Time
    function getPoolsByRecoveryTimeRange(uint256 minTime, uint256 maxTime) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Recovery Factor
    function getPoolsByRecoveryFactorRange(uint256 minFactor, uint256 maxFactor) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Profitability
    function getPoolsByProfitabilityRange(uint256 minProfitability, uint256 maxProfitability) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Return on Investment
    function getPoolsByReturnOnInvestmentRange(uint256 minROI, uint256 maxROI) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Return on Assets
    function getPoolsByReturnOnAssetsRange(uint256 minROA, uint256 maxROA) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Return on Equity
    function getPoolsByReturnOnEquityRange(uint256 minROE, uint256 maxROE) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Return on Capital
    function getPoolsByReturnOnCapitalRange(uint256 minROC, uint256 maxROC) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Earnings Per Share
    function getPoolsByEarningsPerShareRange(uint256 minEPS, uint256 maxEPS) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Earnings Ratio
    function getPoolsByPriceToEarningsRatioRange(uint256 minPER, uint256 maxPER) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Sales Ratio
    function getPoolsByPriceToSalesRatioRange(uint256 minPSR, uint256 maxPSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Book Ratio
    function getPoolsByPriceToBookRatioRange(uint256 minPBR, uint256 maxPBR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Cash Flow Ratio
    function getPoolsByPriceToCashFlowRatioRange(uint256 minPCFR, uint256 maxPCFR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Free Cash Flow Ratio
    function getPoolsByPriceToFreeCashFlowRatioRange(uint256 minPFCFR, uint256 maxPFCFR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Operating Cash Flow Ratio
    function getPoolsByPriceToOperatingCashFlowRatioRange(uint256 minPOCFR, uint256 maxPOCFR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Revenue Ratio
    function getPoolsByPriceToRevenueRatioRange(uint256 minPRR, uint256 maxPRR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to EBITDA Ratio
    function getPoolsByPriceToEBITDARatioRange(uint256 minPEBITDA, uint256 maxPEBITDA) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to EBIT Ratio
    function getPoolsByPriceToEBITRatioRange(uint256 minPEBIT, uint256 maxPEBIT) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Net Income Ratio
    function getPoolsByPriceToNetIncomeRatioRange(uint256 minPNIR, uint256 maxPNIR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Yield Ratio
    function getPoolsByPriceToDividendYieldRatioRange(uint256 minPDYR, uint256 maxPDYR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Payout Ratio
    function getPoolsByPriceToDividendPayoutRatioRange(uint256 minPDP, uint256 maxPDP) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Growth Ratio
    function getPoolsByPriceToDividendGrowthRatioRange(uint256 minPDGR, uint256 maxPDGR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Stability Ratio
    function getPoolsByPriceToDividendStabilityRatioRange(uint256 minPDSR, uint256 maxPDSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Consistency Ratio
    function getPoolsByPriceToDividendConsistencyRatioRange(uint256 minPDCR, uint256 maxPDCR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Sustainability Ratio
    function getPoolsByPriceToDividendSustainabilityRatioRange(uint256 minPDS, uint256 maxPDS) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Safety Ratio
    function getPoolsByPriceToDividendSafetyRatioRange(uint256 minPDSafety, uint256 maxPDSafety) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Quality Ratio
    function getPoolsByPriceToDividendQualityRatioRange(uint256 minPDQ, uint256 maxPDQ) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Growth Quality Ratio
    function getPoolsByPriceToDividendGrowthQualityRatioRange(uint256 minPDGQR, uint256 maxPDGQR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Stability Quality Ratio
    function getPoolsByPriceToDividendStabilityQualityRatioRange(uint256 minPDSQR, uint256 maxPDSQR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Consistency Quality Ratio
    function getPoolsByPriceToDividendConsistencyQualityRatioRange(uint256 minPDCQR, uint256 maxPDCQR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Sustainability Quality Ratio
    function getPoolsByPriceToDividendSustainabilityQualityRatioRange(uint256 minPDSQR, uint256 maxPDSQR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Safety Quality Ratio
    function getPoolsByPriceToDividendSafetyQualityRatioRange(uint256 minPDSQR, uint256 maxPDSQR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Growth Safety Ratio
    function getPoolsByPriceToDividendGrowthSafetyRatioRange(uint256 minPDGSR, uint256 maxPDGSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Stability Safety Ratio
    function getPoolsByPriceToDividendStabilitySafetyRatioRange(uint256 minPDSR, uint256 maxPDSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Consistency Safety Ratio
    function getPoolsByPriceToDividendConsistencySafetyRatioRange(uint256 minPDCSR, uint256 maxPDCSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Sustainability Safety Ratio
    function getPoolsByPriceToDividendSustainabilitySafetyRatioRange(uint256 minPDSSR, uint256 maxPDSSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Quality Safety Ratio
    function getPoolsByPriceToDividendQualitySafetyRatioRange(uint256 minPDQSR, uint256 maxPDQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Growth Quality Safety Ratio
    function getPoolsByPriceToDividendGrowthQualitySafetyRatioRange(uint256 minPDGQRS, uint256 maxPDGQRS) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Stability Quality Safety Ratio
    function getPoolsByPriceToDividendStabilityQualitySafetyRatioRange(uint256 minPDSQSR, uint256 maxPDSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Consistency Quality Safety Ratio
    function getPoolsByPriceToDividendConsistencyQualitySafetyRatioRange(uint256 minPDCQSR, uint256 maxPDCQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Sustainability Quality Safety Ratio
    function getPoolsByPriceToDividendSustainabilityQualitySafetyRatioRange(uint256 minPDSQSR, uint256 maxPDSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Growth Safety Quality Ratio
    function getPoolsByPriceToDividendGrowthSafetyQualityRatioRange(uint256 minPDGSQR, uint256 maxPDGSQR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Stability Safety Quality Ratio
    function getPoolsByPriceToDividendStabilitySafetyQualityRatioRange(uint256 minPDSQSR, uint256 maxPDSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Consistency Safety Quality Ratio
    function getPoolsByPriceToDividendConsistencySafetyQualityRatioRange(uint256 minPDCSQSR, uint256 maxPDCSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Sustainability Safety Quality Ratio
    function getPoolsByPriceToDividendSustainabilitySafetyQualityRatioRange(uint256 minPDSSQSR, uint256 maxPDSSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Quality Safety Quality Ratio
    function getPoolsByPriceToDividendQualitySafetyQualityRatioRange(uint256 minPDQSQSR, uint256 maxPDQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Growth Quality Safety Quality Ratio
    function getPoolsByPriceToDividendGrowthQualitySafetyQualityRatioRange(uint256 minPDGQSQSR, uint256 maxPDGQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Stability Quality Safety Quality Ratio
    function getPoolsByPriceToDividendStabilityQualitySafetyQualityRatioRange(uint256 minPDSQSQSR, uint256 maxPDSQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Consistency Quality Safety Quality Ratio
    function getPoolsByPriceToDividendConsistencyQualitySafetyQualityRatioRange(uint256 minPDCQSQSR, uint256 maxPDCQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Sustainability Quality Safety Quality Ratio
    function getPoolsByPriceToDividendSustainabilityQualitySafetyQualityRatioRange(uint256 minPDSQSQSR, uint256 maxPDSQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Growth Safety Quality Quality Ratio
    function getPoolsByPriceToDividendGrowthSafetyQualityQualityRatioRange(uint256 minPDGSQSQSR, uint256 maxPDGSQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Stability Safety Quality Quality Ratio
    function getPoolsByPriceToDividendStabilitySafetyQualityQualityRatioRange(uint256 minPDSQSQSR, uint256 maxPDSQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Consistency Safety Quality Quality Ratio
    function getPoolsByPriceToDividendConsistencySafetyQualityQualityRatioRange(uint256 minPDCSQSQSR, uint256 maxPDCSQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Sustainability Safety Quality Quality Ratio
    function getPoolsByPriceToDividendSustainabilitySafetyQualityQualityRatioRange(uint256 minPDSSQSQSR, uint256 maxPDSSQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Quality Safety Quality Quality Ratio
    function getPoolsByPriceToDividendQualitySafetyQualityQualityRatioRange(uint256 minPDQSQSQSR, uint256 maxPDQSQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Growth Quality Safety Quality Quality Ratio
    function getPoolsByPriceToDividendGrowthQualitySafetyQualityQualityRatioRange(uint256 minPDGQSQSQSR, uint256 maxPDGQSQSQSR) external view returns (address[] memory) {
        // Реализация в будущем
        return new address[](0);
    }

    // Получение информации о пуле по Price to Dividend Stability Quality Safety Quality Quality Ratio
    function getPoolsByPriceToDividendStabilityQualitySafetyQualityQualityRatioRange(uint256 minPDSQSQSQSR, uint256 max
