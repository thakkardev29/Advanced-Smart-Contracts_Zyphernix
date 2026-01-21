// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title SimpleLending
 * @notice Minimal lending and borrowing protocol for educational purposes
 */
contract SimpleLending {

    /* ========== USER ACCOUNTING ========== */

    mapping(address => uint256) public suppliedBalance;
    mapping(address => uint256) public outstandingDebt;
    mapping(address => uint256) public lockedCollateral;
    mapping(address => uint256) public lastAccrualTime;

    /* ========== PROTOCOL PARAMETERS ========== */

    // Interest rate expressed in basis points (e.g., 500 = 5%)
    uint256 public interestRateBP = 500;

    // Collateral factor (e.g., 7500 = 75%)
    uint256 public collateralFactorBP = 7500;

    /* ========== EVENTS ========== */

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repayment(address indexed user, uint256 amount);
    event CollateralAdded(address indexed user, uint256 amount);
    event CollateralRemoved(address indexed user, uint256 amount);

    /* ========== DEPOSIT & WITHDRAW ========== */

    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");

        suppliedBalance[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Invalid withdrawal amount");
        require(suppliedBalance[msg.sender] >= amount, "Insufficient balance");

        suppliedBalance[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);

        emit Withdraw(msg.sender, amount);
    }

    /* ========== COLLATERAL MANAGEMENT ========== */

    function depositCollateral() external payable {
        require(msg.value > 0, "Collateral must be positive");

        lockedCollateral[msg.sender] += msg.value;
        emit CollateralAdded(msg.sender, msg.value);
    }

    function withdrawCollateral(uint256 amount) external {
        require(amount > 0, "Invalid collateral amount");
        require(lockedCollateral[msg.sender] >= amount, "Not enough collateral");

        uint256 totalDebt = _calculateAccruedDebt(msg.sender);
        uint256 minimumCollateralRequired =
            (totalDebt * 10000) / collateralFactorBP;

        require(
            lockedCollateral[msg.sender] - amount >= minimumCollateralRequired,
            "Collateral ratio violation"
        );

        lockedCollateral[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);

        emit CollateralRemoved(msg.sender, amount);
    }

    /* ========== BORROWING & REPAYMENT ========== */

    function borrow(uint256 amount) external {
        require(amount > 0, "Borrow amount must be positive");
        require(address(this).balance >= amount, "Protocol lacks liquidity");

        uint256 borrowingLimit =
            (lockedCollateral[msg.sender] * collateralFactorBP) / 10000;

        uint256 currentDebt = _calculateAccruedDebt(msg.sender);

        require(
            currentDebt + amount <= borrowingLimit,
            "Borrow limit exceeded"
        );

        outstandingDebt[msg.sender] = currentDebt + amount;
        lastAccrualTime[msg.sender] = block.timestamp;

        payable(msg.sender).transfer(amount);
        emit Borrow(msg.sender, amount);
    }

    function repay() external payable {
        require(msg.value > 0, "Repayment must be positive");

        uint256 totalDebt = _calculateAccruedDebt(msg.sender);
        require(totalDebt > 0, "No active debt");

        uint256 repaymentAmount = msg.value;

        if (repaymentAmount > totalDebt) {
            repaymentAmount = totalDebt;
            payable(msg.sender).transfer(msg.value - totalDebt);
        }

        outstandingDebt[msg.sender] = totalDebt - repaymentAmount;
        lastAccrualTime[msg.sender] = block.timestamp;

        emit Repayment(msg.sender, repaymentAmount);
    }

    /* ========== VIEW FUNCTIONS ========== */

    function _calculateAccruedDebt(address user)
        internal
        view
        returns (uint256)
    {
        uint256 principal = outstandingDebt[user];

        if (principal == 0) {
            return 0;
        }

        uint256 elapsedTime =
            block.timestamp - lastAccrualTime[user];

        uint256 interest =
            (principal * interestRateBP * elapsedTime) /
            (10000 * 365 days);

        return principal + interest;
    }

    function getMaxBorrowable(address user)
        external
        view
        returns (uint256)
    {
        return (lockedCollateral[user] * collateralFactorBP) / 10000;
    }

    function getAvailableLiquidity()
        external
        view
        returns (uint256)
    {
        return address(this).balance;
    }
}
