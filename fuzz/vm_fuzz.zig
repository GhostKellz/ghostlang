const std = @import("std");
const ghostlang = @import("ghostlang");

/// Fuzzing target specifically for VM execution
/// Tests VM robustness with malformed bytecode sequences
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read from stdin
    const stdin = std.io.getStdIn();
    const input = try stdin.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(input);

    // Parse as script code
    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 10 * 1024 * 1024,
        .execution_timeout_ms = 50, // Shorter timeout for VM testing
        .allow_io = false,
        .allow_syscalls = false,
        .deterministic = true,
    };

    var engine = ghostlang.ScriptEngine.create(config) catch return;
    defer engine.deinit();

    var script = engine.loadScript(input) catch return;
    defer script.deinit();

    // Run the VM - this is where we stress test execution
    _ = script.run() catch return;
}

export fn LLVMFuzzerTestOneInput(data: [*]const u8, size: usize) callconv(.c) c_int {
    const input = data[0..size];

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 10 * 1024 * 1024,
        .execution_timeout_ms = 50,
        .allow_io = false,
        .allow_syscalls = false,
        .deterministic = true,
    };

    var engine = ghostlang.ScriptEngine.create(config) catch return 0;
    defer engine.deinit();

    var script = engine.loadScript(input) catch return 0;
    defer script.deinit();

    _ = script.run() catch return 0;

    return 0;
}
