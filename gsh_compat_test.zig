const std = @import("std");
const ghostlang = @import("src/root.zig");

test "GSH: if/then/else statements" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var x = 10
        \\var result = ""
        \\if x > 5 then
        \\    result = "greater"
        \\else
        \\    result = "less"
        \\end
        \\result
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expectEqualStrings("greater", result.string);
}

test "GSH: logical operators (and, or, not)" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var a = true
        \\var b = false
        \\var and_result = a and b
        \\var or_result = a or b
        \\var not_result = not b
        \\and_result
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expect(result.boolean == false);
}

test "GSH: while loops" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var sum = 0
        \\var i = 1
        \\while i <= 5 do
        \\    sum = sum + i
        \\    i = i + 1
        \\end
        \\sum
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expectEqual(@as(f64, 15), result.number);
}

test "GSH: numeric for loops" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var sum = 0
        \\for i = 1, 5 do
        \\    sum = sum + i
        \\end
        \\sum
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expectEqual(@as(f64, 15), result.number);
}

test "GSH: for loop with step" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var sum = 0
        \\for i = 0, 10, 2 do
        \\    sum = sum + i
        \\end
        \\sum
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expectEqual(@as(f64, 30), result.number); // 0+2+4+6+8+10
}

test "GSH: function definitions and calls" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\function add(a, b)
        \\    return a + b
        \\end
        \\var result = add(3, 7)
        \\result
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expectEqual(@as(f64, 10), result.number);
}

test "GSH: function with early return" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\function check(n)
        \\    if n <= 0 then
        \\        return false
        \\    end
        \\    return true
        \\end
        \\check(-5)
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expect(result.boolean == false);
}

test "GSH: multiple return values" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\function get_pair()
        \\    return 42, 84
        \\end
        \\var a, b = get_pair()
        \\a + b
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expectEqual(@as(f64, 126), result.number);
}

test "GSH: elseif chains" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var score = 85
        \\var grade = ""
        \\if score >= 90 then
        \\    grade = "A"
        \\elseif score >= 80 then
        \\    grade = "B"
        \\elseif score >= 70 then
        \\    grade = "C"
        \\else
        \\    grade = "F"
        \\end
        \\grade
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expectEqualStrings("B", result.string);
}

test "GSH: string concatenation" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var user = "ghost"
        \\var host = "linux"
        \\user .. "@" .. host
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expectEqualStrings("ghost@linux", result.string);
}

test "GSH: comparison operators in conditions" {
    const allocator = std.testing.allocator;

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const script =
        \\var x = 10
        \\var result = 0
        \\if x >= 10 then result = 1 end
        \\if x <= 10 then result = result + 1 end
        \\if x == 10 then result = result + 1 end
        \\result
    ;

    var loaded = try engine.loadScript(script);
    defer loaded.deinit();
    const result = try loaded.run();

    try std.testing.expectEqual(@as(f64, 3), result.number);
}
