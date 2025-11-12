//! Smart Contract Testing Framework
//!
//! Comprehensive testing utilities for GhostLang smart contracts:
//! - Mock blockchain environment
//! - Account management
//! - Transaction simulation
//! - Event assertion
//! - Gas profiling
//! - Time manipulation
//! - Multi-contract deployments

const std = @import("std");
const root = @import("root.zig");
const web3 = @import("web3.zig");
const blockchain = @import("blockchain.zig");
const gas_meter = @import("gas_meter.zig");

/// Test account with balance and nonce
pub const TestAccount = struct {
    address: web3.Address,
    balance: u64,
    nonce: u64,
    label: []const u8,

    pub fn init(label: []const u8, balance: u64) TestAccount {
        var prng = std.Random.DefaultPrng.init(@bitCast(std.time.nanoTimestamp()));
        const random = prng.random();

        var address: web3.Address = undefined;
        random.bytes(&address);

        return .{
            .address = address,
            .balance = balance,
            .nonce = 0,
            .label = label,
        };
    }
};

/// Test environment for smart contract testing
pub const TestEnvironment = struct {
    allocator: std.mem.Allocator,
    state: blockchain.WorldState,
    accounts: std.ArrayList(TestAccount),
    deployed_contracts: std.AutoHashMap(web3.Address, DeployedContract),
    block_number: u64,
    block_timestamp: u64,
    chain_id: u64,
    events: std.ArrayList(web3.Event),

    const DeployedContract = struct {
        address: web3.Address,
        code: []const u8,
        label: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) TestEnvironment {
        return .{
            .allocator = allocator,
            .state = blockchain.WorldState.init(allocator),
            .accounts = std.ArrayList(TestAccount).init(allocator),
            .deployed_contracts = std.AutoHashMap(web3.Address, DeployedContract).init(allocator),
            .block_number = 1,
            .block_timestamp = 1234567890,
            .chain_id = 31337, // hardhat default
            .events = std.ArrayList(web3.Event).init(allocator),
        };
    }

    pub fn deinit(self: *TestEnvironment) void {
        self.state.deinit();
        self.accounts.deinit();

        var it = self.deployed_contracts.valueIterator();
        while (it.next()) |contract| {
            self.allocator.free(contract.code);
            self.allocator.free(contract.label);
        }
        self.deployed_contracts.deinit();

        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.deinit();
    }

    /// Create a new test account
    pub fn createAccount(self: *TestEnvironment, label: []const u8, balance: u64) !web3.Address {
        const account = TestAccount.init(label, balance);

        try self.state.setBalance(account.address, balance);
        try self.accounts.append(account);

        std.log.info("Created account '{s}' with balance {d}", .{ label, balance });

        return account.address;
    }

    /// Get account by label
    pub fn getAccount(self: *TestEnvironment, label: []const u8) ?TestAccount {
        for (self.accounts.items) |account| {
            if (std.mem.eql(u8, account.label, label)) {
                return account;
            }
        }
        return null;
    }

    /// Deploy a contract
    pub fn deployContract(
        self: *TestEnvironment,
        label: []const u8,
        deployer: web3.Address,
        bytecode: []const u8,
    ) !web3.Address {
        const nonce = self.state.getNonce(deployer);

        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(&deployer);
        hasher.update(std.mem.asBytes(&nonce));

        var address: web3.Address = undefined;
        hasher.final(&address);

        // Store contract code
        const code_copy = try self.allocator.dupe(u8, bytecode);
        try self.state.deployContract(address, code_copy);

        // Track deployment
        const label_copy = try self.allocator.dupe(u8, label);
        try self.deployed_contracts.put(address, .{
            .address = address,
            .code = code_copy,
            .label = label_copy,
        });

        try self.state.incrementNonce(deployer);

        std.log.info("Deployed contract '{s}' at {x}", .{ label, std.fmt.fmtSliceHexLower(&address) });

        return address;
    }

    /// Call a contract function
    pub fn call(
        self: *TestEnvironment,
        caller: web3.Address,
        contract: web3.Address,
        calldata: []const u8,
        value: u64,
        gas_limit: u64,
    ) !CallResult {
        var executor = blockchain.TransactionExecutor.init(
            self.allocator,
            &self.state,
            self.block_number,
            self.block_timestamp,
            caller, // Use caller as coinbase for tests
            self.chain_id,
        );

        const tx = blockchain.Transaction{
            .from = caller,
            .to = contract,
            .value = value,
            .data = calldata,
            .nonce = self.state.getNonce(caller),
            .gas_limit = gas_limit,
            .gas_price = 1,
            .signature = [_]u8{0} ** 64, // Mock signature for testing
        };

        const receipt = try executor.execute(tx);

        // Collect emitted events
        try self.events.appendSlice(receipt.logs);

        return CallResult{
            .success = receipt.status == .success,
            .gas_used = receipt.gas_used,
            .events = receipt.logs,
        };
    }

    /// Static call (doesn't modify state)
    pub fn staticCall(
        self: *TestEnvironment,
        caller: web3.Address,
        contract: web3.Address,
        calldata: []const u8,
    ) ![]const u8 {
        // TODO: Implement view/pure function calls
        _ = self;
        _ = caller;
        _ = contract;
        _ = calldata;
        return &[_]u8{};
    }

    /// Mine a block (advance time and block number)
    pub fn mineBlock(self: *TestEnvironment) void {
        self.block_number += 1;
        self.block_timestamp += 12; // 12 second block time

        std.log.info("Mined block {d} at timestamp {d}", .{ self.block_number, self.block_timestamp });
    }

    /// Mine multiple blocks
    pub fn mineBlocks(self: *TestEnvironment, count: u64) void {
        var i: u64 = 0;
        while (i < count) : (i += 1) {
            self.mineBlock();
        }
    }

    /// Set block timestamp
    pub fn setTimestamp(self: *TestEnvironment, timestamp: u64) void {
        self.block_timestamp = timestamp;
    }

    /// Advance time by seconds
    pub fn advanceTime(self: *TestEnvironment, seconds: u64) void {
        self.block_timestamp += seconds;
    }

    /// Get balance
    pub fn getBalance(self: *TestEnvironment, address: web3.Address) u64 {
        return self.state.getBalance(address);
    }

    /// Get events emitted during tests
    pub fn getEvents(self: *TestEnvironment) []const web3.Event {
        return self.events.items;
    }

    /// Clear event log
    pub fn clearEvents(self: *TestEnvironment) void {
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.clearRetainingCapacity();
    }

    /// Snapshot state (for reverting)
    pub fn snapshot(self: *TestEnvironment) !Snapshot {
        return Snapshot{
            .block_number = self.block_number,
            .block_timestamp = self.block_timestamp,
            .state_root = try self.state.calculateStateRoot(),
        };
    }

    /// Revert to snapshot
    pub fn revert(self: *TestEnvironment, snap: Snapshot) void {
        self.block_number = snap.block_number;
        self.block_timestamp = snap.block_timestamp;
        // TODO: Implement full state revert
        _ = snap.state_root;
    }

    const Snapshot = struct {
        block_number: u64,
        block_timestamp: u64,
        state_root: [32]u8,
    };
};

/// Result of a contract call
pub const CallResult = struct {
    success: bool,
    gas_used: u64,
    events: []web3.Event,

    pub fn expectSuccess(self: CallResult) !void {
        if (!self.success) {
            return error.CallFailed;
        }
    }

    pub fn expectRevert(self: CallResult) !void {
        if (self.success) {
            return error.ExpectedRevert;
        }
    }

    pub fn expectEvent(self: CallResult, event_name: []const u8) !web3.Event {
        for (self.events) |event| {
            // Match event by first topic (event signature)
            if (event.topics.len > 0) {
                const topic_hash = event.topics[0];
                const expected_hash = web3.Crypto.hash(event_name);

                if (std.mem.eql(u8, &topic_hash, &expected_hash)) {
                    return event;
                }
            }
        }
        std.log.err("Event '{s}' not found in {d} emitted events", .{ event_name, self.events.len });
        return error.EventNotFound;
    }

    pub fn expectGasLessThan(self: CallResult, max_gas: u64) !void {
        if (self.gas_used >= max_gas) {
            std.log.err("Gas used ({d}) exceeds maximum ({d})", .{ self.gas_used, max_gas });
            return error.GasExceeded;
        }
    }
};

/// Assertion helpers for testing
pub const Assertions = struct {
    /// Assert balance equals expected
    pub fn expectBalance(env: *TestEnvironment, account: web3.Address, expected: u64) !void {
        const actual = env.getBalance(account);
        if (actual != expected) {
            std.log.err("Balance mismatch: expected {d}, got {d}", .{ expected, actual });
            return error.BalanceMismatch;
        }
    }

    /// Assert event was emitted
    pub fn expectEventEmitted(env: *TestEnvironment, event_name: []const u8) !web3.Event {
        const events = env.getEvents();
        for (events) |event| {
            if (event.topics.len > 0) {
                const topic_hash = event.topics[0];
                const expected_hash = web3.Crypto.hash(event_name);

                if (std.mem.eql(u8, &topic_hash, &expected_hash)) {
                    return event;
                }
            }
        }
        return error.EventNotFound;
    }

    /// Assert storage value
    pub fn expectStorage(
        env: *TestEnvironment,
        contract: web3.Address,
        key: web3.Hash,
        expected: web3.Hash,
    ) !void {
        const actual = env.state.storageGet(contract, key);
        if (!std.mem.eql(u8, &actual, &expected)) {
            std.log.err("Storage mismatch at contract {x}", .{std.fmt.fmtSliceHexLower(&contract)});
            return error.StorageMismatch;
        }
    }
};

/// Fuzzing utilities for contract testing
pub const Fuzzer = struct {
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) Fuzzer {
        return .{
            .prng = std.Random.DefaultPrng.init(seed),
        };
    }

    pub fn randomAddress(self: *Fuzzer) web3.Address {
        const random = self.prng.random();
        var address: web3.Address = undefined;
        random.bytes(&address);
        return address;
    }

    pub fn randomAmount(self: *Fuzzer, min: u64, max: u64) u64 {
        const random = self.prng.random();
        return random.intRangeAtMost(u64, min, max);
    }

    pub fn randomBytes(self: *Fuzzer, comptime n: usize) [n]u8 {
        const random = self.prng.random();
        var bytes: [n]u8 = undefined;
        random.bytes(&bytes);
        return bytes;
    }
};

test "test environment basic" {
    const allocator = std.testing.allocator;

    var env = TestEnvironment.init(allocator);
    defer env.deinit();

    // Create accounts
    const alice = try env.createAccount("alice", 1000);
    const bob = try env.createAccount("bob", 500);

    // Check balances
    try Assertions.expectBalance(&env, alice, 1000);
    try Assertions.expectBalance(&env, bob, 500);

    // Mine blocks
    env.mineBlock();
    try std.testing.expectEqual(@as(u64, 2), env.block_number);
}

test "fuzzer" {
    var fuzzer = Fuzzer.init(12345);

    const addr1 = fuzzer.randomAddress();
    const addr2 = fuzzer.randomAddress();

    // Should be different
    try std.testing.expect(!std.mem.eql(u8, &addr1, &addr2));

    const amount = fuzzer.randomAmount(100, 1000);
    try std.testing.expect(amount >= 100 and amount <= 1000);
}
