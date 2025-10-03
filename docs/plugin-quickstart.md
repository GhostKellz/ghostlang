# Plugin Developer Quick Start

**Get started building Grim editor plugins with Ghostlang in 30 minutes**

## What is Ghostlang?

Ghostlang is a lightweight scripting language designed specifically for editor plugins. It provides:
- **Safety**: Memory limits, execution timeouts, sandboxing
- **Speed**: Sub-microsecond plugin loading, minimal overhead
- **Simplicity**: Lua-like syntax, easy to learn
- **Security**: Three-tier security model (trusted/normal/sandboxed)

## Your First Plugin (5 minutes)

###  Step 1: Create Plugin File

Create `hello.gza`:

```ghostlang
// My first plugin
var greeting = "Hello from Ghostlang!"
greeting
```

### Step 2: Test It

```bash
cat hello.gza | ./zig-out/bin/ghostlang
# Output: Script result: 7
```

**✓ Congratulations!** Your first plugin works.

---

## Basic Syntax (10 minutes)

### Variables

```ghostlang
var x = 10
var y = 20
var result = x + y  // 30
```

### Arithmetic

```ghostlang
var a = 10
var b = 3

a + b  // 13
a - b  // 7
a * b  // 30
a / b  // 3
```

### Comparisons

```ghostlang
var x = 10
var y = 20

x == y  // false
x < y   // true
x > y   // false
x != y  // true
```

### Logic

```ghostlang
var a = true
var b = false

a && b  // false
a || b  // true
```

### Control Flow

```ghostlang
// If statements
var age = 25
if (age > 18) {
    var adult = true
}

// While loops
var i = 0
while (i < 10) {
    i = i + 1
}
```

---

## Real Plugin: Line Counter (5 minutes)

Let's build something useful - a line counter plugin.

```ghostlang
// Line Counter Plugin
// Counts lines in the current buffer

// Configuration
var count_empty_lines = true
var count_comment_lines = true

// Get buffer info (simulated for now)
var total_lines = 100
var empty_lines = 10
var comment_lines = 15

// Calculate
var code_lines = total_lines - empty_lines - comment_lines

// Display results
var result = code_lines
result
```

**Save as:** `examples/plugins/line_counter.gza`

---

## Plugin Architecture (5 minutes)

Every plugin follows this pattern:

```ghostlang
// 1. CONFIGURATION
var option1 = value1
var option2 = value2

// 2. INPUT (from editor)
var editor_state = getEditorInfo()

// 3. PROCESSING
var result = process(editor_state)

// 4. OUTPUT (return or side effects)
result
```

### Example: Text Transformer

```ghostlang
// Text Transformer Plugin

// 1. CONFIGURATION
var transform_mode = 1  // 1=uppercase, 2=lowercase, 3=reverse

// 2. INPUT
var selection_start = 0
var selection_end = 100
var selection_length = selection_end - selection_start

// 3. PROCESSING
var chars_processed = 0
var i = 0
while (i < selection_length) {
    // Transform each character
    chars_processed = chars_processed + 1
    i = i + 1
}

// 4. OUTPUT
chars_processed
```

---

## Editor Integration (5 minutes)

When integrated with Grim, your plugins get access to editor functions:

```ghostlang
// Line Counter Plugin (with real editor API)

// Get actual buffer info
var total_lines = getLineCount()
var current_line = getCursorLine()

// Process lines
var empty = 0
var i = 0
while (i < total_lines) {
    var line_text = getLineText(i)
    var line_length = len(line_text)

    if (line_length == 0) {
        empty = empty + 1
    }

    i = i + 1
}

// Show result
var code_lines = total_lines - empty
notify("Code lines: " + code_lines)
```

### Available Editor Functions

| Function | Description | Example |
|----------|-------------|---------|
| `getLineCount()` | Total lines in buffer | `var lines = getLineCount()` |
| `getLineText(n)` | Get text of line n | `var text = getLineText(42)` |
| `getCursorLine()` | Current cursor line | `var line = getCursorLine()` |
| `getCursorCol()` | Current cursor column | `var col = getCursorCol()` |
| `insertText(txt)` | Insert at cursor | `insertText("hello")` |
| `notify(msg)` | Show message | `notify("Done!")` |

---

## Common Patterns

### Pattern 1: Process All Lines

```ghostlang
var i = 0
var line_count = getLineCount()

while (i < line_count) {
    var line = getLineText(i)
    // Process line...
    i = i + 1
}
```

### Pattern 2: Process Selection

```ghostlang
var sel_start = getSelectionStart()
var sel_end = getSelectionEnd()

var line = sel_start
while (line < sel_end + 1) {
    var text = getLineText(line)
    // Process selected line...
    line = line + 1
}
```

### Pattern 3: Find & Replace

```ghostlang
var line = 0
var line_count = getLineCount()
var replacements = 0

while (line < line_count) {
    var text = getLineText(line)
    var found = findInLine(text, "old")

    if (found > -1) {
        replaceInLine(line, "old", "new")
        replacements = replacements + 1
    }

    line = line + 1
}

notify("Replaced: " + replacements)
```

---

## Testing Your Plugin

### Quick Test

```bash
# Run your plugin
cat my_plugin.gza | ./zig-out/bin/ghostlang
```

### Integration Test

```zig
// test_my_plugin.zig
const ghostlang = @import("ghostlang");

pub fn main() !void {
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    var plugin = try engine.loadScript(plugin_source);
    defer plugin.deinit();

    const result = try plugin.run();
    // Assert result...
}
```

---

## Security Considerations

Plugins run in three security tiers:

### Sandboxed (Untrusted Plugins)
- 4MB memory limit
- 2 second timeout
- No IO access
- Deterministic mode

```zig
const config = ghostlang.EngineConfig{
    .allocator = allocator,
    .memory_limit = 4 * 1024 * 1024,
    .execution_timeout_ms = 2000,
    .allow_io = false,
    .deterministic = true,
};
```

### Normal (Typical Plugins)
- 16MB memory limit
- 5 second timeout
- Limited IO
- Non-deterministic OK

### Trusted (Core Plugins)
- 64MB memory limit
- 30 second timeout
- Full IO access
- All features enabled

---

## Performance Tips

1. **Avoid nested loops**: They multiply iterations
2. **Cache values**: Don't call `getLineCount()` in a loop
3. **Early exit**: Use conditions to skip unnecessary work
4. **Batch operations**: Process multiple items per iteration

### Bad (Slow)

```ghostlang
var i = 0
while (i < 100) {
    var line_count = getLineCount()  // Called 100 times!
    i = i + 1
}
```

### Good (Fast)

```ghostlang
var line_count = getLineCount()  // Called once
var i = 0
while (i < 100) {
    // Use cached line_count
    i = i + 1
}
```

---

## Next Steps

1. **Explore examples**: Check `examples/plugins/` for working plugins
2. **Read API Cookbook**: `docs/api-cookbook.md` for common recipes
3. **Join community**: Share your plugins and get feedback
4. **Build something cool**: Text transformers, linters, autocomplete...

---

## Quick Reference

### Syntax

```ghostlang
// Variables
var name = value

// Operators
+  -  *  /        // Arithmetic
==  !=  <  >      // Comparison
&&  ||            // Logic

// Control flow
if (condition) { }
while (condition) { }

// Comments
// Single line comment
```

### Common Operations

```ghostlang
// Math
var sum = a + b
var average = sum / count

// Conditions
if (x > 0) {
    var positive = true
}

// Loops
var i = 0
while (i < 10) {
    i = i + 1
}
```

---

**You're ready to build plugins!** Start with simple transformations and gradually add complexity. Happy coding! 🚀
