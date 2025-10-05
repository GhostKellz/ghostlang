# Grove Integration Guide - Ghostlang v0.1.0

Complete guide for integrating Ghostlang v0.1.0 tree-sitter grammar into Grove editor for syntax highlighting and language support.

## Overview

This guide covers how to integrate the Ghostlang v0.1.0 tree-sitter grammar into Grove, enabling full syntax highlighting, code navigation, and language-aware features for Ghostlang scripts with **dual Lua/C-style syntax support**.

**Tree-sitter Version:** 25.0+ (ABI 15)
**Ghostlang Version:** 0.1.0
**Primary Extension:** `.gza`
**Alias Extension:** `.ghost`
**Syntax Support:** Lua-style AND C-style (dual syntax)

## ✅ v0.1.0 Grammar Status - COMPLETE!

All Lua-style and C-style syntax features from the v0.1.0 release are **fully implemented** in the tree-sitter grammar:

### Implemented Features

✅ **Keywords** – `then`, `elseif`, `else`, `do`, `end`, `repeat`, `until`, `in`, `local` all supported
✅ **Loop Rules** – All loop types fully parsed:
   - `repeat ... until <condition>` blocks
   - Numeric `for i = start, stop, step do ... end`
   - Generic `for k, v in pairs(table) do ... end`
   - Generic `for idx, val in ipairs(array) do ... end`
   - C-style `for (init; cond; update) { ... }`
✅ **Function Forms** – Complete support:
   - `local function name() ... end`
   - `function name() ... end`
   - `function name() { ... }` (C-style)
   - Anonymous functions
✅ **Scope Queries** – `locals.scm` updated for:
   - Numeric/generic `for` loop variables
   - `repeat` loop scoping
   - `local` function declarations
   - All iterator variables
✅ **Highlighting** – `highlights.scm` includes:
   - All Lua keywords (`then`, `elseif`, `do`, `end`, `repeat`, `until`, `local`)
   - Lua operators (`and`, `or`, `not`, `~=`, `..`)
   - C-style operators (`&&`, `||`, `!`, `!=`)
   - All v0.1.0 built-in functions
✅ **Comments** – Both C-style (`//`, `/* */`) and Lua-style (`--`) supported
✅ **Tests** – Comprehensive test suite in `test/corpus/lua_style.txt` with 20+ test cases
✅ **Multiple Returns** – `return a, b, c` fully supported
✅ **Break/Continue** – Both keywords supported in loops

### No Further Updates Needed

The grammar is **production-ready** and fully aligned with Ghostlang v0.1.0. All syntax variants (Lua-style and C-style) parse correctly.

## Prerequisites

- Grove editor with tree-sitter 25.0+ support
- Ghostlang tree-sitter grammar (included in `tree-sitter-ghostlang/`)
- Node.js and npm (for building the grammar)
- Tree-sitter.json configuration (included)

## Installation

### 1. Build the Tree-sitter Grammar

```bash
cd tree-sitter-ghostlang
npm install  # Installs tree-sitter-cli 25.0+
npm run generate  # Generates parser with ABI 15
npm test  # Verify grammar works
```

**Tree-sitter 25.0 Changes:**
- Grammar now uses `tree-sitter.json` for configuration (replaces package.json metadata)
- ABI version 15 for improved performance and features
- All query files are specified in tree-sitter.json

### 2. Copy Grammar to Grove

```bash
# Copy the grammar to Grove's language directory (includes tree-sitter.json)
cp -r tree-sitter-ghostlang/ path/to/grove/languages/ghostlang/
```

### 3. Register Language in Grove

Add Ghostlang to Grove's language registry:

```zig
// In Grove's language configuration
const ghostlang_config = LanguageConfig{
    .name = "ghostlang",
    .file_extensions = &[_][]const u8{ ".gza", ".ghost" },  // .gza is primary!
    .grammar_path = "languages/ghostlang",
    .comment_token_c = "//",   // C-style comments
    .comment_token_lua = "--", // Lua-style comments
    .abi_version = 15,  // Tree-sitter 25.0 ABI
};
```

## Syntax Highlighting Features

### Keywords and Operators (v0.1.0 - Dual Syntax)

**Lua-style Keywords:**
- Control flow: `if`, `then`, `elseif`, `else`, `end`, `while`, `do`, `for`, `in`, `repeat`, `until`
- Declarations: `var`, `local`, `function`, `return`, `break`, `continue`
- Logical operators: `and`, `or`, `not`

**C-style Keywords:**
- Control flow: `if`, `else`, `while`, `for`, `function`, `return`, `break`, `continue`
- Declarations: `var`
- Braces and semicolons: `{`, `}`, `;`

**Universal Operators:**
- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Comparison: `<`, `>`, `<=`, `>=`, `==`
- Inequality: `!=` (C-style), `~=` (Lua-style)
- Logical: `&&`/`and`, `||`/`or`, `!`/`not`
- String concatenation: `..` (Lua-style)
- Assignment: `=`, `+=`, `-=`, `*=`, `/=`

**Built-in Functions:**
Special highlighting for all v0.1.0 functions including:
- Array: `createArray`, `arrayPush`, `arrayPop`, `arrayGet`, `arraySet`, `arrayLength`, `tableInsert`, `tableRemove`, `tableConcat`
- Object/Table: `createObject`, `objectSet`, `objectGet`, `objectKeys`, `pairs`, `ipairs`
- String: `split`, `join`, `substring`, `indexOf`, `replace`, `stringMatch`, `stringFind`, `stringGsub`, `stringUpper`, `stringLower`, `stringFormat`
- Editor APIs: `getCurrentLine`, `getLineText`, `notify`, etc.

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

Create `test_plugin.gza`:

```lua
-- Test Ghostlang v0.1.0 dual-syntax highlighting

-- Lua-style function
function processText(input)
  local lines = split(input, "\n")
  local result = createArray()

  for i = 1, arrayLength(lines) do
    local line = arrayGet(lines, i)
    if line ~= "" then
      arrayPush(result, "-- " .. line)
    end
  end

  return join(result, "\n")
end

-- C-style function with braces
function processData(data) {
  var count = 0;
  for (var i = 0; i < arrayLength(data); i++) {
    if (data[i] > 10) {
      count++;
    }
  }
  return count;
}

-- Lua-style generic for with pairs
for key, value in pairs(config) do
  print(key .. ": " .. value)
end

-- Test editor API highlighting
local currentPos = getCursorPosition()
local text = getSelectedText()
notify("Processing: " .. text)

-- String functions (new in v0.1.0)
local upper = stringUpper("hello")
local formatted = stringFormat("Count: %d", 42)
```

### 2. Verify Highlighting

Open the file in Grove and verify:
- **Lua keywords** (`then`, `end`, `do`, `elseif`, `local`, `repeat`, `until`) are highlighted
- **C-style keywords** (`function`, `var`, `for`, `if`, `else`, `while`, `return`) are highlighted
- **Lua operators** (`and`, `or`, `not`, `~=`, `..`) are distinct from C-style (`&&`, `||`, `!`, `!=`)
- **Comments** work in both styles (`--` Lua and `//` C-style)
- **Strings** are properly colored
- **Editor API functions** (`getCursorPosition`, `notify`) have special highlighting
- **Built-in functions** (`arrayPush`, `pairs`, `ipairs`, `stringUpper`, etc.) are highlighted
- **Numbers** and **operators** are distinct
- **Local variables** are recognized with proper scoping

### 3. Test Navigation

Try Grove's navigation features:
- Go to function definition
- Select function parameters
- Navigate between scopes
- Text object selection

## Troubleshooting

### Grammar Not Loading
- Verify grammar files are in correct location
- Check that grammar was built successfully with tree-sitter 25.0
- Ensure Grove language registry includes Ghostlang
- Verify `tree-sitter.json` is present and valid
- Check ABI version compatibility (should be 15)

### Syntax Highlighting Issues
- Verify `highlights.scm` query file is valid
- Check for syntax errors in grammar definition
- Ensure Grove can access query files specified in tree-sitter.json
- Validate tree-sitter.json query paths are correct

### Performance Issues
- Large files may cause parsing delays
- Tree-sitter 25.0 ABI 15 includes performance improvements
- Use incremental parsing features (built into tree-sitter 25.0)
- Profile grammar rules for efficiency

### Tree-sitter 25.0 Migration Issues
- Ensure tree-sitter.json exists with proper format
- Verify ABI version 15 is set in Grove config
- Check that all query files are listed in tree-sitter.json
- Rebuild grammar after updating to 25.0

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

With this v0.1.0 integration, Grove will provide:

### Syntax Support
- ✅ **Full Lua-style syntax**: `if...then...end`, `while...do...end`, `for...do...end`, `repeat...until`
- ✅ **Full C-style syntax**: Braces `{}`, parentheses `()`, semicolons `;`
- ✅ **Dual operators**: Both `and`/`or`/`not` AND `&&`/`||`/`!`
- ✅ **Dual comments**: Lua `--` AND C-style `//`, `/* */`
- ✅ **Local scoping**: `local` keyword for variables and functions
- ✅ **Multiple returns**: `return a, b, c` syntax
- ✅ **String concatenation**: Lua `..` operator

### Features
- ✅ **Complete syntax highlighting** for both Lua and C-style code
- ✅ **Smart code navigation** and text selection for all constructs
- ✅ **Language-aware editing** with proper scoping
- ✅ **File association**: Primary `.gza`, alias `.ghost`
- ✅ **Special highlighting** for all v0.1.0 built-in functions:
  - Array functions (`arrayPush`, `tableInsert`, etc.)
  - Object/table functions (`pairs`, `ipairs`, `objectKeys`)
  - String functions (`stringUpper`, `stringFormat`, `stringGsub`)
  - Editor API functions (`getCurrentLine`, `notify`, etc.)
- ✅ **Tree-sitter 25.0** ABI 15 performance and features

### Performance Benefits
- Improved parsing performance with ABI 15
- Better error recovery and incremental parsing
- Standardized configuration via tree-sitter.json
- Enhanced query system for precise dual-syntax highlighting
- Future-proof compatibility with Grove's tree-sitter 25.0 integration

**The Ghostlang v0.1.0 tree-sitter grammar is production-ready and provides complete dual Lua/C-style syntax support for Grove!** 🚀