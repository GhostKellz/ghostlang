# ghostlang

<p align="center">
  <img src="assets/icons/glang-proto.png" alt="ghostlang logo" width="200"/>
</p>

[![CI/CD](https://github.com/GhostKellz/ghostlang/actions/workflows/main.yml/badge.svg)](https://github.com/GhostKellz/ghostlang/actions/workflows/main.yml)
[![Built with Zig](https://img.shields.io/badge/built%20with-Zig-F7A41D?logo=zig&logoColor=white)](https://ziglang.org/)
[![Version](https://img.shields.io/badge/version-0.16.0--dev-orange)](https://github.com/GhostKellz/ghostlang/releases)
[![Tree-sitter](https://img.shields.io/badge/tree--sitter-grammar-green?logo=tree-sitter&logoColor=white)](https://tree-sitter.github.io/)
[![Cross Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)](https://github.com/GhostKellz/ghostlang)
[![Documentation](https://img.shields.io/badge/docs-available-brightgreen)](https://github.com/GhostKellz/ghostlang/tree/main/docs)

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
