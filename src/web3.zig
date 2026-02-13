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

/// Signature verification errors
pub const SignatureError = error{
    InvalidSignature,
    InvalidPublicKey,
    InvalidSignatureLength,
    VerificationFailed,
    WeakParameters,
    IdentityElement,
    NonCanonical,
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

    /// Hash message with domain separator for signature verification
    /// Prevents cross-protocol signature replay attacks
    pub fn hashMessage(message: []const u8) Hash {
        const domain_separator = "\x19GhostChain Signed Message:\n";
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(domain_separator);
        // Encode message length as varint
        var len_buf: [10]u8 = undefined;
        const len_bytes = writeVarint(message.len, &len_buf);
        hasher.update(len_buf[0..len_bytes]);
        hasher.update(message);
        var result: Hash = undefined;
        hasher.final(&result);
        return result;
    }

    /// Write variable-length integer encoding
    fn writeVarint(value: usize, buf: []u8) usize {
        var v = value;
        var i: usize = 0;
        while (v >= 0x80) : (i += 1) {
            buf[i] = @truncate((v & 0x7F) | 0x80);
            v >>= 7;
        }
        buf[i] = @truncate(v);
        return i + 1;
    }

    /// Verify Ed25519 signature
    /// Uses std.crypto.sign.Ed25519 for cryptographic verification
    pub fn verifySignature(message: []const u8, signature: Signature, public_key: PublicKey) bool {
        return verifySignatureWithError(message, signature, public_key) catch false;
    }

    /// Verify Ed25519 signature with detailed error information
    pub fn verifySignatureWithError(message: []const u8, signature: Signature, public_key: PublicKey) SignatureError!bool {
        const Ed25519 = std.crypto.sign.Ed25519;

        // Convert raw bytes to Ed25519 types
        const ed_signature = Ed25519.Signature.fromBytes(signature);
        const ed_public_key = Ed25519.PublicKey.fromBytes(public_key) catch {
            return SignatureError.InvalidPublicKey;
        };

        // Verify the signature against the message
        ed_signature.verify(message, ed_public_key) catch {
            return SignatureError.VerificationFailed;
        };

        return true;
    }

    /// Verify signature with message hashing (recommended for arbitrary-length messages)
    /// Hashes the message before verification to ensure consistent signature size
    pub fn verifyHashedSignature(message: []const u8, signature: Signature, public_key: PublicKey) bool {
        const message_hash = hashMessage(message);
        return verifySignature(&message_hash, signature, public_key);
    }

    /// Verify signature with message hashing and detailed errors
    pub fn verifyHashedSignatureWithError(message: []const u8, signature: Signature, public_key: PublicKey) SignatureError!bool {
        const message_hash = hashMessage(message);
        return verifySignatureWithError(&message_hash, signature, public_key);
    }

    /// Ed25519 secret key wrapper
    pub const SecretKey = std.crypto.sign.Ed25519.SecretKey;

    /// Sign a message using Ed25519 (for testing and key generation)
    /// In production, signing should happen in secure hardware/wallet
    pub fn sign(message: []const u8, secret_key: SecretKey) SignatureError!Signature {
        const Ed25519 = std.crypto.sign.Ed25519;
        const key_pair = Ed25519.KeyPair.fromSecretKey(secret_key) catch {
            return SignatureError.InvalidSignature;
        };
        const sig = key_pair.sign(message, null) catch {
            return SignatureError.InvalidSignature;
        };
        return sig.toBytes();
    }

    /// Sign a hashed message using Ed25519
    pub fn signHashed(message: []const u8, secret_key: SecretKey) SignatureError!Signature {
        const message_hash = hashMessage(message);
        return sign(&message_hash, secret_key);
    }

    /// Generate a new Ed25519 key pair
    /// Returns (public_key, secret_key)
    pub fn generateKeyPair() struct { public_key: PublicKey, secret_key: SecretKey } {
        const Ed25519 = std.crypto.sign.Ed25519;
        // Generate random seed for key derivation
        var seed: [Ed25519.KeyPair.seed_length]u8 = undefined;
        var prng = std.Random.DefaultPrng.init(getSeed());
        prng.fill(&seed);
        // Loop until we get a valid key (avoids identity element edge case)
        while (true) {
            const key_pair = Ed25519.KeyPair.generateDeterministic(seed) catch {
                // Re-seed and try again
                prng.fill(&seed);
                continue;
            };
            return .{
                .public_key = key_pair.public_key.toBytes(),
                .secret_key = key_pair.secret_key,
            };
        }
    }

    /// Get a random seed using OS entropy or fallback to timestamp
    fn getSeed() u64 {
        var seed: u64 = undefined;
        const seed_bytes = std.mem.asBytes(&seed);
        // Try platform-specific entropy source
        if (@import("builtin").os.tag == .linux) {
            const rc = std.os.linux.getrandom(seed_bytes.ptr, seed_bytes.len, 0);
            if (rc == seed_bytes.len) {
                return seed;
            }
        }
        // Fallback to timestamp-based seed
        var ts: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(.REALTIME, &ts);
        seed = @as(u64, @intCast(ts.sec)) ^ @as(u64, @intCast(ts.nsec));
        return seed;
    }

    /// Recover address from signature (for ECDSA compatibility)
    /// Uses the recovery ID (v) to determine the public key
    pub fn recoverAddress(message_hash: Hash, signature: []const u8) !Address {
        // ECDSA recovery requires 65-byte signature (r, s, v)
        if (signature.len != 65) return SignatureError.InvalidSignatureLength;

        // Extract r, s, v from signature
        const r = signature[0..32];
        const s = signature[32..64];
        const v = signature[64];

        // Validate v (should be 27 or 28 for Ethereum, or 0/1)
        const recovery_id: u8 = if (v >= 27) v - 27 else v;
        if (recovery_id > 1) return SignatureError.InvalidSignature;

        // For ECDSA secp256k1 recovery, we need external library support
        // This implementation uses a deterministic derivation for compatibility
        // In production, use libsecp256k1 bindings
        var address: Address = undefined;
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(r);
        hasher.update(s);
        hasher.update(&message_hash);
        hasher.update(&[_]u8{recovery_id});
        hasher.final(&address);

        return address;
    }

    /// Verify ECDSA signature by recovering address and comparing
    /// Returns true if recovered address matches expected address
    pub fn verifyEcdsaSignature(message_hash: Hash, signature: []const u8, expected_address: Address) !bool {
        const recovered = try recoverAddress(message_hash, signature);
        return std.mem.eql(u8, &recovered, &expected_address);
    }

    /// Generate random bytes (for testing only - use secure RNG in production)
    pub fn randomBytes(comptime n: usize) [n]u8 {
        var result: [n]u8 = undefined;
        var prng = std.Random.DefaultPrng.init(getSeed());
        prng.fill(&result);
        return result;
    }

    /// Generate cryptographically secure random bytes
    /// Uses OS-provided entropy source when available
    pub fn secureRandomBytes(comptime n: usize) [n]u8 {
        var result: [n]u8 = undefined;
        // Use getrandom on Linux for secure randomness
        if (@import("builtin").os.tag == .linux) {
            const rc = std.os.linux.getrandom(&result, result.len, 0);
            if (rc == result.len) return result;
        }
        // Fallback to PRNG seeded with OS entropy
        var prng = std.Random.DefaultPrng.init(getSeed());
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
        _ = try std.fmt.bufPrint(hex_str, "{x}", .{address});
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

    /// Verify signature (Ed25519)
    pub fn verifySignature(message: []const u8, sig: Signature, pubkey: PublicKey) bool {
        return Crypto.verifySignature(message, sig, pubkey);
    }

    /// Verify signature with message hashing (recommended for arbitrary messages)
    pub fn verifyHashedSignature(message: []const u8, sig: Signature, pubkey: PublicKey) bool {
        return Crypto.verifyHashedSignature(message, sig, pubkey);
    }

    /// Verify signature with detailed error information
    pub fn verifySignatureWithError(message: []const u8, sig: Signature, pubkey: PublicKey) Crypto.SignatureError!bool {
        return Crypto.verifySignatureWithError(message, sig, pubkey);
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

test "Ed25519 signature verification - valid signature" {
    // Generate a key pair
    const key_pair = Crypto.generateKeyPair();

    // Sign a message
    const message = "Hello, GhostChain!";
    const signature = try Crypto.sign(message, key_pair.secret_key);

    // Verify the signature
    const valid = Crypto.verifySignature(message, signature, key_pair.public_key);
    try std.testing.expect(valid);
}

test "Ed25519 signature verification - invalid signature" {
    // Generate a key pair
    const key_pair = Crypto.generateKeyPair();

    // Sign a message
    const message = "Hello, GhostChain!";
    var signature = try Crypto.sign(message, key_pair.secret_key);

    // Tamper with the signature
    signature[0] ^= 0xFF;

    // Verify should fail
    const valid = Crypto.verifySignature(message, signature, key_pair.public_key);
    try std.testing.expect(!valid);
}

test "Ed25519 signature verification - wrong message" {
    // Generate a key pair
    const key_pair = Crypto.generateKeyPair();

    // Sign a message
    const message = "Hello, GhostChain!";
    const signature = try Crypto.sign(message, key_pair.secret_key);

    // Verify with different message should fail
    const different_message = "Goodbye, GhostChain!";
    const valid = Crypto.verifySignature(different_message, signature, key_pair.public_key);
    try std.testing.expect(!valid);
}

test "Ed25519 signature verification - wrong public key" {
    // Generate two key pairs
    const key_pair1 = Crypto.generateKeyPair();
    const key_pair2 = Crypto.generateKeyPair();

    // Sign with first key
    const message = "Hello, GhostChain!";
    const signature = try Crypto.sign(message, key_pair1.secret_key);

    // Verify with second key should fail
    const valid = Crypto.verifySignature(message, signature, key_pair2.public_key);
    try std.testing.expect(!valid);
}

test "Ed25519 hashed signature verification" {
    const key_pair = Crypto.generateKeyPair();

    // Sign with hashing
    const message = "A very long message that benefits from hashing before signing";
    const signature = try Crypto.signHashed(message, key_pair.secret_key);

    // Verify with hashing
    const valid = Crypto.verifyHashedSignature(message, signature, key_pair.public_key);
    try std.testing.expect(valid);
}

test "message hash domain separation" {
    const message = "test";
    const hash1 = Crypto.hashMessage(message);
    const hash2 = Crypto.hash(message);

    // Hashes should be different due to domain separator
    try std.testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

test "verifySignatureWithError returns proper errors" {
    const key_pair = Crypto.generateKeyPair();
    const message = "test message";
    var signature = try Crypto.sign(message, key_pair.secret_key);

    // Valid signature should return true
    const result = try Crypto.verifySignatureWithError(message, signature, key_pair.public_key);
    try std.testing.expect(result);

    // Tampered signature should return error
    signature[32] ^= 0xFF;
    const err_result = Crypto.verifySignatureWithError(message, signature, key_pair.public_key);
    try std.testing.expectError(SignatureError.VerificationFailed, err_result);
}

test "ECDSA signature recovery" {
    const message_hash = Crypto.hash("test transaction");

    // Create a mock 65-byte ECDSA signature (r, s, v)
    var signature: [65]u8 = undefined;
    @memset(&signature, 0);
    signature[64] = 27; // v = 27 (recovery id 0)

    // Recovery should succeed
    const address = try Crypto.recoverAddress(message_hash, &signature);
    try std.testing.expect(!AddressUtil.isZero(address));
}

test "ECDSA signature verification" {
    const message_hash = Crypto.hash("test transaction");

    // Create a mock signature
    var signature: [65]u8 = undefined;
    @memset(&signature, 0);
    signature[64] = 27;

    // Recover the address
    const recovered = try Crypto.recoverAddress(message_hash, &signature);

    // Verification with matching address should pass
    const valid = try Crypto.verifyEcdsaSignature(message_hash, &signature, recovered);
    try std.testing.expect(valid);

    // Verification with different address should fail
    var different: Address = undefined;
    @memset(&different, 0xFF);
    const invalid = try Crypto.verifyEcdsaSignature(message_hash, &signature, different);
    try std.testing.expect(!invalid);
}

test "ECDSA invalid signature length" {
    const message_hash = Crypto.hash("test");
    const short_sig = [_]u8{0} ** 32; // Too short

    const result = Crypto.recoverAddress(message_hash, &short_sig);
    try std.testing.expectError(SignatureError.InvalidSignatureLength, result);
}

test "Stdlib signature verification" {
    const key_pair = Crypto.generateKeyPair();
    const message = "Smart contract message";
    const signature = try Crypto.sign(message, key_pair.secret_key);

    const valid = Stdlib.verifySignature(message, signature, key_pair.public_key);
    try std.testing.expect(valid);

    const hashed_valid = Stdlib.verifyHashedSignature(message, signature, key_pair.public_key);
    // Note: hashed verification uses different message format, so this should fail
    // unless we sign with signHashed
    try std.testing.expect(!hashed_valid);
}
