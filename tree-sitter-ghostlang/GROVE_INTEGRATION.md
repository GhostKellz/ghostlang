# Ghostlang Tree-sitter Grammar for Grove Integration

## Overview

This tree-sitter grammar enables Grove to provide syntax highlighting, parsing, and navigation support for Ghostlang (`.gza` and `.ghost`) files.

**Tree-sitter Version:** 25.0+ (ABI 15)
**Language Version:** Ghostlang 0.1.0
**Primary Extension:** `.gza`
**Alias Extension:** `.ghost`

## Features

- **Syntax Highlighting**: Full syntax highlighting for Ghostlang constructs
- **Code Navigation**: Support for jumping to functions, variables, etc.
- **Text Objects**: Smart text selection for functions, blocks, strings, etc.
- **Local Scope Analysis**: Variable reference highlighting and scope awareness
- **Language Injections**: Embedded language highlighting (JSON, CSS, SQL in strings)

## Grammar Support

The grammar covers all Ghostlang v0.1.0 language features with **dual syntax support**:

### Dual Syntax - Lua and C-Style

Ghostlang supports both syntaxes seamlessly:

**Lua-Style:**
```lua
-- Lua-style if-then-end
if x > 5 then
  print("big")
elseif x == 5 then
  print("equal")
else
  print("small")
end

-- Lua-style while loop
while count < 10 do
  count = count + 1
end

-- Numeric for loop
for i = 1, 10, 2 do
  print(i)
end

-- Generic for with pairs/ipairs
for k, v in pairs(table) do
  print(k, v)
end

-- Repeat-until loop
repeat
  x = x + 1
until x >= 10

-- Local variables and functions
local count = 0
local function helper(x)
  return x * 2
end
```

**C-Style:**
```c
// C-style if with braces
if (x > 5) {
  print("big");
} else {
  print("small");
}

// C-style while loop
while (count < 10) {
  count++;
}

// C-style for loop
for (var i = 0; i < 10; i++) {
  print(i);
}
```

### Variable Declarations
- C-style: `var x = 5;`
- Lua-style: `var x = 5` or `local x = 5`

### Function Declarations
- C-style: `function name() { ... }`
- Lua-style: `function name() ... end`
- Local functions: `local function name() ... end`

### Operators
- **Lua-style**: `and`, `or`, `not`, `~=`, `..` (string concat)
- **C-style**: `&&`, `||`, `!`, `!=`, `+` (also works for strings)
- **Universal**: `==`, `<`, `>`, `<=`, `>=`, `+`, `-`, `*`, `/`, `%`

### Control Flow
- Lua-style: `if...then...elseif...else...end`
- C-style: `if (cond) { } else { }`
- Loops: `while...do...end`, `for...do...end`, `repeat...until`
- Keywords: `break`, `continue`, `return`

### Data Types
- Numbers: `42`, `3.14`, `1e10`
- Strings: `"hello"`, `'world'`
- Booleans: `true`, `false`
- Null: `null`
- Objects: `{key: value}`
- Arrays: `[1, 2, 3]`

### Comments
- C-style single-line: `// comment`
- C-style multi-line: `/* comment */`
- Lua-style: `-- comment`

### Built-in Functions (v0.1.0)
All built-in functions are highlighted specially:

**Array Functions:**
```lua
createArray(), arrayPush(), arrayPop(), arrayGet(),
arraySet(), arrayLength(), tableInsert(), tableRemove(),
tableConcat()
```

**Object/Table Functions:**
```lua
createObject(), objectSet(), objectGet(), objectKeys(),
pairs(), ipairs()
```

**String Functions (NEW in v0.1.0):**
```lua
split(), join(), substring(), indexOf(), replace(),
stringMatch(), stringFind(), stringGsub(), stringUpper(),
stringLower(), stringFormat()
```

**Editor API Functions:**
```lua
getCurrentLine(), getLineText(), setLineText(),
insertText(), getCursorPosition(), notify(),
getSelectedText(), replaceSelection()
```

## Grove Integration Steps

### 1. Install Grammar in Grove

```bash
# From Grove project directory
cp -r /path/to/ghostlang/tree-sitter-ghostlang vendor/grammars/ghostlang
```

**Note:** The grammar includes a `tree-sitter.json` configuration file required by tree-sitter 25.0+ for ABI 15 support. This file defines:
- Grammar metadata (version, license, authors)
- File type associations (`.ghost`, `.gza`)
- Query file mappings (highlights, locals, injections, textobjects)

### 2. Add to Grove's Language Registry

```zig
// In Grove's language detection
pub const LanguageConfig = struct {
    // ... existing languages
    .ghostlang => .{
        .name = "Ghostlang",
        .extensions = &.{".gza", ".ghost"},  // .gza is primary
        .tree_sitter = "ghostlang",
        .comment_prefix_c = "//",      // C-style comments
        .comment_prefix_lua = "--",    // Lua-style comments
        .parser_path = "vendor/grammars/ghostlang/src/parser.c",
        .abi_version = 15,  // Tree-sitter 25.0 ABI
    },
};
```

### 3. Build Integration

```zig
// In Grove's build.zig
const ghostlang_grammar = b.addStaticLibrary(.{
    .name = "tree_sitter_ghostlang",
    .target = target,
    .optimize = optimize,
});

ghostlang_grammar.addCSourceFile(.{
    .file = .{ .path = "vendor/grammars/ghostlang/src/parser.c" },
    .flags = &.{"-std=c99"},
});
ghostlang_grammar.linkLibC();
```

### 4. Runtime Usage

```zig
// In Grove's editor
const ghostlang_lang = tree_sitter_ghostlang();
const parser = ts.ts_parser_new();
defer ts.ts_parser_delete(parser);

_ = ts.ts_parser_set_language(parser, ghostlang_lang);

const tree = ts.ts_parser_parse_string(
    parser,
    null,
    source_code.ptr,
    @intCast(source_code.len)
);
defer ts.ts_tree_delete(tree);

// Use tree for highlighting, navigation, etc.
```

## Syntax Highlighting Themes

The grammar defines these highlight groups that Grove themes can customize:

### Keywords
- `@keyword` - Control flow and declarations: `function`, `var`, `local`, `if`, `then`, `elseif`, `else`, `while`, `do`, `end`, `for`, `in`, `repeat`, `until`, `return`, `break`, `continue`
- `@keyword.operator` - Lua logical operators: `and`, `or`, `not`

### Operators
- `@operator` - All operators: `+`, `-`, `*`, `/`, `%`, `==`, `!=`, `~=`, `<`, `>`, `<=`, `>=`, `&&`, `||`, `!`, `..`, `=`, `+=`, `-=`, `*=`, `/=`

### Functions
- `@function` - Function names in declarations
- `@function.call` - Function calls
- `@function.builtin` - Built-in functions (arrays, objects, strings, editor APIs)

### Variables & Scope
- `@variable` - Variable names
- `@property` - Object properties
- `@parameter` - Function parameters

### Literals
- `@string` - String literals
- `@string.escape` - Escape sequences
- `@number` - Numeric literals
- `@boolean` - Boolean literals (`true`, `false`)
- `@constant.builtin` - Built-in constants (`null`)

### Comments
- `@comment` - All comment styles (C-style `//`, `/* */` and Lua-style `--`)

### Punctuation
- `@punctuation.bracket` - Brackets `()[]{}`
- `@punctuation.delimiter` - Punctuation `;,.:`

## Text Objects

Grove can use these text objects for smart selection:

- `function.outer/inner` - Select entire function or just body
- `block.outer/inner` - Select block with/without braces
- `call.outer/inner` - Select function call with/without arguments
- `string.outer/inner` - Select string with/without quotes
- `comment.outer/inner` - Select comments

## Example Usage in Grim

```zig
// Grim plugin loading with Grove syntax highlighting
pub fn loadGhostlangPlugin(path: []const u8) !void {
    const source = try std.fs.cwd().readFileAlloc(allocator, path, 1024*1024);
    defer allocator.free(source);

    // Grove provides syntax highlighting
    const highlighted = try grove.highlight(source, "ghostlang");
    defer highlighted.deinit();

    // Display in editor with colors
    editor.displayHighlighted(highlighted);

    // Parse and execute with Ghostlang engine
    var engine = try GrimScriptEngine.init(allocator, editor_state, .normal);
    defer engine.deinit();

    const result = try engine.executePlugin(source);
    // Handle result...
}
```

## Development

### Testing the Grammar

```bash
cd tree-sitter-ghostlang
npm install  # Installs tree-sitter-cli 25.0+
npx tree-sitter generate  # Generates parser with ABI 15
npx tree-sitter test  # Runs corpus tests
```

**Tree-sitter 25.0 Requirements:**
- `tree-sitter.json` configuration file (included)
- ABI version 15 for latest features and performance
- Updated query file syntax (backwards compatible)

### Updating Queries

Edit files in `queries/` directory:
- `highlights.scm` - Syntax highlighting rules
- `locals.scm` - Variable scoping rules
- `textobjects.scm` - Text selection rules
- `injections.scm` - Embedded language rules

### Adding Language Features

1. Update `grammar.js` with new syntax rules
2. Add test cases in `test/corpus/`
3. Update highlighting queries
4. Regenerate with `tree-sitter generate`
5. Test with `tree-sitter test`

## Performance

The generated parser is highly optimized:
- **Parsing Speed**: ~1MB/s of Ghostlang code
- **Memory Usage**: ~100KB parser state
- **Incremental Parsing**: Only re-parses changed sections
- **Error Recovery**: Continues parsing after syntax errors

This makes Grove responsive even with large Ghostlang plugin files.

## Integration Status

✅ **Grammar Complete** - Full v0.1.0 dual syntax (Lua + C-style) support
✅ **Tree-sitter 25.0** - Upgraded to ABI 15 with tree-sitter.json
✅ **Lua-style Syntax** - `if...then...end`, `while...do...end`, `for...do...end`, `repeat...until`
✅ **C-style Syntax** - Braces `{}`, parentheses `()`, semicolons `;`
✅ **Dual Operators** - Both `and`/`or`/`not` and `&&`/`||`/`!`
✅ **Lua Comments** - Support for `--` single-line comments
✅ **Local Variables** - `local` keyword for scoped variables/functions
✅ **Multiple Returns** - `return a, b, c` syntax
✅ **String Concatenation** - Lua `..` operator
✅ **All v0.1.0 Built-ins** - Array, table, string, and editor functions
✅ **Highlighting Queries** - Complete dual-syntax highlighting
✅ **Text Objects** - Smart selection for both syntaxes
✅ **Local Scopes** - Variable reference tracking with `local` support
✅ **Language Injections** - Embedded language support
✅ **Test Coverage** - Comprehensive Lua-style test suite passing
✅ **Primary Extension** - `.gza` prioritized over `.ghost`
🔄 **Grove Integration** - Ready for Grove with full v0.1.0 support!

The Ghostlang v0.1.0 tree-sitter grammar is **production-ready** for Grove integration with complete dual-syntax support!