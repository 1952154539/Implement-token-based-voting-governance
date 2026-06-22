# 基于 Token 投票治理的实现

基于 Solidity + Foundry 实现的 Token 投票治理系统，通过 DAO 管理 Bank 资金使用。

## 架构设计

```
+--------------+     +------------------+     +--------------+
|   GovToken   |     |       Gov        |     |     Bank     |
|  (ERC20Votes)|---->|  (Governor)      |---->|  (ETH Vault) |
|              |     |                  |     |              |
| - 投票权重    |     | - 提案创建        |     | - 接收ETH    |
| - 委托投票    |     | - 投票计数        |     | - 管理员提现  |
| - 历史快照    |     | - 提案执行        |     |              |
+--------------+     +------------------+     +--------------+
```

### 合约说明

| 合约 | 功能 |
|------|------|
| `GovToken.sol` | ERC20 治理代币，集成 ERC20Votes 实现 checkpoint 机制的投票权重追踪 |
| `Bank.sol` | ETH 资金库，仅管理员（Gov 合约）可调用 `withdraw()` 提取资金 |
| `Gov.sol` | 治理合约，管理提案的完整生命周期：提案→投票→执行 |

### 治理流程

1. **提案阶段**：代币持有者（达到提案阈值）发起提案，指定目标合约和调用数据
2. **投票阶段**：代币持有者在投票期内投票（支持/反对/弃权），投票权重基于提案创建时的代币持有量快照
3. **执行阶段**：投票期结束后，通过的提案可被任何人执行，Gov 合约以管理员身份调用 Bank.withdraw()

## 快速开始

### 环境要求

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### 安装依赖

```bash
forge install
```

### 编译

```bash
forge build
```

### 运行测试

```bash
forge test -vvv
```

### 部署

```bash
# 设置私钥环境变量
export PRIVATE_KEY=<your_private_key>

# 本地部署
forge script script/DeployGovernance.s.sol --rpc-url http://localhost:8545 --broadcast

# Sepolia 测试网部署
forge script script/DeployGovernance.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --broadcast \
  --verify
```

## 测试用例

共 35 个测试用例，覆盖以下场景：

### GovToken 测试（7个）
- 初始供应量验证
- 铸造权限控制
- 投票委托
- 历史投票权重查询（checkpoint 机制）
- 转账更新投票权重
- 接收代币后自我委托

### Bank 测试（10个）
- 初始管理员验证
- 管理员提取资金
- 非管理员提取失败
- 零金额/零地址/余额不足提取失败
- 管理员权限转移
- ETH 接收和余额查询

### 治理测试（18个）
- 提案创建（满足/不满足阈值）
- 投票（支持/反对/弃权）
- 多人投票
- 重复投票阻止
- 投票期前后投票阻止
- 提案状态流转（Pending→Active→Succeeded/Defeated）
- **完整流程：提案→投票→执行（从 Bank 提取 ETH）**
- 投票期未结束执行阻止
- 已否决提案执行阻止
- 重复执行阻止
- 多提案并行处理
- 法定人数不足被否决

## 治理参数

| 参数 | 测试环境 | 生产环境建议 |
|------|---------|------------|
| 初始供应量 | 1,000,000 GOV | 按需设定 |
| 投票延迟 | 1 区块 | ~1 天 |
| 投票周期 | 30 区块 | ~1 周 |
| 提案阈值 | 10,000 GOV | 总供应量的 1% |
| 法定人数 | 4% | 4%-10% |

## 核心机制

### 计票 Token（GovToken）

通过 OpenZeppelin 的 ERC20Votes 实现 checkpoint 机制：

- 每次代币转账或委托时记录投票权重快照
- `getPastVotes(address account, uint256 blockNumber)` 查询历史投票权重
- 治理合约在提案创建时使用 `clock() - 1` 时刻的快照，防止同一区块内的投票权重操纵
- 支持通过 EIP-712 签名进行无 Gas 委托

### 提案执行

Governor 合约通过 `execute()` 函数执行通过的提案：

```solidity
// 提案数据：调用 Bank.withdraw(to, amount)
targets = [bankAddress]
values = [0]
calldatas = [abi.encodeWithSignature("withdraw(address,uint256)", to, amount)]
```

执行时 Gov 合约以 Bank 管理员身份调用 `withdraw()`，将 ETH 从 Bank 转出到提案指定的地址。

## 安全特性

- Bank 使用 `onlyAdmin` 修饰符限制资金提取权限
- GovToken 基于 checkpoint 机制防止投票权重操纵
- 治理合约继承 OpenZeppelin Governor 框架，经过审计和广泛使用
- 提案执行后标记 `executed = true`，防止重入和重复执行

## 参考

- [OpenZeppelin Governor 文档](https://docs.openzeppelin.com/contracts/5.x/governance)
- [ERC20Votes 实现](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#ERC20Votes)
- [基于 Token 投票治理教程](https://learnblockchain.cn/article/3170)
