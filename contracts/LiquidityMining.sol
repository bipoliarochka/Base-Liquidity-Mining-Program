// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidityMining is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable lpToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardPerSecond;
    uint256 public accRewardPerShare; // 1e12
    uint256 public lastUpdate;
    uint256 public totalStaked;

    struct User {
        uint256 amount;
        uint256 rewardDebt;
    }
    mapping(address => User) public users;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);

    // Improvement: recovery
    event Recovered(address indexed token, address indexed to, uint256 amount);

    constructor(address _lp, address _reward, uint256 _rewardPerSecond) Ownable(msg.sender) {
        require(_lp != address(0) && _reward != address(0), "zero");
        lpToken = IERC20(_lp);
        rewardToken = IERC20(_reward);
        rewardPerSecond = _rewardPerSecond;
        lastUpdate = block.timestamp;
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        _updatePool();

        User storage u = users[msg.sender];
        uint256 pending = _pending(u);
        if (pending > 0) {
            rewardToken.safeTransfer(msg.sender, pending);
            emit Claim(msg.sender, pending);
        }

        lpToken.safeTransferFrom(msg.sender, address(this), amount);
        u.amount += amount;
        totalStaked += amount;
        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;

        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        _updatePool();

        User storage u = users[msg.sender];
        require(u.amount >= amount, "insufficient");

        uint256 pending = _pending(u);
        if (pending > 0) {
            rewardToken.safeTransfer(msg.sender, pending);
            emit Claim(msg.sender, pending);
        }

        if (amount > 0) {
            u.amount -= amount;
            totalStaked -= amount;
            lpToken.safeTransfer(msg.sender, amount);
            emit Withdraw(msg.sender, amount);
        }

        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;
    }

    function claim() external nonReentrant {
        _updatePool();
        User storage u = users[msg.sender];

        uint256 pending = _pending(u);
        require(pending > 0, "nothing");

        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;

        rewardToken.safeTransfer(msg.sender, pending);
        emit Claim(msg.sender, pending);
    }

    function _updatePool() internal {
        if (block.timestamp <= lastUpdate) return;
        if (totalStaked == 0) { lastUpdate = block.timestamp; return; }

        uint256 dt = block.timestamp - lastUpdate;
        uint256 reward = dt * rewardPerSecond;

        accRewardPerShare += (reward * 1e12) / totalStaked;
        lastUpdate = block.timestamp;
    }

    function _pending(User storage u) internal view returns (uint256) {
        uint256 accrued = (u.amount * accRewardPerShare) / 1e12;
        if (accrued < u.rewardDebt) return 0;
        return accrued - u.rewardDebt;
    }

    // Improvement: recover stuck tokens (except core tokens)
    function recoverERC20(address token, address to, uint256 amount) external onlyOwner {
        require(token != address(lpToken), "no lp");
        require(token != address(rewardToken), "no reward");
        require(to != address(0), "to=0");
        IERC20(token).safeTransfer(to, amount);
        emit Recovered(token, to, amount);
    }
}
