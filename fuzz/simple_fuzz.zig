const ghostlang = @import("ghostlang");
const std = @import("std");

pub fn main() void {
    // Comprehensive fuzzing test cases
    const test_cases = [_][]const u8{
        // Valid inputs
        "3 + 4",
        "var x = 10",
        "var y = 3.14159",
        "var z = x + y * 2",
        "3 + 4 * 5 - 6 / 2",
        "((((5))))",

        // Edge cases - deeply nested
        "((((((((((1))))))))))",
        "1+2+3+4+5+6+7+8+9+10",

        // Malformed - missing operators
        "var x =",
        "3 +",
        "+ 5",
        "var",

        // Malformed - unbalanced parens
        "(((",
        ")))",
        "((())",
        "(()(",

        // Malformed - invalid syntax
        "if (",
        "while {{{",
        "))) (((  ",
        "x ++ +++ y",
        "***",
        "///" ,

        // Empty and whitespace
        "",
        "   ",
        "\n\n\n",
        "\t\t",

        // Very long expressions
        "1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1",

        // Unicode and special chars (should fail gracefully)
        "💀",
        "var 変数 = 5",
        "\x00\x01\x02",

        // Numbers edge cases
        "0",
        "999999999999",
        "0.000001",
        ".5",
        "5.",

        // String-like (not yet supported, should fail gracefully)
        "\"hello\"",
        "'world'",
        "`backtick`",
    };

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

    var engine = ghostlang.ScriptEngine.create(config) catch {
        std.debug.print("Failed to create engine\n", .{});
        return;
    };
    defer engine.deinit();

    std.debug.print("Running {} fuzz test cases...\n", .{test_cases.len});

    for (test_cases, 0..) |input, i| {
        var script = engine.loadScript(input) catch {
            std.debug.print("[{}] Parse failed (expected): {s}\n", .{ i, input });
            continue;
        };
        defer script.deinit();

        _ = script.run() catch {
            std.debug.print("[{}] Execution failed (expected): {s}\n", .{ i, input });
            continue;
        };

        std.debug.print("[{}] Success: {s}\n", .{ i, input });
    }

    std.debug.print("Fuzzing complete - no crashes!\n", .{});
}
