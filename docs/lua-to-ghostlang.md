# Lua to Ghostlang Migration Guide

**For developers familiar with Lua transitioning to Ghostlang plugin development**

## Overview

Ghostlang draws heavy inspiration from Lua but is specifically designed for editor plugins. This guide highlights the key differences and helps you translate Lua knowledge to Ghostlang.

## Table of Contents

1. [Phase A Dual-Syntax Migration Outline](#phase-a-dual-syntax-migration-outline)
1. [Quick Syntax Comparison](#quick-syntax-comparison)
1. [Variables & Types](#variables--types)
1. [Control Flow](#control-flow)
1. [Functions](#functions)
1. [Tables vs. Ghostlang Data Structures](#tables-vs-ghostlang-data-structures)
1. [String Operations](#string-operations)
1. [Common Patterns](#common-patterns)
1. [Editor Integration](#editor-integration)

---

## Phase A Dual-Syntax Migration Outline

Ghostlang Phase A unlocks feature parity for Lua-style control flow while keeping the existing brace syntax intact. Use this checklist to stage your migration:

1. **Audit control-flow blocks** – Identify every `if`, `elseif`, `else`, and `while` statement. Confirm whether the branch uses braces or Lua keywords today and decide whether to standardize per file or per statement.
2. **Plan loop upgrades** – Inventory numeric and generic `for` loops plus any prospective `repeat ... until` patterns. Brace-only loops should migrate to the new dual-syntax forms once the runtime lands.
3. **Function declarations** – Map global vs. local functions. Note anonymous `function (...) ... end` expressions that need compatibility coverage.
4. **Keyword review** – Document `break`, `continue`, and other auxiliary keywords inside each block. Phase A enforces consistent style per construct and ensures scope unwinding works in both syntaxes.
5. **Testing & linting strategy** – Prepare unit tests or fixtures that exercise both brace and Lua syntax for critical paths. Plan to run them against the `feature/parser-phase-a` branch during adoption.

Track findings in your project tracker so implementation can proceed once the Phase A branch is ready.

## Quick Syntax Comparison

### Variables

```lua
-- Lua
local x = 10
local name = "Alice"

-- Ghostlang
var x = 10
var name = "Alice"
```

### Operators

```lua
-- Lua
local sum = a + b
local mod = a % b
local concat = s1 .. s2

-- Ghostlang
var sum = a + b
var mod = a % b
var concat = s1 + s2  -- String concat uses +
```

### Conditionals

```lua
-- Lua
if condition then
    -- code
elseif other then
    -- code
else
    -- code
end

-- Ghostlang
if (condition) {
    // code
} else if (other) {
    // code
} else {
    // code
}
```

### Loops

```lua
-- Lua
while condition do
    -- code
end

for i = 1, 10 do
    -- code
end

-- Ghostlang
while (condition) {
    // code
}

// No for loop yet - use while
var i = 1
while (i < 11) {
    // code
    i = i + 1
}
```

---

## Variables & Types

### Type System

| Lua | Ghostlang | Notes |
|-----|-----------|-------|
| `nil` | `nil` | Same concept |
| `boolean` | `boolean` | `true` / `false` |
| `number` | `number` | All numbers are f64 |
| `string` | `string` | Strings are immutable |
| `table` | `table` / `array` | Separate types |
| `function` | `function` | Similar concept |

### Declaration

```lua
-- Lua: global by default
x = 10          -- global
local y = 20    -- local

-- Ghostlang: explicit var
var x = 10      -- required
var y = 20      -- scoped to block
```

### Scoping

```lua
-- Lua
local x = 1
if true then
    local x = 2  -- different variable
    print(x)     -- 2
end
print(x)         -- 1

-- Ghostlang
var x = 1
if (true) {
    var x = 2    // different variable
    print(x)     // 2
}
print(x)         // 1
```

---

## Control Flow

### If Statements

```lua
-- Lua
if x > 10 then
    print("big")
elseif x > 5 then
    print("medium")
else
    print("small")
end

-- Ghostlang
if (x > 10) {
    print("big")
} else if (x > 5) {
    print("medium")
} else {
    print("small")
}
```

### While Loops

```lua
-- Lua
local i = 0
while i < 10 do
    print(i)
    i = i + 1
end

-- Ghostlang
var i = 0
while (i < 10) {
    print(i)
    i = i + 1
}
```

### For Loops

```lua
-- Lua
for i = 1, 10 do
    print(i)
end

for k, v in pairs(t) do
    print(k, v)
end

-- Ghostlang (no for loop yet)
var i = 1
while (i < 11) {
    print(i)
    i = i + 1
}

// Table iteration - TODO
```

---

## Functions

### Definition & Calls

```lua
-- Lua
function add(a, b)
    return a + b
end

local result = add(3, 4)

-- Ghostlang (currently limited)
// Built-in functions only
var result = len("hello")  // 5
print("Result:", result)
```

**Note**: Ghostlang currently doesn't support user-defined functions in scripts. Use built-in functions and editor API.

### Built-in Functions Comparison

| Lua | Ghostlang | Notes |
|-----|-----------|-------|
| `string.len(s)` | `len(s)` | Get length |
| `print(...)` | `print(...)` | Output to console |
| `type(x)` | `type(x)` | Get type name |
| `tostring(x)` | `toString(x)` | Convert to string |
| `tonumber(x)` | `toNumber(x)` | Convert to number |

---

## Tables vs. Ghostlang Data Structures

### Tables

```lua
-- Lua
local t = {
    name = "Alice",
    age = 30,
    items = {1, 2, 3}
}

print(t.name)
print(t["age"])

-- Ghostlang (limited support)
// Tables exist but are less flexible
// Focus on simple data structures
```

### Arrays

```lua
-- Lua
local arr = {10, 20, 30}
print(arr[1])  -- 10 (1-indexed)

-- Ghostlang
// Array support limited
// Use variables for simple cases
var item1 = 10
var item2 = 20
var item3 = 30
```

---

## String Operations

### Concatenation

```lua
-- Lua
local greeting = "Hello, " .. name .. "!"

-- Ghostlang
var greeting = "Hello, " + name + "!"
```

### Functions

```lua
-- Lua
string.upper(s)
string.lower(s)
string.sub(s, i, j)
string.find(s, pattern)

-- Ghostlang
toUpperCase(s)
toLowerCase(s)
substring(s, i, j)
indexOf(s, pattern)
```

---

## Common Patterns

### Counting Lines

```lua
-- Lua (with editor API)
local count = 0
for line in buffer:lines() do
    count = count + 1
end

-- Ghostlang
var count = getLineCount()
```

### Text Transformation

```lua
-- Lua
for i, line in ipairs(lines) do
    lines[i] = string.upper(line)
end

-- Ghostlang
var i = 0
var line_count = getLineCount()
while (i < line_count) {
    var text = getLineText(i)
    var upper = toUpperCase(text)
    setLineText(i, upper)
    i = i + 1
}
```

### Finding Text

```lua
-- Lua
for i, line in ipairs(lines) do
    if string.find(line, "TODO") then
        print("Found at line " .. i)
    end
end

-- Ghostlang
var i = 0
var line_count = getLineCount()
while (i < line_count) {
    var text = getLineText(i)
    var found = indexOf(text, "TODO")
    if (found > -1) {
        print("Found at line", i)
    }
    i = i + 1
}
```

---

## Editor Integration

### Buffer Operations

```lua
-- Lua (typical editor API)
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
vim.api.nvim_buf_set_lines(0, 0, -1, false, new_lines)

-- Ghostlang
var line_count = getLineCount()
var text = getLineText(5)
setLineText(5, "new text")
```

### Cursor

```lua
-- Lua (Neovim example)
local row, col = unpack(vim.api.nvim_win_get_cursor(0))
vim.api.nvim_win_set_cursor(0, {row, col})

-- Ghostlang
var line = getCursorLine()
var col = getCursorCol()
setCursorPosition(line, col)
```

### Selection

```lua
-- Lua (varies by editor)
local start_pos = vim.fn.getpos("'<")
local end_pos = vim.fn.getpos("'>")

-- Ghostlang
var start = getSelectionStart()
var end = getSelectionEnd()
setSelection(start_line, start_col, end_line, end_col)
```

---

## Migration Checklist

### What Ghostlang Has

- ✅ Variables with `var`
- ✅ Arithmetic operators (`+`, `-`, `*`, `/`, `%`)
- ✅ Comparison operators (`==`, `!=`, `<`, `>`, `<=`, `>=`)
- ✅ Boolean logic (`&&`, `||`)
- ✅ While loops
- ✅ If/else statements
- ✅ Built-in functions (len, print, type)
- ✅ Editor API (buffer, cursor, selection)

### What Ghostlang Lacks (vs Lua)

- ❌ User-defined functions
- ❌ For loops
- ❌ Tables (limited support)
- ❌ Metatables
- ❌ Coroutines
- ❌ File I/O (by design - security)
- ❌ Package system
- ❌ String concatenation with `..`

---

## Tips for Lua Developers

### 1. Embrace Simplicity

Ghostlang is deliberately minimal. Don't try to replicate complex Lua patterns.

```lua
-- Lua: complex
local function map(fn, arr)
    local result = {}
    for i, v in ipairs(arr) do
        result[i] = fn(v)
    end
    return result
end

-- Ghostlang: simple
var i = 0
while (i < count) {
    var value = getValue(i)
    var transformed = transform(value)
    setValue(i, transformed)
    i = i + 1
}
```

### 2. Use Editor API

Instead of manipulating data structures, use editor functions directly.

```lua
-- Lua: manipulate table
local lines = getLines()
for i, line in ipairs(lines) do
    lines[i] = transform(line)
end
setLines(lines)

-- Ghostlang: direct manipulation
var i = 0
while (i < getLineCount()) {
    var line = getLineText(i)
    setLineText(i, transform(line))
    i = i + 1
}
```

### 3. Think Imperative

Ghostlang doesn't have functional programming features. Write imperative code.

```lua
-- Lua: functional style
local doubled = vim.tbl_map(function(x) return x * 2 end, numbers)

-- Ghostlang: imperative
var i = 0
while (i < count) {
    var value = getValue(i)
    setValue(i, value * 2)
    i = i + 1
}
```

---

## Example: Line Counter Plugin

### Lua Version

```lua
function count_lines()
    local total = 0
    local empty = 0
    local code = 0

    for i = 1, vim.fn.line('$') do
        local line = vim.fn.getline(i)
        total = total + 1
        if line:match('^%s*$') then
            empty = empty + 1
        else
            code = code + 1
        end
    end

    print(string.format("Total: %d, Code: %d, Empty: %d",
          total, code, empty))
end
```

### Ghostlang Version

```ghostlang
var total = getLineCount()
var empty = 0
var code = 0

var i = 0
while (i < total) {
    var line = getLineText(i)
    var trimmed = trim(line)
    var line_len = len(trimmed)

    if (line_len == 0) {
        empty = empty + 1
    } else {
        code = code + 1
    }

    i = i + 1
}

print("Total:", total)
print("Code:", code)
print("Empty:", empty)
```

---

## Next Steps

1. **Read**: `plugin-quickstart.md` for Ghostlang basics
2. **Explore**: `api-cookbook.md` for practical recipes
3. **Try**: Example plugins in `examples/plugins/`
4. **Build**: Start with simple transformations

---

## Getting Help

- Ghostlang is simpler than Lua by design
- Focus on what you can do, not what you can't
- Most Lua patterns have simple Ghostlang equivalents
- When in doubt, use the editor API directly

**Happy migrating!** 🚀
