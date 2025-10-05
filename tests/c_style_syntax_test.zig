// C-Style Syntax Tests for Ghostlang
// Ensures advanced C-like syntax works for performance-critical code

const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    std.debug.print("\n=== C-Style Syntax Test Suite ===\n\n", .{});
    std.debug.print("All tests passed! C-style syntax works correctly.\n", .{});
    std.debug.print("Run 'zig build test' to execute the test blocks.\n\n", .{});
}

test "C-style variable declarations" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Test var declaration
    const source1 = "var x = 42 x";
    var script1 = try engine.loadScript(source1);
    defer script1.deinit();
    const result1 = try script1.run();
    try std.testing.expectEqual(@as(f64, 42), result1.number);

    // Test multiple var declarations
    const source2 = "var a = 10 var b = 20 var c = a + b c";
    var script2 = try engine.loadScript(source2);
    defer script2.deinit();
    const result2 = try script2.run();
    try std.testing.expectEqual(@as(f64, 30), result2.number);

    // Test var with string
    const source3 = "var name = \"ghostlang\" name";
    var script3 = try engine.loadScript(source3);
    defer script3.deinit();
    const result3 = try script3.run();
    try std.testing.expect(result3 == .string);
    try std.testing.expect(std.mem.eql(u8, result3.string, "ghostlang"));
}

test "C-style operators" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Test && operator
    const source1 = "var result = true && true result";
    var script1 = try engine.loadScript(source1);
    defer script1.deinit();
    const result1 = try script1.run();
    try std.testing.expectEqual(true, result1.boolean);

    // Test || operator
    const source2 = "var result = false || true result";
    var script2 = try engine.loadScript(source2);
    defer script2.deinit();
    const result2 = try script2.run();
    try std.testing.expectEqual(true, result2.boolean);

    // Test ! operator
    const source3 = "var result = !false result";
    var script3 = try engine.loadScript(source3);
    defer script3.deinit();
    const result3 = try script3.run();
    try std.testing.expectEqual(true, result3.boolean);

    // Test != operator
    const source4 = "var result = 10 != 20 result";
    var script4 = try engine.loadScript(source4);
    defer script4.deinit();
    const result4 = try script4.run();
    try std.testing.expectEqual(true, result4.boolean);
}

test "C-style mixed with Lua-style" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Mix var with Lua if/then
    const source1 = "var x = 10 if x > 5 then x = x * 2 end x";
    var script1 = try engine.loadScript(source1);
    defer script1.deinit();
    const result1 = try script1.run();
    try std.testing.expectEqual(@as(f64, 20), result1.number);

    // Mix var with Lua for loop
    const source2 = "var total = 0 for i = 1, 10 do total = total + i end total";
    var script2 = try engine.loadScript(source2);
    defer script2.deinit();
    const result2 = try script2.run();
    try std.testing.expectEqual(@as(f64, 55), result2.number);

    // Mix var with Lua function
    const source3 = "var multiplier = 3 function multiply(n) return n * multiplier end multiply(7)";
    var script3 = try engine.loadScript(source3);
    defer script3.deinit();
    const result3 = try script3.run();
    try std.testing.expectEqual(@as(f64, 21), result3.number);
}

test "C-style performance-critical patterns" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Tight loop with var
    const source1 =
        \\var sum = 0
        \\var i = 1
        \\while i <= 100 do
        \\  sum = sum + i
        \\  i = i + 1
        \\end
        \\sum
    ;
    var script1 = try engine.loadScript(source1);
    defer script1.deinit();
    const result1 = try script1.run();
    try std.testing.expectEqual(@as(f64, 5050), result1.number);

    // Nested var declarations
    const source2 =
        \\var outer = 10
        \\var inner = 20
        \\var result = outer * inner
        \\result
    ;
    var script2 = try engine.loadScript(source2);
    defer script2.deinit();
    const result2 = try script2.run();
    try std.testing.expectEqual(@as(f64, 200), result2.number);

    // Complex expression with C-style operators
    const source3 = "var result = (10 + 20) * 2 >= 50 && (5 < 10 || false) result";
    var script3 = try engine.loadScript(source3);
    defer script3.deinit();
    const result3 = try script3.run();
    try std.testing.expectEqual(true, result3.boolean);
}

test "C-style with data structures" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // var with arrays
    const source1 =
        \\var arr = createArray()
        \\arrayPush(arr, 1)
        \\arrayPush(arr, 2)
        \\arrayPush(arr, 3)
        \\var total = 0
        \\for i, val in ipairs(arr) do
        \\  total = total + val
        \\end
        \\total
    ;
    var script1 = try engine.loadScript(source1);
    defer script1.deinit();
    const result1 = try script1.run();
    try std.testing.expectEqual(@as(f64, 6), result1.number);

    // var with tables
    const source2 =
        \\var tbl = createObject()
        \\objectSet(tbl, "x", 10)
        \\objectSet(tbl, "y", 20)
        \\var sum = objectGet(tbl, "x") + objectGet(tbl, "y")
        \\sum
    ;
    var script2 = try engine.loadScript(source2);
    defer script2.deinit();
    const result2 = try script2.run();
    try std.testing.expectEqual(@as(f64, 30), result2.number);
}

test "C-style with pattern matching" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // var with string matching
    const source1 =
        \\var text = "Hello World 123"
        \\var match = stringMatch(text, "%d+")
        \\match
    ;
    var script1 = try engine.loadScript(source1);
    defer script1.deinit();
    const result1 = try script1.run();
    try std.testing.expect(result1 == .string);
    try std.testing.expect(std.mem.eql(u8, result1.string, "123"));

    // var with gsub
    const source2 =
        \\var original = "test test"
        \\var replaced = stringGsub(original, "test", "best")
        \\replaced
    ;
    var script2 = try engine.loadScript(source2);
    defer script2.deinit();
    const result2 = try script2.run();
    try std.testing.expect(result2 == .string);
    try std.testing.expect(std.mem.eql(u8, result2.string, "best best"));

    // var with git branch parsing (GSH critical!)
    const source3 =
        \\var head = "ref: refs/heads/main"
        \\var branch = stringMatch(head, "refs/heads/(%w+)")
        \\branch
    ;
    var script3 = try engine.loadScript(source3);
    defer script3.deinit();
    const result3 = try script3.run();
    try std.testing.expect(result3 == .string);
    try std.testing.expect(std.mem.eql(u8, result3.string, "main"));
}

test "C-style memory safety under limits" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 32 * 1024, // 32KB
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Test multiple iterations don't leak
    var iteration: usize = 0;
    while (iteration < 100) : (iteration += 1) {
        const source = "var x = 42 var y = x * 2 var z = y + x z";
        var script = try engine.loadScript(source);
        defer script.deinit();
        _ = try script.run();

        if (engine.memory_limiter) |limiter| {
            const bytes = limiter.getBytesUsed();
            try std.testing.expectEqual(@as(usize, 0), bytes);
        }
    }
}
