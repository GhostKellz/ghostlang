# Ghostlang API Reference

Comprehensive API documentation for embedding Ghostlang in Zig applications.

## Table of Contents

1. [ScriptEngine](#scriptengine) - Main scripting engine
2. [Script](#script) - Individual script instances
3. [ScriptValue](#scriptvalue) - Value types and operations
4. [EngineConfig](#engineconfig) - Engine configuration
5. [Built-in Functions](#built-in-functions) - Available script functions
6. [Error Types](#error-types) - Error handling
7. [Memory Management](#memory-management) - Memory safety features

## ScriptEngine

The main engine for running scripts with sandboxing and memory safety.

### Creation and Lifecycle

#### `create(config: EngineConfig) !ScriptEngine`

Creates a new scripting engine with the given configuration.

**Parameters:**
- `config`: EngineConfig - Configuration options including memory limits and timeouts

**Returns:** ScriptEngine instance

**Example:**
```zig
const config = ghostlang.EngineConfig{
    .allocator = allocator,
    .execution_timeout_ms = 5000,
    .memory_limit = 10 * 1024 * 1024, // 10MB
};
var engine = try ghostlang.ScriptEngine.create(config);
defer engine.deinit();
```

#### `deinit()`

Deinitializes the engine and frees all resources.

### Script Management

#### `loadScript(source: []const u8) !Script`

Loads and compiles a script from source code.

**Parameters:**
- `source`: []const u8 - The script source code

**Returns:** Script instance

**Errors:**
- `ParseError` - Syntax errors in the script
- `OutOfMemory` - Not enough memory to compile

**Example:**
```zig
const source =
    \\local greeting = "Hello, World!"
    \\print(greeting)
;
var script = try engine.loadScript(source);
defer script.deinit();
```

#### `loadScriptFile(file_path: []const u8) !Script`

Loads a script from a file.

**Parameters:**
- `file_path`: []const u8 - Path to the script file

**Returns:** Script instance

### Function Registration

#### `registerFunction(name: []const u8, func: NativeFunction) !void`

Registers a Zig function that can be called from scripts.

**Parameters:**
- `name`: []const u8 - Function name as it appears in scripts
- `func`: NativeFunction - Function pointer with signature `fn([]const ScriptValue) ScriptValue`

**Example:**
```zig
fn addNumbers(args: []const ScriptValue) ScriptValue {
    if (args.len != 2) return ScriptValue{ .nil = {} };

    const a = args[0].number;
    const b = args[1].number;
    return ScriptValue{ .number = a + b };
}

try engine.registerFunction("add", addNumbers);
```

#### `registerModule(module_name: []const u8, functions: anytype) !void`

Registers multiple functions under a module namespace.

**Parameters:**
- `module_name`: []const u8 - Module name
- `functions`: struct - Struct containing functions to register

**Example:**
```zig
const MathModule = struct {
    fn add(args: []const ScriptValue) ScriptValue { /* ... */ }
    fn multiply(args: []const ScriptValue) ScriptValue { /* ... */ }
};

try engine.registerModule("math", MathModule);
// Scripts can call: math.add(10, 20)
```

## Script

Represents a compiled script ready for execution.

### Execution

#### `run() !ScriptValue`

Executes the script and returns the result.

**Returns:** ScriptValue - The final result of script execution

**Errors:**
- `ExecutionTimeout` - Script exceeded time limit
- `InstructionLimitExceeded` - Script exceeded instruction count limit
- `RuntimeError` - Runtime error during execution
- `StackOverflow` - Call stack overflow
- `OutOfMemory` - Memory limit exceeded

**Example:**
```zig
const result = try script.run();
defer result.deinit(allocator);
```

### Variable Access

#### `getGlobal(name: []const u8) !ScriptValue`

Gets a global variable from the script.

**Parameters:**
- `name`: []const u8 - Variable name

**Returns:** ScriptValue - The variable's value

#### `setGlobal(name: []const u8, value: ScriptValue) !void`

Sets a global variable in the script.

**Parameters:**
- `name`: []const u8 - Variable name
- `value`: ScriptValue - Value to set

### Function Calls

#### `call(function_name: []const u8, args: []const ScriptValue) !ScriptValue`

Calls a script function with arguments.

**Parameters:**
- `function_name`: []const u8 - Name of the function to call
- `args`: []const ScriptValue - Arguments to pass

**Returns:** ScriptValue - Function result

## ScriptValue

Represents all possible values in Ghostlang with automatic memory management.

### Value Types

#### Basic Types
```zig
// Nil value
const nil_val = ScriptValue{ .nil = {} };

// Boolean values
const true_val = ScriptValue{ .boolean = true };
const false_val = ScriptValue{ .boolean = false };

// Numeric values
const number_val = ScriptValue{ .number = 42.0 };

// String values (shared reference)
const string_val = ScriptValue{ .string = "Hello" };

// Owned string (will be freed)
const owned_val = ScriptValue{ .owned_string = owned_str };
```

#### Complex Types
```zig
// Arrays
const array_val = ScriptValue{ .array = array_list };

// Tables (hash maps)
const table_val = ScriptValue{ .table = hash_map };

// Functions (closures)
const func_val = ScriptValue{ .closure = closure_info };
```

### Memory Management

#### `deinit(allocator: std.mem.Allocator)`

Deinitializes the value, freeing any owned resources.

#### `copy(allocator: std.mem.Allocator) !ScriptValue`

Creates a deep copy of the value.

#### `safeStore(value: ScriptValue, allocator: std.mem.Allocator) !ScriptValue`

Safely stores a value with proper ownership tracking (prevents double-free).

### Type Checking and Conversion

#### `isNumber() bool`
#### `isString() bool`
#### `isBoolean() bool`
#### `isNil() bool`
#### `isArray() bool`
#### `isTable() bool`

## EngineConfig

Configuration options for the scripting engine.

### Fields

```zig
pub const EngineConfig = struct {
    allocator: std.mem.Allocator,

    // Execution limits
    execution_timeout_ms: u64 = 5000,      // 5 second default
    max_instruction_count: u64 = 1_000_000, // 1M instructions
    max_call_depth: u32 = 256,              // Call stack depth

    // Memory limits
    memory_limit: usize = 10 * 1024 * 1024, // 10MB default
    max_string_length: usize = 1024 * 1024,  // 1MB max string
    max_array_size: usize = 100_000,         // Max array elements

    // Feature flags
    allow_file_io: bool = true,
    allow_network: bool = false,
    allow_system_calls: bool = false,

    // Debug options
    debug_mode: bool = false,
    trace_execution: bool = false,
};
```

## Built-in Functions

Functions automatically available in all scripts.

### I/O Functions

#### `print(...args)`
Print values to stdout with space separation.

#### `file_read(filename: string) -> string | nil`
Read entire file contents as string.

#### `file_write(filename: string, content: string) -> boolean`
Write content to file, returns success status.

#### `file_exists(filename: string) -> boolean`
Check if file exists.

#### `file_delete(filename: string) -> boolean`
Delete file, returns success status.

### String Functions

#### `strlen(str: string) -> number`
Get string length.

#### `substr(str: string, start: number, length?: number) -> string`
Extract substring.

#### `str_upper(str: string) -> string`
Convert to uppercase.

#### `str_lower(str: string) -> string`
Convert to lowercase.

#### `str_find(str: string, pattern: string) -> number | nil`
Find pattern in string, returns position or nil.

### Array Functions

#### `array_length(arr: array) -> number`
Get array length.

#### `array_push(arr: array, value: any) -> boolean`
Add element to end of array.

## Error Types

Comprehensive error handling for robust applications.

### Compile-time Errors
```zig
pub const CompileError = error{
    ParseError,        // Syntax error in script
    OutOfMemory,       // Not enough memory to compile
    InvalidSyntax,     // Malformed language constructs
};
```

### Runtime Errors
```zig
pub const RuntimeError = error{
    ExecutionTimeout,          // Script exceeded time limit
    InstructionLimitExceeded, // Too many instructions executed
    StackOverflow,            // Call stack overflow
    OutOfMemory,              // Memory limit exceeded
    TypeError,                // Type mismatch in operation
    DivisionByZero,           // Math error
    IndexOutOfBounds,         // Array/string index error
    UndefinedVariable,        // Variable not found
    UndefinedFunction,        // Function not found
};
```

### Error Handling Example
```zig
const script_result = script.run() catch |err| switch (err) {
    error.ExecutionTimeout => {
        std.log.warn("Script timed out after {}ms", .{config.execution_timeout_ms});
        return error.ScriptTimeout;
    },
    error.OutOfMemory => {
        std.log.err("Script exceeded memory limit of {} bytes", .{config.memory_limit});
        return error.ScriptMemoryExceeded;
    },
    else => return err,
};
```

## Memory Management

Ghostlang provides automatic memory management with built-in protection against common memory errors.

### Key Features

1. **Automatic Cleanup**: All values are automatically freed when no longer referenced
2. **Double-free Protection**: `safeStore` prevents double-free errors
3. **Corruption Detection**: Runtime validation prevents crashes from corrupt data
4. **Memory Limits**: Configurable limits prevent runaway memory usage
5. **Leak Detection**: Debug mode tracks allocations and reports leaks

### Best Practices

```zig
// Always use defer for cleanup
var script = try engine.loadScript(source);
defer script.deinit();

// Check return values
const result = try script.run();
defer result.deinit(allocator);

// Use safeStore for shared values
const stored_value = try ScriptValue.safeStore(input_value, allocator);
defer stored_value.deinit(allocator);
```

## Thread Safety

**Important**: Ghostlang is not thread-safe. Each thread should have its own `ScriptEngine` instance.

```zig
// Good: Separate engines per thread
const ThreadLocal = struct {
    engine: *ghostlang.ScriptEngine,

    fn init(allocator: std.mem.Allocator) !ThreadLocal {
        const config = ghostlang.EngineConfig{ .allocator = allocator };
        const engine = try ghostlang.ScriptEngine.create(config);
        return ThreadLocal{ .engine = engine };
    }

    fn deinit(self: *ThreadLocal) void {
        self.engine.deinit();
    }
};
```

---

This API reference covers Ghostlang Phase 2. For usage examples, see the [examples directory](examples/) and [integration guide](grim-integration.md).