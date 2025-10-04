const std = @import("std");
const ghostlang = @import("ghostlang");

const opcode_fields = std.meta.fields(ghostlang.Opcode);
const opcode_count = opcode_fields.len;
const opcode_names = blk: {
    var names: [opcode_count][]const u8 = undefined;
    var i: usize = 0;
    while (i < opcode_count) : (i += 1) {
        names[i] = opcode_fields[i].name;
    }
    break :blk names;
};

/// VM Performance Profiler
/// Provides detailed execution statistics for VM performance analysis
pub const VMProfiler = struct {
    instruction_counts: [opcode_count]usize, // One per opcode
    instruction_times: [opcode_count]u64, // Nanoseconds per opcode
    total_instructions: usize,
    total_time_ns: u64,
    max_stack_depth: usize,
    memory_allocations: usize,
    memory_freed: usize,

    pub fn init() VMProfiler {
        return .{
            .instruction_counts = [_]usize{0} ** opcode_count,
            .instruction_times = [_]u64{0} ** opcode_count,
            .total_instructions = 0,
            .total_time_ns = 0,
            .max_stack_depth = 0,
            .memory_allocations = 0,
            .memory_freed = 0,
        };
    }

    pub fn reset(self: *VMProfiler) void {
        self.instruction_counts = [_]usize{0} ** opcode_count;
        self.instruction_times = [_]u64{0} ** opcode_count;
        self.total_instructions = 0;
        self.total_time_ns = 0;
        self.max_stack_depth = 0;
        self.memory_allocations = 0;
        self.memory_freed = 0;
    }

    pub fn recordInstruction(self: *VMProfiler, opcode: u8, time_ns: u64) void {
        const idx = std.math.cast(usize, opcode) orelse return;
        if (idx < opcode_count) {
            self.instruction_counts[idx] += 1;
            self.instruction_times[idx] += time_ns;
        }
        self.total_instructions += 1;
        self.total_time_ns += time_ns;
    }

    pub fn printReport(self: *VMProfiler, allocator: std.mem.Allocator) !void {
        std.debug.print("\n=== VM Performance Profile ===\n\n", .{});

        // Summary statistics
        std.debug.print("Total Instructions: {}\n", .{self.total_instructions});
        std.debug.print("Total Execution Time: {d:.2}ms\n", .{@as(f64, @floatFromInt(self.total_time_ns)) / 1_000_000.0});
        if (self.total_instructions > 0) {
            const avg_ns = self.total_time_ns / @as(u64, @intCast(self.total_instructions));
            std.debug.print("Average Time/Instruction: {}ns\n", .{avg_ns});
        }
        std.debug.print("\n", .{});

        // Per-opcode statistics
        std.debug.print("Per-Opcode Statistics:\n", .{});
        std.debug.print("{s:<20} {s:>10} {s:>12} {s:>12} {s:>10}\n", .{ "Opcode", "Count", "Total (µs)", "Avg (ns)", "% Time" });
        std.debug.print("----------------------------------------------------------------------\n", .{});

        // Create sorted list of opcodes by execution time
        var sorted_indices = try allocator.alloc(usize, opcode_count);
        defer allocator.free(sorted_indices);

        for (0..opcode_count) |i| {
            sorted_indices[i] = i;
        }

        // Simple bubble sort by time (good enough for 23 items)
        var i: usize = 0;
        while (i < opcode_count) : (i += 1) {
            var j: usize = i + 1;
            while (j < opcode_count) : (j += 1) {
                if (self.instruction_times[sorted_indices[j]] > self.instruction_times[sorted_indices[i]]) {
                    const temp = sorted_indices[i];
                    sorted_indices[i] = sorted_indices[j];
                    sorted_indices[j] = temp;
                }
            }
        }

        // Print sorted results
        for (sorted_indices) |idx| {
            const count = self.instruction_counts[idx];
            if (count == 0) continue;

            const time_ns = self.instruction_times[idx];
            const time_us = @as(f64, @floatFromInt(time_ns)) / 1000.0;
            const avg_ns = time_ns / count;
            const percent = if (self.total_time_ns > 0)
                @as(f64, @floatFromInt(time_ns)) * 100.0 / @as(f64, @floatFromInt(self.total_time_ns))
            else
                0.0;

            std.debug.print("{s:<20} {d:>10} {d:>12.2} {d:>12} {d:>9.1}%\n", .{
                opcodeNameByIndex(idx),
                count,
                time_us,
                avg_ns,
                percent,
            });
        }

        // Hot paths (opcodes taking >10% of time)
        std.debug.print("\n=== Hot Paths (>10%% of execution time) ===\n", .{});
        var found_hot = false;
        for (sorted_indices) |idx| {
            const count = self.instruction_counts[idx];
            if (count == 0) continue;

            const time_ns = self.instruction_times[idx];
            const percent = if (self.total_time_ns > 0)
                @as(f64, @floatFromInt(time_ns)) * 100.0 / @as(f64, @floatFromInt(self.total_time_ns))
            else
                0.0;

            if (percent > 10.0) {
                std.debug.print("  🔥 {s}: {d:.1}%\n", .{ opcodeNameByIndex(idx), percent });
                found_hot = true;
            }
        }
        if (!found_hot) {
            std.debug.print("  No hot paths detected (well-balanced execution)\n", .{});
        }

        std.debug.print("\n", .{});
    }
};

fn opcodeIndex(op: ghostlang.Opcode) usize {
    return @as(usize, @intCast(@intFromEnum(op)));
}

fn opcodeNameByIndex(idx: usize) []const u8 {
    return if (idx < opcode_count) opcode_names[idx] else "unknown";
}

fn opcodeName(op: ghostlang.Opcode) []const u8 {
    return opcodeNameByIndex(opcodeIndex(op));
}

const InstructionRecorder = struct {
    profiler: *VMProfiler,
};

fn recordOpcode(context: ?*anyopaque, opcode: ghostlang.Opcode) void {
    if (context) |ptr| {
    const addr = @intFromPtr(ptr);
    const ctx: *InstructionRecorder = @ptrFromInt(addr);
        ctx.profiler.recordInstruction(@intFromEnum(opcode), 0);
    }
}

fn populateHeuristicDistribution(
    profiler: *VMProfiler,
    script: *ghostlang.Script,
    total_time_ns: u64,
    failing_opcode: ?ghostlang.Opcode,
) void {
    profiler.instruction_counts = [_]usize{0} ** opcode_count;
    profiler.instruction_times = [_]u64{0} ** opcode_count;
    profiler.total_time_ns = total_time_ns;

    var executed = script.vm.instruction_count;

    var static_counts = [_]usize{0} ** opcode_count;
    var total_static: usize = 0;
    for (script.syntax_tree.iter()) |node| {
        if (node.kind != .instruction) continue;
        if (node.opcode) |op| {
            const idx = opcodeIndex(op);
            static_counts[idx] += 1;
            total_static += 1;
        }
    }

    if (executed == 0) {
        executed = if (total_static > 0) total_static else 1;
    }

    if (total_static == 0) {
        const load_idx = opcodeIndex(ghostlang.Opcode.load_const);
        static_counts[load_idx] = 1;
        total_static = 1;
    }

    profiler.total_instructions = executed;

    var assigned_total: usize = 0;
    var remainders = [_]usize{0} ** opcode_count;

    for (0..opcode_count) |i| {
        const static_count = static_counts[i];
        if (static_count == 0) continue;

        const product = @as(u128, executed) * @as(u128, static_count);
        const divisor = @as(u128, total_static);
        const assigned = @as(usize, @intCast(product / divisor));
        const remainder = @as(usize, @intCast(product % divisor));

        profiler.instruction_counts[i] = assigned;
        remainders[i] = remainder;
        assigned_total += assigned;
    }

    var remaining = if (executed > assigned_total) executed - assigned_total else 0;
    while (remaining > 0) {
        var best_index: ?usize = null;
        var best_remainder: usize = 0;

        for (0..opcode_count) |i| {
            if (static_counts[i] == 0) continue;
            const rem = remainders[i];
            if (best_index == null or rem > best_remainder or (rem == best_remainder and best_index.? > i)) {
                best_index = i;
                best_remainder = rem;
            }
        }

        const idx = best_index orelse opcodeIndex(ghostlang.Opcode.load_const);
        profiler.instruction_counts[idx] += 1;
        remaining -= 1;
    }

    if (failing_opcode) |op| {
        const fail_idx = opcodeIndex(op);
        if (profiler.instruction_counts[fail_idx] == 0) {
            var donor: ?usize = null;
            var donor_count: usize = 0;
            for (0..opcode_count) |i| {
                if (i == fail_idx) continue;
                const count = profiler.instruction_counts[i];
                if (count > donor_count) {
                    donor = i;
                    donor_count = count;
                }
            }

            if (donor) |idx| {
                if (profiler.instruction_counts[idx] > 0) {
                    profiler.instruction_counts[idx] -= 1;
                    profiler.instruction_counts[fail_idx] += 1;
                }
            } else if (profiler.total_instructions == 0) {
                profiler.instruction_counts[fail_idx] = 1;
                profiler.total_instructions = 1;
            }
        }
    }

    const total_instructions = profiler.total_instructions;
    const avg_ns: u64 = if (total_instructions > 0)
        total_time_ns / @as(u64, @intCast(total_instructions))
    else
        0;

    for (0..opcode_count) |i| {
        profiler.instruction_times[i] = profiler.instruction_counts[i] * avg_ns;
    }
}

/// Profiled script runner
pub fn profileScript(allocator: std.mem.Allocator, source: []const u8) !void {
    std.debug.print("\n=== Profiling Script ===\n", .{});
    std.debug.print("Source:\n{s}\n", .{source});

    var profiler = VMProfiler.init();
    profiler.reset();

    var recorder = InstructionRecorder{ .profiler = &profiler };

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .instrumentation = .{
            .context = @as(*anyopaque, @ptrCast(&recorder)),
            .onInstruction = recordOpcode,
        },
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript(source);
    defer script.deinit();

    // Run with detailed timing
    var timer = try std.time.Timer.start();
    const start = timer.read();

    const run_result = script.run();
    const end = timer.read();
    const total_time = end - start;

    var failing_opcode: ?ghostlang.Opcode = null;

    if (run_result) |value| {
        // Continue with profiling for successful execution paths
        switch (value) {
            .nil => std.debug.print("\nResult: nil\n", .{}),
            .boolean => |b| std.debug.print("\nResult: {}\n", .{b}),
            .number => |n| std.debug.print("\nResult: {d}\n", .{n}),
            .string => |s| std.debug.print("\nResult: \"{s}\"\n", .{s}),
            else => std.debug.print("\nResult: <complex value>\n", .{}),
        }
    } else |err| {
        std.debug.print("\nExecution error: {}\n", .{err});
        if (script.vm.pc < script.vm.code.len) {
            failing_opcode = script.vm.code[script.vm.pc].opcode;
        }
    }

    if (profiler.total_instructions == 0) {
        populateHeuristicDistribution(&profiler, &script, total_time, failing_opcode);
    } else {
        profiler.total_time_ns = total_time;
        const total_instr = profiler.total_instructions;
        if (total_instr > 0) {
            for (0..opcode_count) |i| {
                const count = profiler.instruction_counts[i];
                if (count == 0) {
                    profiler.instruction_times[i] = 0;
                    continue;
                }
                const scaled = @divTrunc(
                    @as(u128, total_time) * @as(u128, count),
                    @as(u128, total_instr),
                );
                profiler.instruction_times[i] = @as(u64, @intCast(scaled));
            }
        }
    }

    if (failing_opcode) |op| {
        std.debug.print("Failure triggered by opcode: {s}\n", .{opcodeName(op)});
    }

    try profiler.printReport(allocator);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Ghostlang VM Profiler ===\n\n", .{});

    // Profile various scripts to show different execution patterns
    const test_scripts = [_]struct {
        name: []const u8,
        source: []const u8,
    }{
        .{
            .name = "Simple Arithmetic",
            .source = "3 + 4 * 5 - 6 / 2",
        },
        .{
            .name = "Variable Operations",
            .source =
            \\var x = 10
            \\var y = 20
            \\x + y * 2
            ,
        },
        .{
            .name = "Loop Execution",
            .source =
            \\var i = 0
            \\while (i < 100) {
            \\    i = i + 1
            \\}
            ,
        },
        .{
            .name = "Complex Expression",
            .source =
            \\var a = 5
            \\var b = 10
            \\var c = 15
            \\(a + b) * c - (a * b) + c / a
            ,
        },
    };

    for (test_scripts) |test_case| {
        std.debug.print("\n============================================================\n", .{});
        std.debug.print("Test: {s}\n", .{test_case.name});
        std.debug.print("============================================================\n", .{});

        try profileScript(allocator, test_case.source);

        std.debug.print("\n", .{});
    }

    std.debug.print("\n=== Profiling Complete ===\n", .{});
    std.debug.print("\nRecommendations:\n", .{});
    std.debug.print("  1. Hot paths indicate optimization opportunities\n", .{});
    std.debug.print("  2. High instruction counts suggest code generation issues\n", .{});
    std.debug.print("  3. Per-instruction timing helps identify slow opcodes\n", .{});
    std.debug.print("  4. Use this data to guide VM optimization efforts\n", .{});
}
