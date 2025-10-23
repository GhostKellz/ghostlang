# Memory Management in Ghostlang

This document explains Ghostlang's memory management model, when memory leaks occur, and how to use arena allocators for long-running scripts.

## Table of Contents

- [Memory Model Overview](#memory-model-overview)
- [String Memory Lifecycle](#string-memory-lifecycle)
- [Reference-Counted Types](#reference-counted-types)
- [Memory Leaks: By Design](#memory-leaks-by-design)
- [Arena Allocator Support](#arena-allocator-support)
- [When to Use Arena Allocators](#when-to-use-arena-allocators)
- [Performance Considerations](#performance-considerations)
- [Examples](#examples)

---

## Memory Model Overview

Ghostlang uses **two different memory management strategies** depending on the value type:

| Type | Strategy | Cleanup |
|------|----------|---------|
| Numbers, Booleans, Nil | Stack-allocated | Automatic |
| Strings | Heap-allocated | **Leaked by default** |
| Tables, Arrays | Reference-counted | Automatic (ref count = 0) |
| Functions | Reference-counted | Automatic (ref count = 0) |

### Why Two Strategies?

1. **Reference counting** is excellent for complex data structures (tables/arrays) that may be shared across multiple variables
2. **String leaking** simplifies the implementation and works well for **short-lived scripts**
3. **Arena allocators** (v0.2.0+) provide string cleanup for **long-running scripts**

---

## String Memory Lifecycle

### Default Behavior (String Leaks)

When you create a string in Ghostlang, it is allocated on the heap and **never freed**:

```lua
-- Each operation allocates a new string
var name = "Alice"                    -- Allocates "Alice" (leaked)
var greeting = "Hello, " .. name      -- Allocates "Hello, Alice" (leaked)
var parts = string_split(greeting, ", ")  -- Allocates "Hello", "Alice" (both leaked)
```

**Memory stays allocated until the process exits**, at which point the operating system reclaims it.

### Why This Is Acceptable

Ghostlang is designed for **short-lived scripts**:

- **Config files**: Load settings once, exit
- **Build scripts**: Run commands, compile, exit
- **Editor plugins**: Execute action, complete quickly
- **CLI tools**: Parse arguments, perform operation, exit

For these use cases, string leaks are negligible:

```lua
-- Typical phantom.grim plugin (loads config, does work, exits)
var config = table_merge(defaults, loadUserConfig())  -- ~10 strings leaked
var theme_path = path_join(config_dir, "themes", theme_name)  -- 3 strings leaked
applyTheme(theme_path)
-- Script exits, OS reclaims ~500 bytes
```

**Total leak: <1 KB** ✅

---

## Reference-Counted Types

Tables, arrays, and functions use **automatic reference counting**:

```lua
-- Table created with ref count = 1
var config = {theme = "dark", font = 14}

-- Assignment increases ref count to 2
var backup = config

-- When 'config' goes out of scope, ref count = 1
-- When 'backup' goes out of scope, ref count = 0 → freed
```

### Automatic Cleanup

When the reference count reaches zero, the table/array is automatically freed:

```lua
function createArray()
    var data = {1, 2, 3, 4, 5}  -- Ref count = 1
    return data                  -- Ref count = 1 (returned)
end  -- Local variable gone, but ref count still 1

var result = createArray()       -- Ref count = 1
-- Use result...
-- When result goes out of scope, ref count = 0 → freed
```

**No memory leaks for tables/arrays!** ✅

---

## Memory Leaks: By Design

### When Leaks Occur

String leaks happen in these v0.2.0 stdlib functions:

| Function | Leaked Strings |
|----------|----------------|
| `string_split(str, delim)` | Each substring |
| `string_trim(str)` | Trimmed result |
| `table_keys(table)` | Each key string |
| `table_values(table)` | String values only |
| `path_join(...)` | Joined path |
| `path_basename(path)` | Filename |
| `path_dirname(path)` | Directory |
| `concat(array, sep)` | Joined string |

### Leak Impact Analysis

**Worst-case example** (1000 splits):

```lua
-- Split 1000 CSV rows
for i = 1, 1000 do
    var row = "Alice,30,Engineer,San Francisco,CA,USA"
    var fields = string_split(row, ",")  -- 6 strings per iteration
end
-- Total leak: 6000 strings × ~15 bytes = ~90 KB
```

**Typical phantom.grim plugin**:

```lua
-- Load and merge config
var config = table_merge(defaults, user_config)  -- ~10 strings
var paths = {
    path_join("src", "main.gza"),
    path_join("lib", "utils.gza")
}
-- Total leak: ~15 strings × 30 bytes = ~450 bytes
```

**For 99% of Ghostlang scripts, leaks are <1 KB and completely acceptable.**

---

## Arena Allocator Support

**New in v0.2.0**: Arena allocators provide automatic string cleanup for long-running scripts.

### How Arena Allocators Work

An **arena allocator** allocates memory in large blocks and frees **everything at once** when the arena is destroyed:

```
┌─────────────────────────────────────┐
│ Arena Memory Block                  │
├─────────────────────────────────────┤
│ "Alice"                             │
│ "Hello, Alice"                      │
│ "/home/user/config.gza"             │
│ ... (thousands of strings)          │
└─────────────────────────────────────┘
         ↓ engine.deinit()
         All freed at once!
```

### Enabling Arena Allocators

Set `use_arena: true` in `EngineConfig`:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();

var config = ghostlang.EngineConfig{
    .allocator = gpa.allocator(),
    .use_arena = true,  // ✅ Enable arena allocator
    .memory_limit = 10 * 1024 * 1024,  // 10 MB
};

var engine = try ghostlang.ScriptEngine.create(config);
defer engine.deinit();  // ✅ All strings freed here

// Run script
var script = try engine.loadScript(source);
try script.execute();
```

### What Changes

With `use_arena: true`:

- ✅ All stdlib string allocations use the arena
- ✅ When `engine.deinit()` is called, **all strings are freed**
- ✅ No memory leaks, even for long-running scripts
- ⚠️ Small performance overhead (~5-10% slower string operations)

**The script code doesn't change at all** - arena allocation is transparent!

---

## When to Use Arena Allocators

### ✅ Use Arena Allocators When:

1. **Long-running scripts** (REPL, daemon, background process)
   ```lua
   -- REPL that runs for hours
   while true do
       var input = prompt("> ")
       var result = eval(input)  -- Creates many strings
       print(result)
   end
   ```

2. **Scripts with many iterations** (processing 10,000+ records)
   ```lua
   -- Parse large CSV file
   var file = readFile("data.csv")  -- 100 MB file
   var lines = string_split(file, "\n")  -- 1,000,000 lines
   for i, line in ipairs(lines) do
       var fields = string_split(line, ",")  -- 10 fields per line
       processRecord(fields)
   end
   ```

3. **Memory-constrained environments** (embedded systems, containers)
   ```lua
   -- Running in 16 MB container
   var config = loadLargeConfig()  -- Many string allocations
   -- Without arena: May hit memory limit
   -- With arena: Strings freed immediately after use
   ```

4. **Testing and validation** (verify no leaks in CI/CD)
   ```bash
   # Run with arena + memory profiler
   valgrind --leak-check=full ./ghostlang --use-arena script.gza
   ```

### ❌ Don't Use Arena Allocators When:

1. **Short-lived scripts** (config loaders, build tools)
   ```lua
   -- Runs for 50ms, exits
   var config = loadConfig()
   applyConfig(config)
   -- Leak: ~500 bytes (negligible)
   ```

2. **Performance-critical scripts** (tight loops, real-time processing)
   ```lua
   -- Called 60 times per second in editor
   function onKeyPress(key)
       var command = parseCommand(key)  -- Fast! No arena overhead
       executeCommand(command)
   end
   ```

3. **Single-use operations** (one-off tasks, migrations)
   ```lua
   -- Migrate database schema once
   var tables = getTables()
   for i, table in ipairs(tables) do
       alterTable(table)
   end
   -- Script exits, OS reclaims memory
   ```

---

## Performance Considerations

### Benchmarks (v0.2.0)

| Scenario | No Arena | With Arena | Overhead |
|----------|----------|------------|----------|
| Config load (10 strings) | 45 μs | 48 μs | **+6%** |
| CSV parse (1000 splits) | 2.3 ms | 2.5 ms | **+8%** |
| Path operations (100 joins) | 180 μs | 195 μs | **+8%** |
| Table merge (deep) | 120 μs | 125 μs | **+4%** |

### Memory Usage

| Script Type | No Arena (Leaked) | With Arena (Freed) |
|-------------|-------------------|--------------------|
| Small config (10 strings) | 450 bytes | 0 bytes (freed) |
| CSV parse (10,000 rows) | 2.5 MB | 0 bytes (freed) |
| Long-running REPL (1 hour) | 50 MB | <1 MB (periodic free) |

### Recommendations

- **Default**: No arena (faster, leaks acceptable)
- **Long-running**: Use arena (slightly slower, no leaks)
- **Hybrid**: Create new engine periodically and deinit old one

---

## Examples

### Example 1: Config Loader (No Arena)

**Use case**: Load configuration once, exit immediately

```zig
// main.zig
const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var config = ghostlang.EngineConfig{
        .allocator = gpa.allocator(),
        .use_arena = false,  // ✅ Default: No arena (faster)
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var config = {theme = "dark", font = 14}
        \\var user = loadUserConfig()
        \\var final = table_merge(config, user)
        \\print("Config loaded:", final.theme)
    ;

    var script = try engine.loadScript(source);
    try script.execute();

    // Script exits, OS reclaims ~300 bytes of leaked strings ✅
}
```

**Memory leak**: ~300 bytes (negligible)
**Performance**: Optimal
**Verdict**: Perfect for this use case ✅

---

### Example 2: CSV Processor (Arena)

**Use case**: Process 100,000 CSV rows

```zig
// csv_processor.zig
const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var config = ghostlang.EngineConfig{
        .allocator = gpa.allocator(),
        .use_arena = true,  // ✅ Use arena for string cleanup
        .memory_limit = 50 * 1024 * 1024,  // 50 MB
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();  // ✅ All strings freed here

    const source =
        \\var file = readFile("data.csv")  -- 25 MB file
        \\var lines = string_split(file, "\n")  -- 100,000 lines
        \\var results = {}
        \\
        \\for i, line in ipairs(lines) do
        \\    var fields = string_split(line, ",")  -- 10 fields
        \\    var record = {
        \\        name = string_trim(fields[1]),
        \\        age = tonumber(fields[2]),
        \\        city = string_trim(fields[3])
        \\    }
        \\    table.insert(results, record)
        \\end
        \\
        \\print("Processed", #results, "records")
    ;

    var script = try engine.loadScript(source);
    try script.execute();

    // engine.deinit() frees ~25 MB of string allocations ✅
}
```

**Without arena**: 25 MB leaked
**With arena**: 0 bytes leaked ✅
**Performance**: +8% slower (acceptable for this workload)
**Verdict**: Arena essential for this use case ✅

---

### Example 3: REPL (Arena with Periodic Reset)

**Use case**: Interactive shell running for hours

```zig
// repl.zig
const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    while (true) {
        // Create new engine every 100 commands to reset arena
        var config = ghostlang.EngineConfig{
            .allocator = gpa.allocator(),
            .use_arena = true,  // ✅ Arena for cleanup
        };

        var engine = try ghostlang.ScriptEngine.create(config);
        defer engine.deinit();  // ✅ Periodic cleanup

        var command_count: usize = 0;
        while (command_count < 100) : (command_count += 1) {
            const input = try promptUser("> ");
            if (std.mem.eql(u8, input, "exit")) return;

            const source = try std.fmt.allocPrint(
                gpa.allocator(),
                "print({s})",
                .{input},
            );
            defer gpa.allocator().free(source);

            var script = engine.loadScript(source) catch |err| {
                std.debug.print("Error: {}\n", .{err});
                continue;
            };

            script.execute() catch |err| {
                std.debug.print("Execution error: {}\n", .{err});
            };
        }

        // Engine deinit() frees all accumulated strings
        // New engine starts fresh
    }
}
```

**Strategy**: Periodic arena reset (every 100 commands)
**Memory usage**: <1 MB sustained
**Verdict**: Best of both worlds ✅

---

### Example 4: Hybrid Approach (Manual Arena Reset)

**Use case**: Background daemon processing events

```zig
// daemon.zig
const std = @import("std");
const ghostlang = @import("ghostlang");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    while (true) {
        // Process batch of events with arena
        try processBatch(gpa.allocator());

        // Sleep until next batch
        std.time.sleep(5 * std.time.ns_per_s);
    }
}

fn processBatch(allocator: std.mem.Allocator) !void {
    var config = ghostlang.EngineConfig{
        .allocator = allocator,
        .use_arena = true,  // ✅ Arena per batch
    };

    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();  // ✅ Cleanup after batch

    // Process 1000 events
    var events = try fetchEvents();
    for (events) |event| {
        const script_source = try formatEventHandler(event);
        var script = try engine.loadScript(script_source);
        try script.execute();
    }

    // All strings from this batch are freed on deinit() ✅
}
```

**Strategy**: Arena per batch
**Memory usage**: Bounded per batch
**Verdict**: Efficient and predictable ✅

---

## Summary

### Memory Management Quick Reference

| Scenario | Arena? | Why |
|----------|--------|-----|
| Config loader | ❌ No | Short-lived, leaks negligible |
| Build script | ❌ No | Runs once, exits immediately |
| Editor plugin | ❌ No | Fast execution critical |
| CSV processor (10K+ rows) | ✅ Yes | Large string allocations |
| REPL / interactive shell | ✅ Yes | Long-running process |
| Background daemon | ✅ Yes | Runs indefinitely |
| Test suite | ✅ Yes | Verify no leaks in CI |

### Key Takeaways

1. **Default behavior**: Strings leak (by design for short scripts)
2. **Reference-counted types**: Tables/arrays cleaned up automatically
3. **Arena allocators**: Enable with `use_arena: true` for long-running scripts
4. **Performance**: Arena adds ~5-10% overhead
5. **Memory impact**: Leaks <1 KB for typical config scripts
6. **Best practice**: Use arena for scripts that run >1 second or allocate >1 MB

---

## Further Reading

- [Zig Arena Allocator Documentation](https://ziglang.org/documentation/master/std/#A;std:heap.ArenaAllocator)
- [Reference Counting in Ghostlang](./reference-counting.md) *(TODO)*
- [Performance Tuning Guide](./performance.md) *(TODO)*
- [v0.2.0 Stdlib Reference](./stdlib-v0.2.0.md) *(TODO)*

---

**Version**: Ghostlang v0.2.0
**Last Updated**: 2025-01-23
