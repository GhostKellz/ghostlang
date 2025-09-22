# Embedding Ghostlang

Ghostlang is designed to be easily embedded in Zig applications. This guide shows how to integrate ghostlang into your project.

## Adding as a Dependency

First, add ghostlang to your project:

```bash
zig fetch --save https://github.com/ghostkellz/ghostlang/archive/refs/heads/main.tar.gz
```

Then in your `build.zig.zon`, add to dependencies:

```zig
.dependencies = .{
    .ghostlang = .{
        .url = "https://github.com/ghostkellz/ghostlang/archive/refs/heads/main.tar.gz",
        .hash = "...", // Use the hash from zig fetch
    },
},
```

In your `build.zig`:

```zig
const ghostlang = b.dependency("ghostlang", .{});
exe.root_module.addImport("ghostlang", ghostlang.module("ghostlang"));
```

## Basic Usage

```zig
const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create engine
    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Register functions
    try engine.registerFunction("print", myPrintFunc);

    // Load and run script
    var script = try engine.loadScript("print(42)");
    defer script.deinit();
    _ = try script.run();
}

fn myPrintFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    for (args) |arg| {
        std.debug.print("{}\n", .{arg});
    }
    return .{ .nil = {} };
}
```

## Configuration

Customize the engine with `EngineConfig`:

```zig
const config = ghostlang.EngineConfig{
    .allocator = allocator,
    .memory_limit = 2 * 1024 * 1024, // 2MB
    .execution_timeout_ms = 5000,    // 5 seconds
    .allow_io = true,                // Allow file I/O
};
```

## Calling Script Functions

```zig
// Assuming script defines a function 'add'
const result = try engine.call("add", .{3, 4});
std.debug.print("3 + 4 = {}\n", .{result.number});
```

## Sandboxing

Ghostlang provides sandboxing features:

- Memory limits prevent excessive memory usage
- Execution timeouts prevent infinite loops
- I/O and syscall restrictions for security
- Deterministic mode for reproducible execution

Enable these in `EngineConfig` as needed for your use case.

## Error Handling

All ghostlang functions return errors. Handle them appropriately:

```zig
var script = engine.loadScript(source) catch |err| {
    std.debug.print("Failed to load script: {}\n", .{err});
    return err;
};
defer script.deinit();

const result = script.run() catch |err| {
    std.debug.print("Script execution failed: {}\n", .{err});
    return err;
};
```

## Performance Tips

- Reuse `ScriptEngine` instances when possible
- Use memory pools for frequent allocations
- Enable JIT when available for performance-critical code
- Profile memory usage and adjust limits accordingly