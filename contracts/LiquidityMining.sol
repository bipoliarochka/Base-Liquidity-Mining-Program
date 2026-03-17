// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LiquidityMining is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public lpToken; 
    IERC20 public rewardToken;

    uint256 public rewardPerSecond;
    uint256 public lastUpdateTime;
    uint256 public accRewardPerShare;
    uint256 public totalStaked;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }

    mapping(address => UserInfo) public users;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event RewardPerSecondUpdated(uint256 oldValue, uint256 newValue);
    event Recovered(address indexed token, address indexed to, uint256 amount);

    constructor(address _lpToken, address _rewardToken, uint256 _rewardPerSecond) Ownable(msg.sender) {
        lpToken = IERC20(_lpToken);
        rewardToken = IERC20(_rewardToken);
        rewardPerSecond = _rewardPerSecond;
        lastUpdateTime = block.timestamp;
    }

    function _updatePool() internal {
        if (block.timestamp <= lastUpdateTime) return;
        if (totalStaked == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }

        uint256 elapsed = block.timestamp - lastUpdateTime;
        uint256 reward = elapsed * rewardPerSecond;

        accRewardPerShare += (reward * 1e12) / totalStaked;
        lastUpdateTime = block.timestamp;
    }

    function deposit(uint256 amount) external nonReentrant {
        UserInfo storage user = users[msg.sender];

        _updatePool();

        if (user.amount > 0) {
            uint256 pending = (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt;
            if (pending > 0) {
                rewardToken.safeTransfer(msg.sender, pending);
                emit Claim(msg.sender, pending);
            }
        }

        lpToken.safeTransferFrom(msg.sender, address(this), amount);

        user.amount += amount;
        totalStaked += amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        UserInfo storage user = users[msg.sender];
        require(user.amount >= amount, "too much");

        _updatePool();

        uint256 pending = (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt;
        if (pending > 0) {
            rewardToken.safeTransfer(msg.sender, pending);
            emit Claim(msg.sender, pending);
        }

        user.amount -= amount;
        totalStaked -= amount;
        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;

        lpToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    function claim() external nonReentrant {
        UserInfo storage user = users[msg.sender];

        _updatePool();

        uint256 pending = (user.amount * accRewardPerShare) / 1e12 - user.rewardDebt;
        require(pending > 0, "no rewards");

        user.rewardDebt = (user.amount * accRewardPerShare) / 1e12;

        rewardToken.safeTransfer(msg.sender, pending);
        emit Claim(msg.sender, pending);
    }

    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = users[msg.sender];
        uint256 amount = user.amount;
        require(amount > 0, "zero");

        user.amount = 0;
        user.rewardDebt = 0;
        totalStaked -= amount;

        lpToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdraw(msg.sender, amount);
    }

    function setRewardPerSecond(uint256 newRate) external onlyOwner {
        _updatePool();
        uint256 oldValue = rewardPerSecond;
        rewardPerSecond = newRate;
        emit RewardPerSecondUpdated(oldValue, newRate);
    }

    function recoverERC20(address token, address to, uint256 amount) external onlyOwner {
        require(token != address(lpToken), "no lp");
        require(token != address(rewardToken), "no reward");
        require(to != address(0), "to=0");

        IERC20(token).safeTransfer(to, amount);
        emit Recovered(token, to, amount);
    }
}
