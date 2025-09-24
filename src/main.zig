const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    try engine.registerFunction("print", printFunc);

    // Load and run a script
    var script = try engine.loadScript("3 + 4");
    defer script.deinit();
    const result = try script.run();
    std.debug.print("Script result: {}\n", .{result.number});

    // Call a script function
    // const call_result = try engine.call("add", .{1, 2});
    // std.debug.print("Call result: {}\n", .{call_result});
}

fn printFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    for (args) |arg| {
        switch (arg) {
            .number => |n| std.debug.print("{}", .{n}),
            .string => |s| std.debug.print("{s}", .{s}),
            else => std.debug.print("{}", .{arg}),
        }
    }
    std.debug.print("\n", .{});
    return if (args.len > 0) args[0] else .{ .nil = {} };
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
