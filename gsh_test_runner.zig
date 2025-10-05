const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read script from file if provided, otherwise use test script
    var script_content: []const u8 = undefined;
    var should_free = false;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        // Read from file
        const file = try std.fs.cwd().openFile(args[1], .{});
        defer file.close();
        script_content = try file.readToEndAlloc(allocator, 1024 * 1024);
        should_free = true;
    } else {
        script_content =
            \\print("No script file provided. Use: gsh_test script.gza")
        ;
    }
    defer if (should_free) allocator.free(script_content);

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Register all required functions for GSH
    try engine.registerFunction("print", printFunc);
    try engine.registerFunction("createArray", createArrayFunc);
    try engine.registerFunction("arrayPush", arrayPushFunc);
    try engine.registerFunction("arrayGet", arrayGetFunc);
    try engine.registerFunction("arrayLength", arrayLengthFunc);
    try engine.registerFunction("createObject", createObjectFunc);
    try engine.registerFunction("objectSet", objectSetFunc);
    try engine.registerFunction("objectGet", objectGetFunc);

    // Load and run the script
    var script = engine.loadScript(script_content) catch |err| {
        std.debug.print("Error loading script: {}\n", .{err});
        return err;
    };
    defer script.deinit();

    const result = script.run() catch |err| {
        std.debug.print("Error running script: {}\n", .{err});
        return err;
    };

    // Print final result
    std.debug.print("\n[Script returned: ", .{});
    printValue(result);
    std.debug.print("]\n", .{});
}

fn printValue(val: ghostlang.ScriptValue) void {
    switch (val) {
        .nil => std.debug.print("nil", .{}),
        .boolean => |b| std.debug.print("{}", .{b}),
        .number => |n| std.debug.print("{d}", .{n}),
        .string => |s| std.debug.print("{s}", .{s}),
        .function => std.debug.print("<function>", .{}),
        .native_function => std.debug.print("<native_function>", .{}),
        .script_function => std.debug.print("<script_function>", .{}),
        .table => std.debug.print("<table>", .{}),
        .array => std.debug.print("<array>", .{}),
        .iterator => std.debug.print("<iterator>", .{}),
        .upvalue => std.debug.print("<upvalue>", .{}),
    }
}

fn printFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    for (args, 0..) |arg, i| {
        if (i > 0) std.debug.print(" ", .{});
        printValue(arg);
    }
    std.debug.print("\n", .{});
    return .{ .nil = {} };
}

fn createArrayFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    // This should be properly implemented by getting allocator from engine context
    // For now, return a placeholder
    return .{ .nil = {} };
}

fn arrayPushFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

fn arrayGetFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .string = "test_item" };
}

fn arrayLengthFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .number = 3 };
}

fn createObjectFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

fn objectSetFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

fn objectGetFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .string = "test_value" };
}
