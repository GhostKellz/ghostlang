const std = @import("std");
const ghostlang = @import("ghostlang");

/// Fuzzing target for the Ghostlang parser
/// This will test parser robustness against arbitrary input
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read from stdin
    const stdin = std.io.getStdIn();
    const input = try stdin.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(input);

    // Create minimal engine config for fuzzing
    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 10 * 1024 * 1024, // 10MB for fuzzing
        .execution_timeout_ms = 100, // 100ms timeout
        .allow_io = false,
        .allow_syscalls = false,
        .deterministic = true,
    };

    var engine = ghostlang.ScriptEngine.create(config) catch {
        // Engine creation failed - this is fine, just exit
        return;
    };
    defer engine.deinit();

    // Try to parse the input - we don't care if it fails, just that it doesn't crash
    var script = engine.loadScript(input) catch {
        // Parse failed - this is expected for most fuzz inputs
        return;
    };
    defer script.deinit();

    // Try to run the script - again, failure is fine
    _ = script.run() catch {
        // Execution failed - expected for most inputs
        return;
    };

    // If we got here, the input was valid and executed successfully
}

// Export for libFuzzer/AFL++ integration
export fn LLVMFuzzerTestOneInput(data: [*]const u8, size: usize) callconv(.c) c_int {
    const input = data[0..size];

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 10 * 1024 * 1024,
        .execution_timeout_ms = 100,
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
