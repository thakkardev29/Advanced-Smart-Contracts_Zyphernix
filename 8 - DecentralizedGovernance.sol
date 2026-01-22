// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract DecentralizedGovernance is ReentrancyGuard {
    using SafeCast for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct GovernanceProposal {
        uint256 proposalId;
        string details;
        uint256 votingEnd;
        uint256 votesInFavor;
        uint256 votesAgainst;
        bool finalized;
        address proposer;
        address[] targets;
        bytes[] callData;
        uint256 eta; // execution timestamp after timelock
    }

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable govToken;
    address public admin;

    uint256 public proposalCount;
    uint256 public votingPeriod;
    uint256 public timelockPeriod;

    uint256 public quorumPercent = 5;
    uint256 public proposalDeposit = 10;

    mapping(uint256 => GovernanceProposal) private proposalRegistry;
    mapping(uint256 => mapping(address => bool)) private voteStatus;

    /* ========== EVENTS ========== */

    event ProposalSubmitted(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        uint256 deposit
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votingPower
    );

    event ProposalFinalized(uint256 indexed proposalId, bool approved);
    event QuorumFailure(uint256 indexed proposalId, uint256 votesCast, uint256 quorumRequired);

    event DepositCollected(address indexed proposer, uint256 amount);
    event DepositReturned(address indexed proposer, uint256 amount);

    event TimelockConfigured(uint256 duration);
    event ExecutionScheduled(uint256 indexed proposalId, uint256 executionTime);

    /* ========== MODIFIERS ========== */

    modifier onlyAdmin() {
        require(msg.sender == admin, "Caller is not admin");
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _govToken,
        uint256 _votingPeriod,
        uint256 _timelockPeriod
    ) {
        govToken = IERC20(_govToken);
        votingPeriod = _votingPeriod;
        timelockPeriod = _timelockPeriod;
        admin = msg.sender;

        emit TimelockConfigured(_timelockPeriod);
    }

    /* ========== ADMIN CONTROLS ========== */

    function updateQuorum(uint256 newQuorum) external onlyAdmin {
        require(newQuorum <= 100, "Invalid quorum value");
        quorumPercent = newQuorum;
    }

    function updateProposalDeposit(uint256 newDeposit) external onlyAdmin {
        proposalDeposit = newDeposit;
    }

    function updateTimelock(uint256 newTimelock) external onlyAdmin {
        timelockPeriod = newTimelock;
        emit TimelockConfigured(newTimelock);
    }

    /* ========== PROPOSAL CREATION ========== */

    function submitProposal(
        string calldata description,
        address[] calldata targets,
        bytes[] calldata data
    ) external returns (uint256) {
        require(
            govToken.balanceOf(msg.sender) >= proposalDeposit,
            "Insufficient tokens for deposit"
        );
        require(targets.length == data.length, "Execution data mismatch");

        govToken.transferFrom(msg.sender, address(this), proposalDeposit);
        emit DepositCollected(msg.sender, proposalDeposit);

        proposalRegistry[proposalCount] = GovernanceProposal({
            proposalId: proposalCount,
            details: description,
            votingEnd: block.timestamp + votingPeriod,
            votesInFavor: 0,
            votesAgainst: 0,
            finalized: false,
            proposer: msg.sender,
            targets: targets,
            callData: data,
            eta: 0
        });

        emit ProposalSubmitted(
            proposalCount,
            msg.sender,
            description,
            proposalDeposit
        );

        proposalCount++;
        return proposalCount - 1;
    }

    /* ========== VOTING ========== */

    function castVote(uint256 proposalId, bool support) external {
        GovernanceProposal storage proposal = proposalRegistry[proposalId];

        require(block.timestamp < proposal.votingEnd, "Voting closed");
        require(govToken.balanceOf(msg.sender) > 0, "No voting power");
        require(!voteStatus[proposalId][msg.sender], "Already voted");

        uint256 votingPower = govToken.balanceOf(msg.sender);

        if (support) {
            proposal.votesInFavor += votingPower;
        } else {
            proposal.votesAgainst += votingPower;
        }

        voteStatus[proposalId][msg.sender] = true;

        emit VoteCast(proposalId, msg.sender, support, votingPower);
    }

    /* ========== FINALIZATION ========== */

    function finalizeProposal(uint256 proposalId) external {
        GovernanceProposal storage proposal = proposalRegistry[proposalId];

        require(block.timestamp >= proposal.votingEnd, "Voting ongoing");
        require(!proposal.finalized, "Already finalized");
        require(proposal.eta == 0, "Execution already scheduled");

        uint256 totalVotes =
            proposal.votesInFavor + proposal.votesAgainst;

        uint256 quorumRequired =
            (govToken.totalSupply() * quorumPercent) / 100;

        if (totalVotes >= quorumRequired && proposal.votesInFavor > proposal.votesAgainst) {
            proposal.eta = block.timestamp + timelockPeriod;
            emit ExecutionScheduled(proposalId, proposal.eta);
        } else {
            proposal.finalized = true;
            emit ProposalFinalized(proposalId, false);

            if (totalVotes < quorumRequired) {
                emit QuorumFailure(proposalId, totalVotes, quorumRequired);
            }
        }
    }

    /* ========== EXECUTION ========== */

    function executeProposal(uint256 proposalId) external nonReentrant {
        GovernanceProposal storage proposal = proposalRegistry[proposalId];

        require(!proposal.finalized, "Already executed");
        require(proposal.eta > 0, "Execution not scheduled");
        require(block.timestamp >= proposal.eta, "Timelock active");

        proposal.finalized = true;

        bool approved =
            proposal.votesInFavor > proposal.votesAgainst;

        if (approved) {
            for (uint256 i = 0; i < proposal.targets.length; i++) {
                (bool success, bytes memory result) =
                    proposal.targets[i].call(proposal.callData[i]);
                require(success, string(result));
            }

            govToken.transfer(proposal.proposer, proposalDeposit);
            emit DepositReturned(proposal.proposer, proposalDeposit);
            emit ProposalFinalized(proposalId, true);
        } else {
            emit ProposalFinalized(proposalId, false);
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    function proposalOutcome(uint256 proposalId)
        external
        view
        returns (string memory)
    {
        GovernanceProposal storage proposal = proposalRegistry[proposalId];
        require(proposal.finalized, "Proposal not finalized");

        uint256 totalVotes =
            proposal.votesInFavor + proposal.votesAgainst;

        uint256 quorumRequired =
            (govToken.totalSupply() * quorumPercent) / 100;

        if (totalVotes < quorumRequired) {
            return "FAILED: Quorum not met";
        }
        if (proposal.votesInFavor > proposal.votesAgainst) {
            return "PASSED";
        }
        return "REJECTED";
    }

    function getProposal(uint256 proposalId)
        external
        view
        returns (GovernanceProposal memory)
    {
        return proposalRegistry[proposalId];
    }
}
