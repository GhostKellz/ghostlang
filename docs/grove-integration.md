# Grove Integration Guide

Complete guide for integrating Ghostlang tree-sitter grammar into Grove editor for syntax highlighting and language support.

## Overview

This guide covers how to integrate the Ghostlang tree-sitter grammar into Grove, enabling full syntax highlighting, code navigation, and language-aware features for Ghostlang scripts.

## Prerequisites

- Grove editor with tree-sitter support
- Ghostlang tree-sitter grammar (included in `tree-sitter-ghostlang/`)
- Node.js and npm (for building the grammar)

## Installation

### 1. Build the Tree-sitter Grammar

```bash
cd tree-sitter-ghostlang
npm install
npm run generate
```

### 2. Copy Grammar to Grove

```bash
# Copy the grammar to Grove's language directory
cp -r tree-sitter-ghostlang/ path/to/grove/languages/ghostlang/
```

### 3. Register Language in Grove

Add Ghostlang to Grove's language registry:

```zig
// In Grove's language configuration
const ghostlang_config = LanguageConfig{
    .name = "ghostlang",
    .file_extensions = &[_][]const u8{ ".ghost" },
    .grammar_path = "languages/ghostlang",
    .comment_token = "//",
};
```

## Syntax Highlighting Features

### Keywords and Operators
- **Control flow**: `if`, `else`, `while`, `for`, `function`, `return`
- **Declarations**: `var`
- **Operators**: `+`, `-`, `*`, `/`, `==`, `!=`, `<`, `>`, `&&`, `||`
- **Built-ins**: Special highlighting for editor API functions

### Editor API Highlighting

The grammar specially highlights Ghostlang's editor API functions:

```javascript
// These functions get special highlighting as built-ins
getCurrentLine()
getLineText(5)
notify("Hello from plugin!")
getCursorPosition()
```

### String and Comment Support

```javascript
// Single-line comments are highlighted
var message = "String literals with escape support: \n\t";
```

## Query Files

The grammar includes four query files for different Grove features:

### highlights.scm
Defines syntax highlighting rules:
- Keywords in blue
- Strings in green
- Comments in gray
- Numbers in orange
- Editor APIs as built-ins

### locals.scm
Handles variable scoping and references:
- Function definitions
- Variable declarations
- Scope boundaries
- Reference resolution

### textobjects.scm
Smart text selection support:
- Select entire functions
- Select function parameters
- Select code blocks
- Select string contents

### injections.scm
Embedded language highlighting:
- JSON strings
- CSS in style strings
- SQL queries
- Regular expressions

## Configuration Example

```zig
// Grove configuration for Ghostlang
pub const ghostlang_support = struct {
    pub fn setupLanguage(grove: *Grove) !void {
        try grove.registerLanguage(LanguageConfig{
            .name = "ghostlang",
            .extensions = &[_][]const u8{ ".ghost" },
            .grammar_path = "languages/ghostlang",

            // Syntax highlighting
            .highlight_queries = "queries/highlights.scm",
            .locals_queries = "queries/locals.scm",
            .textobjects_queries = "queries/textobjects.scm",
            .injections_queries = "queries/injections.scm",

            // Language-specific settings
            .comment_token = "//",
            .indent_size = 4,
            .auto_indent = true,
        });
    }
};
```

## Testing the Integration

### 1. Create Test File

Create `test_plugin.ghost`:

```javascript
// Test Ghostlang syntax highlighting
function processText(input) {
    var lines = split(input, "\n");
    var result = createArray();

    for (var i = 0; i < arrayLength(lines); i++) {
        var line = arrayGet(lines, i);
        if (line != "") {
            arrayPush(result, "// " + line);
        }
    }

    return join(result, "\n");
}

// Test editor API highlighting
var currentPos = getCursorPosition();
var text = getSelectedText();
notify("Processing: " + text);
```

### 2. Verify Highlighting

Open the file in Grove and verify:
- Keywords (`function`, `var`, `for`, `if`) are highlighted
- Strings are properly colored
- Comments are styled correctly
- Editor API functions (`getCursorPosition`, `notify`) have special highlighting
- Numbers and operators are distinct

### 3. Test Navigation

Try Grove's navigation features:
- Go to function definition
- Select function parameters
- Navigate between scopes
- Text object selection

## Troubleshooting

### Grammar Not Loading
- Verify grammar files are in correct location
- Check that grammar was built successfully
- Ensure Grove language registry includes Ghostlang

### Syntax Highlighting Issues
- Verify `highlights.scm` query file is valid
- Check for syntax errors in grammar definition
- Ensure Grove can access query files

### Performance Issues
- Large files may cause parsing delays
- Consider implementing incremental parsing
- Profile grammar rules for efficiency

## Advanced Features

### Custom Theme Integration

Extend Grove themes to support Ghostlang-specific highlighting:

```zig
pub const ghostlang_theme = struct {
    pub const editor_api = Color{ .r = 100, .g = 150, .b = 200 }; // Blue for editor APIs
    pub const plugin_keyword = Color{ .r = 150, .g = 100, .b = 200 }; // Purple for plugin-specific keywords
};
```

### Code Completion Integration

Set up language server protocol support:

```zig
pub fn setupLSP(grove: *Grove) !void {
    try grove.registerLSPConfig(.{
        .language = "ghostlang",
        .server_command = &[_][]const u8{ "ghostlang-lsp", "--stdio" },
        .completion_triggers = &[_][]const u8{ ".", "(", "," },
    });
}
```

## File Association

Configure Grove to recognize Ghostlang files:

```zig
// File associations
const file_associations = &[_]FileAssociation{
    .{
        .pattern = "*.ghost",
        .language = "ghostlang",
        .icon = "🔮",
    },
    .{
        .pattern = "*.ghostlang",
        .language = "ghostlang",
        .icon = "🔮",
    },
};
```

## Summary

With this integration, Grove will provide:
- Full syntax highlighting for Ghostlang scripts
- Smart code navigation and text selection
- Language-aware editing features
- Proper file association and recognition
- Special highlighting for editor API functions

The tree-sitter grammar ensures accurate parsing and enables all modern editor features that Grove users expect from a fully supported programming language.