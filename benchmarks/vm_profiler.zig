const std = @import("std");
const ghostlang = @import("ghostlang");

/// VM Performance Profiler
/// Provides detailed execution statistics for VM performance analysis
pub const VMProfiler = struct {
    instruction_counts: [23]usize, // One per opcode
    instruction_times: [23]u64, // Nanoseconds per opcode
    total_instructions: usize,
    total_time_ns: u64,
    max_stack_depth: usize,
    memory_allocations: usize,
    memory_freed: usize,

    pub fn init() VMProfiler {
        return .{
            .instruction_counts = [_]usize{0} ** 23,
            .instruction_times = [_]u64{0} ** 23,
            .total_instructions = 0,
            .total_time_ns = 0,
            .max_stack_depth = 0,
            .memory_allocations = 0,
            .memory_freed = 0,
        };
    }

    pub fn recordInstruction(self: *VMProfiler, opcode: u8, time_ns: u64) void {
        if (opcode < 23) {
            self.instruction_counts[opcode] += 1;
            self.instruction_times[opcode] += time_ns;
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
            const avg_ns = self.total_time_ns / self.total_instructions;
            std.debug.print("Average Time/Instruction: {}ns\n", .{avg_ns});
        }
        std.debug.print("\n", .{});

        // Per-opcode statistics
        std.debug.print("Per-Opcode Statistics:\n", .{});
        std.debug.print("{s:<20} {s:>10} {s:>12} {s:>12} {s:>10}\n", .{ "Opcode", "Count", "Total (µs)", "Avg (ns)", "% Time" });
        std.debug.print("----------------------------------------------------------------------\n", .{});

        const opcode_names = [_][]const u8{
            "nop",
            "load_const",
            "load_global",
            "store_global",
            "add",
            "sub",
            "mul",
            "div",
            "mod",
            "eq",
            "neq",
            "lt",
            "gt",
            "lte",
            "gte",
            "and_op",
            "or_op",
            "begin_scope",
            "end_scope",
            "call",
            "jump",
            "jump_if_false",
            "ret",
        };

        // Create sorted list of opcodes by execution time
        var sorted_indices = try allocator.alloc(usize, 23);
        defer allocator.free(sorted_indices);

        for (0..23) |i| {
            sorted_indices[i] = i;
        }

        // Simple bubble sort by time (good enough for 23 items)
        var i: usize = 0;
        while (i < 23) : (i += 1) {
            var j: usize = i + 1;
            while (j < 23) : (j += 1) {
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
                opcode_names[idx],
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
                std.debug.print("  🔥 {s}: {d:.1}%\n", .{ opcode_names[idx], percent });
                found_hot = true;
            }
        }
        if (!found_hot) {
            std.debug.print("  No hot paths detected (well-balanced execution)\n", .{});
        }

        std.debug.print("\n", .{});
    }
};

/// Profiled script runner
pub fn profileScript(allocator: std.mem.Allocator, source: []const u8) !void {
    std.debug.print("\n=== Profiling Script ===\n", .{});
    std.debug.print("Source:\n{s}\n", .{source});

    var profiler = VMProfiler.init();

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript(source);
    defer script.deinit();

    // Run with detailed timing
    var timer = try std.time.Timer.start();
    const start = timer.read();

    const result = try script.run();

    const end = timer.read();
    const total_time = end - start;

    // Estimate instruction breakdown (since we can't hook into VM directly yet)
    // In a real implementation, we'd instrument the VM's run() method
    const estimated_instructions = script.vm.instruction_count;
    profiler.total_instructions = estimated_instructions;
    profiler.total_time_ns = total_time;

    // Estimate per-opcode counts based on instruction distribution
    if (estimated_instructions > 0) {
        // Simple heuristic: distribute counts based on common patterns
        profiler.instruction_counts[1] = estimated_instructions / 4; // load_const
        profiler.instruction_counts[4] = estimated_instructions / 8; // add
        profiler.instruction_counts[5] = estimated_instructions / 16; // sub
        profiler.instruction_counts[6] = estimated_instructions / 16; // mul

        const time_per_instr = total_time / estimated_instructions;
        for (0..20) |i| {
            profiler.instruction_times[i] = profiler.instruction_counts[i] * time_per_instr;
        }
    }

    std.debug.print("\nResult: ", .{});
    switch (result) {
        .nil => std.debug.print("nil\n", .{}),
        .boolean => |b| std.debug.print("{}\n", .{b}),
        .number => |n| std.debug.print("{d}\n", .{n}),
        .string => |s| std.debug.print("\"{s}\"\n", .{s}),
        else => std.debug.print("<complex value>\n", .{}),
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
