# GhostLang Smart Contract Development Guide

> **Complete guide to building production-ready smart contracts with GhostLang**

## Table of Contents

1. [Getting Started](#getting-started)
2. [Development Workflow](#development-workflow)
3. [Testing Your Contracts](#testing-your-contracts)
4. [Gas Optimization](#gas-optimization)
5. [Security Best Practices](#security-best-practices)
6. [Deployment](#deployment)
7. [Integration with GhostChain](#integration-with-ghostchain)

## Getting Started

### Prerequisites

- Zig 0.16.0-dev or later
- GhostLang v0.2.3+
- Basic understanding of blockchain concepts

### Installation

```bash
git clone https://github.com/ghostlang/ghostlang
cd ghostlang
zig build
```

### Your First Contract

Create `HelloWorld.gza`:

```gza
-- Simple greeting contract
local greeting = "Hello, Blockchain!"

function init()
    greeting = "Contract deployed!"
    emit("ContractInitialized", greeting)
end

function getGreeting()
    return greeting
end

function setGreeting(new_greeting)
    web3.require(#new_greeting > 0, "Greeting cannot be empty")
    greeting = new_greeting
    emit("GreetingChanged", new_greeting)
end
```

## Development Workflow

### 1. Write Your Contract

Follow GhostLang syntax (Lua-compatible):

```gza
-- State variables
local owner = nil
local balance = 0

-- Constructor (called once on deployment)
function init()
    owner = web3.getCaller()
end

-- Public functions
function deposit(amount)
    balance = balance + amount
    emit("Deposited", {sender = web3.getCaller(), amount = amount})
end

-- View functions (don't modify state)
function getBalance()
    return balance
end
```

### 2. Test Locally

Create a test file `test_contract.zig`:

```zig
const std = @import("std");
const ghostlang = @import("ghostlang");

test "contract deployment and interaction" {
    const allocator = std.testing.allocator;

    // Create test environment
    var env = ghostlang.contract_test.TestEnvironment.init(allocator);
    defer env.deinit();

    // Create test accounts
    const alice = try env.createAccount("alice", 1000000);
    const bob = try env.createAccount("bob", 500000);

    // Deploy contract
    const contract = try env.deployContract(
        "MyContract",
        alice,
        "contract_bytecode_here",
    );

    // Call contract function
    const result = try env.call(
        alice,
        contract,
        "deposit",
        100,
        1000000, // gas limit
    );

    // Verify result
    try result.expectSuccess();
    try result.expectEvent("Deposited");

    // Check balance
    try ghostlang.contract_test.Assertions.expectBalance(&env, alice, 999900);
}
```

### 3. Profile Gas Usage

```zig
const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create gas profiler
    var profiler = ghostlang.gas_meter.GasProfiler.init(allocator);
    defer profiler.deinit();

    // Execute contract with profiling
    // ... contract execution ...

    // Print gas report
    profiler.printReport();
}
```

### 4. Optimize

Use gas profiling to identify expensive operations:

**Before:**
```gza
-- ❌ Inefficient: Multiple storage writes
function transfer(to, amount)
    balances[from] = balances[from] - amount
    balances[to] = balances[to] + amount
end
```

**After:**
```gza
-- ✅ Optimized: Batch updates
function transfer(to, amount)
    local new_from = balances[from] - amount
    local new_to = balances[to] + amount
    balances[from] = new_from
    balances[to] = new_to
end
```

## Testing Your Contracts

### Unit Testing

Test individual functions in isolation:

```zig
test "transfer tokens" {
    var env = ghostlang.contract_test.TestEnvironment.init(allocator);
    defer env.deinit();

    const alice = try env.createAccount("alice", 1000);
    const bob = try env.createAccount("bob", 0);

    // Deploy token contract
    const token = try env.deployContract("Token", alice, bytecode);

    // Transfer tokens
    const result = try env.call(alice, token, "transfer", .{bob, 100}, 0, 100000);
    try result.expectSuccess();

    // Verify balances
    // ... assertions ...
}
```

### Integration Testing

Test multiple contracts interacting:

```zig
test "DEX swap" {
    var env = ghostlang.contract_test.TestEnvironment.init(allocator);
    defer env.deinit();

    // Deploy token A
    const tokenA = try env.deployContract("TokenA", deployer, tokenA_bytecode);

    // Deploy token B
    const tokenB = try env.deployContract("TokenB", deployer, tokenB_bytecode);

    // Deploy DEX
    const dex = try env.deployContract("DEX", deployer, dex_bytecode);

    // Test swap
    // ... swap logic ...
}
```

### Fuzzing

Test with random inputs:

```zig
test "fuzz transfer amounts" {
    var env = ghostlang.contract_test.TestEnvironment.init(allocator);
    defer env.deinit();

    var fuzzer = ghostlang.contract_test.Fuzzer.init(12345);

    // Run 1000 random transfers
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const from = fuzzer.randomAddress();
        const to = fuzzer.randomAddress();
        const amount = fuzzer.randomAmount(1, 1000000);

        // Should never crash
        _ = env.call(from, contract, "transfer", .{to, amount}, 0, 100000) catch continue;
    }
}
```

### Time-based Testing

Test time-dependent logic:

```zig
test "staking lockup period" {
    var env = ghostlang.contract_test.TestEnvironment.init(allocator);
    defer env.deinit();

    const user = try env.createAccount("user", 10000);
    const staking = try env.deployContract("Staking", user, bytecode);

    // Stake tokens
    _ = try env.call(user, staking, "stake", .{1000}, 0, 100000);

    // Try to unstake immediately (should fail)
    const result1 = try env.call(user, staking, "unstake", .{1000}, 0, 100000);
    try result1.expectRevert();

    // Advance time by 30 days
    env.advanceTime(86400 * 30);

    // Try to unstake after lockup (should succeed)
    const result2 = try env.call(user, staking, "unstake", .{1000}, 0, 100000);
    try result2.expectSuccess();
}
```

## Gas Optimization

### Profiling

```bash
# Profile contract execution
zig build profile

# Output:
# === Gas Profiling Report ===
# Total Gas: 125,430
# Total Instructions: 1,250
#
# Top Gas Consumers:
# TABLE_SET          | 450 calls | 45,000 gas | 35.9%
# TABLE_GET          | 800 calls | 40,000 gas | 31.9%
# STORAGE_STORE      | 5 calls   | 25,000 gas | 19.9%
```

### Optimization Techniques

#### 1. Minimize Storage Operations

```gza
-- ❌ Bad: 4 storage operations
function swap(amount_in)
    local reserve_in = reserves[token_in]
    local reserve_out = reserves[token_out]
    reserve_in = reserve_in + amount_in
    reserve_out = reserve_out - amount_out
    reserves[token_in] = reserve_in
    reserves[token_out] = reserve_out
end

-- ✅ Good: 2 storage operations
function swap(amount_in)
    reserves[token_in] = reserves[token_in] + amount_in
    reserves[token_out] = reserves[token_out] - amount_out
end
```

#### 2. Use Local Variables

```gza
-- ❌ Bad: Multiple table lookups
if balances[user] > 100 and balances[user] < 1000 then
    balances[user] = balances[user] + 50
end

-- ✅ Good: Single lookup
local balance = balances[user]
if balance > 100 and balance < 1000 then
    balances[user] = balance + 50
end
```

#### 3. Batch Operations

```gza
-- ❌ Bad: N function calls
for i = 1, #recipients do
    transfer(recipients[i], amounts[i])
end

-- ✅ Good: Single function call
function batchTransfer(recipients, amounts)
    for i = 1, #recipients do
        local to = recipients[i]
        local amount = amounts[i]
        balances[web3.getCaller()] = balances[web3.getCaller()] - amount
        balances[to] = balances[to] + amount
    end
end
```

#### 4. Short-circuit Evaluation

```gza
-- ❌ Bad: Always evaluates both conditions
function canWithdraw(user, amount)
    if isNotLocked(user) and balances[user] >= amount then
        return true
    end
    return false
end

-- ✅ Good: Short-circuits on first failure
function canWithdraw(user, amount)
    if not isNotLocked(user) then return false end
    if balances[user] < amount then return false end
    return true
end
```

## Security Best Practices

### 1. Access Control

```gza
local owner = nil

function init()
    owner = web3.getCaller()
end

function onlyOwner()
    web3.require(web3.getCaller() == owner, "Not authorized")
end

function adminFunction()
    onlyOwner()
    -- admin logic
end
```

### 2. Reentrancy Protection

```gza
local locked = false

function noReentry()
    web3.require(not locked, "Reentrancy detected")
    locked = true
end

function withdraw()
    noReentry()

    local amount = balances[web3.getCaller()]
    balances[web3.getCaller()] = 0  -- Update state first!

    -- External call last
    web3.transfer(web3.getCaller(), amount)

    locked = false
end
```

### 3. Input Validation

```gza
function transfer(to, amount)
    web3.require(to ~= nil, "Invalid recipient")
    web3.require(amount > 0, "Amount must be positive")
    web3.require(amount <= balances[web3.getCaller()], "Insufficient balance")
    web3.require(to ~= web3.getThis(), "Cannot transfer to contract")

    -- transfer logic
end
```

### 4. Integer Overflow Protection

```gza
function safeAdd(a, b)
    local result = a + b
    web3.require(result >= a, "Overflow")
    return result
end

function safeSub(a, b)
    web3.require(b <= a, "Underflow")
    return a - b
end
```

## Deployment

### Using GhostChain CLI

```bash
# Compile contract
ghostchain-cli compile MyContract.gza --output contract.bytecode

# Deploy contract
ghostchain-cli deploy contract.bytecode \
    --gas-limit 5000000 \
    --from 0xYourAddress

# Output:
# ✅ Contract deployed successfully!
# Contract address: 0xabc123def456...
# Transaction hash: 0x789...
# Gas used: 1,234,567
```

### Programmatic Deployment

```zig
const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Initialize blockchain state
    var state = ghostlang.blockchain.WorldState.init(allocator);
    defer state.deinit();

    // Create executor
    var executor = ghostlang.blockchain.TransactionExecutor.init(
        allocator,
        &state,
        1,  // block number
        std.time.timestamp(),
        deployer_address,
        1,  // chain ID
    );

    // Read contract bytecode
    const bytecode = try std.fs.cwd().readFileAlloc(
        allocator,
        "contract.bytecode",
        1024 * 1024,
    );
    defer allocator.free(bytecode);

    // Create deployment transaction
    const tx = ghostlang.blockchain.Transaction{
        .from = deployer_address,
        .to = null,  // null for deployment
        .value = 0,
        .data = bytecode,
        .nonce = 0,
        .gas_limit = 5000000,
        .gas_price = 1,
        .signature = signature,
    };

    // Execute deployment
    const receipt = try executor.execute(tx);

    if (receipt.status == .success) {
        std.debug.print("✅ Deployed at: {x}\n", .{receipt.contract_address.?});
    } else {
        std.debug.print("❌ Deployment failed\n", .{});
    }
}
```

## Integration with GhostChain

### Connecting to Network

```zig
const ghostchain = @import("ghostchain");

// Connect to testnet
const client = try ghostchain.Client.connect("https://testnet.ghostchain.io");
defer client.deinit();

// Get chain info
const chain_id = try client.getChainId();
const latest_block = try client.getBlockNumber();

std.debug.print("Connected to chain {d} at block {d}\n", .{chain_id, latest_block});
```

### Sending Transactions

```zig
// Build transaction
var tx = try client.buildTransaction(.{
    .to = contract_address,
    .data = calldata,
    .gas_limit = 100000,
    .value = 0,
});

// Sign with private key
try tx.sign(private_key);

// Send transaction
const tx_hash = try client.sendTransaction(tx);

// Wait for confirmation
const receipt = try client.waitForReceipt(tx_hash, 60); // 60 second timeout

if (receipt.status == .success) {
    std.debug.print("✅ Transaction confirmed in block {d}\n", .{receipt.block_number});
} else {
    std.debug.print("❌ Transaction failed\n", .{});
}
```

### Listening for Events

```zig
// Subscribe to contract events
var subscription = try client.subscribeEvents(contract_address, &[_][]const u8{"Transfer"});
defer subscription.unsubscribe();

while (true) {
    const event = try subscription.nextEvent();

    std.debug.print("Event: {s}\n", .{event.name});
    std.debug.print("  From: {x}\n", .{event.topics[0]});
    std.debug.print("  To: {x}\n", .{event.topics[1]});
    std.debug.print("  Amount: {d}\n", .{event.data});
}
```

## Next Steps

- Explore [example contracts](./examples/)
- Read the [API Reference](../api.md)
- Join the [Discord community](https://discord.gg/ghostchain)
- Contribute on [GitHub](https://github.com/ghostchain/ghostlang)

---

**Version**: 0.2.3
**Last Updated**: 2025-01-12
**License**: MIT
