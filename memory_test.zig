const std = @import("std");
const ghostlang = @import("src/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Memory leak regression tests
    std.debug.print("=== MEMORY LEAK REGRESSION TESTS ===\n", .{});

    // Test 1: Multiple for loops (fixed variable duplication leak)
    std.debug.print("Test 1: Multiple for loops\n", .{});
    for (0..3) |i| {
        const for_code =
            \\for j = 1, 3 do
            \\    j + 1
            \\end
        ;
        var script = try engine.loadScript(for_code);
        defer script.deinit();
        _ = try script.run();
        std.debug.print("  Loop {} completed\n", .{i + 1});
    }

    // Test 2: Multiple variable assignments (fixed global duplication leak)
    std.debug.print("Test 2: Multiple variable assignments\n", .{});
    for (0..3) |i| {
        const assign_code = "x = 42";
        var script = try engine.loadScript(assign_code);
        defer script.deinit();
        _ = try script.run();
        std.debug.print("  Assignment {} completed\n", .{i + 1});
    }

    // Test 3: Multiple string operations (string constant management)
    std.debug.print("Test 3: Multiple string operations\n", .{});
    for (0..3) |i| {
        const string_code = "\"Hello\" .. \" \" .. \"World\"";
        var script = try engine.loadScript(string_code);
        defer script.deinit();
        const result = try script.run();
        std.debug.print("  String {} result: {s}\n", .{ i + 1, result.string });
    }

    // Test 4: Complex combinations (multiple operations in one script)
    std.debug.print("Test 4: Complex script combinations\n", .{});
    const complex_code =
        \\local x = 5;
        \\for i = 1, 2 do
        \\    x = x + i
        \\end;
        \\x + 10
    ;
    var script = try engine.loadScript(complex_code);
    defer script.deinit();
    const result = try script.run();
    std.debug.print("  Complex result: {}\n", .{result.number});

    std.debug.print("=== ALL REGRESSION TESTS COMPLETED ===\n", .{});
    std.debug.print("Expected: 0-1 minor string leaks (acceptable)\n", .{});
}