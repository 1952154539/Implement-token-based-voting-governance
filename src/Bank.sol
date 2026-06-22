// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Bank
 * @dev 持有 ETH 的资金库，仅管理员可调用 withdraw() 提取资金
 *      管理员为 Gov 治理合约，实现 DAO 对资金的管理
 */
contract Bank {
    error Bank__NotAdmin();
    error Bank__ZeroAddress();
    error Bank__ZeroAmount();
    error Bank__InsufficientBalance();
    error Bank__TransferFailed();

    address public admin;
    uint256 public totalDeposits;

    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Bank__NotAdmin();
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    /**
     * @dev 接收 ETH 存款
     */
    receive() external payable {
        totalDeposits += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @dev 仅管理员提取资金
     * @param to 接收地址
     * @param amount 提取金额
     */
    function withdraw(address to, uint256 amount) external onlyAdmin {
        if (to == address(0)) revert Bank__ZeroAddress();
        if (amount == 0) revert Bank__ZeroAmount();
        if (amount > address(this).balance) revert Bank__InsufficientBalance();

        totalDeposits -= amount;
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert Bank__TransferFailed();

        emit Withdrawn(to, amount);
    }

    /**
     * @dev 转移管理员权限
     * @param newAdmin 新管理员地址
     */
    function setAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert Bank__ZeroAddress();
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }

    /**
     * @dev 查询合约余额
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
