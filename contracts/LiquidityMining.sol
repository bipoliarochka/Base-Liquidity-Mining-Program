// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;



import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BaseLiquidityMining is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable lpToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardPerSecond;
    uint256 public accRewardPerShare;
    uint256 public lastUpdate;
    uint256 public totalStaked;

    uint256 public vestDuration = 7 days;

    struct User {
        uint256 amount;
        uint256 rewardDebt;
        uint256 vested;       // already vested rewards available
        uint256 unvested;     // pending to vest
        uint256 lastVestTime;
    }

    mapping(address => User) public users;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event Params(uint256 rewardPerSecond, uint256 vestDuration);

    constructor(address _lp, address _reward, uint256 _rps) Ownable(msg.sender) {
        require(_lp != address(0) && _reward != address(0), "zero");
        lpToken = IERC20(_lp);
        rewardToken = IERC20(_reward);
        rewardPerSecond = _rps;
        lastUpdate = block.timestamp;
    }

    function setParams(uint256 _rps, uint256 _vest) external onlyOwner {
        _updatePool();
        rewardPerSecond = _rps;
        vestDuration = _vest;
        emit Params(_rps, _vest);
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        _updatePool();
        User storage u = users[msg.sender];
        _vest(u);

        uint256 pending = _pending(u);
        if (pending > 0) u.unvested += pending;

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
        _vest(u);

        uint256 pending = _pending(u);
        if (pending > 0) u.unvested += pending;

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
        _vest(u);

        uint256 pending = _pending(u);
        if (pending > 0) u.unvested += pending;

        u.rewardDebt = (u.amount * accRewardPerShare) / 1e12;

        require(u.vested > 0, "nothing");
        uint256 amount = u.vested;
        u.vested = 0;

        rewardToken.safeTransfer(msg.sender, amount);
        emit Claim(msg.sender, amount);
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

    function _vest(User storage u) internal {
        uint256 t = block.timestamp;
        if (u.lastVestTime == 0) { u.lastVestTime = t; return; }

        if (u.unvested == 0) { u.lastVestTime = t; return; }

        uint256 dt = t - u.lastVestTime;
        uint256 v = (u.unvested * dt) / vestDuration;
        if (v > u.unvested) v = u.unvested;

        u.unvested -= v;
        u.vested += v;
        u.lastVestTime = t;
    }
}
