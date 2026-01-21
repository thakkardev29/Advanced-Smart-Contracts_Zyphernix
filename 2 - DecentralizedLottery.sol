// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { VRFConsumerBaseV2Plus } 
    from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import { VRFV2PlusClient } 
    from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract FairChainLottery is VRFConsumerBaseV2Plus {

    enum LotteryPhase {
        OPEN,
        CLOSED,
        CALCULATING
    }

    LotteryPhase public currentPhase;

    address payable[] private participantList;
    address public lastWinner;
    uint256 public ticketPrice;

    // Chainlink VRF configuration
    uint256 public subscriptionId;
    bytes32 public gasLane;
    uint32 public callbackGasLimit = 100_000;
    uint16 public confirmations = 3;
    uint32 public randomWordCount = 1;
    uint256 public requestId;

    constructor(
        address coordinator,
        uint256 subId,
        bytes32 keyHash,
        uint256 entryCost
    ) VRFConsumerBaseV2Plus(coordinator) {
        subscriptionId = subId;
        gasLane = keyHash;
        ticketPrice = entryCost;
        currentPhase = LotteryPhase.CLOSED;
    }

    function enterLottery() external payable {
        require(currentPhase == LotteryPhase.OPEN, "Lottery inactive");
        require(msg.value >= ticketPrice, "Insufficient ETH sent");

        participantList.push(payable(msg.sender));
    }

    function startLottery() external onlyOwner {
        require(currentPhase == LotteryPhase.CLOSED, "Lottery already running");
        currentPhase = LotteryPhase.OPEN;
    }

    function closeLottery() external onlyOwner {
        require(currentPhase == LotteryPhase.OPEN, "Lottery not open");
        currentPhase = LotteryPhase.CALCULATING;

        VRFV2PlusClient.RandomWordsRequest memory request =
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: gasLane,
                subId: subscriptionId,
                requestConfirmations: confirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: randomWordCount,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({ nativePayment: true })
                )
            });

        requestId = s_vrfCoordinator.requestRandomWords(request);
    }

    function fulfillRandomWords(
        uint256,
        uint256[] calldata randomWords
    ) internal override {
        require(
            currentPhase == LotteryPhase.CALCULATING,
            "Winner selection not allowed"
        );

        uint256 winnerIndex =
            randomWords[0] % participantList.length;

        address payable selectedWinner =
            participantList[winnerIndex];

        lastWinner = selectedWinner;

        delete participantList;
        currentPhase = LotteryPhase.CLOSED;

        (bool success, ) =
            selectedWinner.call{ value: address(this).balance }("");

        require(success, "ETH transfer failed");
    }

    function getParticipants()
        external
        view
        returns (address payable[] memory)
    {
        return participantList;
    }
}
