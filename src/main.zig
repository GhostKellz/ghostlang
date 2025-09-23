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

    // Register file I/O functions (temporarily disabled)
    // try engine.registerFunction("readFile", readFileFunc);
    // try engine.registerFunction("writeFile", writeFileFunc);
    // try engine.registerFunction("fileExists", fileExistsFunc);

    // Test simple expression
    std.debug.print("Testing: 3 + 4\n", .{});
    var script1 = try engine.loadScript("3 + 4");
    defer script1.deinit();

    // Print generated instructions for debugging
    std.debug.print("Generated {} instructions:\n", .{script1.vm.code.len});
    for (script1.vm.code, 0..) |instr, i| {
        std.debug.print("  {}: opcode={} operands=[{}, {}, {}]\n", .{i, instr.opcode, instr.operands[0], instr.operands[1], instr.operands[2]});
    }
    std.debug.print("Generated {} constants:\n", .{script1.vm.constants.len});
    for (script1.vm.constants, 0..) |constant, i| {
        std.debug.print("  {}: {}\n", .{i, constant});
    }

    const result1 = try script1.run();
    std.debug.print("Simple expression result: {}\n", .{result1.number});

    // Test just function call (without definition)
    std.debug.print("\nTesting simple function call:\n", .{});
    const call_code = "print(42)";

    var script2a = try engine.loadScript(call_code);
    defer script2a.deinit();
    std.debug.print("Call instructions:\n", .{});
    for (script2a.vm.code, 0..) |instr, i| {
        std.debug.print("  {}: opcode={} operands=[{}, {}, {}]\n", .{i, instr.opcode, instr.operands[0], instr.operands[1], instr.operands[2]});
    }
    _ = try script2a.run();

    // Test just function definition
    std.debug.print("\nTesting function definition:\n", .{});
    const def_code =
        \\function add(a, b)
        \\    return 5 + 6
        \\end
    ;

    var script2b = try engine.loadScript(def_code);
    defer script2b.deinit();
    _ = try script2b.run();

    // Functions are not shared between scripts for now

    // Test function definition + actual function call
    std.debug.print("\nTesting function def + calling defined function:\n", .{});
    const func_and_call =
        \\function add(a, b)
        \\    return 5 + 6
        \\end;
        \\add(1, 2)
    ;

    var script2e = try engine.loadScript(func_and_call);
    defer script2e.deinit();
    const result2e = try script2e.run();
    std.debug.print("Function + call result: {}\n", .{result2e});

    // Test local variables
    std.debug.print("\nTesting local variables:\n", .{});
    const local_code =
        \\local x = 42;
        \\local y = 10;
        \\x + y
    ;

    var script3 = try engine.loadScript(local_code);
    defer script3.deinit();
    const result3 = try script3.run();
    std.debug.print("Local variables result: {}\n", .{result3});

    // Test simple if statement (no else)
    std.debug.print("\nTesting simple if statement:\n", .{});
    const simple_if_code =
        \\local x = 5;
        \\if (x < 10) {
        \\    42
        \\}
    ;

    var script4 = try engine.loadScript(simple_if_code);
    defer script4.deinit();
    const result4 = try script4.run();
    std.debug.print("Simple if result: {}\n", .{result4});

    // Test table creation
    std.debug.print("\nTesting table creation:\n", .{});
    const table_code = "local t = {name = 42}";

    var script5 = try engine.loadScript(table_code);
    defer script5.deinit();
    const result5 = try script5.run();
    std.debug.print("Table creation result: {}\n", .{result5});

    // Test require (basic stub)
    std.debug.print("\nTesting require statement:\n", .{});
    const require_code = "require(\"utils.gza\")";

    var script6 = try engine.loadScript(require_code);
    defer script6.deinit();
    std.debug.print("Require instructions:\n", .{});
    for (script6.vm.code, 0..) |instr, i| {
        std.debug.print("  {}: opcode={} operands=[{}, {}, {}]\n", .{i, instr.opcode, instr.operands[0], instr.operands[1], instr.operands[2]});
    }
    const result6 = try script6.run();
    std.debug.print("Require result: {}\n", .{result6});

    // Test string operations
    std.debug.print("\nTesting string operations:\n", .{});
    const string_code = "\"Hello\" .. \" \" .. \"World\"";
    var script7 = try engine.loadScript(string_code);
    defer script7.deinit();
    const result7 = try script7.run();
    std.debug.print("String concatenation result: {}\n", .{result7});

    // Test for loop
    std.debug.print("\nTesting for loop:\n", .{});
    const for_code =
        \\for i = 1, 3 do
        \\    print(i)
        \\end
    ;
    var script8 = try engine.loadScript(for_code);
    defer script8.deinit();
    _ = try script8.run();

    // Test assignment
    std.debug.print("\nTesting assignment:\n", .{});
    const assign_code = "x = 5";
    var script9a = try engine.loadScript(assign_code);
    defer script9a.deinit();
    _ = try script9a.run();

    // Test while loop
    std.debug.print("\nTesting while loop:\n", .{});
    const while_code =
        \\local x = 1;
        \\while x < 3 do
        \\    x = x + 1
        \\end
    ;
    var script9 = try engine.loadScript(while_code);
    defer script9.deinit();
    _ = try script9.run();

    // File I/O test temporarily disabled due to API compatibility
    std.debug.print("\nFile I/O infrastructure added (test disabled)\n", .{});

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

fn readFileFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    if (args.len < 1 or args[0] != .string) {
        return .{ .nil = {} };
    }

    const allocator = std.heap.page_allocator;
    const filename = args[0].string;
    const content = std.fs.cwd().readFileAlloc(filename, allocator, 1024 * 1024) catch {
        return .{ .nil = {} };
    };

    return .{ .string = content };
}

fn writeFileFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    if (args.len < 2 or args[0] != .string or args[1] != .string) {
        return .{ .boolean = false };
    }

    const filename = args[0].string;
    const content = args[1].string;
    std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content }) catch {
        return .{ .boolean = false };
    };

    return .{ .boolean = true };
}

fn fileExistsFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    if (args.len < 1 or args[0] != .string) {
        return .{ .boolean = false };
    }

    const filename = args[0].string;
    std.fs.cwd().access(filename, .{}) catch {
        return .{ .boolean = false };
    };

    return .{ .boolean = true };
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
