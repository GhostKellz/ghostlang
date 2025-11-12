//! GhostLang Web3 Module
//!
//! Crypto-native smart contract integration for GhostChain
//! - Address manipulation and validation
//! - Transaction building and signing
//! - Balance queries and transfers
//! - Event emission and logging
//! - Storage operations (kv, indexed)
//! - Gas metering and cost estimation
//! - ABI encoding/decoding
//! - Post-quantum cryptography support

const std = @import("std");

/// 32-byte address (compatible with Ethereum/GhostChain)
pub const Address = [32]u8;

/// 32-byte hash
pub const Hash = [32]u8;

/// 64-byte signature (Dilithium post-quantum)
pub const Signature = [64]u8;

/// Public key (32 bytes)
pub const PublicKey = [32]u8;

/// Transaction receipt
pub const Receipt = struct {
    tx_hash: Hash,
    from: Address,
    to: ?Address, // null for contract creation
    status: Status,
    gas_used: u64,
    logs: []Event,
    contract_address: ?Address, // set if contract creation

    pub const Status = enum(u8) {
        success = 1,
        failure = 0,
    };
};

/// Blockchain event/log
pub const Event = struct {
    address: Address,
    topics: []Hash, // indexed parameters
    data: []const u8, // non-indexed data
    block_number: u64,
    tx_hash: Hash,
    log_index: u32,

    pub fn deinit(self: *Event, allocator: std.mem.Allocator) void {
        allocator.free(self.topics);
        allocator.free(self.data);
    }
};

/// Storage slot (256-bit key-value)
pub const StorageSlot = struct {
    key: Hash,
    value: Hash,
};

/// Gas cost calculator
pub const Gas = struct {
    /// Base transaction cost
    pub const TX_BASE: u64 = 21000;

    /// Per-byte calldata cost
    pub const CALLDATA_BYTE: u64 = 16;

    /// Contract creation base cost
    pub const CREATE: u64 = 32000;

    /// Storage set from zero
    pub const SSTORE_SET: u64 = 20000;

    /// Storage update
    pub const SSTORE_UPDATE: u64 = 5000;

    /// Storage load
    pub const SLOAD: u64 = 200;

    /// Memory expansion (per word)
    pub const MEMORY_WORD: u64 = 3;

    /// Hash operation (SHA256, Keccak256)
    pub const HASH: u64 = 30;

    /// Signature verification (post-quantum)
    pub const VERIFY_PQ: u64 = 3000;

    /// Signature verification (ECDSA)
    pub const VERIFY_ECDSA: u64 = 3000;

    pub fn calculateCalldata(data: []const u8) u64 {
        return data.len * CALLDATA_BYTE;
    }

    pub fn calculateMemory(size_bytes: usize) u64 {
        const words = (size_bytes + 31) / 32;
        return words * MEMORY_WORD;
    }
};

/// Contract context - available to all smart contracts
pub const Context = struct {
    /// Allocator for contract execution
    allocator: std.mem.Allocator,

    /// Caller address (msg.sender)
    caller: Address,

    /// Contract address (address(this))
    this: Address,

    /// Transaction origin (tx.origin)
    origin: Address,

    /// Value transferred (msg.value)
    value: u64,

    /// Gas available
    gas_available: u64,

    /// Block number
    block_number: u64,

    /// Block timestamp (Unix time)
    block_timestamp: u64,

    /// Block coinbase (validator address)
    block_coinbase: Address,

    /// Chain ID
    chain_id: u64,

    /// Storage backend
    storage: *Storage,

    /// Event logger
    event_logger: *EventLogger,

    /// Balance query interface
    balance_query: *BalanceQuery,

    pub fn getBalance(self: *Context, address: Address) !u64 {
        return self.balance_query.get(address);
    }

    pub fn transfer(self: *Context, to: Address, amount: u64) !void {
        if (amount > try self.getBalance(self.this)) {
            return error.InsufficientBalance;
        }
        try self.balance_query.transfer(self.this, to, amount);
    }

    pub fn emitEvent(self: *Context, topics: []const Hash, data: []const u8) !void {
        try self.event_logger.emit(self.this, topics, data);
    }

    pub fn storageGet(self: *Context, key: Hash) !Hash {
        return self.storage.get(self.this, key);
    }

    pub fn storageSet(self: *Context, key: Hash, value: Hash) !void {
        try self.storage.set(self.this, key, value);
    }

    pub fn consumeGas(self: *Context, amount: u64) !void {
        if (amount > self.gas_available) {
            return error.OutOfGas;
        }
        self.gas_available -= amount;
    }
};

/// Storage interface
pub const Storage = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        get: *const fn (ptr: *anyopaque, contract: Address, key: Hash) anyerror!Hash,
        set: *const fn (ptr: *anyopaque, contract: Address, key: Hash, value: Hash) anyerror!void,
    };

    pub fn get(self: *Storage, contract: Address, key: Hash) !Hash {
        return self.vtable.get(@ptrCast(self), contract, key);
    }

    pub fn set(self: *Storage, contract: Address, key: Hash, value: Hash) !void {
        return self.vtable.set(@ptrCast(self), contract, key, value);
    }
};

/// Event logger interface
pub const EventLogger = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        emit: *const fn (ptr: *anyopaque, contract: Address, topics: []const Hash, data: []const u8) anyerror!void,
    };

    pub fn emit(self: *EventLogger, contract: Address, topics: []const Hash, data: []const u8) !void {
        return self.vtable.emit(@ptrCast(self), contract, topics, data);
    }
};

/// Balance query interface
pub const BalanceQuery = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        get: *const fn (ptr: *anyopaque, address: Address) anyerror!u64,
        transfer: *const fn (ptr: *anyopaque, from: Address, to: Address, amount: u64) anyerror!void,
    };

    pub fn get(self: *BalanceQuery, address: Address) !u64 {
        return self.vtable.get(@ptrCast(self), address);
    }

    pub fn transfer(self: *BalanceQuery, from: Address, to: Address, amount: u64) !void {
        return self.vtable.transfer(@ptrCast(self), from, to, amount);
    }
};

/// ABI encoder/decoder
pub const ABI = struct {
    /// Encode function selector (first 4 bytes of keccak256(signature))
    pub fn encodeSelector(allocator: std.mem.Allocator, signature: []const u8) ![4]u8 {
        _ = allocator;
        var selector: [4]u8 = undefined;

        // Simplified hash - in production, use Keccak256
        var hash: u32 = 0;
        for (signature) |byte| {
            hash = hash *% 31 +% byte;
        }

        std.mem.writeInt(u32, &selector, hash, .big);
        return selector;
    }

    /// Encode address (32 bytes, left-padded)
    pub fn encodeAddress(address: Address) [32]u8 {
        return address;
    }

    /// Encode uint256
    pub fn encodeUint256(value: u256) [32]u8 {
        var result: [32]u8 = [_]u8{0} ** 32;
        std.mem.writeInt(u256, &result, value, .big);
        return result;
    }

    /// Encode uint64
    pub fn encodeUint64(value: u64) [32]u8 {
        var result: [32]u8 = [_]u8{0} ** 32;
        std.mem.writeInt(u64, result[24..32], value, .big);
        return result;
    }

    /// Decode uint256
    pub fn decodeUint256(data: []const u8) !u256 {
        if (data.len < 32) return error.InvalidABIData;
        return std.mem.readInt(u256, data[0..32], .big);
    }

    /// Decode uint64
    pub fn decodeUint64(data: []const u8) !u64 {
        if (data.len < 32) return error.InvalidABIData;
        return std.mem.readInt(u64, data[24..32], .big);
    }

    /// Decode address
    pub fn decodeAddress(data: []const u8) !Address {
        if (data.len < 32) return error.InvalidABIData;
        var address: Address = undefined;
        @memcpy(&address, data[0..32]);
        return address;
    }
};

/// Cryptographic utilities
pub const Crypto = struct {
    /// Hash data using SHA256 (placeholder for Keccak256/Blake3)
    pub fn hash(data: []const u8) Hash {
        var result: Hash = undefined;
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(data);
        hasher.final(&result);
        return result;
    }

    /// Verify signature (post-quantum Dilithium)
    pub fn verifySignature(message: []const u8, signature: Signature, public_key: PublicKey) bool {
        // Placeholder - integrate with Dilithium library
        _ = message;
        _ = signature;
        _ = public_key;
        return true; // TODO: actual verification
    }

    /// Recover address from signature (for ECDSA compatibility)
    pub fn recoverAddress(message_hash: Hash, signature: []const u8) !Address {
        // Placeholder for ECDSA recovery
        _ = message_hash;
        _ = signature;
        return [_]u8{0} ** 32;
    }

    /// Generate random bytes (for testing only - use secure RNG in production)
    pub fn randomBytes(comptime n: usize) [n]u8 {
        var result: [n]u8 = undefined;
        var prng = std.Random.DefaultPrng.init(@bitCast(std.time.nanoTimestamp()));
        prng.fill(&result);
        return result;
    }
};

/// Address utilities
pub const AddressUtil = struct {
    /// Zero address (0x0000...0000)
    pub const ZERO = [_]u8{0} ** 32;

    /// Check if address is zero
    pub fn isZero(address: Address) bool {
        return std.mem.eql(u8, &address, &ZERO);
    }

    /// Format address as hex string
    pub fn format(address: Address, allocator: std.mem.Allocator) ![]const u8 {
        const hex_str = try allocator.alloc(u8, 64);
        _ = try std.fmt.bufPrint(hex_str, "{}", .{std.fmt.fmtSliceHexLower(&address)});
        return hex_str;
    }

    /// Parse address from hex string
    pub fn parse(hex_str: []const u8) !Address {
        if (hex_str.len != 64) return error.InvalidAddressFormat;

        var address: Address = undefined;
        var i: usize = 0;
        while (i < 32) : (i += 1) {
            const byte_str = hex_str[i * 2 .. i * 2 + 2];
            address[i] = try std.fmt.parseInt(u8, byte_str, 16);
        }
        return address;
    }
};

/// Smart contract standard library for GhostLang scripts
pub const Stdlib = struct {
    /// Get caller address
    pub fn getCaller(ctx: *Context) Address {
        return ctx.caller;
    }

    /// Get contract address
    pub fn getThis(ctx: *Context) Address {
        return ctx.this;
    }

    /// Get current balance
    pub fn getBalance(ctx: *Context, address: Address) !u64 {
        return ctx.getBalance(address);
    }

    /// Transfer tokens
    pub fn transfer(ctx: *Context, to: Address, amount: u64) !void {
        try ctx.transfer(to, amount);
    }

    /// Get block number
    pub fn getBlockNumber(ctx: *Context) u64 {
        return ctx.block_number;
    }

    /// Get block timestamp
    pub fn getTimestamp(ctx: *Context) u64 {
        return ctx.block_timestamp;
    }

    /// Hash bytes
    pub fn hashBytes(data: []const u8) Hash {
        return Crypto.hash(data);
    }

    /// Verify signature
    pub fn verifySignature(message: []const u8, sig: Signature, pubkey: PublicKey) bool {
        return Crypto.verifySignature(message, sig, pubkey);
    }

    /// Store value
    pub fn storageSet(ctx: *Context, key: Hash, value: Hash) !void {
        try ctx.storageSet(key, value);
    }

    /// Load value
    pub fn storageGet(ctx: *Context, key: Hash) !Hash {
        return ctx.storageGet(key);
    }

    /// Emit event
    pub fn emitEvent(ctx: *Context, topics: []const Hash, data: []const u8) !void {
        try ctx.emitEvent(topics, data);
    }

    /// Revert transaction with error
    pub fn revert(message: []const u8) !void {
        std.log.err("Contract revert: {s}", .{message});
        return error.ContractRevert;
    }

    /// Require condition
    pub fn require(condition: bool, message: []const u8) !void {
        if (!condition) {
            return revert(message);
        }
    }
};

test "address utilities" {
    const addr = AddressUtil.ZERO;
    try std.testing.expect(AddressUtil.isZero(addr));

    const allocator = std.testing.allocator;
    const hex = try AddressUtil.format(addr, allocator);
    defer allocator.free(hex);

    const parsed = try AddressUtil.parse(hex);
    try std.testing.expectEqualSlices(u8, &addr, &parsed);
}

test "ABI encoding/decoding" {
    const allocator = std.testing.allocator;

    // Function selector
    const selector = try ABI.encodeSelector(allocator, "transfer(address,uint256)");
    try std.testing.expect(selector.len == 4);

    // Encode uint64
    const encoded = ABI.encodeUint64(12345);
    const decoded = try ABI.decodeUint64(&encoded);
    try std.testing.expectEqual(@as(u64, 12345), decoded);
}

test "gas calculation" {
    const calldata = "hello world";
    const gas = Gas.calculateCalldata(calldata);
    try std.testing.expectEqual(@as(u64, calldata.len * Gas.CALLDATA_BYTE), gas);

    const mem_gas = Gas.calculateMemory(1024);
    try std.testing.expect(mem_gas > 0);
}

test "crypto hash" {
    const data = "test data";
    const hash1 = Crypto.hash(data);
    const hash2 = Crypto.hash(data);
    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}
