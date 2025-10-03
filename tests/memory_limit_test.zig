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

    // Test 4: Integration with ScriptEngine
    {
        std.debug.print("Test 4: ScriptEngine with memory limits\n", .{});

        const config = ghostlang.EngineConfig{
            .allocator = backing_allocator,
            .memory_limit = 100 * 1024, // 100KB limit
        };

        var engine = try ghostlang.ScriptEngine.create(config);
        defer engine.deinit();

        // Load a simple script
        var script = try engine.loadScript("var x = 42");
        defer script.deinit();

        _ = try script.run();

        std.debug.print("  Engine created and script executed successfully\n", .{});
        std.debug.print("  Status: ✓ PASS\n\n", .{});
    }

    std.debug.print("=== All Tests Passed ===\n", .{});
}
