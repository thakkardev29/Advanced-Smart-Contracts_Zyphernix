// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DecentralizedEscrow {

    enum EscrowStatus {
        AWAITING_PAYMENT,
        AWAITING_DELIVERY,
        COMPLETE,
        DISPUTED,
        CANCELLED
    }

    address public immutable buyer;
    address public immutable seller;
    address public immutable arbiter;

    uint256 public escrowAmount;
    uint256 public paymentTimestamp;
    uint256 public deliveryPeriod;

    EscrowStatus public currentStatus;

    /* ========== EVENTS ========== */

    event FundsDeposited(address indexed buyer, uint256 value);
    event DeliveryApproved(address indexed buyer, address indexed seller, uint256 value);
    event DisputeInitiated(address indexed caller);
    event DisputeFinalized(address indexed arbiter, address indexed recipient, uint256 value);
    event EscrowTerminated(address indexed caller);
    event DeliveryTimeout(address indexed buyer);

    constructor(
        address _seller,
        address _arbiter,
        uint256 _deliveryPeriod
    ) {
        require(_deliveryPeriod > 0, "Invalid delivery duration");

        buyer = msg.sender;
        seller = _seller;
        arbiter = _arbiter;
        deliveryPeriod = _deliveryPeriod;

        currentStatus = EscrowStatus.AWAITING_PAYMENT;
    }

    receive() external payable {
        revert("Direct ETH transfers not accepted");
    }

    /* ========== ESCROW FLOW ========== */

    function deposit() external payable {
        require(msg.sender == buyer, "Only buyer allowed");
        require(currentStatus == EscrowStatus.AWAITING_PAYMENT, "Payment already made");
        require(msg.value > 0, "Zero value deposit");

        escrowAmount = msg.value;
        paymentTimestamp = block.timestamp;
        currentStatus = EscrowStatus.AWAITING_DELIVERY;

        emit FundsDeposited(buyer, msg.value);
    }

    function confirmDelivery() external {
        require(msg.sender == buyer, "Only buyer can confirm");
        require(
            currentStatus == EscrowStatus.AWAITING_DELIVERY,
            "Delivery not pending"
        );

        currentStatus = EscrowStatus.COMPLETE;
        payable(seller).transfer(escrowAmount);

        emit DeliveryApproved(buyer, seller, escrowAmount);
    }

    /* ========== DISPUTE HANDLING ========== */

    function raiseDispute() external {
        require(
            msg.sender == buyer || msg.sender == seller,
            "Unauthorized caller"
        );
        require(
            currentStatus == EscrowStatus.AWAITING_DELIVERY,
            "Dispute not allowed now"
        );

        currentStatus = EscrowStatus.DISPUTED;
        emit DisputeInitiated(msg.sender);
    }

    function resolveDispute(bool releaseToSeller) external {
        require(msg.sender == arbiter, "Only arbiter permitted");
        require(
            currentStatus == EscrowStatus.DISPUTED,
            "No active dispute"
        );

        currentStatus = EscrowStatus.COMPLETE;

        address payable recipient =
            releaseToSeller ? payable(seller) : payable(buyer);

        recipient.transfer(escrowAmount);
        emit DisputeFinalized(msg.sender, recipient, escrowAmount);
    }

    /* ========== CANCELLATION LOGIC ========== */

    function cancelAfterTimeout() external {
        require(msg.sender == buyer, "Only buyer allowed");
        require(
            currentStatus == EscrowStatus.AWAITING_DELIVERY,
            "Cancellation not allowed"
        );
        require(
            block.timestamp >= paymentTimestamp + deliveryPeriod,
            "Delivery window still active"
        );

        currentStatus = EscrowStatus.CANCELLED;
        payable(buyer).transfer(address(this).balance);

        emit EscrowTerminated(buyer);
        emit DeliveryTimeout(buyer);
    }

    function cancelByMutualConsent() external {
        require(
            msg.sender == buyer || msg.sender == seller,
            "Unauthorized caller"
        );
        require(
            currentStatus == EscrowStatus.AWAITING_PAYMENT ||
            currentStatus == EscrowStatus.AWAITING_DELIVERY,
            "Cancellation not possible"
        );

        EscrowStatus previous = currentStatus;
        currentStatus = EscrowStatus.CANCELLED;

        if (previous == EscrowStatus.AWAITING_DELIVERY) {
            payable(buyer).transfer(address(this).balance);
        }

        emit EscrowTerminated(msg.sender);
    }

    /* ========== VIEW UTILITIES ========== */

    function remainingTime() external view returns (uint256) {
        if (currentStatus != EscrowStatus.AWAITING_DELIVERY) return 0;

        uint256 endTime = paymentTimestamp + deliveryPeriod;
        if (block.timestamp >= endTime) return 0;

        return endTime - block.timestamp;
    }
}
