//! GhostLang Core Types
//!
//! This module contains the fundamental types shared across the GhostLang
//! codebase including error types, configuration, and core value types.

const std = @import("std");

/// Memory-limited allocator that enforces maximum allocation bounds.
/// Used to prevent scripts from consuming unbounded memory.
pub const MemoryLimitAllocator = struct {
    backing_allocator: std.mem.Allocator,
    max_bytes: usize,
    used_bytes: std.atomic.Value(usize),

    pub fn init(backing_allocator: std.mem.Allocator, max_bytes: usize) MemoryLimitAllocator {
        return MemoryLimitAllocator{
            .backing_allocator = backing_allocator,
            .max_bytes = max_bytes,
            .used_bytes = std.atomic.Value(usize).init(0),
        };
    }

    pub fn allocator(self: *MemoryLimitAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }

    fn alloc(ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, return_address: usize) ?[*]u8 {
        const self: *MemoryLimitAllocator = @ptrCast(@alignCast(ptr));
        const current = self.used_bytes.load(.monotonic);
        if (current + len > self.max_bytes) {
            return null; // Memory limit exceeded
        }
        if (self.backing_allocator.rawAlloc(len, alignment, return_address)) |result_ptr| {
            _ = self.used_bytes.fetchAdd(len, .monotonic);
            return result_ptr;
        }
        return null;
    }

    fn resize(ptr: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, return_address: usize) bool {
        const self: *MemoryLimitAllocator = @ptrCast(@alignCast(ptr));
        if (new_len > buf.len) {
            const additional = new_len - buf.len;
            const current = self.used_bytes.load(.monotonic);
            if (current + additional > self.max_bytes) {
                return false; // Memory limit would be exceeded
            }
        }

        if (self.backing_allocator.rawResize(buf, alignment, new_len, return_address)) {
            if (new_len > buf.len) {
                _ = self.used_bytes.fetchAdd(new_len - buf.len, .monotonic);
            } else {
                _ = self.used_bytes.fetchSub(buf.len - new_len, .monotonic);
            }
            return true;
        }
        return false;
    }

    fn free(ptr: *anyopaque, buf: []u8, alignment: std.mem.Alignment, return_address: usize) void {
        const self: *MemoryLimitAllocator = @ptrCast(@alignCast(ptr));
        self.backing_allocator.rawFree(buf, alignment, return_address);
        _ = self.used_bytes.fetchSub(buf.len, .monotonic);
    }

    fn remap(ptr: *anyopaque, buf: []u8, alignment: std.mem.Alignment, old_size: usize, new_size: usize) ?[*]u8 {
        _ = ptr;
        _ = buf;
        _ = alignment;
        _ = old_size;
        _ = new_size;
        return null; // Not supported - use alloc/free instead
    }

    /// Returns the current number of bytes used by this allocator.
    pub fn getBytesUsed(self: *MemoryLimitAllocator) usize {
        return self.used_bytes.load(.monotonic);
    }
};

/// Errors that can occur during script execution.
pub const ExecutionError = error{
    MemoryLimitExceeded,
    ExecutionTimeout,
    IONotAllowed,
    SyscallNotAllowed,
    SecurityViolation,
    ParseError,
    TypeError,
    FunctionNotFound,
    NotAFunction,
    UndefinedVariable,
    ScopeUnderflow,
    InvalidFunctionName,
    InvalidGlobalName,
    GlobalNotFound,
    UnsupportedArgumentType,
    OutOfMemory,
    ScriptError,
};

/// Result from a native function call.
pub const NativeCallResult = struct {
    last_result_count: u16,
    advance_pc: bool = true,
};

/// Native function that can be called from scripts.
/// The context field allows passing external state to the function.
pub const NativeFunction = struct {
    context: ?*anyopaque = null,
    call: *const fn (context: ?*anyopaque, vm_ptr: *anyopaque, dest_reg: u16, arg_start: u16, arg_count: u16, expected_results: u16) ExecutionError!NativeCallResult,
};

/// Instrumentation callbacks for debugging and profiling.
pub const Instrumentation = struct {
    on_instruction: ?*const fn (usize, u8) void = null,
    on_call: ?*const fn ([]const u8) void = null,
};

/// Configuration options for the script engine.
pub const EngineConfig = struct {
    memory_limit: usize = 16 * 1024 * 1024, // 16 MB default
    instruction_limit: usize = 10_000_000, // 10M instructions default
    enable_native_calls: bool = true,
    enable_io: bool = false,
    enable_syscalls: bool = false,
    deterministic: bool = false, // Disable time-based functions, random, etc.
    instrumentation: ?Instrumentation = null,
    use_grove: bool = false, // Use Grove parser when available
};

/// Security context defining what operations are allowed.
pub const SecurityContext = struct {
    /// Allowed file paths for read operations
    allowed_read_paths: []const []const u8 = &[_][]const u8{},

    /// Allowed file paths for write operations
    allowed_write_paths: []const []const u8 = &[_][]const u8{},

    /// Whether network access is allowed
    allow_network: bool = false,

    /// Whether execution of external processes is allowed
    allow_exec: bool = false,

    /// Whether access to environment variables is allowed
    allow_env: bool = false,

    /// Maximum execution time in milliseconds
    max_execution_time_ms: u64 = 5000,

    /// Maximum memory usage in bytes
    max_memory_bytes: usize = 16 * 1024 * 1024, // 16 MB

    /// Check if a path is allowed for reading
    pub fn canRead(self: *const SecurityContext, path: []const u8) bool {
        for (self.allowed_read_paths) |allowed| {
            if (std.mem.startsWith(u8, path, allowed)) {
                return true;
            }
        }
        return false;
    }

    /// Check if a path is allowed for writing
    pub fn canWrite(self: *const SecurityContext, path: []const u8) bool {
        for (self.allowed_write_paths) |allowed| {
            if (std.mem.startsWith(u8, path, allowed)) {
                return true;
            }
        }
        return false;
    }
};

/// Grammar types supported by the parser.
pub const GrammarKind = enum {
    lua,
    ghostlang,
    custom,
};

/// Information about a grammar.
pub const GrammarInfo = struct {
    kind: GrammarKind,
    name: []const u8,
    version: []const u8,
    file_extensions: []const []const u8,
};

/// Severity levels for parse diagnostics.
pub const ParseSeverity = enum {
    hint,
    info,
    warning,
    @"error",
};

/// A diagnostic message from the parser.
pub const ParseDiagnostic = struct {
    severity: ParseSeverity,
    message: []const u8,
    line: usize,
    column: usize,
    length: usize,
    source: ?[]const u8 = null, // Optional source context

    pub fn format(self: ParseDiagnostic, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}:{d}:{d}: {s}: {s}", .{
            self.source orelse "script",
            self.line + 1,
            self.column + 1,
            @tagName(self.severity),
            self.message,
        });
    }
};

test "MemoryLimitAllocator respects limits" {
    var limit_alloc = MemoryLimitAllocator.init(std.testing.allocator, 1024);
    const alloc = limit_alloc.allocator();

    // Should succeed
    const small = try alloc.alloc(u8, 100);
    defer alloc.free(small);

    // Should fail (exceeds limit)
    const result = alloc.alloc(u8, 2000);
    try std.testing.expect(result == error.OutOfMemory);
}

test "SecurityContext path checking" {
    const ctx = SecurityContext{
        .allowed_read_paths = &[_][]const u8{ "/home/user", "/tmp" },
        .allowed_write_paths = &[_][]const u8{"/tmp"},
    };

    try std.testing.expect(ctx.canRead("/home/user/file.txt"));
    try std.testing.expect(ctx.canRead("/tmp/test"));
    try std.testing.expect(!ctx.canRead("/etc/passwd"));

    try std.testing.expect(ctx.canWrite("/tmp/output"));
    try std.testing.expect(!ctx.canWrite("/home/user/file.txt"));
}
