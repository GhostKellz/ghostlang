# Grove Integration Guide

Complete guide for integrating Ghostlang tree-sitter grammar into Grove editor for syntax highlighting and language support.

## Overview

This guide covers how to integrate the Ghostlang tree-sitter grammar into Grove, enabling full syntax highlighting, code navigation, and language-aware features for Ghostlang scripts.

**Tree-sitter Version:** 25.0+ (ABI 15)
**Ghostlang Version:** 0.1.0

## Phase A Grammar Update Prep

Upcoming Phase A work introduces full Lua-style control-flow support. Prepare the Grove grammar and test collateral with this checklist:

- **Keyword inventory** – Ensure the lexer lists `then`, `elseif`, `else`, `do`, `end`, `repeat`, `until`, `in`, and `local` as reserved tokens alongside the existing brace keywords.
- **Loop rules** – Add parsing rules for `repeat ... until` blocks and distinguish numeric vs. generic `for` loops (`for name = start, stop[, step]` and `for name, name in iterator`).
- **Function forms** – Support `local function` declarations and anonymous `function (...) ... end` expressions as statement or expression nodes.
- **Scope queries** – Update `locals.scm` to capture variables introduced by numeric/generic `for`, `repeat` loops, and local functions.
- **Highlighting** – Extend `highlights.scm` to color the new Lua keywords and treat iterator identifiers consistently.
- **Fixtures** – Create paired sample files (`phase_a_brace.ghost`, `phase_a_lua.ghost`) covering every construct in both syntaxes for regression testing.
- **CI hooks** – Add new fixtures to the grammar's `npm test` suite and wire Grove's smoke tests to load both samples.

Keep these updates on the `feature/parser-phase-a` branch so grammar work stays synchronized with parser changes.

### Immediate follow-up (main branch)

With numeric `for` loops and `repeat ... until` now live in Ghostlang’s main branch, Grove should:

- **Grammar** – Extend the existing Ghostlang grammar rules to accept `for name = start, stop[, step] do ... end` (including negative step values) and the new `repeat` block that terminates with `until <expr>`.
- **AST fields** – Emit dedicated nodes for numeric for clauses (`numeric_for`, `numeric_for_clause`, or equivalent) so LSP tooling can expose loop bounds and steps.
- **Queries** – Update `locals.scm` to mark the loop control variable as scoped and to register any auxiliary `__for_*` temporaries as internal so they stay hidden from navigation.
- **Highlights** – Add keyword captures for `repeat`, `until`, and the `do` token used by the numeric loop. Ensure iterator variables receive the same highlight class across range, numeric, and generic forms.
- **Tests** – Add fixtures mirroring the new integration test (`tests/integration_test.zig` → `Test 6`) to guarantee Grove stays in sync with runtime behavior.

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
    .file_extensions = &[_][]const u8{ ".ghost", ".gza" },
    .grammar_path = "languages/ghostlang",
    .comment_token = "//",
    .abi_version = 15,  // Tree-sitter 25.0 ABI
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

With this integration, Grove will provide:
- Full syntax highlighting for Ghostlang scripts
- Smart code navigation and text selection
- Language-aware editing features
- Proper file association and recognition (`.ghost`, `.gza`)
- Special highlighting for editor API functions
- Tree-sitter 25.0 ABI 15 performance and features

**Tree-sitter 25.0 Benefits:**
- Improved parsing performance with ABI 15
- Better error recovery and incremental parsing
- Standardized configuration via tree-sitter.json
- Enhanced query system for more precise highlighting
- Future-proof compatibility with Grove's tree-sitter 25.0 integration

The tree-sitter grammar ensures accurate parsing and enables all modern editor features that Grove users expect from a fully supported programming language.