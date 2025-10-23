# 👻 Ghostlang Wishlist for GShell Integration

<div align="center">
  <strong>What GShell needs from Ghostlang for amazing shell scripting</strong>
</div>

---

## 📋 Current Status

✅ **Already Have:**
- v0.1.2 complete with VM, FFI, sandboxing
- Lua-like syntax with JavaScript compatibility
- Register-based VM with small footprint
- Bidirectional FFI (Zig ↔ Ghostlang)
- Sandboxing (memory limits, timeouts, API restrictions)
- Security audit suite
- `.gza` file extension

⏳ **Current FFI in GShell:**
- 30+ shell functions already exposed
- Command execution, file ops, env vars, etc.

---

## 🎯 What GShell Needs

### **P0: Critical Path** (Needed for GShell v0.2.0 - Next 4 weeks)

#### 1. **Shell-Specific Standard Library** (`ghostlang/stdlib/shell.gza`)

Provide a standard library specifically for shell scripting:

```lua
-- shell.gza - Standard library for GShell scripts
local shell = {}

-- File operations
function shell.readfile(path)
  local f = io.open(path, "r")
  if not f then return nil, "File not found" end
  local content = f:read("*all")
  f:close()
  return content
end

function shell.writefile(path, content)
  local f = io.open(path, "w")
  if not f then return false, "Cannot write to file" end
  f:write(content)
  f:close()
  return true
end

function shell.exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

-- Directory operations
function shell.listdir(path)
  -- FFI call to GShell's directory listing
  return _shell_listdir(path)
end

function shell.mkdir(path)
  return _shell_mkdir(path)
end

-- Process management
function shell.exec(command)
  -- Execute command and return result
  local result = _shell_exec(command)
  return {
    stdout = result.stdout,
    stderr = result.stderr,
    exit_code = result.exit_code,
  }
end

function shell.spawn(command)
  -- Execute command in background
  return _shell_spawn(command)
end

-- Environment
function shell.getenv(name)
  return _shell_getenv(name)
end

function shell.setenv(name, value)
  return _shell_setenv(name, value)
end

-- Path utilities
function shell.join(...)
  local parts = {...}
  return table.concat(parts, "/")
end

function shell.basename(path)
  return path:match("^.+/(.+)$") or path
end

function shell.dirname(path)
  return path:match("^(.+)/.+$") or "."
end

-- String utilities for shell scripting
function shell.split(str, sep)
  local parts = {}
  for part in str:gmatch("([^" .. sep .. "]+)") do
    table.insert(parts, part)
  end
  return parts
end

function shell.trim(str)
  return str:match("^%s*(.-)%s*$")
end

return shell
```

**Use Case:**
```lua
-- In ~/.gshrc.gza
local shell = require("shell")

-- Easy file operations
if shell.exists("~/.ssh/config") then
  local config = shell.readfile("~/.ssh/config")
  print("SSH config loaded")
end

-- Easy command execution
local result = shell.exec("git status --short")
if result.exit_code == 0 then
  print("Git status:", result.stdout)
end

-- Easy environment management
shell.setenv("EDITOR", "grim")
local editor = shell.getenv("EDITOR")
```

#### 2. **Better Error Messages for Scripts**

When scripts fail, provide clear, actionable error messages:

**Current (Confusing):**
```
Error in script: attempt to call nil value
  at line 42
```

**Improved (Clear):**
```
Error in ~/.gshrc.gza:42
  shell.alias("ll", "ls -la")
  ^^^^^^^^^^^^
  Undefined function 'shell.alias'

Did you mean:
  - shell.exec(command)
  - shell.setenv(name, value)
  - shell.getenv(name)

Help: Import the shell module with: local shell = require("shell")
```

**Implementation:**
```zig
// In Ghostlang's error reporting
pub fn formatError(
    error_info: ErrorInfo,
    source: []const u8,
    suggestions: []const []const u8,
) []const u8 {
    // Format with:
    // - File path and line number
    // - Code snippet with error highlighted
    // - Clear error message
    // - Suggestions for fixing
}
```

#### 3. **Async/Await for Shell Operations**

Some shell operations are slow (network, disk I/O). Support async:

```lua
-- Proposed syntax (optional P1 if complex)
local function update_prompt()
  local branch = await git.current_branch()  -- Async git call
  local status = await git.status()           -- Async git status
  return "[" .. branch .. "]$ "
end

shell.on_prompt(update_prompt)
```

**Alternative: Callbacks (Simpler for P0):**
```lua
-- Callback-based async (easier to implement)
git.current_branch(function(branch)
  if branch then
    shell.update_prompt("[" .. branch .. "]$ ")
  end
end)
```

---

### **P1: Important** (Needed for GShell v0.3.0 - 4-8 weeks)

#### 4. **Coroutines for Long-Running Scripts**

Support for scripts that run in background:

```lua
-- Long-running background task
local function monitor_logs()
  while true do
    local line = shell.read_log("/var/log/app.log")
    if line:match("ERROR") then
      shell.notify("Error detected in logs!")
    end
    sleep(5)  -- Sleep 5 seconds
  end
end

-- Start as coroutine
shell.background(monitor_logs)
```

**Implementation Needed:**
```zig
// In Ghostlang
pub fn createCoroutine(func: ScriptValue) !Coroutine {
    // Create coroutine that can be suspended/resumed
}

pub fn resumeCoroutine(coro: *Coroutine) !void {
    // Resume coroutine execution
}
```

#### 5. **Pattern Matching for Shell Scripts**

Make string matching easier:

```lua
-- Current (awkward)
if string.match(filename, "%.txt$") then
  print("Text file")
elseif string.match(filename, "%.md$") then
  print("Markdown file")
end

-- Proposed (cleaner)
match filename {
  "*.txt" => print("Text file"),
  "*.md" => print("Markdown file"),
  "*.gz" => print("Compressed file"),
  _ => print("Other file"),
}
```

**Implementation:**
```lua
-- Could be implemented as library function
function match(value, patterns)
  for pattern, action in pairs(patterns) do
    if pattern == "_" then
      return action()
    elseif string.match(value, pattern) then
      return action()
    end
  end
end
```

#### 6. **Pipe Operator**

Make function chaining easier:

```lua
-- Current (nested calls)
print(trim(split(read_file("data.txt"), "\n")[1]))

-- Proposed (pipeline)
read_file("data.txt")
  |> split("\n")
  |> first()
  |> trim()
  |> print()

-- Or Lua-style
read_file("data.txt")
  :split("\n")
  :first()
  :trim()
  :print()
```

#### 7. **Structured Error Handling**

Better than `pcall`:

```lua
-- Current (pcall is awkward)
local success, result = pcall(function()
  return shell.exec("git status")
end)
if not success then
  print("Error:", result)
end

-- Proposed (try/catch)
try {
  local result = shell.exec("git status")
  print(result.stdout)
} catch (error) {
  print("Git error:", error)
}

-- Or Result type (Rust-style)
local result = shell.exec("git status")
if result:is_ok() then
  print(result:unwrap().stdout)
else
  print("Error:", result:unwrap_err())
end
```

---

### **P2: Nice to Have** (Needed for GShell v0.4.0+ - 8+ weeks)

#### 8. **Destructuring Assignment**

Make data handling easier:

```lua
-- Current
local result = git.ahead_behind()
local ahead = result.ahead
local behind = result.behind

-- Proposed
local {ahead, behind} = git.ahead_behind()

-- Array destructuring
local [first, second, ...rest] = split("a b c d", " ")
```

#### 9. **String Interpolation**

More readable than concatenation:

```lua
-- Current
print("Branch: " .. branch .. ", status: " .. status)

-- Proposed
print("Branch: ${branch}, status: ${status}")

-- With expressions
print("Result: ${x + y}")
```

#### 10. **List/Table Comprehensions**

Functional programming for data:

```lua
-- Current
local squared = {}
for i, v in ipairs(numbers) do
  table.insert(squared, v * v)
end

-- Proposed
local squared = [v * v for v in numbers]

-- With filtering
local evens = [v for v in numbers if v % 2 == 0]
```

#### 11. **Optional Chaining**

Safe navigation:

```lua
-- Current
local branch = nil
if config and config.git and config.git.branch then
  branch = config.git.branch
end

-- Proposed
local branch = config?.git?.branch

-- With function calls
local result = git.status()?.lines[1]?.trim()
```

#### 12. **Type Annotations (Optional)**

Optional static typing for better tooling:

```lua
-- Type annotations (checked at parse time)
function calculate_prompt(config: table): string
  local branch: string | nil = git.current_branch()
  local status: table = git.status()

  return string.format("[%s]$ ", branch or "main")
end

-- Type checking
local result: string = calculate_prompt({})  -- OK
local result: number = calculate_prompt({})  -- Error: Expected string, got number
```

---

### **P3: Future Vision** (Nice to have, no timeline)

#### 13. **Modules and Packages**

Better code organization:

```lua
-- In ~/.config/gshell/modules/git.gza
module "git"

export function current_branch()
  -- Implementation
end

export function is_dirty()
  -- Implementation
end

-- In ~/.gshrc.gza
import { current_branch, is_dirty } from "git"

shell.on_prompt(function()
  local branch = current_branch()
  local dirty = is_dirty() and "*" or ""
  return "[" .. branch .. dirty .. "]$ "
end)
```

#### 14. **JIT Compilation**

For performance-critical scripts:

```lua
-- Hot path functions get JIT compiled
@jit
function calculate_complex_prompt()
  -- This gets compiled for speed
end
```

---

## 🔧 What's Already Great

GShell loves these Ghostlang features:

1. ✅ **Lua-like Syntax** - Familiar and clean
2. ✅ **FFI Support** - Easy integration with Zig
3. ✅ **Sandboxing** - Secure script execution
4. ✅ **Small Footprint** - Fast startup, low memory
5. ✅ **`.gza` Extension** - Clear file association

---

## 📊 Integration Success Metrics

When Ghostlang enhancements are complete, GShell users should have:

- ✅ Shell standard library for common operations
- ✅ Clear, actionable error messages
- ✅ Async support for slow operations
- ✅ Pattern matching for clean conditionals
- ✅ Pipeline operator for function chaining
- ✅ Better error handling than `pcall`
- ✅ Optional type annotations for tooling support

---

## 🤝 Collaboration

GShell is happy to:
- Test Ghostlang features with real shell scripts
- Provide feedback on language design
- Contribute PRs for shell-specific features
- Write example scripts and documentation

Ghostlang can prioritize:
- P0: Shell stdlib + error messages (next 4 weeks)
- P1: Pattern matching + error handling (4-8 weeks)
- P2: Advanced features (8+ weeks)

**Let's make Ghostlang the best shell scripting language ever!** 🚀

---

## 📞 Contact

For questions or coordination:
- Open an issue in GShell repo: [ghostkellz/gshell](https://github.com/ghostkellz/gshell)
- Reference this wishlist in Ghostlang issues/PRs
- Coordinate timelines in DRAFT_DISCOVERY.md

**Thank you for building Ghostlang!** 👻

---

## 💡 Language Design Philosophy

For shell scripting, the ideal language should be:

1. **Readable**: Shell scripts are often read more than written
2. **Concise**: Common operations should be brief
3. **Safe**: Errors should be caught early
4. **Fast**: Shell should feel instant
5. **Familiar**: Lua/JS syntax is widely known

Ghostlang already has (1), (4), and (5) ✅

This wishlist focuses on improving (2) and (3)!
