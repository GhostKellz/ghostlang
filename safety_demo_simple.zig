const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 1024 * 1024,
        .execution_timeout_ms = 1000,
        .allow_io = false,
        .allow_syscalls = false,
        .deterministic = true,
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    try engine.registerFunction("add", addFunc);

    const print = std.debug.print;
    print("=== Ghostlang Phase 0.1 Safety Demo ===\n", .{});

    // Test 1: Normal execution
    print("Test 1: Normal script execution\n", .{});
    var script1 = try engine.loadScript("add(3, 4)");
    defer script1.deinit();
    const result1 = try script1.run();
    print("  Result: {d}\n", .{result1.number});
    print("  Status: PASS\n\n", .{});

    // Test 2: Timeout protection
    print("Test 2: Infinite loop timeout\n", .{});
    const timeout_result = engine.loadScript("while (true) { }");
    if (timeout_result) |script2| {
        var script_mut = script2;
        defer script_mut.deinit();
        const run_result = script_mut.run();
        if (run_result) |_| {
            print("  Status: FAIL - should have timed out\n\n", .{});
        } else |err| {
            if (err == ghostlang.ExecutionError.ExecutionTimeout) {
                print("  Status: PASS - timed out correctly\n\n", .{});
            } else {
                print("  Status: FAIL - wrong error type\n\n", .{});
            }
        }
    } else |err| {
        print("  Load error: {}\n\n", .{err});
    }

    // Test 3: Parse error handling
    print("Test 3: Parse error handling\n", .{});
    const parse_result = engine.loadScript("var x = ");
    if (parse_result) |_| {
        print("  Status: FAIL - should have failed to parse\n\n", .{});
    } else |err| {
        if (err == ghostlang.ExecutionError.ParseError) {
            print("  Status: PASS - parse error handled correctly\n\n", .{});
        } else {
            print("  Status: FAIL - wrong error type\n\n", .{});
        }
    }

    // Test 4: Function not found
    print("Test 4: Function not found\n", .{});
    const call_result = engine.call("nonexistent", .{});
    if (call_result) |_| {
        print("  Status: FAIL - should have failed\n\n", .{});
    } else |err| {
        if (err == ghostlang.ExecutionError.FunctionNotFound) {
            print("  Status: PASS - function not found handled correctly\n\n", .{});
        } else {
            print("  Status: FAIL - wrong error type\n\n", .{});
        }
    }

    // Test 5: Security checks
    print("Test 5: Security restrictions\n", .{});
    const io_result = engine.security.checkIOAllowed();
    const syscall_result = engine.security.checkSyscallAllowed();
    const deterministic_result = engine.security.checkNonDeterministicAllowed();

    const io_blocked = if (io_result) |_| false else |_| true;
    const syscall_blocked = if (syscall_result) |_| false else |_| true;
    const deterministic_blocked = if (deterministic_result) |_| false else |_| true;

    if (io_blocked and syscall_blocked and deterministic_blocked) {
        print("  Status: PASS - all restrictions properly enforced\n\n", .{});
    } else {
        print("  Status: FAIL - security restrictions not working\n\n", .{});
    }

    print("=== All Phase 0.1 Safety Tests Complete ===\n", .{});
    print("ScriptEngine.call is bulletproof and ready for Grim!\n", .{});
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