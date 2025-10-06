const std = @import("std");
const ghostlang = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Test 1: Wrong syntax (what Grim is using)
    std.debug.print("\n=== Test 1: Wrong Syntax (Grim's code) ===\n", .{});
    const wrong_script =
        \\const message = "Plugin loaded"
        \\
        \\fn setup() {
        \\    print(message)
        \\}
    ;

    var script1 = engine.loadScript(wrong_script) catch |err| {
        std.debug.print("ERROR: {}\n", .{err});
        std.debug.print("This is the error Grim is seeing!\n\n", .{});

        // Test 2: Correct syntax
        std.debug.print("=== Test 2: Correct Syntax ===\n", .{});
        const correct_script =
            \\local message = "Plugin loaded"
            \\
            \\function setup()
            \\    print(message)
            \\end
        ;

        var script2 = engine.loadScript(correct_script) catch |err2| {
            std.debug.print("ERROR: {}\n", .{err2});
            return;
        };
        defer script2.deinit();

        std.debug.print("✓ Script loaded successfully!\n", .{});
        const result = try script2.run();
        std.debug.print("Result: {}\n", .{result});
        return;
    };
    defer script1.deinit();
}
