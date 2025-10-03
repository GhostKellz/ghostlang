# Ghostlang Example Plugins

This directory contains working example plugins demonstrating common editor operations implemented in Ghostlang.

## Available Plugins

### 1. Line Numbers (`line_numbers.gza`)
Adds line numbers to the current buffer with configurable formatting.

**Features:**
- Configurable number width
- Adjustable spacing
- Dynamic buffer size handling

**Usage:**
```ghostlang
var show_line_numbers = true
var number_width = 4
```

---

### 2. Auto Indent (`auto_indent.gza`)
Automatically indents code based on context (braces, parentheses, keywords).

**Features:**
- Configurable indent size
- Space/tab preference
- Smart indentation for common patterns
- Context-aware nesting

**Usage:**
```ghostlang
var indent_size = 4
var use_spaces = true
```

---

### 3. Comment Toggle (`comment_toggle.gza`)
Toggles line or block comments for selected text.

**Features:**
- Line comment support (`//`)
- Block comment support (`/* */`)
- Multi-line selection handling
- Smart comment detection

**Usage:**
```ghostlang
var comment_style = 2  // 1=line, 2=block
```

---

### 4. Word Count (`word_count.gza`)
Counts words, characters, and lines in selection or entire buffer.

**Features:**
- Selection or buffer-wide counting
- Words, characters, and lines
- Reading time estimation
- Detailed statistics

**Usage:**
```ghostlang
var count_mode = 1  // 1=selection, 2=buffer, 3=paragraph
```

---

### 5. Duplicate Line (`duplicate_line.gza`)
Duplicates the current line or selected lines.

**Features:**
- Single line duplication
- Multi-line selection support
- Cursor position preservation
- Configurable insert position

**Usage:**
```ghostlang
// Cursor on line to duplicate, run plugin
```

---

## Plugin Structure

All plugins follow a common structure:

```ghostlang
// 1. Configuration Section
var config_option = value

// 2. Input Gathering
var editor_state = getValue()

// 3. Processing Logic
var result = process(editor_state)

// 4. Result/Side Effects
result
```

## Integration with Grim Editor

These plugins are designed to integrate with the Grim editor through the Ghostlang API:

```zig
// In Grim editor (Zig code)
const ghostlang = @import("ghostlang");

// Load plugin
var engine = try ghostlang.ScriptEngine.create(config);
var plugin = try engine.loadScript(plugin_source);

// Register editor functions
try engine.registerFunction("getLineCount", getLineCountFunc);
try engine.registerFunction("getLineText", getLineTextFunc);
try engine.registerFunction("setCursor", setCursorFunc);
// ... more API functions

// Execute plugin
const result = try plugin.run();
```

## Testing Plugins

Test your plugins using the provided test harness:

```bash
# Run all plugin scenarios
zig build test-plugins

# Run integration tests
zig build test-integration
```

## Creating Your Own Plugins

### Template

```ghostlang
// My Plugin Name
// Brief description of what it does

// Configuration
var my_option = default_value

// Get editor state
var current_state = 0  // Would use editor API

// Process
var result = current_state + 1

// Return result
result
```

### Best Practices

1. **Clear Configuration**: Put all configurable options at the top
2. **Comment Your Code**: Explain complex logic
3. **Error Handling**: Check for invalid states
4. **Performance**: Avoid unnecessary loops
5. **API Usage**: Use editor APIs sparingly (they're expensive)

### Editor API Functions

When integrated with Grim, these functions will be available:

- `getLineCount()` - Get total lines in buffer
- `getLineText(line)` - Get text of specific line
- `getCursorPosition()` - Get current cursor position
- `setCursorPosition(line, col)` - Move cursor
- `getSelection()` - Get selected text range
- `insertText(text)` - Insert text at cursor
- `replaceText(start, end, text)` - Replace text range
- `notify(message)` - Show message to user

## Contributing

To add your plugin to this collection:

1. Create `your_plugin.gza` in this directory
2. Follow the established structure and conventions
3. Add documentation to this README
4. Test thoroughly with `zig build test-plugins`

## License

These example plugins are provided as templates and can be freely modified and distributed.
