# ghostlang

<p align="center">
  <img src="assets/icons/glang-proto.png" alt="ghostlang logo" width="200"/>
</p>

[![Built with Zig](https://img.shields.io/badge/built%20with-Zig-orange)](https://ziglang.org/)
[![Zig Version](https://img.shields.io/badge/zig-0.16.0--dev-orange)](https://ziglang.org/download/)

A lightweight embedded scripting engine written in Zig, designed as a modern replacement for Lua. It provides Lua-like syntax with JavaScript compatibility, sandboxing, foreign function interface, and optional JIT compilation.

## Features

- **Embedded Scripting**: Perfect for configuration, automation, plugins, and game scripting
- **Lightweight VM**: Register-based virtual machine with small constant footprint
- **FFI**: Bidirectional calls between Zig and scripts (zero-copy where possible)
- **Sandboxing**: Memory limits, execution timeouts, API restrictions, and deterministic mode
- **Language Support**: Lua-like syntax with JavaScript compatibility
- **JIT Ready**: Optional runtime optimization for hot paths
- **Debugging**: Breakpoints, stack traces, and variable inspection

## Quick Start

### Adding as a Dependency

```bash
zig fetch --save https://github.com/ghostkellz/ghostlang/archive/refs/heads/main.tar.gz
```

### Example Usage

```zig
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

    // Register a Zig function
    try engine.registerFunction("print", printFunc);

    // Load and run a script
    var script = try engine.loadScript("3 + 4");
    defer script.deinit();
    const result = try script.run();
    std.debug.print("Result: {}\n", .{result.number});
}

fn printFunc(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    for (args) |arg| {
        std.debug.print("{}\n", .{arg});
    }
    return args[0];
}
```

## Building

```bash
zig build
./zig-out/bin/ghostlang
```

## File Extension

Scripts use the `.gza` extension (ghostlang zig assembly).
