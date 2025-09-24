# Grim Editor Integration Guide

This guide shows how to integrate **Ghostlang** as the scripting engine for the **Grim** editor (Neovim clone).

## Overview

Ghostlang serves as the configuration and plugin language for Grim, providing:

- **Configuration scripts** for editor settings
- **Plugin development** with full language features
- **Event handling** for editor events
- **Text processing** and manipulation
- **Memory-safe execution** with sandboxing

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Grim Editor    │◄──►│  Ghostlang VM    │◄──►│ User Scripts    │
│  (Zig Core)     │    │  (Embedded)      │    │ (.gza files)    │
├─────────────────┤    ├──────────────────┤    ├─────────────────┤
│ • Buffer Mgmt   │    │ • Script Engine  │    │ • config.gza    │
│ • Event System  │    │ • FFI Bindings   │    │ • plugins/      │
│ • Command Proc  │    │ • Memory Safety  │    │ • keybinds.gza  │
│ • File I/O      │    │ • Sandboxing     │    │ • themes/       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Integration Setup

### 1. Embedding Ghostlang in Grim

```zig
// grim/src/scripting.zig
const std = @import("std");
const ghostlang = @import("ghostlang");

pub const ScriptingEngine = struct {
    engine: *ghostlang.ScriptEngine,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !ScriptingEngine {
        const config = ghostlang.EngineConfig{
            .allocator = allocator,
            .execution_timeout_ms = 5000, // 5 second timeout
        };

        var engine = try ghostlang.ScriptEngine.create(config);

        // Register editor functions
        try registerEditorFunctions(engine);

        return ScriptingEngine{
            .engine = engine,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ScriptingEngine) void {
        self.engine.deinit();
    }
};
```

### 2. Registering Editor Functions

```zig
fn registerEditorFunctions(engine: *ghostlang.ScriptEngine) !void {
    // Buffer operations
    try engine.registerFunction("get_current_buffer", getCurrentBuffer);
    try engine.registerFunction("create_buffer", createBuffer);
    try engine.registerFunction("buffer_get_line", bufferGetLine);
    try engine.registerFunction("buffer_set_line", bufferSetLine);
    try engine.registerFunction("buffer_insert", bufferInsert);
    try engine.registerFunction("buffer_delete", bufferDelete);

    // Cursor operations
    try engine.registerFunction("get_cursor", getCursor);
    try engine.registerFunction("set_cursor", setCursor);
    try engine.registerFunction("move_cursor", moveCursor);

    // Window operations
    try engine.registerFunction("split_window", splitWindow);
    try engine.registerFunction("close_window", closeWindow);
    try engine.registerFunction("resize_window", resizeWindow);

    // Editor operations
    try engine.registerFunction("register_command", registerCommand);
    try engine.registerFunction("register_keymap", registerKeymap);
    try engine.registerFunction("register_event_handler", registerEventHandler);

    // File operations (already provided by ghostlang)
    // file_read, file_write, file_exists, file_delete
}
```

### 3. FFI Function Implementations

```zig
// Buffer FFI functions
fn getCurrentBuffer(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    // Get the current buffer from Grim's buffer manager
    const buffer_id = grim.buffer_manager.getCurrentBufferId();
    return ghostlang.ScriptValue{ .number = @floatFromInt(buffer_id) };
}

fn bufferGetLine(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    if (args.len != 2) return ghostlang.ScriptValue{ .nil = {} };

    const buffer_id = @as(u32, @intFromFloat(args[0].number));
    const line_num = @as(u32, @intFromFloat(args[1].number));

    if (grim.buffer_manager.getLine(buffer_id, line_num)) |line_content| {
        return ghostlang.ScriptValue{
            .owned_string = std.mem.dupe(u8, line_content) catch return ghostlang.ScriptValue{ .nil = {} }
        };
    }

    return ghostlang.ScriptValue{ .nil = {} };
}

fn registerCommand(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    if (args.len != 2) return ghostlang.ScriptValue{ .boolean = false };

    const cmd_name = args[0].string;
    const cmd_function = args[1]; // Store function reference

    // Register command in Grim's command system
    grim.command_manager.registerCommand(cmd_name, cmd_function) catch {
        return ghostlang.ScriptValue{ .boolean = false };
    };

    return ghostlang.ScriptValue{ .boolean = true };
}
```

## Configuration System

### Basic Configuration (`~/.config/grim/init.gza`)

```lua
-- Grim Editor Configuration
local config = {
    -- Editor settings
    line_numbers = true,
    relative_line_numbers = false,
    word_wrap = false,
    tab_width = 4,
    auto_indent = true,

    -- Theme settings
    theme = "dark",
    color_scheme = "monokai",

    -- Window settings
    split_below = true,
    split_right = true,

    -- File settings
    auto_save = false,
    backup_files = true
}

-- Apply configuration
for key, value in pairs(config) do
    set_option(key, value)
end

-- Load additional config files
require("keybindings")
require("plugins/init")
```

### Key Bindings (`~/.config/grim/keybindings.gza`)

```lua
-- Grim Key Bindings
local keymap = register_keymap

-- Normal mode bindings
keymap("n", "<leader>w", ":write<CR>", { desc = "Save file" })
keymap("n", "<leader>q", ":quit<CR>", { desc = "Quit" })
keymap("n", "<leader>e", ":edit<CR>", { desc = "Edit file" })

-- Buffer navigation
keymap("n", "<leader>bn", ":bnext<CR>", { desc = "Next buffer" })
keymap("n", "<leader>bp", ":bprev<CR>", { desc = "Previous buffer" })
keymap("n", "<leader>bd", ":bdelete<CR>", { desc = "Delete buffer" })

-- Window management
keymap("n", "<leader>sv", ":vsplit<CR>", { desc = "Vertical split" })
keymap("n", "<leader>sh", ":split<CR>", { desc = "Horizontal split" })
keymap("n", "<leader>sc", ":close<CR>", { desc = "Close window" })

-- Custom functions
keymap("n", "<leader>ff", function()
    local current_file = get_current_file()
    print("Current file: " .. current_file)
end, { desc = "Show current file" })

-- Plugin keybindings
keymap("n", "<leader>t", ":ToggleTreeView<CR>", { desc = "Toggle file tree" })
keymap("n", "<leader>f", ":FuzzyFind<CR>", { desc = "Fuzzy file finder" })
```

## Plugin Development

### Plugin Structure

```lua
-- plugins/auto-formatter.gza
local plugin = {
    name = "auto-formatter",
    version = "1.0.0",
    author = "Grim Community",
    description = "Automatic code formatting plugin"
}

-- Plugin state
local state = {
    enabled = true,
    format_on_save = true,
    supported_languages = ["rust", "zig", "javascript", "python"]
}

-- Main plugin functionality
function format_current_buffer()
    local buffer_id = get_current_buffer()
    local filetype = get_buffer_filetype(buffer_id)

    if !array_contains(state.supported_languages, filetype) then
        print("Formatting not supported for " .. filetype)
        return false
    end

    -- Get current content
    local line_count = get_buffer_line_count(buffer_id)
    local content = {}

    for i = 0, line_count - 1 do
        local line = buffer_get_line(buffer_id, i)
        array_push(content, line)
    end

    -- Format content (call external formatter)
    local formatted = call_formatter(filetype, array_join(content, "\n"))

    if formatted && formatted != array_join(content, "\n") then
        -- Replace buffer content
        local formatted_lines = str_split(formatted, "\n")
        replace_buffer_content(buffer_id, formatted_lines)
        print("Buffer formatted successfully")
        return true
    end

    return false
end

-- Event handlers
function on_buffer_save(buffer_id)
    if state.enabled && state.format_on_save then
        format_current_buffer()
    end
end

function on_text_changed(buffer_id, line, column, text)
    if state.enabled && (text == "}" || text == ";") then
        -- Format current function/block
        format_current_scope(buffer_id, line)
    end
end

-- Plugin initialization
function init()
    print("Auto-formatter plugin loaded")

    -- Register commands
    register_command("Format", format_current_buffer)
    register_command("ToggleFormatOnSave", function()
        state.format_on_save = !state.format_on_save
        print("Format on save: " .. (state.format_on_save && "enabled" || "disabled"))
    end)

    -- Register event handlers
    register_event_handler("buffer_save", on_buffer_save)
    register_event_handler("text_changed", on_text_changed)

    return true
end

-- Plugin cleanup
function deinit()
    print("Auto-formatter plugin unloaded")
end

return plugin
```

### Advanced Plugin: File Tree

```lua
-- plugins/file-tree.gza
local tree_state = {
    visible = false,
    width = 30,
    current_dir = get_cwd(),
    expanded_dirs = {}
}

function toggle_tree()
    if tree_state.visible then
        close_tree_window()
    else
        open_tree_window()
    end
    tree_state.visible = !tree_state.visible
end

function open_tree_window()
    -- Create vertical split
    local tree_win = create_window({
        type = "split",
        direction = "vertical",
        size = tree_state.width
    })

    -- Populate tree content
    refresh_tree_content(tree_win)

    -- Set window-specific keybindings
    set_window_keymap(tree_win, "n", "<CR>", function()
        local line = get_current_line()
        local file_path = parse_tree_line(line)
        if is_directory(file_path) then
            toggle_directory(file_path)
        else
            open_file(file_path)
        end
    end)
end

function refresh_tree_content(window)
    local tree_lines = generate_tree_lines(tree_state.current_dir, 0)
    set_window_content(window, tree_lines)
end

function generate_tree_lines(dir_path, depth)
    local lines = []
    local entries = list_directory(dir_path)

    for entry in entries do
        local indent = str_repeat("  ", depth)
        local icon = is_directory(entry) && "📁 " || "📄 "
        local line = indent .. icon .. get_basename(entry)
        array_push(lines, line)

        -- Add expanded subdirectories
        if is_directory(entry) && is_expanded(entry) then
            local sub_lines = generate_tree_lines(entry, depth + 1)
            for sub_line in sub_lines do
                array_push(lines, sub_line)
            end
        end
    end

    return lines
end

-- Register plugin
register_command("ToggleTreeView", toggle_tree)
```

## Event System Integration

### Editor Events

Grim can emit events that Ghostlang scripts can handle:

```lua
-- Event handlers registration
register_event_handler("buffer_created", function(buffer_id)
    print("New buffer created: " .. buffer_id)
end)

register_event_handler("buffer_opened", function(buffer_id, filename)
    print("Opened file: " .. filename)
    -- Auto-detect file type and apply settings
    local filetype = detect_filetype(filename)
    set_buffer_option(buffer_id, "filetype", filetype)
end)

register_event_handler("cursor_moved", function(buffer_id, line, column)
    -- Update status line
    update_status_line("Line " .. line .. ", Col " .. column)
end)

register_event_handler("text_inserted", function(buffer_id, line, column, text)
    -- Auto-completion logic
    if text == "." then
        trigger_completion(buffer_id, line, column)
    end
end)
```

## Performance Considerations

### Script Sandboxing

```zig
// Configure execution limits
const config = ghostlang.EngineConfig{
    .allocator = allocator,
    .execution_timeout_ms = 1000,      // 1 second timeout
    .max_memory_usage = 10 * 1024 * 1024, // 10MB memory limit
};
```

### Hot Reloading

```lua
-- Development mode: auto-reload config on changes
if development_mode then
    register_event_handler("file_changed", function(filename)
        if str_find(filename, ".gza") then
            print("Reloading: " .. filename)
            reload_script(filename)
        end
    end)
end
```

## Benefits Over Lua

1. **Memory Safety**: No manual memory management
2. **Better Error Handling**: Clear error propagation and sandboxing
3. **Modern Syntax**: Familiar to developers from other languages
4. **Zig Integration**: Seamless interop with Grim's Zig codebase
5. **Type Safety**: Better static analysis possibilities

## Migration from Lua/Vimscript

### Common Patterns

```lua
-- Lua/Vimscript → Ghostlang

-- Variable assignment
vim.opt.number = true          → set_option("line_numbers", true)
vim.keymap.set("n", "<leader>w", ":w<CR>") → register_keymap("n", "<leader>w", ":write<CR>")

-- Function definitions
function MyFunction()          → function my_function()
  return "hello"                   return "hello"
end                           → end

-- Conditional logic
if vim.bo.filetype == "lua"   → if get_buffer_filetype(buffer_id) == "lua" then
  -- do something                 -- do something
end                           → end
```

---

This guide provides the foundation for integrating Ghostlang with the Grim editor. For more examples, see the [examples directory](examples/).