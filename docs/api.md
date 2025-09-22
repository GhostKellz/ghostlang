# Ghostlang API Reference

## ScriptEngine

The main engine for running scripts.

### `create(config: EngineConfig) !ScriptEngine`

Creates a new scripting engine with the given configuration.

**Parameters:**
- `config`: EngineConfig - Configuration options

**Returns:** ScriptEngine

### `deinit()`

Deinitializes the engine and frees resources.

### `loadScript(source: []const u8) !Script`

Loads a script from source code.

**Parameters:**
- `source`: []const u8 - The script source code

**Returns:** Script

### `call(function: []const u8, args: anytype) !ScriptValue`

Calls a script function with arguments.

**Parameters:**
- `function`: []const u8 - Function name
- `args`: anytype - Arguments to pass

**Returns:** ScriptValue - Result of the call

### `registerFunction(name: []const u8, func: fn(args: []const ScriptValue) ScriptValue) !void`

Registers a Zig function that can be called from scripts.

**Parameters:**
- `name`: []const u8 - Function name in scripts
- `func`: Function pointer - The Zig function

## Script

Represents a loaded script.

### `run() !ScriptValue`

Runs the script.

**Returns:** ScriptValue - Result of execution

### `getGlobal(name: []const u8) !ScriptValue`

Gets a global variable from the script.

**Parameters:**
- `name`: []const u8 - Variable name

**Returns:** ScriptValue

### `setGlobal(name: []const u8, value: ScriptValue) !void`

Sets a global variable in the script.

**Parameters:**
- `name`: []const u8 - Variable name
- `value`: ScriptValue - Value to set

### `deinit()`

Frees script resources.

## ScriptValue

Represents values in the scripting language.

### Variants

- `nil`
- `boolean(bool)`
- `number(f64)`
- `string([]const u8)`
- `function(fn(args: []const ScriptValue) ScriptValue)`
- `table(std.StringHashMap(ScriptValue))`

### `deinit(allocator: std.mem.Allocator)`

Deinitializes the value, freeing any owned resources.

## EngineConfig

Configuration for the scripting engine.

### Fields

- `allocator`: std.mem.Allocator - Memory allocator
- `memory_limit`: usize = 1MB - Maximum memory usage
- `execution_timeout_ms`: u64 = 1000 - Execution timeout in milliseconds
- `allow_io`: bool = false - Allow I/O operations
- `allow_syscalls`: bool = false - Allow system calls