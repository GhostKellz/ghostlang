//! GhostLang VM Optimizations
//!
//! Performance enhancements for the VM execution layer:
//! - Inline instruction dispatch (computed goto via labels)
//! - Register pressure reduction
//! - Constant folding
//! - Dead code elimination
//! - Bytecode peephole optimization
//! - JIT compilation infrastructure (future)

const std = @import("std");
const root = @import("root.zig");

/// Bytecode optimization pass
pub const BytecodeOptimizer = struct {
    allocator: std.mem.Allocator,
    stats: OptimizationStats,

    pub const OptimizationStats = struct {
        instructions_removed: usize = 0,
        constants_folded: usize = 0,
        registers_coalesced: usize = 0,
        jumps_eliminated: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) BytecodeOptimizer {
        return .{
            .allocator = allocator,
            .stats = .{},
        };
    }

    /// Run all optimization passes
    pub fn optimize(self: *BytecodeOptimizer, code: []root.Instruction) ![]root.Instruction {
        var optimized = try self.allocator.dupe(root.Instruction, code);

        // Pass 1: Constant folding
        optimized = try self.foldConstants(optimized);

        // Pass 2: Dead code elimination
        optimized = try self.eliminateDeadCode(optimized);

        // Pass 3: Peephole optimization
        optimized = try self.peepholeOptimize(optimized);

        return optimized;
    }

    /// Fold constant arithmetic at compile time
    fn foldConstants(self: *BytecodeOptimizer, code: []root.Instruction) ![]root.Instruction {
        var result = std.ArrayList(root.Instruction).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < code.len) : (i += 1) {
            const instr = code[i];

            // Pattern: ADD/SUB/MUL/DIV with constant operands
            // TODO: Implement constant folding for arithmetic
            // For now, just pass through
            try result.append(instr);
        }

        return try result.toOwnedSlice();
    }

    /// Remove unreachable code after returns/jumps
    fn eliminateDeadCode(self: *BytecodeOptimizer, code: []root.Instruction) ![]root.Instruction {
        var result = std.ArrayList(root.Instruction).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        var in_dead_section = false;

        while (i < code.len) : (i += 1) {
            const instr = code[i];

            // Check for unconditional control flow
            if (instr.opcode == .ret) {
                try result.append(instr);
                in_dead_section = true;
                continue;
            }

            // Check for jump targets (labels)
            // If we hit a label, code becomes reachable again
            if (isJumpTarget(instr)) {
                in_dead_section = false;
            }

            if (!in_dead_section) {
                try result.append(instr);
            } else {
                self.stats.instructions_removed += 1;
            }
        }

        return try result.toOwnedSlice();
    }

    /// Peephole optimization (local instruction patterns)
    fn peepholeOptimize(self: *BytecodeOptimizer, code: []root.Instruction) ![]root.Instruction {
        var result = std.ArrayList(root.Instruction).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < code.len) {
            // Pattern 1: MOVE R1, R1 → NOP
            if (code[i].opcode == .move and
                code[i].operands[0] == code[i].operands[1])
            {
                // Skip redundant move
                self.stats.instructions_removed += 1;
                i += 1;
                continue;
            }

            // Pattern 2: MOVE R1, R2; MOVE R2, R1 → MOVE R1, R2
            if (i + 1 < code.len and
                code[i].opcode == .move and
                code[i + 1].opcode == .move and
                code[i].operands[0] == code[i + 1].operands[1] and
                code[i].operands[1] == code[i + 1].operands[0])
            {
                // Keep only first move
                try result.append(code[i]);
                self.stats.instructions_removed += 1;
                i += 2;
                continue;
            }

            // Pattern 3: LOAD_CONST followed by unused register
            // TODO: Implement register liveness analysis

            // No optimization, keep instruction
            try result.append(code[i]);
            i += 1;
        }

        return try result.toOwnedSlice();
    }

    fn isJumpTarget(instr: root.Instruction) bool {
        // TODO: Track jump targets during compilation
        _ = instr;
        return false;
    }

    pub fn printStats(self: BytecodeOptimizer) void {
        std.debug.print("\nBytecode Optimization Stats:\n", .{});
        std.debug.print("  Instructions removed: {d}\n", .{self.stats.instructions_removed});
        std.debug.print("  Constants folded: {d}\n", .{self.stats.constants_folded});
        std.debug.print("  Registers coalesced: {d}\n", .{self.stats.registers_coalesced});
        std.debug.print("  Jumps eliminated: {d}\n", .{self.stats.jumps_eliminated});
    }
};

/// Instruction cache for hot paths
pub const InstructionCache = struct {
    entries: []CacheEntry,
    capacity: usize,
    hits: std.atomic.Value(u64),
    misses: std.atomic.Value(u64),

    const CacheEntry = struct {
        pc: usize,
        instr: root.Instruction,
        hot_count: u32,
    };

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !InstructionCache {
        const entries = try allocator.alloc(CacheEntry, capacity);
        @memset(entries, .{
            .pc = std.math.maxInt(usize),
            .instr = undefined,
            .hot_count = 0,
        });

        return .{
            .entries = entries,
            .capacity = capacity,
            .hits = std.atomic.Value(u64).init(0),
            .misses = std.atomic.Value(u64).init(0),
        };
    }

    pub fn deinit(self: *InstructionCache, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
    }

    pub fn get(self: *InstructionCache, pc: usize) ?root.Instruction {
        const idx = pc % self.capacity;
        const entry = &self.entries[idx];

        if (entry.pc == pc) {
            entry.hot_count +|= 1;
            _ = self.hits.fetchAdd(1, .monotonic);
            return entry.instr;
        }

        _ = self.misses.fetchAdd(1, .monotonic);
        return null;
    }

    pub fn put(self: *InstructionCache, pc: usize, instr: root.Instruction) void {
        const idx = pc % self.capacity;
        self.entries[idx] = .{
            .pc = pc,
            .instr = instr,
            .hot_count = 1,
        };
    }

    pub fn hitRate(self: *InstructionCache) f64 {
        const total_hits = self.hits.load(.monotonic);
        const total_misses = self.misses.load(.monotonic);
        const total = total_hits + total_misses;

        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(total_hits)) / @as(f64, @floatFromInt(total));
    }
};

/// Register allocation optimizer
pub const RegisterAllocator = struct {
    live_ranges: std.AutoHashMap(u16, LiveRange),
    allocator: std.mem.Allocator,

    const LiveRange = struct {
        first_use: usize,
        last_use: usize,
        reg: u16,
    };

    pub fn init(allocator: std.mem.Allocator) RegisterAllocator {
        return .{
            .live_ranges = std.AutoHashMap(u16, LiveRange).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RegisterAllocator) void {
        self.live_ranges.deinit();
    }

    /// Analyze register usage and compute live ranges
    pub fn analyzeLiveness(self: *RegisterAllocator, code: []const root.Instruction) !void {
        for (code, 0..) |instr, pc| {
            // For each register used in this instruction
            for (instr.operands) |reg| {
                if (reg == 0) continue; // Skip unused operands

                const entry = try self.live_ranges.getOrPut(reg);
                if (entry.found_existing) {
                    entry.value_ptr.last_use = pc;
                } else {
                    entry.value_ptr.* = .{
                        .first_use = pc,
                        .last_use = pc,
                        .reg = reg,
                    };
                }
            }
        }
    }

    /// Suggest register coalescing opportunities
    pub fn suggestCoalescing(self: *RegisterAllocator) ![]CoalescePair {
        var pairs = std.ArrayList(CoalescePair).init(self.allocator);

        var it1 = self.live_ranges.iterator();
        while (it1.next()) |entry1| {
            var it2 = self.live_ranges.iterator();
            while (it2.next()) |entry2| {
                if (entry1.key_ptr.* >= entry2.key_ptr.*) continue;

                // Check if live ranges don't overlap
                if (entry1.value_ptr.last_use < entry2.value_ptr.first_use or
                    entry2.value_ptr.last_use < entry1.value_ptr.first_use)
                {
                    try pairs.append(.{
                        .reg1 = entry1.key_ptr.*,
                        .reg2 = entry2.key_ptr.*,
                    });
                }
            }
        }

        return try pairs.toOwnedSlice();
    }

    const CoalescePair = struct {
        reg1: u16,
        reg2: u16,
    };
};

/// JIT compilation infrastructure (placeholder for future)
pub const JITCompiler = struct {
    allocator: std.mem.Allocator,
    hot_threshold: u32,
    compiled_functions: std.AutoHashMap(usize, CompiledFunction),

    const CompiledFunction = struct {
        start_pc: usize,
        end_pc: usize,
        native_code: []const u8,
        call_count: u32,
    };

    pub fn init(allocator: std.mem.Allocator, hot_threshold: u32) JITCompiler {
        return .{
            .allocator = allocator,
            .hot_threshold = hot_threshold,
            .compiled_functions = std.AutoHashMap(usize, CompiledFunction).init(allocator),
        };
    }

    pub fn deinit(self: *JITCompiler) void {
        var it = self.compiled_functions.valueIterator();
        while (it.next()) |func| {
            self.allocator.free(func.native_code);
        }
        self.compiled_functions.deinit();
    }

    /// Check if a function should be JIT-compiled
    pub fn shouldCompile(self: *JITCompiler, start_pc: usize, call_count: u32) bool {
        _ = start_pc;
        return call_count >= self.hot_threshold;
    }

    /// Compile bytecode to native code (placeholder)
    pub fn compile(self: *JITCompiler, code: []const root.Instruction, start_pc: usize, end_pc: usize) !void {
        _ = self;
        _ = code;
        _ = start_pc;
        _ = end_pc;

        // TODO: Implement native code generation
        // - x86_64 / ARM64 code generation
        // - Register allocation for native registers
        // - Call convention handling
        // - OSR (on-stack replacement) support

        std.log.info("JIT compilation not yet implemented", .{});
    }
};

/// Memory pool for frequently allocated objects
pub const ObjectPool = struct {
    allocator: std.mem.Allocator,
    table_pool: std.ArrayList(*root.ScriptTable),
    array_pool: std.ArrayList(*root.ScriptArray),
    pool_size_limit: usize,

    pub fn init(allocator: std.mem.Allocator, pool_size_limit: usize) ObjectPool {
        return .{
            .allocator = allocator,
            .table_pool = std.ArrayList(*root.ScriptTable).init(allocator),
            .array_pool = std.ArrayList(*root.ScriptArray).init(allocator),
            .pool_size_limit = pool_size_limit,
        };
    }

    pub fn deinit(self: *ObjectPool) void {
        // Free pooled objects
        for (self.table_pool.items) |table| {
            table.release();
        }
        self.table_pool.deinit();

        for (self.array_pool.items) |array| {
            array.release();
        }
        self.array_pool.deinit();
    }

    /// Get a table from pool or allocate new
    pub fn acquireTable(self: *ObjectPool) !*root.ScriptTable {
        if (self.table_pool.items.len > 0) {
            const table = self.table_pool.pop();
            table.map.clearRetainingCapacity();
            table.retain();
            return table;
        }

        return try root.ScriptTable.create(self.allocator);
    }

    /// Return table to pool
    pub fn releaseTable(self: *ObjectPool, table: *root.ScriptTable) void {
        if (self.table_pool.items.len < self.pool_size_limit) {
            self.table_pool.append(table) catch {
                table.release();
            };
        } else {
            table.release();
        }
    }

    /// Get an array from pool or allocate new
    pub fn acquireArray(self: *ObjectPool) !*root.ScriptArray {
        if (self.array_pool.items.len > 0) {
            const array = self.array_pool.pop();
            array.items.clearRetainingCapacity();
            array.retain();
            return array;
        }

        return try root.ScriptArray.create(self.allocator);
    }

    /// Return array to pool
    pub fn releaseArray(self: *ObjectPool, array: *root.ScriptArray) void {
        if (self.array_pool.items.len < self.pool_size_limit) {
            self.array_pool.append(array) catch {
                array.release();
            };
        } else {
            array.release();
        }
    }
};

test "bytecode optimizer" {
    const allocator = std.testing.allocator;

    var optimizer = BytecodeOptimizer.init(allocator);

    // Create test bytecode with redundant moves
    var code = [_]root.Instruction{
        .{ .opcode = .move, .operands = .{ 1, 1, 0, 0 } }, // MOVE R1, R1 (redundant)
        .{ .opcode = .nop, .operands = .{ 0, 0, 0, 0 } },
    };

    const optimized = try optimizer.optimize(&code);
    defer allocator.free(optimized);

    // Should remove redundant move
    try std.testing.expect(optimized.len == 1);
    try std.testing.expect(optimized[0].opcode == .nop);
}

test "instruction cache" {
    const allocator = std.testing.allocator;

    var cache = try InstructionCache.init(allocator, 16);
    defer cache.deinit(allocator);

    const test_instr = root.Instruction{
        .opcode = .nop,
        .operands = .{ 0, 0, 0, 0 },
    };

    // Miss
    try std.testing.expect(cache.get(0) == null);

    // Put
    cache.put(0, test_instr);

    // Hit
    try std.testing.expect(cache.get(0) != null);
}
