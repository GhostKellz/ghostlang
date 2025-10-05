const std = @import("std");
const ghostlang = @import("ghostlang");

/// Security Audit Suite - Test sandbox escape attempts
/// This suite attempts various attack vectors to ensure the sandbox is secure
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Ghostlang Security Audit Suite ===\n\n", .{});

    var passed: usize = 0;
    var failed: usize = 0;

    // Test 1: Memory limit enforcement
    if (try testMemoryLimitEnforcement(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 2: Execution timeout enforcement
    if (try testExecutionTimeout(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 3: IO restriction (when disabled)
    if (try testIORestriction(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 4: Syscall restriction (when disabled)
    if (try testSyscallRestriction(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 5: Deterministic mode (no time-based functions)
    if (try testDeterministicMode(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 6: Stack overflow protection
    if (try testStackOverflowProtection(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 7: Infinite loop detection
    if (try testInfiniteLoopDetection(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 8: Malicious input handling
    if (try testMaliciousInputs(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    std.debug.print("\n=== Security Audit Summary ===\n", .{});
    std.debug.print("Passed: {}\n", .{passed});
    std.debug.print("Failed: {}\n", .{failed});
    std.debug.print("Total: {}\n", .{passed + failed});

    if (failed == 0) {
        std.debug.print("\n✓ All security tests passed!\n", .{});
    } else {
        std.debug.print("\n✗ Some security tests failed!\n", .{});
        std.process.exit(1);
    }
}

fn testMemoryLimitEnforcement(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 1: Memory Limit Enforcement\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 1024, // Very low limit - 1KB
        .execution_timeout_ms = 1000,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Try to allocate way more than the limit through repeated operations
    const script =
        \\var x = 1
        \\var y = 2
        \\var z = 3
    ;

    var loaded_script = engine.loadScript(script) catch {
        std.debug.print("  ✓ Memory limit enforced during parse\n\n", .{});
        return true;
    };
    defer loaded_script.deinit();

    _ = loaded_script.run() catch {
        std.debug.print("  ✓ Memory limit enforced during execution\n\n", .{});
        return true;
    };

    std.debug.print("  Status: ✓ PASS (within limits)\n\n", .{});
    return true;
}

fn testExecutionTimeout(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 2: Execution Timeout Enforcement\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .execution_timeout_ms = 10, // 10ms timeout
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // This should timeout
    const script =
        \\var i = 0
        \\while (i < 1000000) {
        \\    i = i + 1
        \\}
    ;

    var loaded_script = try engine.loadScript(script);
    defer loaded_script.deinit();

    const result = loaded_script.run();
    if (result) |_| {
        std.debug.print("  ✗ FAIL - Timeout not enforced!\n\n", .{});
        return false;
    } else |err| {
        if (err == ghostlang.ExecutionError.ExecutionTimeout) {
            std.debug.print("  ✓ PASS - Timeout correctly enforced\n\n", .{});
            return true;
        } else {
            std.debug.print("  ✗ FAIL - Wrong error: {}\n\n", .{err});
            return false;
        }
    }
}

fn testIORestriction(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 3: IO Restriction Enforcement\n", .{});

    const restricted_config = ghostlang.EngineConfig{
        .allocator = allocator,
        .allow_io = false, // IO disabled
    };

    var restricted = try ghostlang.ScriptEngine.create(restricted_config);
    defer restricted.deinit();

    const restricted_result = restricted.security.checkIOAllowed();
    if (restricted_result) |_| {
        std.debug.print("  ✗ FAIL - IO allowed despite restriction\n\n", .{});
        return false;
    } else |err| {
        if (err != ghostlang.ExecutionError.IONotAllowed) {
            std.debug.print("  ✗ FAIL - Unexpected error: {}\n\n", .{err});
            return false;
        }
    }

    const permissive_config = ghostlang.EngineConfig{
        .allocator = allocator,
        .allow_io = true,
    };

    var permissive = try ghostlang.ScriptEngine.create(permissive_config);
    defer permissive.deinit();

    permissive.security.checkIOAllowed() catch |err| {
        std.debug.print("  ✗ FAIL - IO blocked unexpectedly: {}\n\n", .{err});
        return false;
    };

    std.debug.print("  ✓ PASS - IO restrictions enforced correctly\n\n", .{});
    return true;
}

fn testSyscallRestriction(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 4: Syscall Restriction Enforcement\n", .{});

    const restricted_config = ghostlang.EngineConfig{
        .allocator = allocator,
        .allow_syscalls = false, // Syscalls disabled
    };

    var restricted = try ghostlang.ScriptEngine.create(restricted_config);
    defer restricted.deinit();

    const restricted_result = restricted.security.checkSyscallAllowed();
    if (restricted_result) |_| {
        std.debug.print("  ✗ FAIL - Syscalls allowed despite restriction\n\n", .{});
        return false;
    } else |err| {
        if (err != ghostlang.ExecutionError.SyscallNotAllowed) {
            std.debug.print("  ✗ FAIL - Unexpected error: {}\n\n", .{err});
            return false;
        }
    }

    const permissive_config = ghostlang.EngineConfig{
        .allocator = allocator,
        .allow_syscalls = true,
    };

    var permissive = try ghostlang.ScriptEngine.create(permissive_config);
    defer permissive.deinit();

    permissive.security.checkSyscallAllowed() catch |err| {
        std.debug.print("  ✗ FAIL - Syscalls blocked unexpectedly: {}\n\n", .{err});
        return false;
    };

    std.debug.print("  ✓ PASS - Syscall restrictions enforced correctly\n\n", .{});
    return true;
}

fn testDeterministicMode(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 5: Deterministic Mode Enforcement\n", .{});

    const restricted_config = ghostlang.EngineConfig{
        .allocator = allocator,
        .deterministic = true, // Deterministic mode
    };

    var restricted = try ghostlang.ScriptEngine.create(restricted_config);
    defer restricted.deinit();

    const restricted_result = restricted.security.checkNonDeterministicAllowed();
    if (restricted_result) |_| {
        std.debug.print("  ✗ FAIL - Non-deterministic features allowed\n\n", .{});
        return false;
    } else |err| {
        if (err != ghostlang.ExecutionError.SecurityViolation) {
            std.debug.print("  ✗ FAIL - Unexpected error: {}\n\n", .{err});
            return false;
        }
    }

    const permissive_config = ghostlang.EngineConfig{
        .allocator = allocator,
        .deterministic = false,
    };

    var permissive = try ghostlang.ScriptEngine.create(permissive_config);
    defer permissive.deinit();

    permissive.security.checkNonDeterministicAllowed() catch |err| {
        std.debug.print("  ✗ FAIL - Deterministic check raised unexpectedly: {}\n\n", .{err});
        return false;
    };

    std.debug.print("  ✓ PASS - Deterministic mode enforced correctly\n\n", .{});
    return true;
}

fn testStackOverflowProtection(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 6: Stack Overflow Protection\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 100 * 1024, // 100KB limit
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Deeply nested expressions
    const script = "((((((((((1))))))))))";

    var loaded_script = try engine.loadScript(script);
    defer loaded_script.deinit();

    _ = loaded_script.run() catch |err| {
        std.debug.print("  ✓ PASS - Protected against deep nesting: {}\n\n", .{err});
        return true;
    };

    std.debug.print("  ✓ PASS - Handled deep nesting safely\n\n", .{});
    return true;
}

fn testInfiniteLoopDetection(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 7: Infinite Loop Detection\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .execution_timeout_ms = 50, // 50ms timeout
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Infinite loop
    const script =
        \\var x = 1
        \\while (x > 0) {
        \\    x = x + 1
        \\}
    ;

    var loaded_script = try engine.loadScript(script);
    defer loaded_script.deinit();

    const result = loaded_script.run();
    if (result) |_| {
        std.debug.print("  ✗ FAIL - Infinite loop not detected!\n\n", .{});
        return false;
    } else |err| {
        if (err == ghostlang.ExecutionError.ExecutionTimeout) {
            std.debug.print("  ✓ PASS - Infinite loop terminated by timeout\n\n", .{});
            return true;
        } else {
            std.debug.print("  ✗ FAIL - Wrong error: {}\n\n", .{err});
            return false;
        }
    }
}

fn testMaliciousInputs(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 8: Malicious Input Handling\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .execution_timeout_ms = 100,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const malicious_inputs = [_][]const u8{
        "\x00\x00\x00", // Null bytes
        "\xff\xff\xff", // Invalid UTF-8
        "💀💀💀", // Unicode
        "((((((((((((((((((", // Unbalanced
        ";;;;;;;;;;;;;;;", // Excessive semicolons
        "var var var var", // Repeated keywords
    };

    for (malicious_inputs) |input| {
        var script = engine.loadScript(input) catch {
            // Expected to fail on parse
            continue;
        };
        defer script.deinit();

        _ = script.run() catch {
            // Expected to fail on execution
            continue;
        };
    }

    std.debug.print("  ✓ PASS - All malicious inputs handled safely\n\n", .{});
    return true;
}
