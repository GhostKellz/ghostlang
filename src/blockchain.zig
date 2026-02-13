//! GhostLang Blockchain VM Integration
//!
//! This module implements the execution layer that bridges:
//! - GhostChain consensus (transaction ordering, state roots)
//! - GhostLang VM (script execution, gas metering)
//! - Web3 API (storage, events, crypto)
//!
//! Architecture:
//! ```
//! GhostChain Consensus
//!         ↓
//!   TransactionExecutor (this module)
//!         ↓
//!   GhostLang VM + Web3 API
//!         ↓
//!   State Transition
//! ```

const std = @import("std");
const root = @import("root.zig");
const web3 = @import("web3.zig");

/// Transaction types
pub const TransactionType = enum(u8) {
    transfer = 0, // Native token transfer
    contract_deploy = 1, // Deploy new contract
    contract_call = 2, // Call existing contract
};

/// Transaction structure
pub const Transaction = struct {
    from: web3.Address,
    to: ?web3.Address, // null for contract creation
    value: u64,
    data: []const u8, // calldata or bytecode
    nonce: u64,
    gas_limit: u64,
    gas_price: u64,
    signature: web3.Signature,

    pub fn hash(self: Transaction) web3.Hash {
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(&self.from);
        if (self.to) |to_addr| {
            hasher.update(&to_addr);
        }
        hasher.update(std.mem.asBytes(&self.value));
        hasher.update(self.data);
        hasher.update(std.mem.asBytes(&self.nonce));
        hasher.update(std.mem.asBytes(&self.gas_limit));

        var result: web3.Hash = undefined;
        hasher.final(&result);
        return result;
    }

    pub fn gasRequired(self: Transaction) u64 {
        var total: u64 = web3.Gas.TX_BASE;

        // Add calldata cost
        total += web3.Gas.calculateCalldata(self.data);

        // Add contract creation cost if applicable
        if (self.to == null) {
            total += web3.Gas.CREATE;
        }

        return total;
    }
};

/// World state - global blockchain state
pub const WorldState = struct {
    allocator: std.mem.Allocator,

    /// Account balances
    balances: std.AutoHashMap(web3.Address, u64),

    /// Contract code storage
    contracts: std.AutoHashMap(web3.Address, []const u8),

    /// Contract storage (address -> key -> value)
    storage: std.AutoHashMap(web3.Address, std.AutoHashMap(web3.Hash, web3.Hash)),

    /// Nonce tracking (for replay protection)
    nonces: std.AutoHashMap(web3.Address, u64),

    /// Event log buffer
    events: std.ArrayList(web3.Event),

    pub fn init(allocator: std.mem.Allocator) WorldState {
        return .{
            .allocator = allocator,
            .balances = std.AutoHashMap(web3.Address, u64).init(allocator),
            .contracts = std.AutoHashMap(web3.Address, []const u8).init(allocator),
            .storage = std.AutoHashMap(web3.Address, std.AutoHashMap(web3.Hash, web3.Hash)).init(allocator),
            .nonces = std.AutoHashMap(web3.Address, u64).init(allocator),
            .events = std.ArrayList(web3.Event).init(allocator),
        };
    }

    pub fn deinit(self: *WorldState) void {
        self.balances.deinit();

        // Free contract bytecode
        var contract_it = self.contracts.valueIterator();
        while (contract_it.next()) |code| {
            self.allocator.free(code.*);
        }
        self.contracts.deinit();

        // Free storage maps
        var storage_it = self.storage.valueIterator();
        while (storage_it.next()) |map| {
            map.deinit();
        }
        self.storage.deinit();

        self.nonces.deinit();

        // Free event data
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.deinit();
    }

    /// Get account balance
    pub fn getBalance(self: *WorldState, address: web3.Address) u64 {
        return self.balances.get(address) orelse 0;
    }

    /// Set account balance
    pub fn setBalance(self: *WorldState, address: web3.Address, balance: u64) !void {
        try self.balances.put(address, balance);
    }

    /// Transfer value between accounts
    pub fn transfer(self: *WorldState, from: web3.Address, to: web3.Address, amount: u64) !void {
        const from_balance = self.getBalance(from);
        if (from_balance < amount) return error.InsufficientBalance;

        const to_balance = self.getBalance(to);

        try self.setBalance(from, from_balance - amount);
        try self.setBalance(to, to_balance + amount);
    }

    /// Get contract code
    pub fn getCode(self: *WorldState, address: web3.Address) ?[]const u8 {
        return self.contracts.get(address);
    }

    /// Deploy contract code
    pub fn deployContract(self: *WorldState, address: web3.Address, code: []const u8) !void {
        const code_copy = try self.allocator.dupe(u8, code);
        try self.contracts.put(address, code_copy);
    }

    /// Check if address is a contract
    pub fn isContract(self: *WorldState, address: web3.Address) bool {
        return self.contracts.contains(address);
    }

    /// Get storage value
    pub fn storageGet(self: *WorldState, contract: web3.Address, key: web3.Hash) web3.Hash {
        if (self.storage.get(contract)) |contract_storage| {
            return contract_storage.get(key) orelse [_]u8{0} ** 32;
        }
        return [_]u8{0} ** 32;
    }

    /// Set storage value
    pub fn storageSet(self: *WorldState, contract: web3.Address, key: web3.Hash, value: web3.Hash) !void {
        const entry = try self.storage.getOrPut(contract);
        if (!entry.found_existing) {
            entry.value_ptr.* = std.AutoHashMap(web3.Hash, web3.Hash).init(self.allocator);
        }
        try entry.value_ptr.put(key, value);
    }

    /// Get nonce
    pub fn getNonce(self: *WorldState, address: web3.Address) u64 {
        return self.nonces.get(address) orelse 0;
    }

    /// Increment nonce
    pub fn incrementNonce(self: *WorldState, address: web3.Address) !void {
        const current = self.getNonce(address);
        try self.nonces.put(address, current + 1);
    }

    /// Add event log
    pub fn emitEvent(self: *WorldState, event: web3.Event) !void {
        try self.events.append(event);
    }

    /// Calculate state root (Merkle root of all accounts)
    pub fn calculateStateRoot(self: *WorldState) ![32]u8 {
        // Simplified - in production, use Merkle Patricia Trie
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});

        var it = self.balances.iterator();
        while (it.next()) |entry| {
            hasher.update(&entry.key_ptr.*);
            hasher.update(std.mem.asBytes(&entry.value_ptr.*));
        }

        var result: [32]u8 = undefined;
        hasher.final(&result);
        return result;
    }
};

/// Storage interface implementation for WorldState
const WorldStateStorage = struct {
    state: *WorldState,

    pub fn storageVTable() web3.Storage.VTable {
        return .{
            .get = get,
            .set = set,
        };
    }

    fn get(ptr: *anyopaque, contract: web3.Address, key: web3.Hash) !web3.Hash {
        const self: *WorldStateStorage = @ptrCast(@alignCast(ptr));
        return self.state.storageGet(contract, key);
    }

    fn set(ptr: *anyopaque, contract: web3.Address, key: web3.Hash, value: web3.Hash) !void {
        const self: *WorldStateStorage = @ptrCast(@alignCast(ptr));
        try self.state.storageSet(contract, key, value);
    }
};

/// Event logger implementation
const WorldStateEventLogger = struct {
    state: *WorldState,
    contract_address: web3.Address,
    block_number: u64,
    tx_hash: web3.Hash,

    pub fn eventLoggerVTable() web3.EventLogger.VTable {
        return .{
            .emit = emit,
        };
    }

    fn emit(ptr: *anyopaque, contract: web3.Address, topics: []const web3.Hash, data: []const u8) !void {
        const self: *WorldStateEventLogger = @ptrCast(@alignCast(ptr));

        const topics_copy = try self.state.allocator.dupe(web3.Hash, topics);
        const data_copy = try self.state.allocator.dupe(u8, data);

        const event = web3.Event{
            .address = contract,
            .topics = topics_copy,
            .data = data_copy,
            .block_number = self.block_number,
            .tx_hash = self.tx_hash,
            .log_index = @intCast(self.state.events.items.len),
        };

        try self.state.emitEvent(event);
    }
};

/// Balance query implementation
const WorldStateBalanceQuery = struct {
    state: *WorldState,

    pub fn balanceQueryVTable() web3.BalanceQuery.VTable {
        return .{
            .get = get,
            .transfer = transfer,
        };
    }

    fn get(ptr: *anyopaque, address: web3.Address) !u64 {
        const self: *WorldStateBalanceQuery = @ptrCast(@alignCast(ptr));
        return self.state.getBalance(address);
    }

    fn transfer(ptr: *anyopaque, from: web3.Address, to: web3.Address, amount: u64) !void {
        const self: *WorldStateBalanceQuery = @ptrCast(@alignCast(ptr));
        try self.state.transfer(from, to, amount);
    }
};

/// Transaction executor - executes transactions and updates state
pub const TransactionExecutor = struct {
    allocator: std.mem.Allocator,
    state: *WorldState,
    block_number: u64,
    block_timestamp: u64,
    block_coinbase: web3.Address,
    chain_id: u64,

    pub fn init(
        allocator: std.mem.Allocator,
        state: *WorldState,
        block_number: u64,
        block_timestamp: u64,
        block_coinbase: web3.Address,
        chain_id: u64,
    ) TransactionExecutor {
        return .{
            .allocator = allocator,
            .state = state,
            .block_number = block_number,
            .block_timestamp = block_timestamp,
            .block_coinbase = block_coinbase,
            .chain_id = chain_id,
        };
    }

    /// Execute a transaction
    pub fn execute(self: *TransactionExecutor, tx: Transaction) !web3.Receipt {
        // Verify nonce
        const expected_nonce = self.state.getNonce(tx.from);
        if (tx.nonce != expected_nonce) {
            return error.InvalidNonce;
        }

        // Check gas limit
        const required_gas = tx.gasRequired();
        if (tx.gas_limit < required_gas) {
            return error.InsufficientGas;
        }

        // Calculate gas cost
        const gas_cost = tx.gas_limit * tx.gas_price;

        // Check sender balance (value + gas)
        const sender_balance = self.state.getBalance(tx.from);
        if (sender_balance < tx.value + gas_cost) {
            return error.InsufficientBalance;
        }

        // Deduct gas pre-payment
        try self.state.setBalance(tx.from, sender_balance - gas_cost);

        // Increment nonce
        try self.state.incrementNonce(tx.from);

        var gas_used: u64 = required_gas;
        var status = web3.Receipt.Status.success;
        var contract_address: ?web3.Address = null;

        // Execute based on transaction type
        if (tx.to == null) {
            // Contract deployment
            contract_address = blk: {
                const addr = self.deployContract(tx) catch |err| {
                    std.log.err("Contract deployment failed: {}", .{err});
                    status = .failure;
                    break :blk null;
                };
                break :blk addr;
            };
        } else if (self.state.isContract(tx.to.?)) {
            // Contract call
            gas_used = blk: {
                const gas = self.callContract(tx, &status) catch |err| {
                    std.log.err("Contract call failed: {}", .{err});
                    status = .failure;
                    break :blk required_gas;
                };
                break :blk gas;
            };
        } else {
            // Simple transfer
            self.state.transfer(tx.from, tx.to.?, tx.value) catch |err| {
                std.log.err("Transfer failed: {}", .{err});
                status = .failure;
            };
        }

        // Refund unused gas
        const gas_refund = tx.gas_limit - gas_used;
        const refund_amount = gas_refund * tx.gas_price;
        const new_balance = self.state.getBalance(tx.from) + refund_amount;
        try self.state.setBalance(tx.from, new_balance);

        // Pay gas fee to validator
        const fee = gas_used * tx.gas_price;
        const validator_balance = self.state.getBalance(self.block_coinbase);
        try self.state.setBalance(self.block_coinbase, validator_balance + fee);

        // Collect events emitted during execution
        const events = try self.allocator.dupe(web3.Event, self.state.events.items);

        return web3.Receipt{
            .tx_hash = tx.hash(),
            .from = tx.from,
            .to = tx.to,
            .status = status,
            .gas_used = gas_used,
            .logs = events,
            .contract_address = contract_address,
        };
    }

    /// Deploy a contract
    fn deployContract(self: *TransactionExecutor, tx: Transaction) !web3.Address {
        // Generate contract address (deterministic from sender + nonce)
        const address = self.generateContractAddress(tx.from, tx.nonce);

        // Store contract code
        try self.state.deployContract(address, tx.data);

        // Transfer value to contract
        if (tx.value > 0) {
            try self.state.transfer(tx.from, address, tx.value);
        }

        std.log.info("Deployed contract at {x}", .{std.fmt.fmtSliceHexLower(&address)});

        // Execute constructor if present
        try self.executeConstructor(address, tx.from, tx.value, tx.gas_limit);

        return address;
    }

    /// Execute contract constructor (init/constructor function)
    fn executeConstructor(
        self: *TransactionExecutor,
        contract: web3.Address,
        deployer: web3.Address,
        value: u64,
        gas_limit: u64,
    ) !void {
        // Get contract code
        const code = self.state.getCode(contract) orelse return;

        // Check for constructor signature in bytecode
        // In GhostLang, constructors are functions named "constructor" or "init"
        const has_constructor = findConstructor(code);

        if (!has_constructor) {
            std.log.debug("No constructor found in contract", .{});
            return;
        }

        // Create execution context for constructor
        var storage_impl = WorldStateStorage{ .state = self.state };
        var event_logger_impl = WorldStateEventLogger{
            .state = self.state,
            .contract_address = contract,
            .block_number = self.block_number,
            .tx_hash = [_]u8{0} ** 32, // No tx hash for constructor
        };
        var balance_query_impl = WorldStateBalanceQuery{ .state = self.state };

        var ctx = web3.Context{
            .allocator = self.allocator,
            .caller = deployer,
            .this = contract,
            .origin = deployer,
            .value = value,
            .gas_available = gas_limit,
            .block_number = self.block_number,
            .block_timestamp = self.block_timestamp,
            .block_coinbase = self.block_coinbase,
            .chain_id = self.chain_id,
            .storage = @ptrCast(@alignCast(&storage_impl)),
            .event_logger = @ptrCast(@alignCast(&event_logger_impl)),
            .balance_query = @ptrCast(@alignCast(&balance_query_impl)),
        };

        // Execute constructor
        // The constructor receives no calldata (or constructor args in data)
        _ = try self.executeContractCode(contract, &[_]u8{}, &ctx);

        std.log.info("Constructor executed for contract {x}", .{std.fmt.fmtSliceHexLower(&contract)});
    }

    /// Check if bytecode contains a constructor function
    fn findConstructor(code: []const u8) bool {
        // Search for "constructor" or "init" function signature in bytecode
        // This is a simplified check - in production, parse the bytecode properly
        const constructor_sig = "constructor";
        const init_sig = "function init";

        if (std.mem.indexOf(u8, code, constructor_sig) != null) return true;
        if (std.mem.indexOf(u8, code, init_sig) != null) return true;

        return false;
    }

    /// Call a contract
    fn callContract(self: *TransactionExecutor, tx: Transaction, status: *web3.Receipt.Status) !u64 {
        const contract_address = tx.to.?;

        // Create execution context
        var storage_impl = WorldStateStorage{ .state = self.state };
        _ = &storage_impl; // used via pointer cast

        var event_logger_impl = WorldStateEventLogger{
            .state = self.state,
            .contract_address = contract_address,
            .block_number = self.block_number,
            .tx_hash = tx.hash(),
        };
        _ = &event_logger_impl; // used via pointer cast

        var balance_query_impl = WorldStateBalanceQuery{ .state = self.state };
        _ = &balance_query_impl; // used via pointer cast

        var ctx = web3.Context{
            .allocator = self.allocator,
            .caller = tx.from,
            .this = contract_address,
            .origin = tx.from,
            .value = tx.value,
            .gas_available = tx.gas_limit,
            .block_number = self.block_number,
            .block_timestamp = self.block_timestamp,
            .block_coinbase = self.block_coinbase,
            .chain_id = self.chain_id,
            .storage = @ptrCast(@alignCast(&storage_impl)),
            .event_logger = @ptrCast(@alignCast(&event_logger_impl)),
            .balance_query = @ptrCast(@alignCast(&balance_query_impl)),
        };

        // Execute contract code (placeholder - integrate GhostLang VM)
        const result = self.executeContractCode(contract_address, tx.data, &ctx) catch |err| {
            status.* = .failure;
            return err;
        };

        _ = result;

        const gas_used = tx.gas_limit - ctx.gas_available;
        return gas_used;
    }

    /// Execute contract bytecode (placeholder for GhostLang VM integration)
    fn executeContractCode(
        self: *TransactionExecutor,
        contract: web3.Address,
        calldata: []const u8,
        ctx: *web3.Context,
    ) !void {
        _ = self;
        _ = contract;
        _ = calldata;
        _ = ctx;

        // TODO: Integrate with GhostLang VM
        // 1. Load contract bytecode/script
        // 2. Parse function selector from calldata
        // 3. Execute GhostLang script with context
        // 4. Return result

        std.log.warn("Contract execution not yet implemented - VM integration pending", .{});
    }

    /// Generate deterministic contract address
    fn generateContractAddress(self: *TransactionExecutor, sender: web3.Address, nonce: u64) web3.Address {
        _ = self;
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(&sender);
        hasher.update(std.mem.asBytes(&nonce));

        var result: web3.Address = undefined;
        hasher.final(&result);
        return result;
    }
};

test "world state basics" {
    const allocator = std.testing.allocator;

    var state = WorldState.init(allocator);
    defer state.deinit();

    const alice = [_]u8{0xAA} ** 32;
    const bob = [_]u8{0xBB} ** 32;

    // Set balances
    try state.setBalance(alice, 1000);
    try state.setBalance(bob, 500);

    try std.testing.expectEqual(@as(u64, 1000), state.getBalance(alice));
    try std.testing.expectEqual(@as(u64, 500), state.getBalance(bob));

    // Transfer
    try state.transfer(alice, bob, 300);

    try std.testing.expectEqual(@as(u64, 700), state.getBalance(alice));
    try std.testing.expectEqual(@as(u64, 800), state.getBalance(bob));
}

test "contract deployment" {
    const allocator = std.testing.allocator;

    var state = WorldState.init(allocator);
    defer state.deinit();

    const contract_addr = [_]u8{0xCC} ** 32;
    const bytecode = "compiled_contract_bytecode";

    try state.deployContract(contract_addr, bytecode);

    try std.testing.expect(state.isContract(contract_addr));
    try std.testing.expectEqualStrings(bytecode, state.getCode(contract_addr).?);
}

test "storage operations" {
    const allocator = std.testing.allocator;

    var state = WorldState.init(allocator);
    defer state.deinit();

    const contract = [_]u8{0xCC} ** 32;
    const key = [_]u8{0x01} ** 32;
    const value = [_]u8{0x42} ** 32;

    try state.storageSet(contract, key, value);

    const retrieved = state.storageGet(contract, key);
    try std.testing.expectEqualSlices(u8, &value, &retrieved);
}

test "transaction execution" {
    const allocator = std.testing.allocator;

    var state = WorldState.init(allocator);
    defer state.deinit();

    const alice = [_]u8{0xAA} ** 32;
    const bob = [_]u8{0xBB} ** 32;

    // Setup initial balances
    try state.setBalance(alice, 10000);

    var executor = TransactionExecutor.init(
        allocator,
        &state,
        1, // block number
        1234567890, // timestamp
        [_]u8{0x99} ** 32, // validator
        1, // chain_id
    );

    const tx = Transaction{
        .from = alice,
        .to = bob,
        .value = 100,
        .data = &[_]u8{},
        .nonce = 0,
        .gas_limit = 100000,
        .gas_price = 1,
        .signature = [_]u8{0} ** 64,
    };

    const receipt = try executor.execute(tx);

    try std.testing.expectEqual(web3.Receipt.Status.success, receipt.status);
    try std.testing.expectEqual(@as(u64, 100), state.getBalance(bob));
}
