# ghostlang

<p align="center">
  <img src="assets/icons/glang-proto.png" alt="ghostlang logo" width="200"/>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Zig-F7A41D?style=for-the-badge&logo=zig&logoColor=white" alt="Zig">
  <img src="https://img.shields.io/badge/Tree--sitter-6EBF8B?style=for-the-badge&logo=treesitter&logoColor=white" alt="Tree-sitter">
  <img src="https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS">
  <img src="https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows">
</p>

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

### Running Scripts

After building, execute Ghostlang scripts directly from the CLI:

```bash
./zig-out/bin/ghostlang path/to/script.gla
```

### Example Plugin Script

Create `plugin.gla`:

```ghostlang
-- Simple Ghostlang plugin
var tracker = { count = 0 }

function setup()
    print("ghostlang plugin activated")
end

function on_command(name)
    tracker.count = tracker.count + 1
    print("command:", name, "invocations:", tracker.count)
end

setup()
on_command("demo")
```

Run it with the CLI:

```bash
./zig-out/bin/ghostlang plugin.gla
```

## File Extension

Scripts use the `.gla` extension.

## QA & Security Testing

### Security audit toggles

The security audit suite (`security/sandbox_audit.zig`) is the canonical checklist for verifying gShell and plugin sandboxes. Each test now exercises **both** sides of the security context so regressions are caught immediately.

- Run the suite with `zig build security`.
- Every scenario configures a **restricted** engine (`allow_io = false`, `allow_syscalls = false`, `deterministic = true`) and a **permissive** engine where the same capability is explicitly allowed.
- When adding new host integrations (filesystem, networking, timers, etc.), extend the audit to assert the correct `ExecutionError` is raised in restricted mode and that the action succeeds when permitted.
- Keep scripts lightweight—the audit is designed to fail fast and give actionable output while gating gShell deployments.

For broader QA coverage see:

- `zig build test-integration` – end-to-end plugin flows exercised the way gShell loads multiple extensions.
- `zig build test-plugins` – scenario library for editor ergonomics.
- `zig build bench` / `zig build profile` – performance tracking, including the VM profiler reports enriched for error-path visibility.
