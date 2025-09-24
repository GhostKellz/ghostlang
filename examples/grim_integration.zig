const std = @import("std");
const ghostlang = @import("ghostlang");

// Grim-specific ScriptEngine configuration templates and integration patterns

pub const GrimPluginConfig = struct {
    // Security levels for different plugin types
    pub const SecurityLevel = enum {
        trusted,     // Full access, longer timeouts
        normal,      // Standard restrictions
        sandboxed,   // Heavily restricted
    };

    // Pre-configured settings for different use cases
    pub fn createConfig(allocator: std.mem.Allocator, level: SecurityLevel) ghostlang.EngineConfig {
        return switch (level) {
            .trusted => ghostlang.EngineConfig{
                .allocator = allocator,
                .memory_limit = 64 * 1024 * 1024,  // 64MB for complex plugins
                .execution_timeout_ms = 30000,      // 30 seconds for heavy operations
                .allow_io = false,                  // Still no direct file access
                .allow_syscalls = false,            // No system calls
                .deterministic = false,             // Allow timestamps, random
            },
            .normal => ghostlang.EngineConfig{
                .allocator = allocator,
                .memory_limit = 16 * 1024 * 1024,  // 16MB for typical plugins
                .execution_timeout_ms = 5000,       // 5 seconds
                .allow_io = false,
                .allow_syscalls = false,
                .deterministic = false,
            },
            .sandboxed => ghostlang.EngineConfig{
                .allocator = allocator,
                .memory_limit = 4 * 1024 * 1024,   // 4MB for untrusted plugins
                .execution_timeout_ms = 2000,       // 2 seconds
                .allow_io = false,
                .allow_syscalls = false,
                .deterministic = true,              // Fully deterministic
            },
        };
    }
};

// Mock Grim types for demonstration
pub const GrimBuffer = struct {
    id: u32,
    content: []u8,
    cursor_line: usize,
    cursor_col: usize,
    filename: ?[]const u8,
    language: []const u8,
    modified: bool,

    pub fn getLineText(self: *GrimBuffer, line: usize) []const u8 {
        _ = self;
        _ = line;
        return "mock line text";
    }

    pub fn setLineText(self: *GrimBuffer, line: usize, text: []const u8) void {
        _ = self;
        _ = line;
        _ = text;
    }

    pub fn insertText(self: *GrimBuffer, text: []const u8) void {
        _ = self;
        _ = text;
    }
};

pub const GrimEditorState = struct {
    active_buffer: ?*GrimBuffer,
    buffers: std.ArrayList(*GrimBuffer),

    pub fn getActiveBuffer(self: *GrimEditorState) ?*GrimBuffer {
        return self.active_buffer;
    }
};

// Main Grim integration layer
pub const GrimScriptEngine = struct {
    engine: ghostlang.ScriptEngine,
    editor_state: *GrimEditorState,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator,
                editor_state: *GrimEditorState,
                security_level: GrimPluginConfig.SecurityLevel) !GrimScriptEngine {

        const config = GrimPluginConfig.createConfig(allocator, security_level);
        const engine = try ghostlang.ScriptEngine.create(config);

        var grim_engine = GrimScriptEngine{
            .engine = engine,
            .editor_state = editor_state,
            .allocator = allocator,
        };

        try grim_engine.registerEditorAPI();
        return grim_engine;
    }

    pub fn deinit(self: *GrimScriptEngine) void {
        self.engine.deinit();
    }

    // Register all editor APIs that plugins can use
    fn registerEditorAPI(self: *GrimScriptEngine) !void {
        // Buffer operations
        try self.engine.registerFunction("getCurrentLine", getCurrentLineWrapper);
        try self.engine.registerFunction("getLineText", getLineTextWrapper);
        try self.engine.registerFunction("setLineText", setLineTextWrapper);
        try self.engine.registerFunction("insertText", insertTextWrapper);
        try self.engine.registerFunction("getAllText", getAllTextWrapper);
        try self.engine.registerFunction("replaceAllText", replaceAllTextWrapper);
        try self.engine.registerFunction("getLineCount", getLineCountWrapper);

        // Cursor operations
        try self.engine.registerFunction("getCursorPosition", getCursorPositionWrapper);
        try self.engine.registerFunction("setCursorPosition", setCursorPositionWrapper);
        try self.engine.registerFunction("moveCursor", moveCursorWrapper);

        // Selection operations
        try self.engine.registerFunction("getSelection", getSelectionWrapper);
        try self.engine.registerFunction("setSelection", setSelectionWrapper);
        try self.engine.registerFunction("getSelectedText", getSelectedTextWrapper);
        try self.engine.registerFunction("replaceSelection", replaceSelectionWrapper);
        try self.engine.registerFunction("selectWord", selectWordWrapper);
        try self.engine.registerFunction("selectLine", selectLineWrapper);

        // File operations (safe, through Grim)
        try self.engine.registerFunction("getFilename", getFilenameWrapper);
        try self.engine.registerFunction("getFileLanguage", getFileLanguageWrapper);
        try self.engine.registerFunction("isModified", isModifiedWrapper);

        // Editor utilities
        try self.engine.registerFunction("notify", notifyWrapper);
        try self.engine.registerFunction("prompt", promptWrapper);
        try self.engine.registerFunction("log", logWrapper);

        // Advanced operations
        try self.engine.registerFunction("findAll", findAllWrapper);
        try self.engine.registerFunction("replaceAll", replaceAllWrapper);
        try self.engine.registerFunction("matchesPattern", matchesPatternWrapper);
    }

    // Plugin execution with error handling
    pub fn executePlugin(self: *GrimScriptEngine, plugin_source: []const u8) !ghostlang.ScriptValue {
        var script = self.engine.loadScript(plugin_source) catch |err| {
            const error_msg = switch (err) {
                ghostlang.ExecutionError.ParseError => "Plugin has syntax errors",
                ghostlang.ExecutionError.MemoryLimitExceeded => "Plugin uses too much memory",
                else => "Failed to load plugin",
            };
            try self.notifyUser(error_msg);
            return .{ .nil = {} };
        };
        defer script.deinit();

        const result = script.run() catch |err| {
            const error_msg = switch (err) {
                ghostlang.ExecutionError.ExecutionTimeout => "Plugin execution timed out",
                ghostlang.ExecutionError.TypeError => "Plugin type error",
                ghostlang.ExecutionError.FunctionNotFound => "Plugin uses undefined function",
                ghostlang.ExecutionError.SecurityViolation => "Plugin violates security policy",
                else => "Plugin execution failed",
            };
            try self.notifyUser(error_msg);
            return .{ .nil = {} };
        };

        return result;
    }

    pub fn callPluginFunction(self: *GrimScriptEngine, function_name: []const u8, args: anytype) !ghostlang.ScriptValue {
        const result = self.engine.call(function_name, args) catch |err| {
            const error_msg = switch (err) {
                ghostlang.ExecutionError.FunctionNotFound => "Function not found in plugin",
                ghostlang.ExecutionError.ExecutionTimeout => "Function execution timed out",
                ghostlang.ExecutionError.TypeError => "Function argument error",
                else => "Function call failed",
            };
            try self.notifyUser(error_msg);
            return .{ .nil = {} };
        };

        return result;
    }

    fn notifyUser(self: *GrimScriptEngine, message: []const u8) !void {
        _ = self;
        std.debug.print("GRIM NOTIFICATION: {s}\n", .{message});
    }
};

// API wrapper functions (these would call actual Grim functions)
fn getCurrentLineWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    // Mock implementation - would call grim.getCurrentLine()
    return .{ .number = 42 };
}

fn getLineTextWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    // Mock implementation - would call grim.getLineText(line)
    return .{ .string = "mock line text" };
}

fn setLineTextWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    // Mock implementation - would call grim.setLineText(line, text)
    return .{ .nil = {} };
}

fn insertTextWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    // Mock implementation - would call grim.insertText(text)
    return .{ .nil = {} };
}

fn getAllTextWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .string = "mock document content" };
}

fn replaceAllTextWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

fn getLineCountWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .number = 100 };
}

fn getCursorPositionWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    // Return cursor position as object
    // In real implementation, would create a ScriptValue.table with line/column
    return .{ .number = 42 }; // Simplified
}

fn setCursorPositionWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

fn moveCursorWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

fn getSelectionWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .string = "selected text" };
}

fn setSelectionWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

fn getSelectedTextWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .string = "selected text" };
}

fn replaceSelectionWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

fn selectWordWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

fn selectLineWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .nil = {} };
}

fn getFilenameWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .string = "example.zig" };
}

fn getFileLanguageWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .string = "zig" };
}

fn isModifiedWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .boolean = false };
}

fn notifyWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    if (args.len > 0 and args[0] == .string) {
        std.debug.print("PLUGIN NOTIFICATION: {s}\n", .{args[0].string});
    }
    return .{ .nil = {} };
}

fn promptWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    // Mock implementation - in real Grim would show input dialog
    return .{ .string = "user input" };
}

fn logWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    if (args.len > 0 and args[0] == .string) {
        std.debug.print("PLUGIN LOG: {s}\n", .{args[0].string});
    }
    return .{ .nil = {} };
}

fn findAllWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    // Mock - would return array of match positions
    return .{ .number = 0 }; // Number of matches found
}

fn replaceAllWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .number = 5 }; // Number of replacements made
}

fn matchesPatternWrapper(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    _ = args;
    return .{ .boolean = true };
}