# Integrating zdoc into GhostLang

**zdoc** generates beautiful documentation for your Lua clone! This guide shows how to integrate it.

## 🚀 Quick Start

### 1. Add zdoc as a dependency

```bash
zig fetch --save https://github.com/GhostKellz/zdoc/archive/refs/tags/v0.1.0.tar.gz
```

Or use the latest main branch:
```bash
zig fetch --save https://github.com/GhostKellz/zdoc/archive/refs/heads/main.tar.gz
```

### 2. Update build.zig

Add zdoc to your build.zig:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ... your existing build configuration ...

    // Add zdoc integration
    const zdoc_dep = b.dependency("zdoc", .{
        .target = target,
        .optimize = optimize,
    });

    const zdoc_exe = zdoc_dep.artifact("zdoc");

    // Create docs generation step
    const docs_step = b.step("docs", "Generate API documentation");

    const run_zdoc = b.addRunArtifact(zdoc_exe);
    run_zdoc.addArgs(&.{
        "--format=html",
        "src/root.zig",
        "src/main.zig",
        "src/pattern.zig",
        "docs/",
    });

    docs_step.dependOn(&run_zdoc.step);
}
```

### 3. Generate Documentation

```bash
zig build docs
```

This generates:
- `docs/index.html` - Module hierarchy
- `docs/[module]/index.html` - API documentation
- `docs/[module]/search_index.json` - Symbol indexes

## 📁 Generated Documentation Structure

```
docs/
├── index.html                    # Language overview
├── root/
│   ├── index.html                # Core VM documentation
│   └── search_index.json
├── main/
│   ├── index.html                # Entry point
│   └── search_index.json
└── pattern/
    ├── index.html                # Pattern matching
    └── search_index.json
```

## 🎨 Perfect for Programming Languages

### Documenting VM Internals
- ✅ **Bytecode Instructions**: Document each opcode
- ✅ **Stack Operations**: Clear parameter/return documentation
- ✅ **Memory Management**: GC algorithms explained
- ✅ **Type System**: Type checking and coercion
- ✅ **Error Handling**: VM error propagation

### Language Features
- ✅ **Pattern Matching**: Your Lua enhancements
- ✅ **Standard Library**: All built-in functions
- ✅ **FFI**: Foreign function interface
- ✅ **Metaprogramming**: Metatable operations

### GitHub Integration
Source links to your implementation:
```
https://github.com/GhostKellz/ghostlang/blob/main/src/pattern.zig#L42
```

## 📝 Documenting Language Features

### VM Operations

```zig
/// Execute a bytecode instruction
///
/// Dispatches to the appropriate handler based on opcode.
/// Updates the instruction pointer and manages the stack.
///
/// @param vm Virtual machine instance
/// @param instruction Bytecode instruction to execute
/// @return Execution result or error
/// @error StackOverflow if stack limit exceeded
/// @error TypeError if operand types are incompatible
/// @error RuntimeError for other runtime failures
pub fn execute(vm: *VM, instruction: Instruction) !void {
    // ...
}
```

### Pattern Matching

```zig
/// Match a value against a pattern
///
/// Implements Lua-style pattern matching with GhostLang extensions.
/// Supports:
/// - Wildcard patterns (_)
/// - Type patterns (number, string, table)
/// - Structural destructuring
/// - Guard clauses
///
/// @param pattern Pattern to match against
/// @param value Value to test
/// @return Match result with captured bindings
/// @error PatternError if pattern is invalid
///
/// ## Example
/// ```lua
/// match value with
///   | { x, y } -> print(x + y)
///   | n when n > 10 -> print("big")
///   | _ -> print("default")
/// end
/// ```
pub fn matchPattern(pattern: Pattern, value: Value) !MatchResult {
    // ...
}
```

### Standard Library

```zig
/// GhostLang string library
///
/// Provides string manipulation functions compatible with Lua,
/// plus GhostLang-specific extensions.
///
/// ## Functions
/// - `string.len(s)` - Get string length
/// - `string.sub(s, i, j)` - Extract substring
/// - `string.match(s, pattern)` - Pattern matching
/// - `string.gsub(s, pattern, repl)` - Global substitution
pub const string_lib = struct {
    // ...
};
```

## 🔧 Advanced Configuration

### Document Compiler Pipeline

```zig
run_zdoc.addArgs(&.{
    "--format=html",
    "src/lexer.zig",
    "src/parser.zig",
    "src/compiler.zig",
    "src/codegen.zig",
    "src/vm.zig",
    "docs/compiler/",
});
```

### Document Standard Library

```zig
run_zdoc.addArgs(&.{
    "--format=html",
    "src/lib/string.zig",
    "src/lib/table.zig",
    "src/lib/math.zig",
    "src/lib/io.zig",
    "docs/stdlib/",
});
```

### Multiple Formats

```zig
// HTML for web viewing
const html_docs = b.addRunArtifact(zdoc_exe);
html_docs.addArgs(&.{ "--format=html", "src/*.zig", "docs/html/" });

// JSON for language server integration
const json_docs = b.addRunArtifact(zdoc_exe);
json_docs.addArgs(&.{ "--format=json", "src/*.zig", "docs/api/" });

docs_step.dependOn(&html_docs.step);
docs_step.dependOn(&json_docs.step);
```

## 📚 Language-Specific Tips

### Document Bytecode Format

```zig
/// Bytecode instruction format
///
/// Instructions are 4 bytes:
/// ```
/// | opcode (1 byte) | arg1 (1 byte) | arg2 (2 bytes) |
/// ```
///
/// Opcodes:
/// - 0x00: MOVE - Move value between registers
/// - 0x01: LOADK - Load constant
/// - 0x02: ADD - Addition
/// - ... (full opcode list)
pub const Instruction = packed struct {
    opcode: u8,
    arg1: u8,
    arg2: u16,
};
```

### Document Type System

```zig
/// GhostLang value types
///
/// Supports all Lua types plus GhostLang extensions.
pub const ValueType = enum {
    nil,        // Nil value
    boolean,    // True/false
    number,     // 64-bit float
    string,     // UTF-8 string
    table,      // Associative array
    function,   // Function closure
    userdata,   // Foreign data
    thread,     // Coroutine
    // GhostLang extensions:
    pattern,    // Pattern for matching
    symbol,     // Interned symbol
};
```

### Document Garbage Collector

```zig
/// Mark-and-sweep garbage collector
///
/// Implements tri-color marking for incremental collection.
/// Supports weak references and finalizers.
///
/// @param gc GC instance
/// @return Number of bytes freed
pub fn collectGarbage(gc: *GC) !usize {
    // ...
}
```

## 🌐 Integration with Language Docs

Link API docs with language documentation:

```
docs/
├── index.html              # Generated: API overview
├── root/index.html         # Generated: VM internals
├── pattern/index.html      # Generated: Pattern matching API
└── api-cookbook.md         # Existing: Language tutorial
```

## 🎯 For GhostLang Specifically

### VM Documentation
- Execution model
- Stack layout
- Calling convention
- Error propagation

### Compiler Documentation
- Lexical analysis
- Parsing algorithm
- Code generation
- Optimization passes

### Standard Library
- All built-in functions
- Module system
- Package management
- FFI bindings

### Pattern Matching
- Pattern syntax
- Match semantics
- Compilation strategy
- Performance characteristics

## 📖 Viewing Documentation

### Local Preview

```bash
zig build docs
cd docs
python -m http.server
# Open http://localhost:8000
```

### Deploy to GitHub Pages

```yaml
- name: Generate Documentation
  run: zig build docs

- name: Deploy
  uses: peaceiris/actions-gh-pages@v3
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./docs
```

## 🔗 Resources

- **zdoc Repository**: https://github.com/GhostKellz/zdoc
- **GhostLang Repository**: Your repo URL
- **Generated Docs**: `docs/index.html`
- **Language Docs**: `docs/api-cookbook.md`

---

**Your Lua clone now has beautiful API documentation!** 🎉 Perfect for contributors and VM hackers!
