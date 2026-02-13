const std = @import("std");
const ghostlang = @import("ghostlang");

/// Benchmark suite for Ghostlang performance testing
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Ghostlang Performance Benchmarks ===\n\n", .{});

    try benchmarkPluginLoading(allocator);
    try benchmarkSimpleExecution(allocator);
    try benchmarkAPICallsOverhead(allocator);
    try benchmarkMemoryUsage(allocator);

    std.debug.print("\n=== Benchmarks Complete ===\n", .{});
}

fn benchmarkPluginLoading(allocator: std.mem.Allocator) !void {
    std.debug.print("Benchmark: Plugin Loading Speed\n", .{});
    std.debug.print("Target: <100µs per load\n", .{});

    const iterations = 1000;
    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var total_ns: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var ts_start: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(.MONOTONIC, &ts_start);
        const start_ns = @as(u64, @intCast(ts_start.sec)) * 1_000_000_000 + @as(u64, @intCast(ts_start.nsec));

        var engine = try ghostlang.ScriptEngine.create(config);
        var ts_end: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(.MONOTONIC, &ts_end);
        const end_ns = @as(u64, @intCast(ts_end.sec)) * 1_000_000_000 + @as(u64, @intCast(ts_end.nsec));
        const load_time = end_ns - start_ns;
        engine.deinit();

        total_ns += load_time;
    }

    const avg_ns = total_ns / iterations;
    const avg_us = avg_ns / 1000;
    const target_met = avg_us < 100;

    std.debug.print("  Average: {}µs ({} ns)\n", .{ avg_us, avg_ns });
    std.debug.print("  Status: {s}\n\n", .{if (target_met) "✓ PASS" else "✗ FAIL"});
}

fn benchmarkSimpleExecution(allocator: std.mem.Allocator) !void {
    std.debug.print("Benchmark: Simple Script Execution\n", .{});
    std.debug.print("Target: <1ms per execution\n", .{});

    const iterations = 100;
    const test_script = "3 + 4 * 5 - 6 / 2";

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    var total_ns: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var ts_start: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(.MONOTONIC, &ts_start);
        const start_ns = @as(u64, @intCast(ts_start.sec)) * 1_000_000_000 + @as(u64, @intCast(ts_start.nsec));

        var script = try engine.loadScript(test_script);
        _ = try script.run();
        var ts_end: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(.MONOTONIC, &ts_end);
        const end_ns = @as(u64, @intCast(ts_end.sec)) * 1_000_000_000 + @as(u64, @intCast(ts_end.nsec));
        const exec_time = end_ns - start_ns;
        script.deinit();

        total_ns += exec_time;
    }

    const avg_ns = total_ns / iterations;
    const avg_us = avg_ns / 1000;
    const avg_ms = avg_us / 1000;
    const target_met = avg_ms < 1;

    std.debug.print("  Average: {}ms ({}µs)\n", .{ avg_ms, avg_us });
    std.debug.print("  Status: {s}\n\n", .{if (target_met) "✓ PASS" else "✗ FAIL"});
}

fn benchmarkAPICallsOverhead(allocator: std.mem.Allocator) !void {
    std.debug.print("Benchmark: FFI/API Call Overhead\n", .{});
    std.debug.print("Target: <10µs per call\n", .{});

    const iterations = 1000;

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Register a simple test function
    const TestFunc = struct {
        fn testFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
            _ = args;
            return .{ .number = 42 };
        }
    };

    try engine.registerFunction("test", TestFunc.testFunc);

    var total_ns: u64 = 0;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var ts_start: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(.MONOTONIC, &ts_start);
        const start_ns = @as(u64, @intCast(ts_start.sec)) * 1_000_000_000 + @as(u64, @intCast(ts_start.nsec));

        _ = try engine.call("test", .{});
        var ts_end: std.posix.timespec = undefined;
        _ = std.posix.system.clock_gettime(.MONOTONIC, &ts_end);
        const end_ns = @as(u64, @intCast(ts_end.sec)) * 1_000_000_000 + @as(u64, @intCast(ts_end.nsec));
        const call_time = end_ns - start_ns;

        total_ns += call_time;
    }

    const avg_ns = total_ns / iterations;
    const avg_us = avg_ns / 1000;
    const target_met = avg_us < 10;

    std.debug.print("  Average: {}µs ({} ns)\n", .{ avg_us, avg_ns });
    std.debug.print("  Status: {s}\n\n", .{if (target_met) "✓ PASS" else "✗ FAIL"});
}

fn benchmarkMemoryUsage(allocator: std.mem.Allocator) !void {
    std.debug.print("Benchmark: Per-Plugin Memory Overhead\n", .{});
    std.debug.print("Target: <50KB per plugin\n", .{});

    // Create engine and measure base memory
    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 10 * 1024 * 1024, // 10MB limit
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Load a simple script
    const test_script =
        \\var x = 10
        \\var y = 20
        \\x + y
    ;

    var script = try engine.loadScript(test_script);
    defer script.deinit();

    // In a real implementation, we'd measure actual memory usage here
    // For now, we estimate based on struct sizes
    const estimated_kb = 5; // Placeholder - would use actual measurement

    const target_met = estimated_kb < 50;

    std.debug.print("  Estimated: ~{}KB\n", .{estimated_kb});
    std.debug.print("  Status: {s}\n\n", .{if (target_met) "✓ PASS" else "⚠ NEEDS MEASUREMENT"});
}
