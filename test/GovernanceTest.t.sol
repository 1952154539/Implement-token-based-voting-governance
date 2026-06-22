// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {GovToken} from "../src/GovToken.sol";
import {Bank} from "../src/Bank.sol";
import {Gov} from "../src/Gov.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract GovTokenTest is Test {
    GovToken public token;
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_SUPPLY = 1_000_000;
    uint256 constant DECIMALS_MULTIPLIER = 1e18;

    function setUp() public {
        vm.prank(owner);
        token = new GovToken(INITIAL_SUPPLY);
    }

    function test_InitialSupply() public view {
        assertEq(token.totalSupply(), INITIAL_SUPPLY * DECIMALS_MULTIPLIER);
        assertEq(token.balanceOf(owner), INITIAL_SUPPLY * DECIMALS_MULTIPLIER);
    }

    function test_Mint() public {
        vm.prank(owner);
        token.mint(alice, 1000 * DECIMALS_MULTIPLIER);
        assertEq(token.balanceOf(alice), 1000 * DECIMALS_MULTIPLIER);
    }

    function test_Revert_MintByNonOwner() public {
        vm.prank(alice);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        token.mint(alice, 1000 * DECIMALS_MULTIPLIER);
    }

    function test_Delegate() public {
        vm.prank(owner);
        token.delegate(alice);

        assertEq(token.delegates(owner), alice);
        assertEq(token.getVotes(alice), INITIAL_SUPPLY * DECIMALS_MULTIPLIER);
    }

    function test_GetPastVotes() public {
        vm.prank(owner);
        token.delegate(owner);

        // Advance to next block so we can query past
        vm.roll(block.number + 1);

        uint256 snapshot = block.number - 1;
        assertEq(token.getPastVotes(owner, snapshot), INITIAL_SUPPLY * DECIMALS_MULTIPLIER);
    }

    function test_TransferUpdatesVotingPower() public {
        vm.prank(owner);
        token.delegate(owner);

        uint256 transferAmount = 1000 * DECIMALS_MULTIPLIER;
        vm.prank(owner);
        token.transfer(alice, transferAmount);

        uint256 expectedRemaining = (INITIAL_SUPPLY - 1000) * DECIMALS_MULTIPLIER;
        assertEq(token.getVotes(owner), expectedRemaining);
        assertEq(token.getVotes(alice), 0); // alice hasn't delegated yet
    }

    function test_SelfDelegateAfterReceivingTokens() public {
        vm.prank(owner);
        token.delegate(owner);

        uint256 transferAmount = 5000 * DECIMALS_MULTIPLIER;
        vm.prank(owner);
        token.transfer(alice, transferAmount);

        vm.prank(alice);
        token.delegate(alice);

        assertEq(token.getVotes(alice), transferAmount);
    }
}

contract BankTest is Test {
    Bank public bank;

    address public admin;
    address public attacker = makeAddr("attacker");
    address public recipient = makeAddr("recipient");

    function setUp() public {
        admin = address(this);
        bank = new Bank();

        // Fund Bank via receive() to properly update totalDeposits
        (bool success, ) = address(bank).call{value: 100 ether}("");
        require(success, "fund failed");
    }

    function test_InitialAdmin() public view {
        assertEq(bank.admin(), admin);
    }

    function test_WithdrawByAdmin() public {
        uint256 amount = 10 ether;
        uint256 recipientBefore = recipient.balance;
        uint256 bankBefore = address(bank).balance;

        bank.withdraw(recipient, amount);

        assertEq(address(bank).balance, bankBefore - amount);
        assertEq(recipient.balance, recipientBefore + amount);
        assertEq(bank.totalDeposits(), 100 ether - amount);
    }

    function test_Revert_WithdrawByNonAdmin() public {
        vm.prank(attacker);
        vm.expectRevert(Bank.Bank__NotAdmin.selector);
        bank.withdraw(attacker, 1 ether);
    }

    function test_Revert_WithdrawZeroAmount() public {
        vm.expectRevert(Bank.Bank__ZeroAmount.selector);
        bank.withdraw(recipient, 0);
    }

    function test_Revert_WithdrawToZeroAddress() public {
        vm.expectRevert(Bank.Bank__ZeroAddress.selector);
        bank.withdraw(address(0), 1 ether);
    }

    function test_Revert_WithdrawInsufficientBalance() public {
        vm.expectRevert(Bank.Bank__InsufficientBalance.selector);
        bank.withdraw(recipient, 200 ether);
    }

    function test_SetAdmin() public {
        bank.setAdmin(attacker);
        assertEq(bank.admin(), attacker);

        // Old admin can no longer withdraw
        vm.expectRevert(Bank.Bank__NotAdmin.selector);
        bank.withdraw(recipient, 1 ether);

        // New admin can withdraw
        vm.prank(attacker);
        bank.withdraw(recipient, 1 ether);

        assertEq(bank.totalDeposits(), 100 ether - 1 ether);
    }

    function test_Revert_SetAdminToZeroAddress() public {
        vm.expectRevert(Bank.Bank__ZeroAddress.selector);
        bank.setAdmin(address(0));
    }

    function test_ReceiveETH() public {
        vm.deal(attacker, 5 ether);
        vm.prank(attacker);
        (bool success, ) = address(bank).call{value: 5 ether}("");
        assertTrue(success);
        assertEq(address(bank).balance, 105 ether);
        assertEq(bank.totalDeposits(), 105 ether);
    }

    function test_GetBalance() public view {
        assertEq(bank.getBalance(), 100 ether);
    }
}

contract GovernanceTest is Test {
    GovToken public token;
    Bank public bank;
    Gov public gov;

    address public owner = makeAddr("owner");
    address public voter1 = makeAddr("voter1");
    address public voter2 = makeAddr("voter2");
    address public voter3 = makeAddr("voter3");
    address public nonHolder = makeAddr("nonHolder");
    address public withdrawTarget = makeAddr("withdrawTarget");

    uint256 constant INITIAL_SUPPLY = 1_000_000;
    uint256 constant TOKEN_DECIMALS = 1e18;

    uint48 constant VOTING_DELAY = 1;
    uint32 constant VOTING_PERIOD = 30;
    uint256 constant PROPOSAL_THRESHOLD = 10_000 * TOKEN_DECIMALS;
    uint256 constant QUORUM_NUMERATOR = 4; // 4%

    function setUp() public {
        // 1. Deploy GovToken - initial supply goes to address(this)
        token = new GovToken(INITIAL_SUPPLY);

        // 2. Deploy Bank
        bank = new Bank();

        // 3. Deploy Gov
        gov = new Gov(
            token,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_NUMERATOR
        );

        // 4. Set Gov as Bank admin
        bank.setAdmin(address(gov));

        // 5. Fund Bank with ETH via receive()
        (bool success, ) = address(bank).call{value: 100 ether}("");
        require(success, "fund bank failed");

        // 6. Distribute tokens from address(this) to participants
        // address(this) holds all initial supply

        // owner: 150k tokens
        uint256 ownerAmount = 150_000 * TOKEN_DECIMALS;
        token.transfer(owner, ownerAmount);
        vm.prank(owner);
        token.delegate(owner);

        // voter1: 200k tokens
        uint256 voter1Amount = 200_000 * TOKEN_DECIMALS;
        token.transfer(voter1, voter1Amount);
        vm.prank(voter1);
        token.delegate(voter1);

        // voter2: 150k tokens
        uint256 voter2Amount = 150_000 * TOKEN_DECIMALS;
        token.transfer(voter2, voter2Amount);
        vm.prank(voter2);
        token.delegate(voter2);

        // voter3: 50k tokens
        uint256 voter3Amount = 50_000 * TOKEN_DECIMALS;
        token.transfer(voter3, voter3Amount);
        vm.prank(voter3);
        token.delegate(voter3);

        // address(this) delegates remaining tokens to itself
        token.delegate(address(this));

        // Advance blocks so voting power checkpoints are recorded
        vm.roll(block.number + 5);
    }

    // --- Helper ---

    function _createWithdrawProposal(
        address proposer,
        address to,
        uint256 amount
    ) internal returns (uint256 proposalId) {
        address[] memory targets = new address[](1);
        targets[0] = address(bank);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("withdraw(address,uint256)", to, amount);

        string memory description = "Proposal: Withdraw from Bank";

        vm.prank(proposer);
        proposalId = gov.propose(targets, values, calldatas, description);
    }

    // --- Proposal Tests ---

    function test_CreateProposal() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Pending));
        assertEq(gov.proposalProposer(proposalId), owner);
    }

    function test_Revert_ProposalByNonHolder() public {
        address[] memory targets = new address[](1);
        targets[0] = address(bank);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("withdraw(address,uint256)", withdrawTarget, 10 ether);

        vm.prank(nonHolder);
        vm.expectRevert(); // GovernorNotAProposer
        gov.propose(targets, values, calldatas, "Should fail");
    }

    function test_Revert_ProposalBelowThreshold() public {
        // Give nonHolder a small amount below threshold
        uint256 smallAmount = 1000 * TOKEN_DECIMALS;
        token.transfer(nonHolder, smallAmount);
        vm.prank(nonHolder);
        token.delegate(nonHolder);

        address[] memory targets = new address[](1);
        targets[0] = address(bank);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("withdraw(address,uint256)", withdrawTarget, 10 ether);

        vm.prank(nonHolder);
        vm.expectRevert(); // GovernorNotAProposer (below threshold)
        gov.propose(targets, values, calldatas, "Should fail - below threshold");
    }

    // --- Voting Tests ---

    function test_CastVoteFor() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        gov.castVote(proposalId, 1); // For

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = gov.proposalVotes(proposalId);
        assertEq(forVotes, 200_000 * TOKEN_DECIMALS);
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);
    }

    function test_CastVoteAgainst() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        gov.castVote(proposalId, 0); // Against

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = gov.proposalVotes(proposalId);
        assertEq(forVotes, 0);
        assertEq(againstVotes, 200_000 * TOKEN_DECIMALS);
        assertEq(abstainVotes, 0);
    }

    function test_CastVoteAbstain() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        gov.castVote(proposalId, 2); // Abstain

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = gov.proposalVotes(proposalId);
        assertEq(forVotes, 0);
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 200_000 * TOKEN_DECIMALS);
    }

    function test_MultipleVoters() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        gov.castVote(proposalId, 1); // For: 200k
        vm.prank(voter2);
        gov.castVote(proposalId, 0); // Against: 150k
        vm.prank(voter3);
        gov.castVote(proposalId, 2); // Abstain: 50k

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = gov.proposalVotes(proposalId);
        assertEq(forVotes, 200_000 * TOKEN_DECIMALS);
        assertEq(againstVotes, 150_000 * TOKEN_DECIMALS);
        assertEq(abstainVotes, 50_000 * TOKEN_DECIMALS);
    }

    function test_Revert_DoubleVote() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.startPrank(voter1);
        gov.castVote(proposalId, 1);
        vm.expectRevert(); // Already voted
        gov.castVote(proposalId, 0);
        vm.stopPrank();
    }

    function test_Revert_VoteBeforeVotingPeriod() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.prank(voter1);
        vm.expectRevert(); // Proposal not active
        gov.castVote(proposalId, 1);
    }

    function test_Revert_VoteAfterVotingPeriod() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.roll(block.number + VOTING_DELAY + VOTING_PERIOD + 1);

        vm.prank(voter1);
        vm.expectRevert(); // Voting period ended
        gov.castVote(proposalId, 1);
    }

    // --- Proposal State Tests ---

    function test_ProposalStateTransitions() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        // Pending
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        // Active
        vm.roll(block.number + VOTING_DELAY + 1);
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        // Vote to pass
        vm.prank(voter1);
        gov.castVote(proposalId, 1); // 200k For (20% > 4% quorum)

        // Succeeded
        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function test_ProposalDefeated() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        gov.castVote(proposalId, 0);
        vm.prank(voter2);
        gov.castVote(proposalId, 0);
        vm.prank(voter3);
        gov.castVote(proposalId, 0);

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }

    // --- Execution Tests ---

    function test_ExecuteProposal_FullFlow() public {
        address[] memory targets = new address[](1);
        targets[0] = address(bank);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        uint256 withdrawAmount = 10 ether;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("withdraw(address,uint256)", withdrawTarget, withdrawAmount);

        string memory description = "Proposal: Withdraw 10 ETH from Bank";

        // 1. Create proposal
        vm.prank(owner);
        uint256 proposalId = gov.propose(targets, values, calldatas, description);
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Pending));

        // 2. Advance to active
        vm.roll(block.number + VOTING_DELAY + 1);
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Active));

        // 3. Vote
        vm.prank(voter1);
        gov.castVote(proposalId, 1); // 200k For
        vm.prank(voter2);
        gov.castVote(proposalId, 1); // 150k For
        vm.prank(voter3);
        gov.castVote(proposalId, 1); // 50k For

        // 4. Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Succeeded));

        // 5. Execute
        uint256 targetBefore = withdrawTarget.balance;
        uint256 bankBefore = address(bank).balance;

        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        gov.execute(targets, values, calldatas, descriptionHash);

        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        assertEq(withdrawTarget.balance, targetBefore + withdrawAmount);
        assertEq(address(bank).balance, bankBefore - withdrawAmount);
    }

    function test_Revert_ExecuteBeforeVotingEnds() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        gov.castVote(proposalId, 1);

        address[] memory targets = new address[](1);
        targets[0] = address(bank);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("withdraw(address,uint256)", withdrawTarget, 10 ether);

        bytes32 descriptionHash = keccak256(abi.encodePacked("Proposal: Withdraw from Bank"));

        vm.expectRevert(Gov.Gov__ProposalNotSucceeded.selector);
        gov.execute(targets, values, calldatas, descriptionHash);
    }

    function test_Revert_ExecuteDefeatedProposal() public {
        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        gov.castVote(proposalId, 0);
        vm.prank(voter2);
        gov.castVote(proposalId, 0);

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));

        address[] memory targets = new address[](1);
        targets[0] = address(bank);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("withdraw(address,uint256)", withdrawTarget, 10 ether);

        bytes32 descriptionHash = keccak256(abi.encodePacked("Proposal: Withdraw from Bank"));

        vm.expectRevert(Gov.Gov__ProposalNotSucceeded.selector);
        gov.execute(targets, values, calldatas, descriptionHash);
    }

    function test_Revert_ReexecuteProposal() public {
        address[] memory targets = new address[](1);
        targets[0] = address(bank);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        uint256 withdrawAmount = 5 ether;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("withdraw(address,uint256)", withdrawTarget, withdrawAmount);
        string memory description = "Proposal: Withdraw 5 ETH";

        vm.prank(owner);
        uint256 proposalId = gov.propose(targets, values, calldatas, description);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        gov.castVote(proposalId, 1);
        vm.prank(voter2);
        gov.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        gov.execute(targets, values, calldatas, descriptionHash);

        // Try to execute again
        vm.expectRevert(Gov.Gov__ProposalNotSucceeded.selector);
        gov.execute(targets, values, calldatas, descriptionHash);
    }

    // --- Multiple Proposals ---

    function test_MultipleProposals() public {
        address[] memory targets1 = new address[](1);
        targets1[0] = address(bank);
        uint256[] memory values1 = new uint256[](1);
        values1[0] = 0;
        bytes[] memory calldatas1 = new bytes[](1);
        calldatas1[0] = abi.encodeWithSignature("withdraw(address,uint256)", voter1, 5 ether);
        string memory desc1 = "Proposal 1: Withdraw 5 ETH to voter1";

        vm.prank(owner);
        uint256 pid1 = gov.propose(targets1, values1, calldatas1, desc1);

        address[] memory targets2 = new address[](1);
        targets2[0] = address(bank);
        uint256[] memory values2 = new uint256[](1);
        values2[0] = 0;
        bytes[] memory calldatas2 = new bytes[](1);
        calldatas2[0] = abi.encodeWithSignature("withdraw(address,uint256)", voter2, 3 ether);
        string memory desc2 = "Proposal 2: Withdraw 3 ETH to voter2";

        vm.prank(owner);
        uint256 pid2 = gov.propose(targets2, values2, calldatas2, desc2);

        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(voter1);
        gov.castVote(pid1, 1);
        vm.prank(voter2);
        gov.castVote(pid1, 1);

        vm.prank(voter1);
        gov.castVote(pid2, 1);
        vm.prank(voter2);
        gov.castVote(pid2, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        bytes32 descHash1 = keccak256(abi.encodePacked(desc1));
        gov.execute(targets1, values1, calldatas1, descHash1);

        bytes32 descHash2 = keccak256(abi.encodePacked(desc2));
        gov.execute(targets2, values2, calldatas2, descHash2);

        assertEq(voter1.balance, 5 ether);
        assertEq(voter2.balance, 3 ether);
        assertEq(address(bank).balance, 92 ether);
    }

    // --- Quorum Test ---

    function test_QuorumNotReached() public {
        address smallHolder = makeAddr("smallHolder");
        uint256 smallAmount = 1000 * TOKEN_DECIMALS; // 0.1%
        token.transfer(smallHolder, smallAmount);
        vm.prank(smallHolder);
        token.delegate(smallHolder);

        uint256 proposalId = _createWithdrawProposal(owner, withdrawTarget, 10 ether);

        vm.roll(block.number + VOTING_DELAY + 1);

        // Only smallHolder votes (0.1% << 4% quorum)
        vm.prank(smallHolder);
        gov.castVote(proposalId, 1);

        vm.roll(block.number + VOTING_PERIOD + 1);

        // Defeated due to quorum not met
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Defeated));
    }
}
