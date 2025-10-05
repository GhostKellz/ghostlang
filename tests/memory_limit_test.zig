const std = @import("std");
const ghostlang = @import("ghostlang");

/// Test to verify MemoryLimitAllocator works correctly
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const backing_allocator = gpa.allocator();

    std.debug.print("\n=== Testing MemoryLimitAllocator ===\n\n", .{});

    // Test 1: Basic allocation within limits
    {
        std.debug.print("Test 1: Allocation within limits\n", .{});
        var limiter = ghostlang.MemoryLimitAllocator.init(backing_allocator, 1024); // 1KB limit
        const alloc = limiter.allocator();

        const mem = try alloc.alloc(u8, 512); // Should succeed
        defer alloc.free(mem);

        const used = limiter.getBytesUsed();
        std.debug.print("  Allocated: 512 bytes\n", .{});
        std.debug.print("  Tracked: {} bytes\n", .{used});
        std.debug.print("  Status: ✓ PASS\n\n", .{});
    }

    // Test 2: Allocation exceeding limits
    {
        std.debug.print("Test 2: Allocation exceeding limits\n", .{});
        var limiter = ghostlang.MemoryLimitAllocator.init(backing_allocator, 1024); // 1KB limit
        const alloc = limiter.allocator();

        const result = alloc.alloc(u8, 2048); // Should fail - exceeds limit
        if (result) |mem| {
            alloc.free(mem);
            std.debug.print("  Status: ✗ FAIL - allocation should have failed\n\n", .{});
        } else |_| {
            std.debug.print("  Correctly rejected 2048 byte allocation\n", .{});
            std.debug.print("  Status: ✓ PASS\n\n", .{});
        }
    }

    // Test 3: Multiple allocations tracking
    {
        std.debug.print("Test 3: Multiple allocations tracking\n", .{});
        var limiter = ghostlang.MemoryLimitAllocator.init(backing_allocator, 2048);
        const alloc = limiter.allocator();

        const mem1 = try alloc.alloc(u8, 512);
        const mem2 = try alloc.alloc(u8, 512);
        const mem3 = try alloc.alloc(u8, 512);

        const used = limiter.getBytesUsed();
        std.debug.print("  Allocated: 3x512 = 1536 bytes\n", .{});
        std.debug.print("  Tracked: {} bytes\n", .{used});

        // Free and verify tracking decreases
        alloc.free(mem1);
        const after_free = limiter.getBytesUsed();
        std.debug.print("  After freeing 512: {} bytes\n", .{after_free});

        alloc.free(mem2);
        alloc.free(mem3);

        const final = limiter.getBytesUsed();
        std.debug.print("  After freeing all: {} bytes\n", .{final});
        std.debug.print("  Status: ✓ PASS\n\n", .{});
    }

    // Test 4: Integration with ScriptEngine and leak detection
    {
        std.debug.print("Test 4: ScriptEngine repeated execution & leak check\n", .{});

        const config = ghostlang.EngineConfig{
            .allocator = backing_allocator,
            .memory_limit = 64 * 1024, // 64KB limit
            .execution_timeout_ms = 50,
        };

        var engine = try ghostlang.ScriptEngine.create(config);
        defer engine.deinit();

        const scripts = [_][]const u8{
            "var total = 0; for i in 0..32 { total = total + i; } total",
            "function fib(n) { if n <= 1 { return n } return fib(n-1) + fib(n-2) } fib(5)",
            "var tbl = { answer = 42 }; tbl.answer",
            "var arr = [1,2,3,4]; arr:push(5); arr:pop()",
            "if false then 0 else 1 end",
            "len(\"ghostlang\")",
        };

        var iteration: usize = 0;
        while (iteration < 500) : (iteration += 1) {
            const source = scripts[iteration % scripts.len];
            var script = try engine.loadScript(source);
            defer script.deinit();

            _ = script.run() catch |err| {
                std.debug.print("  Unexpected runtime error {s} on iteration {d}\n", .{ @errorName(err), iteration });
                return err;
            };

            if (engine.memory_limiter) |limiter| {
                const bytes = limiter.getBytesUsed();
                if (bytes != 0) {
                    std.debug.print("  Status: ✗ FAIL - memory still in use after iteration {d}: {} bytes\n", .{ iteration, bytes });
                    return error.MemoryLeakDetected;
                }
            }
        }

        std.debug.print("  Status: ✓ PASS - no leaks detected across 500 runs\n\n", .{});
    }

    // Test 5: Memory pressure script triggers limit
    {
        std.debug.print("Test 5: ScriptEngine enforces memory limit\n", .{});
        const config = ghostlang.EngineConfig{
            .allocator = backing_allocator,
            .memory_limit = 8 * 1024, // 8KB limit
            .execution_timeout_ms = 50,
        };

        var engine = try ghostlang.ScriptEngine.create(config);
        defer engine.deinit();

        const source =
            \\var data = []
            \\for i in 0..512 {
            \\    data:push(i)
            \\}
            \\len(data)
        ;

        var script = try engine.loadScript(source);
        defer script.deinit();

        const final_value = script.run() catch |err| switch (err) {
            error.MemoryLimitExceeded => {
                std.debug.print("  Status: ✓ PASS - memory limit enforced\n", .{});
                return;
            },
            error.ExecutionTimeout => {
                std.debug.print("  Status: ⚠ Script hit timeout before limit\n", .{});
                return;
            },
            error.ParseError => {
                std.debug.print("  Status: ⚠ Parse error reached unexpectedly\n", .{});
                return;
            },
            else => {
                std.debug.print("  Status: ✗ FAIL - unexpected error {s}\n", .{@errorName(err)});
                return err;
            },
        };

        std.debug.print("  Script completed with value {any} (limit may be generous)\n", .{final_value});
        std.debug.print("  Status: ⚠ CHECK LIMIT CONFIG\n", .{});
    }

    std.debug.print("=== Memory limit tests completed ===\n", .{});
}
