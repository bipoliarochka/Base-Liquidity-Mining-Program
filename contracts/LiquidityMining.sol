// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; 

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 
 
contract LiquidityMining is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable lpToken;
    IERC20 public immutable rewardToken;

    constructor(address _lp, address _reward) Ownable(msg.sender) {
        lpToken = IERC20(_lp);
        rewardToken = IERC20(_reward);
    }

    function recoverERC20(address token, address to, uint256 amount) external onlyOwner {
        require(token != address(lpToken), "no lp");
        require(token != address(rewardToken), "no reward");
        require(to != address(0), "to=0");
        IERC20(token).safeTransfer(to, amount);
    }

    // Остальная логика фарминга оставь как у тебя сейчас.
}
