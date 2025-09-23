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

    // Test 1: Simple arithmetic (should have no leaks)
    std.debug.print("Test 1: Simple arithmetic\n", .{});
    {
        var script = try engine.loadScript("3 + 4");
        defer script.deinit();
        const result = try script.run();
        std.debug.print("Result: {}\n", .{result.number});
    }

    // Test 2: Local variable (likely source of leaks)
    std.debug.print("Test 2: Local variable\n", .{});
    {
        var script = try engine.loadScript("local x = 42");
        defer script.deinit();
        _ = try script.run();
    }

    // Test 3: String constant (likely source of leaks)
    std.debug.print("Test 3: String constant\n", .{});
    {
        var script = try engine.loadScript("\"hello\"");
        defer script.deinit();
        const result = try script.run();
        std.debug.print("Result: {s}\n", .{result.string});
    }

    // Test 4: String concatenation (likely source of leaks)
    std.debug.print("Test 4: String concatenation\n", .{});
    {
        var script = try engine.loadScript("\"Hello\" .. \" \" .. \"World\"");
        defer script.deinit();
        const result = try script.run();
        std.debug.print("Result: {s}\n", .{result.string});
    }

    // Test 5: For loop (likely source of leaks)
    std.debug.print("Test 5: For loop\n", .{});
    {
        const for_code =
            \\for i = 1, 2 do
            \\    i
            \\end
        ;
        var script = try engine.loadScript(for_code);
        defer script.deinit();
        _ = try script.run();
    }

    // Test 6: File I/O operations (likely source of leaks)
    try engine.registerFunction("writeFile", writeFileFunc);
    try engine.registerFunction("readFile", readFileFunc);

    std.debug.print("Test 6: File I/O\n", .{});
    {
        const file_code = "writeFile(\"test.txt\", \"Hello World\")";
        var script = try engine.loadScript(file_code);
        defer script.deinit();
        _ = try script.run();
    }

    std.debug.print("All tests completed\n", .{});
}

fn writeFileFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    if (args.len < 2 or args[0] != .string or args[1] != .string) {
        return .{ .boolean = false };
    }
    return .{ .boolean = true };
}

fn readFileFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    if (args.len < 1 or args[0] != .string) {
        return .{ .nil = {} };
    }
    return .{ .string = "Hello, Ghostlang!" };
}