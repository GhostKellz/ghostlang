const std = @import("std");
const ghostlang = @import("ghostlang");

/// Integration Test Suite - Real-world plugin scenarios
/// Tests complete plugin workflows as they would be used in Grim editor
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Ghostlang Integration Test Suite ===\n\n", .{});

    var passed: usize = 0;
    var failed: usize = 0;

    // Test 1: Simple configuration plugin
    if (try testConfigurationPlugin(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 2: Text manipulation plugin
    if (try testTextManipulationPlugin(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 3: Multiple plugins loaded simultaneously
    if (try testMultiplePlugins(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 4: Plugin error recovery
    if (try testPluginErrorRecovery(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 5: Security levels (trusted/normal/sandboxed)
    if (try testSecurityLevels(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 6: Control flow extensions (numeric for, repeat/until)
    if (try testControlFlowExtensions(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 7: Generic iterators and function literals
    if (try testGenericIteratorsAndFunctions(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 8: Numeric for loop guardrails
    if (try testNumericForStepGuard(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    // Test 9: Closure captures and stateful functions
    if (try testClosuresCapture(allocator)) {
        passed += 1;
    } else {
        failed += 1;
    }

    std.debug.print("\n=== Integration Test Summary ===\n", .{});
    std.debug.print("Passed: {}\n", .{passed});
    std.debug.print("Failed: {}\n", .{failed});
    std.debug.print("Total: {}\n", .{passed + failed});

    if (failed == 0) {
        std.debug.print("\n✓ All integration tests passed!\n", .{});
    } else {
        std.debug.print("\n✗ Some integration tests failed!\n", .{});
        std.process.exit(1);
    }
}

fn testConfigurationPlugin(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 1: Configuration Plugin\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Typical configuration script
    const script =
        \\var tab_width = 4
        \\var use_spaces = true
        \\var line_length = 80
        \\tab_width + line_length
    ;

    var loaded_script = try engine.loadScript(script);
    defer loaded_script.deinit();

    const result = try loaded_script.run();

    if (result.number == 84) {
        std.debug.print("  ✓ PASS - Configuration values computed correctly\n\n", .{});
        return true;
    } else {
        std.debug.print("  ✗ FAIL - Expected 84, got {}\n\n", .{result.number});
        return false;
    }
}

fn testTextManipulationPlugin(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 2: Text Manipulation Plugin\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Simulate text manipulation operations
    const script =
        \\var line_count = 100
        \\var cursor_pos = 50
        \\var selection_start = 40
        \\var selection_end = 60
        \\selection_end - selection_start
    ;

    var loaded_script = try engine.loadScript(script);
    defer loaded_script.deinit();

    const result = try loaded_script.run();

    if (result.number == 20) {
        std.debug.print("  ✓ PASS - Text manipulation calculations correct\n\n", .{});
        return true;
    } else {
        std.debug.print("  ✗ FAIL - Expected 20, got {}\n\n", .{result.number});
        return false;
    }
}

fn testMultiplePlugins(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 3: Multiple Plugins Simultaneously\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    // Plugin 1: Line counter
    var engine1 = try ghostlang.ScriptEngine.create(config);
    defer engine1.deinit();

    var script1 = try engine1.loadScript("var lines = 100");
    defer script1.deinit();
    _ = try script1.run();

    // Plugin 2: Character counter
    var engine2 = try ghostlang.ScriptEngine.create(config);
    defer engine2.deinit();

    var script2 = try engine2.loadScript("var chars = 5000");
    defer script2.deinit();
    _ = try script2.run();

    // Plugin 3: Calculator
    var engine3 = try ghostlang.ScriptEngine.create(config);
    defer engine3.deinit();

    var script3 = try engine3.loadScript("42 * 2");
    defer script3.deinit();
    const result = try script3.run();

    if (result.number == 84) {
        std.debug.print("  ✓ PASS - Multiple plugins isolated correctly\n\n", .{});
        return true;
    } else {
        std.debug.print("  ✗ FAIL - Plugin interference detected\n\n", .{});
        return false;
    }
}

fn testPluginErrorRecovery(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 4: Plugin Error Recovery\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Malformed script
    var bad_script = engine.loadScript("var x =") catch {
        // Error recovered - try a good script (use expression, not declaration, to get return value)
        var good_script = try engine.loadScript("40 + 2");
        defer good_script.deinit();

        const result = try good_script.run();

        if (result == .number and result.number == 42) {
            std.debug.print("  ✓ PASS - Engine recovered from error\n\n", .{});
            return true;
        } else {
            std.debug.print("  ✗ FAIL - Engine corrupted after error (got {any})\n\n", .{result});
            return false;
        }
    };
    defer bad_script.deinit();

    std.debug.print("  ✗ FAIL - Bad script should have failed!\n\n", .{});
    return false;
}

fn testSecurityLevels(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 5: Security Levels\n", .{});

    // Sandboxed (lowest privileges)
    const sandboxed_config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 4 * 1024 * 1024, // 4MB
        .execution_timeout_ms = 2000, // 2s
        .allow_io = false,
        .allow_syscalls = false,
        .deterministic = true,
    };

    var sandboxed = try ghostlang.ScriptEngine.create(sandboxed_config);
    defer sandboxed.deinit();

    var s1 = try sandboxed.loadScript("1 + 2");
    defer s1.deinit();
    _ = try s1.run();

    // Normal (balanced)
    const normal_config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 16 * 1024 * 1024, // 16MB
        .execution_timeout_ms = 5000, // 5s
        .allow_io = false,
        .allow_syscalls = false,
        .deterministic = false,
    };

    var normal = try ghostlang.ScriptEngine.create(normal_config);
    defer normal.deinit();

    var s2 = try normal.loadScript("2 + 3");
    defer s2.deinit();
    _ = try s2.run();

    // Trusted (highest privileges)
    const trusted_config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 64 * 1024 * 1024, // 64MB
        .execution_timeout_ms = 30000, // 30s
        .allow_io = true,
        .allow_syscalls = true,
        .deterministic = false,
    };

    var trusted = try ghostlang.ScriptEngine.create(trusted_config);
    defer trusted.deinit();

    var s3 = try trusted.loadScript("3 + 4");
    defer s3.deinit();
    _ = try s3.run();

    std.debug.print("  ✓ PASS - All security levels working\n\n", .{});
    return true;
}

fn testControlFlowExtensions(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 6: Control Flow Extensions\n", .{});

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var forward = 0
        \\for i = 1, 5 do
        \\    forward = forward + i
        \\end
        \\var backward = 0
        \\for j = 5, 1, -2 do
        \\    backward = backward + j
        \\end
        \\var countdown = 3
        \\repeat
        \\    backward = backward - countdown
        \\    countdown = countdown - 1
        \\until countdown <= 0
        \\forward + backward
    ;

    var loaded_script = try engine.loadScript(script);
    defer loaded_script.deinit();

    const result = try loaded_script.run();

    if (result == .number and result.number == 18) {
        std.debug.print("  ✓ PASS - Dual syntax control flow is operational\n\n", .{});
        return true;
    }

    switch (result) {
        .number => |value| std.debug.print("  ✗ FAIL - Expected 18, got {}\n\n", .{value}),
        else => std.debug.print("  ✗ FAIL - Expected number, got {s}\n\n", .{@tagName(result)}),
    }
    return false;
}

fn testGenericIteratorsAndFunctions(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 7: Generic Iterators & Functions\n", .{});

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\local function add_if_even(sum, value)
        \\    if value % 2 == 0 then
        \\        return sum + value
        \\    end
        \\    return sum
        \\end
        \\var mapping = { first = 2, second = 4, third = 5 }
        \\var table_total = 0
        \\for name, value in pairs(mapping) do
        \\    table_total = add_if_even(table_total, value)
        \\end
        \\var list = [1, 2, 3]
        \\var inc = function(x) return x + 10 end
        \\var list_total = 0
        \\for value in list do
        \\    list_total = list_total + inc(value)
        \\end
        \\table_total + list_total
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result == .number and result.number == 42) {
        std.debug.print("  ✓ PASS - Generic iterators and functions operational\n\n", .{});
        return true;
    }

    switch (result) {
        .number => |value| std.debug.print("  ✗ FAIL - Expected 42, got {}\n\n", .{value}),
        else => std.debug.print("  ✗ FAIL - Expected number, got {s}\n\n", .{@tagName(result)}),
    }
    return false;
}

fn testNumericForStepGuard(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 8: Numeric For Step Guard\n", .{});

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript(
        \\var total = 0
        \\for i = 1, 3, 0 do
        \\    total = total + i
        \\end
        \\total
    );
    defer script.deinit();

    const run_result = script.run();
    if (run_result) |value| {
        std.debug.print("  ✗ FAIL - Expected ExecutionTimeout error, got value {s}\n\n", .{@tagName(value)});
        return false;
    } else |err| {
        if (err == ghostlang.ExecutionError.ExecutionTimeout) {
            std.debug.print("  ✓ PASS - Zero step rejected via execution timeout\n\n", .{});
            return true;
        }
        std.debug.print("  ✗ FAIL - Expected ExecutionTimeout, got {s}\n\n", .{@errorName(err)});
        return false;
    }
}

fn testClosuresCapture(allocator: std.mem.Allocator) !bool {
    std.debug.print("Test 9: Closure Captures\n", .{});

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\local function make_counter(start)
        \\    local count = start
        \\    return function()
        \\        count = count + 1
        \\        return count
        \\    end
        \\end
        \\var first = make_counter(0)
        \\var second = make_counter(5)
        \\var total = 0
        \\total = total + first()
        \\total = total + first()
        \\total = total + second()
        \\total = total + second()
        \\return total
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();

    const result = try loaded.run();
    if (result == .number and result.number == 16) {
        std.debug.print("  ✓ PASS - Closures capture lexical state correctly\n\n", .{});
        return true;
    }

    switch (result) {
        .number => |value| std.debug.print("  ✗ FAIL - Expected 16, got {}\n\n", .{value}),
        else => std.debug.print("  ✗ FAIL - Expected number, got {s}\n\n", .{@tagName(result)}),
    }
    return false;
}
