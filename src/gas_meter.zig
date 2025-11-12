//! Gas Metering for GhostLang VM
//!
//! Tracks execution costs for smart contracts:
//! - Per-instruction gas costs
//! - Memory allocation costs
//! - Storage operation costs
//! - External call costs

const std = @import("std");
const root = @import("root.zig");

/// Gas costs for VM operations (compatible with EVM where possible)
pub const GasCosts = struct {
    // Base operations
    pub const NOP: u64 = 0;
    pub const MOVE: u64 = 3;
    pub const LOAD_CONST: u64 = 3;

    // Arithmetic
    pub const ADD: u64 = 3;
    pub const SUB: u64 = 3;
    pub const MUL: u64 = 5;
    pub const DIV: u64 = 5;
    pub const MOD: u64 = 5;
    pub const POW: u64 = 10;

    // Comparison
    pub const EQ: u64 = 3;
    pub const LT: u64 = 3;
    pub const LE: u64 = 3;
    pub const GT: u64 = 3;
    pub const GE: u64 = 3;

    // Logical
    pub const AND: u64 = 3;
    pub const OR: u64 = 3;
    pub const NOT: u64 = 3;

    // Control flow
    pub const JUMP: u64 = 8;
    pub const JUMP_IF: u64 = 10;
    pub const CALL: u64 = 40;
    pub const RET: u64 = 0;

    // Memory operations
    pub const NEW_TABLE: u64 = 20;
    pub const NEW_ARRAY: u64 = 20;
    pub const TABLE_GET: u64 = 50;
    pub const TABLE_SET: u64 = 100;
    pub const ARRAY_GET: u64 = 30;
    pub const ARRAY_SET: u64 = 50;
    pub const ARRAY_PUSH: u64 = 50;

    // String operations
    pub const STRING_CONCAT: u64 = 30;
    pub const STRING_LENGTH: u64 = 3;

    // Storage (expensive!)
    pub const STORAGE_LOAD: u64 = 200;
    pub const STORAGE_STORE_NEW: u64 = 20000;
    pub const STORAGE_STORE_UPDATE: u64 = 5000;

    // Crypto operations
    pub const HASH: u64 = 30;
    pub const VERIFY_SIG: u64 = 3000;

    // External calls
    pub const CALL_EXTERNAL: u64 = 700;
    pub const CREATE_CONTRACT: u64 = 32000;

    // Memory expansion (per 32-byte word)
    pub const MEMORY_WORD: u64 = 3;
};

/// Gas meter tracks gas usage during execution
pub const GasMeter = struct {
    gas_limit: u64,
    gas_used: u64,
    memory_used: usize,
    memory_peak: usize,

    pub fn init(gas_limit: u64) GasMeter {
        return .{
            .gas_limit = gas_limit,
            .gas_used = 0,
            .memory_used = 0,
            .memory_peak = 0,
        };
    }

    /// Consume gas for an operation
    pub fn consume(self: *GasMeter, amount: u64) !void {
        const new_total = self.gas_used + amount;
        if (new_total > self.gas_limit) {
            return error.OutOfGas;
        }
        self.gas_used = new_total;
    }

    /// Consume gas for instruction execution
    pub fn consumeInstruction(self: *GasMeter, opcode: root.Opcode) !void {
        const cost = getInstructionCost(opcode);
        try self.consume(cost);
    }

    /// Consume gas for memory expansion
    pub fn consumeMemory(self: *GasMeter, bytes: usize) !void {
        const new_memory = self.memory_used + bytes;
        const words = (new_memory + 31) / 32;
        const gas_cost = words * GasCosts.MEMORY_WORD;

        try self.consume(gas_cost);

        self.memory_used = new_memory;
        if (new_memory > self.memory_peak) {
            self.memory_peak = new_memory;
        }
    }

    /// Get remaining gas
    pub fn remaining(self: *GasMeter) u64 {
        return self.gas_limit - self.gas_used;
    }

    /// Get gas used
    pub fn used(self: *GasMeter) u64 {
        return self.gas_used;
    }

    /// Get gas used as percentage
    pub fn usagePercent(self: *GasMeter) f64 {
        if (self.gas_limit == 0) return 0.0;
        return @as(f64, @floatFromInt(self.gas_used)) / @as(f64, @floatFromInt(self.gas_limit)) * 100.0;
    }

    /// Check if gas limit would be exceeded
    pub fn wouldExceed(self: *GasMeter, amount: u64) bool {
        return self.gas_used + amount > self.gas_limit;
    }

    /// Get instruction cost
    fn getInstructionCost(opcode: root.Opcode) u64 {
        return switch (opcode) {
            .nop => GasCosts.NOP,
            .move => GasCosts.MOVE,
            .load_const => GasCosts.LOAD_CONST,

            .add, .sub => GasCosts.ADD,
            .mul => GasCosts.MUL,
            .div, .mod => GasCosts.DIV,
            .pow => GasCosts.POW,

            .eq => GasCosts.EQ,
            .lt, .le, .gt, .ge, .ne => GasCosts.LT,

            .@"and", .@"or" => GasCosts.AND,
            .not => GasCosts.NOT,

            .jump => GasCosts.JUMP,
            .jump_if_false, .jump_if_true => GasCosts.JUMP_IF,
            .call, .call_native => GasCosts.CALL,
            .ret => GasCosts.RET,

            .new_table => GasCosts.NEW_TABLE,
            .new_array => GasCosts.NEW_ARRAY,
            .table_get_field, .table_get_index => GasCosts.TABLE_GET,
            .table_set_field, .table_set_index => GasCosts.TABLE_SET,
            .array_get => GasCosts.ARRAY_GET,
            .array_set => GasCosts.ARRAY_SET,
            .array_push => GasCosts.ARRAY_PUSH,

            .concat => GasCosts.STRING_CONCAT,
            .len => GasCosts.STRING_LENGTH,

            else => 1, // default cost
        };
    }
};

/// Gas profiler for analyzing contract gas usage
pub const GasProfiler = struct {
    allocator: std.mem.Allocator,
    instruction_costs: std.AutoHashMap(root.Opcode, InstructionStats),
    total_gas: u64,
    total_instructions: u64,

    const InstructionStats = struct {
        count: u64,
        total_gas: u64,
        avg_gas: f64,
    };

    pub fn init(allocator: std.mem.Allocator) GasProfiler {
        return .{
            .allocator = allocator,
            .instruction_costs = std.AutoHashMap(root.Opcode, InstructionStats).init(allocator),
            .total_gas = 0,
            .total_instructions = 0,
        };
    }

    pub fn deinit(self: *GasProfiler) void {
        self.instruction_costs.deinit();
    }

    /// Record instruction execution
    pub fn recordInstruction(self: *GasProfiler, opcode: root.Opcode, gas_cost: u64) !void {
        self.total_gas += gas_cost;
        self.total_instructions += 1;

        const entry = try self.instruction_costs.getOrPut(opcode);
        if (entry.found_existing) {
            entry.value_ptr.count += 1;
            entry.value_ptr.total_gas += gas_cost;
            entry.value_ptr.avg_gas = @as(f64, @floatFromInt(entry.value_ptr.total_gas)) /
                @as(f64, @floatFromInt(entry.value_ptr.count));
        } else {
            entry.value_ptr.* = .{
                .count = 1,
                .total_gas = gas_cost,
                .avg_gas = @as(f64, @floatFromInt(gas_cost)),
            };
        }
    }

    /// Print profiling report
    pub fn printReport(self: *GasProfiler) void {
        std.debug.print("\n=== Gas Profiling Report ===\n", .{});
        std.debug.print("Total Gas: {d}\n", .{self.total_gas});
        std.debug.print("Total Instructions: {d}\n", .{self.total_instructions});

        if (self.total_instructions > 0) {
            const avg = @as(f64, @floatFromInt(self.total_gas)) /
                @as(f64, @floatFromInt(self.total_instructions));
            std.debug.print("Avg Gas/Instruction: {d:.2}\n\n", .{avg});
        }

        std.debug.print("Top Gas Consumers:\n", .{});
        std.debug.print("-" ** 60 ++ "\n", .{});

        var it = self.instruction_costs.iterator();
        while (it.next()) |entry| {
            const opcode = entry.key_ptr.*;
            const stats = entry.value_ptr.*;

            const percent = @as(f64, @floatFromInt(stats.total_gas)) /
                @as(f64, @floatFromInt(self.total_gas)) * 100.0;

            std.debug.print("{s:20} | {d:8} calls | {d:10} gas | {d:5.1}%\n", .{
                @tagName(opcode),
                stats.count,
                stats.total_gas,
                percent,
            });
        }
    }

    /// Get top gas consumers
    pub fn getTopConsumers(self: *GasProfiler, allocator: std.mem.Allocator, count: usize) ![]struct { opcode: root.Opcode, gas: u64 } {
        var list = std.ArrayList(struct { opcode: root.Opcode, gas: u64 }).init(allocator);

        var it = self.instruction_costs.iterator();
        while (it.next()) |entry| {
            try list.append(.{
                .opcode = entry.key_ptr.*,
                .gas = entry.value_ptr.total_gas,
            });
        }

        // Sort by gas consumption
        const items = try list.toOwnedSlice();
        std.sort.pdq(
            @TypeOf(items[0]),
            items,
            {},
            struct {
                fn lessThan(_: void, a: @TypeOf(items[0]), b: @TypeOf(items[0])) bool {
                    return a.gas > b.gas;
                }
            }.lessThan,
        );

        // Return top N
        const result_count = @min(count, items.len);
        const result = try allocator.alloc(@TypeOf(items[0]), result_count);
        @memcpy(result, items[0..result_count]);

        allocator.free(items);
        return result;
    }
};

/// Gas estimation for smart contract functions
pub fn estimateGas(code: []const root.Instruction, constants: []const root.ScriptValue) u64 {
    var estimated: u64 = 0;

    for (code) |instr| {
        estimated += GasMeter.getInstructionCost(instr.opcode);

        // Add extra costs for specific operations
        switch (instr.opcode) {
            .load_const => {
                const const_idx = instr.operands[1];
                if (const_idx < constants.len) {
                    const value = constants[const_idx];
                    // Strings and tables cost more to load
                    if (value == .string) {
                        estimated += value.string.len / 32 * GasCosts.MEMORY_WORD;
                    }
                }
            },
            .new_array, .new_table => {
                estimated += GasCosts.MEMORY_WORD * 10; // Initial allocation
            },
            else => {},
        }
    }

    return estimated;
}

test "gas meter basic" {
    var meter = GasMeter.init(1000);

    try meter.consume(100);
    try std.testing.expectEqual(@as(u64, 100), meter.used());
    try std.testing.expectEqual(@as(u64, 900), meter.remaining());

    try meter.consume(200);
    try std.testing.expectEqual(@as(u64, 300), meter.used());

    // Should fail - exceeds limit
    try std.testing.expectError(error.OutOfGas, meter.consume(800));
}

test "gas profiler" {
    const allocator = std.testing.allocator;

    var profiler = GasProfiler.init(allocator);
    defer profiler.deinit();

    try profiler.recordInstruction(.add, GasCosts.ADD);
    try profiler.recordInstruction(.add, GasCosts.ADD);
    try profiler.recordInstruction(.mul, GasCosts.MUL);

    try std.testing.expectEqual(@as(u64, 11), profiler.total_gas);
    try std.testing.expectEqual(@as(u64, 3), profiler.total_instructions);
}
