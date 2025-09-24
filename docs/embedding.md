# Embedding Ghostlang

Ghostlang is built first and foremost as an embeddable scripting engine for Zig applications. The runtime is still early, but the public API is already stable enough for experiments. This guide shows the minimal wiring required to run scripts and exchange data with host functions.

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

`EngineConfig` currently exposes future-facing knobs (memory limits, execution timeouts, capability flags). In the current build only the allocator is honoured; limit enforcement is on the roadmap. You can still set the fields today to document intent:

```zig
const config = ghostlang.EngineConfig{
    .allocator = allocator,
    .memory_limit = 2 * 1024 * 1024, // TODO: enforcement
    .execution_timeout_ms = 1000,     // TODO: enforcement
    .allow_io = false,                // TODO: enforcement
};
```

## Calling Script Functions

`ScriptEngine.call` is stubbed while we bring the parser and VM up to parity. For the moment, treat Zig → script calls as a planned feature. The recommended pattern is to load scripts that return a value or mutate shared globals, then read those globals via `Script.getGlobal`.

```zig
var script = try engine.loadScript("var total = sum(1, 2, 3); total");
defer script.deinit();
const result = try script.run();
if (result == .number) {
    std.debug.print("total = {}\n", .{result.number});
}
```

Once the function-call surface lands, this section will be expanded with concrete examples.

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

## What’s Next

- Enforce `EngineConfig` limits and capabilities
- Finish `ScriptEngine.call`
- Add deep-copy semantics for tables/strings when crossing the boundary
- Publish a standard library surface for host ↔ script data exchange

Track `ROADMAP.md` for the latest status on these tasks.