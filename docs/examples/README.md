# Ghostlang Examples

This directory contains practical examples demonstrating various aspects of Ghostlang programming.

## Directory Structure

### [Basic Examples](basic/)
Learn the fundamentals of Ghostlang:
- [Hello World](basic/hello-world.gza) - Your first Ghostlang program
- [Variables and Types](basic/variables.gza) - Working with different data types
- [Control Flow](basic/control-flow.gza) - Conditionals and loops
- [Functions](basic/functions.gza) - Function definitions and calls
- [Tables and Arrays](basic/data-structures.gza) - Working with complex data
- [String Operations](basic/strings.gza) - Text processing examples
- [File I/O](basic/file-io.gza) - Reading and writing files

### [Grim Configuration](grim-config/)
Configure the Grim editor with Ghostlang:
- [Basic Config](grim-config/init.gza) - Essential editor configuration
- [Key Bindings](grim-config/keybindings.gza) - Custom key mappings
- [Theme Configuration](grim-config/theme.gza) - Visual customization
- [Advanced Settings](grim-config/advanced.gza) - Power user configurations

### [Plugin Development](plugins/)
Build plugins for the Grim editor:
- [Simple Plugin](plugins/hello-plugin.gza) - Basic plugin structure
- [Auto-Formatter](plugins/auto-formatter.gza) - Code formatting plugin
- [File Tree](plugins/file-tree.gza) - File browser sidebar
- [Status Line](plugins/status-line.gza) - Custom status line
- [Fuzzy Finder](plugins/fuzzy-finder.gza) - File search functionality

### [FFI Examples](ffi/)
Integrate with Zig code using FFI:
- [Basic FFI](ffi/basic-ffi.gza) - Simple function calls
- [Buffer Operations](ffi/buffer-api.gza) - Editor buffer manipulation
- [System Integration](ffi/system-calls.gza) - OS interaction
- [Custom Libraries](ffi/custom-lib.gza) - Using external libraries

## Running Examples

### Individual Examples
```bash
# Run a specific example
./zig-out/bin/ghostlang docs/examples/basic/hello-world.gza

# Run with output
./zig-out/bin/ghostlang docs/examples/basic/control-flow.gza
```

### Interactive Mode
```bash
# Start interactive mode
./zig-out/bin/ghostlang

# Then type commands interactively
>>> print("Hello from interactive mode!")
>>> local x = 10 + 20
>>> print("Result:", x)
```

## Example Categories

### 🎯 Beginner Examples
Perfect for learning Ghostlang basics:
- Variable declarations
- Basic arithmetic
- Simple conditionals
- Function calls

### 🔧 Intermediate Examples
More complex programming concepts:
- Advanced control flow
- Table manipulation
- String processing
- File operations

### 🚀 Advanced Examples
Real-world applications:
- Plugin development
- Editor integration
- System programming
- Performance optimization

## Contributing Examples

When adding new examples:

1. **Clear Documentation**: Each example should be well-commented
2. **Progressive Complexity**: Start simple, build complexity gradually
3. **Real-World Relevance**: Show practical use cases
4. **Error Handling**: Demonstrate proper error handling
5. **Best Practices**: Follow Ghostlang conventions

### Example Template

```lua
-- Example: [Brief Description]
-- Purpose: [What this example demonstrates]
-- Concepts: [Key concepts covered]

-- Setup
local example_data = "Hello, Ghostlang!"

-- Main logic
function demonstrate_feature()
    -- Clear explanation of what's happening
    local result = process_data(example_data)
    print("Result:", result)
    return result
end

-- Helper functions
function process_data(data)
    -- Processing logic
    return str_upper(data)
end

-- Execute example
demonstrate_feature()

-- Expected output:
-- Result: HELLO, GHOSTLANG!
```

## Getting Help

- **Documentation**: See the main [docs](../README.md) directory
- **Language Guide**: Check the [Language Guide](../language-guide.md)
- **API Reference**: Browse the [API Reference](../api.md)

---

**Happy learning with Ghostlang examples!** 🎓