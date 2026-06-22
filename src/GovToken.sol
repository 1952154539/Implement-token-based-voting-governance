// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GovToken
 * @dev 支持投票计票的治理代币，集成 ERC20Votes 实现 checkpoint 机制的投票权重追踪
 */
contract GovToken is ERC20, ERC20Permit, ERC20Votes, Ownable {
    error GovToken__ZeroAddress();

    constructor(uint256 initialSupply)
        ERC20("GovernanceToken", "GOV")
        ERC20Permit("GovernanceToken")
        Ownable(msg.sender)
    {
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev 铸造代币，仅限 owner
     * @param to 接收地址
     * @param amount 铸造数量
     */
    function mint(address to, uint256 amount) public onlyOwner {
        if (to == address(0)) revert GovToken__ZeroAddress();
        _mint(to, amount);
    }

    // 以下 override 是 Solidity 要求的，因为 ERC20 和 ERC20Votes 都需要这些函数
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
