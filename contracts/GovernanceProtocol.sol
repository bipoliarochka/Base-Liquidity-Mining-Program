// base-governance/contracts/GovernanceProtocol.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract GovernanceProtocol is Ownable, ReentrancyGuard {
    struct Proposal {
        uint256 proposalId;
        address proposer;
        string description;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
        bool canceled;
        bool quorumReached;
    }

    struct Vote {
        bool support;
        uint256 votes;
    }

    struct Voter {
        uint256 votingPower;
        mapping(uint256 => bool) hasVoted;
    }

    IERC20 public token;
    uint256 public quorumThreshold; // 10% кворум
    uint256 public votingDelay; // 1 день задержка
    uint256 public votingPeriod; // 7 дней период голосования
    
    mapping(uint256 => Proposal) public proposals;
    mapping(address => Voter) public voters;
    mapping(uint256 => mapping(address => Vote)) public proposalVotes;
    
    uint256 public nextProposalId;
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        uint256 startTime,
        uint256 endTime
    );
    
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 votes
    );
    
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);

    constructor(
        address _token,
        uint256 _quorumThreshold,
        uint256 _votingDelay,
        uint256 _votingPeriod
    ) {
        token = IERC20(_token);
        quorumThreshold = _quorumThreshold;
        votingDelay = _votingDelay;
        votingPeriod = _votingPeriod;
    }

    function propose(
        string memory description
    ) external {
        require(token.balanceOf(msg.sender) > 0, "Insufficient balance");
        
        uint256 proposalId = nextProposalId++;
        uint256 startTime = block.timestamp + votingDelay;
        uint256 endTime = startTime + votingPeriod;
        
        proposals[proposalId] = Proposal({
            proposalId: proposalId,
            proposer: msg.sender,
            description: description,
            startTime: startTime,
            endTime: endTime,
            forVotes: 0,
            againstVotes: 0,
            executed: false,
            canceled: false,
            quorumReached: false
        });
        
        emit ProposalCreated(proposalId, msg.sender, description, startTime, endTime);
    }

    function vote(
        uint256 proposalId,
        bool support
    ) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.startTime, "Voting not started");
        require(block.timestamp <= proposal.endTime, "Voting ended");
        require(!proposal.canceled, "Proposal canceled");
        require(!proposal.executed, "Proposal executed");
        require(!proposalVotes[proposalId][msg.sender].support, "Already voted");
        
        uint256 votingPower = token.balanceOf(msg.sender);
        require(votingPower > 0, "No voting power");
        
        proposalVotes[proposalId][msg.sender] = Vote({
            support: support,
            votes: votingPower
        });
        
        if (support) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }
        
        emit VoteCast(proposalId, msg.sender, support, votingPower);
    }

    function executeProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal canceled");
        require(block.timestamp > proposal.endTime, "Voting not finished");
        require(proposal.forVotes > proposal.againstVotes, "Not enough votes for");
        
        // Проверка кворума
        uint256 totalVoted = proposal.forVotes + proposal.againstVotes;
        uint256 totalSupply = token.totalSupply();
        require(totalVoted >= (totalSupply * quorumThreshold) / 10000, "Quorum not reached");
        
        proposal.executed = true;
        proposal.quorumReached = true;
        
        emit ProposalExecuted(proposalId);
    }

    function cancelProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(msg.sender == proposal.proposer || msg.sender == owner(), "Not authorized");
        require(!proposal.executed, "Proposal already executed");
        require(!proposal.canceled, "Proposal already canceled");
        
        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    function getProposalState(uint256 proposalId) external view returns (string memory) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) return "Canceled";
        if (proposal.executed) return "Executed";
        if (block.timestamp < proposal.startTime) return "Pending";
        if (block.timestamp < proposal.endTime) return "Active";
        return "Finished";
    }

    function getProposalInfo(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }
   
function calculatePendingReward(address user, address token) public view returns (uint256) {
    
    uint256 rewardPerToken = pool.rewardPerTokenStored;
    uint256 userReward = userInfo[token][user].rewardDebt;
    
    if (userInfo[token][user].amount > 0) {
        uint256 userEarned = userInfo[token][user].amount.mul(rewardPerToken.sub(userReward)).div(1e18);
        // Защита от переполнения
        require(userEarned <= type(uint256).max, "Reward calculation overflow");
        return userEarned;
    }
    return 0;
}
}
