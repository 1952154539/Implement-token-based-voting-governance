// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";

/**
 * @title Gov
 * @dev 基于 Token 投票的治理合约，作为 Bank 合约的管理员
 *      代币持有者可以发起提案、投票并执行从 Bank 提取资金的操作
 *
 * 继承关系:
 *   Governor - 核心治理逻辑
 *   GovernorSettings - 投票延迟/周期/提案阈值配置
 *   GovernorCountingSimple - 简单计数(赞成/反对/弃权)
 *   GovernorVotes - 代币投票权重
 *   GovernorVotesQuorumFraction - 法定人数(以代币总量百分比计)
 */
contract Gov is Governor, GovernorSettings, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {

    error Gov__ProposalNotSucceeded();
    error Gov__ProposalAlreadyExecuted();

    constructor(
        IVotes _token,
        uint48 _initialVotingDelay,
        uint32 _initialVotingPeriod,
        uint256 _initialProposalThreshold,
        uint256 _quorumNumerator
    )
        Governor("Gov")
        GovernorSettings(_initialVotingDelay, _initialVotingPeriod, _initialProposalThreshold)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(_quorumNumerator)
    {}

    /**
     * @dev 获取法定人数（重写以解决多个继承的冲突）
     */
    function quorum(uint256 blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    /**
     * @dev 投票延迟
     */
    function votingDelay()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    /**
     * @dev 投票周期
     */
    function votingPeriod()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    /**
     * @dev 提案阈值 - 发起提案所需的最低代币数量
     */
    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    /**
     * @dev 提案执行，仅当提案状态为 Succeeded 时允许
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable override returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        ProposalState status = state(proposalId);
        if (status != ProposalState.Succeeded) {
            revert Gov__ProposalNotSucceeded();
        }

        return super.execute(targets, values, calldatas, descriptionHash);
    }
}
