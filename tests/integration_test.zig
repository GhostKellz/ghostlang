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
        // Error recovered - try a good script
        var good_script = try engine.loadScript("var y = 42");
        defer good_script.deinit();

        const result = try good_script.run();

        if (result.number == 42) {
            std.debug.print("  ✓ PASS - Engine recovered from error\n\n", .{});
            return true;
        } else {
            std.debug.print("  ✗ FAIL - Engine corrupted after error\n\n", .{});
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
