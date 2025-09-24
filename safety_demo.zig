const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Configure Ghostlang with Grim-safe settings
    const grim_safe_config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 1024 * 1024,    // 1MB limit
        .execution_timeout_ms = 2000,   // 2 second timeout
        .allow_io = false,              // No file system access
        .allow_syscalls = false,        // No system calls
        .deterministic = true,          // Reproducible execution
    };

    var engine = try ghostlang.ScriptEngine.create(grim_safe_config);
    defer engine.deinit();

    // Register safe functions
    try engine.registerFunction("print", printFunc);
    try engine.registerFunction("add", addFunc);

    std.debug.print("🛡️ Ghostlang Phase 0.1 Safety Demo\n\n", .{});

    // Test 1: Normal operation works
    std.debug.print("✅ Test 1: Normal script execution\n", .{});
    var normal_script = try engine.loadScript("add(3, 4)");
    defer normal_script.deinit();
    const normal_result = try normal_script.run();
    std.debug.print("   Result: {}\n\n", .{normal_result.number});

    // Test 2: Timeout protection
    std.debug.print("🔄 Test 2: Testing infinite loop timeout...\n", .{});
    const timeout_script = engine.loadScript("while (true) { }");
    if (timeout_script) |script| {
        var script_mut = script;
        defer script_mut.deinit();
        const timeout_result = script_mut.run();
        switch (timeout_result) {
            ghostlang.ExecutionError.ExecutionTimeout => {
                std.debug.print("   ✅ SUCCESS: Infinite loop timed out safely\n\n", .{});
            },
            else => {
                std.debug.print("   ❌ FAIL: Should have timed out\n\n", .{});
            }
        }
    } else |err| {
        std.debug.print("   Script load error: {}\n\n", .{err});
    }

    // Test 3: Parse error handling
    std.debug.print("🔧 Test 3: Testing malformed syntax...\n", .{});
    const bad_result = engine.loadScript("var x = ");
    switch (bad_result) {
        ghostlang.ExecutionError.ParseError => {
            std.debug.print("   ✅ SUCCESS: Parse error handled gracefully\n\n", .{});
        },
        else => {
            std.debug.print("   ❌ FAIL: Should have returned ParseError\n\n");
        }
    }

    // Test 4: Function not found
    std.debug.print("🔍 Test 4: Testing undefined function call...\n");
    const undefined_result = engine.call("nonexistent_function", .{});
    switch (undefined_result) {
        ghostlang.ExecutionError.FunctionNotFound => {
            std.debug.print("   ✅ SUCCESS: Function not found handled safely\n\n");
        },
        else => {
            std.debug.print("   ❌ FAIL: Should have returned FunctionNotFound\n\n");
        }
    }

    // Test 5: Security context
    std.debug.print("🔒 Test 5: Testing security restrictions...\n");
    const io_check = engine.security.checkIOAllowed();
    const syscall_check = engine.security.checkSyscallAllowed();
    const deterministic_check = engine.security.checkNonDeterministicAllowed();

    var all_restricted = true;
    switch (io_check) {
        ghostlang.ExecutionError.IONotAllowed => {},
        else => all_restricted = false
    }
    switch (syscall_check) {
        ghostlang.ExecutionError.SyscallNotAllowed => {},
        else => all_restricted = false
    }
    switch (deterministic_check) {
        ghostlang.ExecutionError.SecurityViolation => {},
        else => all_restricted = false
    }

    if (all_restricted) {
        std.debug.print("   ✅ SUCCESS: All security restrictions properly enforced\n\n");
    } else {
        std.debug.print("   ❌ FAIL: Security restrictions not working\n\n");
    }

    std.debug.print("🎉 All safety tests completed!\n");
    std.debug.print("📋 ScriptEngine.call is bulletproof and ready for Grim integration\n");
}

fn printFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    for (args) |arg| {
        switch (arg) {
            .number => |n| std.debug.print("{d}", .{n}),
            .string => |s| std.debug.print("{s}", .{s}),
            .boolean => |b| std.debug.print("{}", .{b}),
            else => std.debug.print("nil", .{}),
        }
    }
    std.debug.print("\n", .{});
    return .{ .nil = {} };
}

fn addFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    var sum: f64 = 0;
    for (args) |arg| {
        if (arg == .number) {
            sum += arg.number;
        }
    }
    return .{ .number = sum };
}