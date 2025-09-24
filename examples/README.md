# Grim Editor Integration Examples

This directory contains example scripts demonstrating how Ghostlang can be used as the scripting language for the Grim editor (a Neovim clone).

## Files

### `grim_config.gza` - Editor Configuration
Shows how to configure the editor using Ghostlang:
- Theme and display settings
- Key bindings for different modes
- Plugin configuration
- Hook functions for events
- Custom commands
- Status line configuration

### `buffer_api.gza` - Buffer Manipulation
Demonstrates buffer operations:
- Creating and modifying buffers
- Text insertion, deletion, and replacement
- Cursor positioning and selection
- File I/O operations
- Search functionality
- Auto-indentation

### `plugin_system.gza` - Plugin Development
Example of a complete plugin:
- Plugin metadata and state management
- Language-specific code formatting
- Event handling (save, text changes)
- Command registration
- Scope detection for smart formatting

## Key Features for Grim Integration

### 1. **Memory Safety**
- Zero memory leaks in string operations
- Proper cleanup of all allocated resources
- Safe array/table operations

### 2. **Performance**
- Register-based VM for fast execution
- Minimal allocations during script execution
- Efficient string operations with shared/owned distinction

### 3. **Sandboxing**
- Execution timeout limits (configurable)
- Instruction count limits to prevent infinite loops
- Memory usage controls

### 4. **Language Features**
- Local variable scoping for plugin isolation
- Arrays for buffer line manipulation
- Tables for configuration objects
- String operations for text processing
- File I/O for configuration and plugin loading

### 5. **FFI-Ready**
The language is designed to work seamlessly with Zig FFI:
- Simple data types that map to Zig
- Clear separation between Ghostlang and native code
- Minimal marshaling overhead

## Usage in Grim

```zig
// In grim's Zig code:
const ghostlang = @import("ghostlang");

// Initialize the scripting engine
var config = ghostlang.EngineConfig{
    .allocator = allocator,
    .execution_timeout_ms = 5000, // 5 second timeout
};
var engine = try ghostlang.ScriptEngine.create(config);
defer engine.deinit();

// Register editor functions
try engine.registerFunction("get_current_buffer", getCurrentBuffer);
try engine.registerFunction("new_buffer", createBuffer);
try engine.registerFunction("register_command", registerCommand);

// Load user configuration
var config_script = try engine.loadScript(user_config_content);
defer config_script.deinit();
const config_result = try config_script.run();

// Execute plugin
var plugin_script = try engine.loadScript(plugin_content);
defer plugin_script.deinit();
const plugin_result = try plugin_script.run();
```

## Example FFI Functions

These functions would be implemented in Grim's Zig code and exposed to Ghostlang:

```zig
// Buffer operations
fn getCurrentBuffer(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;
fn createBuffer(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;
fn bufferGetLine(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;
fn bufferSetLine(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;

// Editor operations
fn registerCommand(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;
fn registerEventHandler(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;

// File operations (already implemented)
fn fileRead(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;
fn fileWrite(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;

// String operations
fn stringToUpper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;
fn stringToLower(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;
fn stringSplit(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue;
```

## Testing the Examples

To test the basic language features used in these examples:

```bash
# Build ghostlang
zig build

# Test basic functionality
./zig-out/bin/ghostlang

# The examples above use some functions that would be provided by Grim's FFI
# but demonstrate the language patterns and structures
```

## Next Steps for Grim Integration

1. **Implement FFI bindings** - Connect Ghostlang to Grim's buffer, cursor, and editor APIs
2. **Add more built-in functions** - String manipulation, array utilities, etc.
3. **Event system** - Hook into Grim's event system for real-time script execution
4. **Plugin manager** - Load and manage multiple Ghostlang plugins
5. **Debugging support** - Add debugging capabilities for script development
6. **Hot reloading** - Reload scripts without restarting the editor

## Benefits over Lua

- **Memory safety**: No manual memory management concerns
- **Better error handling**: Clear error propagation and sandboxing
- **Modern syntax**: More familiar to developers coming from other languages
- **Zig integration**: Seamless interop with Grim's Zig codebase
- **Type safety**: Better static analysis possibilities