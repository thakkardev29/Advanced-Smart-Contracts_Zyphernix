// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IERC20Metadata is IERC20 {
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

/**
 * @title YieldFarming
 * @notice Stake ERC20 tokens to earn time-based rewards
 */
contract YieldFarming is ReentrancyGuard {
    using SafeCast for uint256;

    IERC20 public immutable stakeToken;
    IERC20 public immutable rewardToken;

    address public immutable admin;

    uint256 public rewardsPerSecond;
    uint8 public stakeTokenDecimals;

    struct Farmer {
        uint256 balance;
        uint256 accruedRewards;
        uint256 lastCheckpoint;
    }

    mapping(address => Farmer) private farmers;

    /* ========== EVENTS ========== */

    event TokensStaked(address indexed user, uint256 amount);
    event TokensUnstaked(address indexed user, uint256 amount);
    event RewardsPaid(address indexed user, uint256 amount);
    event EmergencyExit(address indexed user, uint256 amount);
    event RewardsSupplied(address indexed admin, uint256 amount);

    /* ========== MODIFIERS ========== */

    modifier onlyAdmin() {
        require(msg.sender == admin, "Caller is not admin");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _stakeToken,
        address _rewardToken,
        uint256 _rewardsPerSecond
    ) {
        stakeToken = IERC20(_stakeToken);
        rewardToken = IERC20(_rewardToken);
        rewardsPerSecond = _rewardsPerSecond;
        admin = msg.sender;

        // Attempt to read staking token decimals
        try IERC20Metadata(_stakeToken).decimals() returns (uint8 dec) {
            stakeTokenDecimals = dec;
        } catch {
            stakeTokenDecimals = 18;
        }
    }

    /* ========== STAKING LOGIC ========== */

    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than zero");

        _updateUserRewards(msg.sender);

        stakeToken.transferFrom(msg.sender, address(this), amount);
        farmers[msg.sender].balance += amount;

        emit TokensStaked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid unstake amount");
        require(farmers[msg.sender].balance >= amount, "Insufficient stake");

        _updateUserRewards(msg.sender);

        farmers[msg.sender].balance -= amount;
        stakeToken.transfer(msg.sender, amount);

        emit TokensUnstaked(msg.sender, amount);
    }

    /* ========== REWARD LOGIC ========== */

    function claimRewards() external nonReentrant {
        _updateUserRewards(msg.sender);

        uint256 reward = farmers[msg.sender].accruedRewards;
        require(reward > 0, "No rewards available");
        require(
            rewardToken.balanceOf(address(this)) >= reward,
            "Reward pool depleted"
        );

        farmers[msg.sender].accruedRewards = 0;
        rewardToken.transfer(msg.sender, reward);

        emit RewardsPaid(msg.sender, reward);
    }

    /* ========== EMERGENCY FUNCTIONS ========== */

    function emergencyWithdraw() external nonReentrant {
        uint256 staked = farmers[msg.sender].balance;
        require(staked > 0, "No stake found");

        farmers[msg.sender].balance = 0;
        farmers[msg.sender].accruedRewards = 0;
        farmers[msg.sender].lastCheckpoint = block.timestamp;

        stakeToken.transfer(msg.sender, staked);

        emit EmergencyExit(msg.sender, staked);
    }

    /* ========== ADMIN FUNCTIONS ========== */

    function supplyRewards(uint256 amount) external onlyAdmin {
        rewardToken.transferFrom(msg.sender, address(this), amount);
        emit RewardsSupplied(msg.sender, amount);
    }

    /* ========== INTERNAL ACCOUNTING ========== */

    function _updateUserRewards(address user) internal {
        Farmer storage farmer = farmers[user];

        if (farmer.balance > 0) {
            uint256 elapsed = block.timestamp - farmer.lastCheckpoint;
            uint256 scale = 10 ** stakeTokenDecimals;

            uint256 earned =
                (elapsed * rewardsPerSecond * farmer.balance) / scale;

            farmer.accruedRewards += earned;
        }

        farmer.lastCheckpoint = block.timestamp;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function pendingRewards(address user)
        external
        view
        returns (uint256)
    {
        Farmer memory farmer = farmers[user];
        uint256 totalRewards = farmer.accruedRewards;

        if (farmer.balance > 0) {
            uint256 elapsed = block.timestamp - farmer.lastCheckpoint;
            uint256 scale = 10 ** stakeTokenDecimals;

            totalRewards +=
                (elapsed * rewardsPerSecond * farmer.balance) / scale;
        }

        return totalRewards;
    }

    function getStakeTokenDecimals() external view returns (uint8) {
        return stakeTokenDecimals;
    }
}
