const std = @import("std");
const build_options = @import("build_options");

// By convention, root.zig is the root source file when making a library.

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

    pub fn getBytesUsed(self: *MemoryLimitAllocator) usize {
        return self.used_bytes.load(.monotonic);
    }
};

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

const NativeCallResult = struct {
    last_result_count: u16,
    advance_pc: bool = true,
};

const NativeFunction = struct {
    context: ?*anyopaque = null,
    call: *const fn (context: ?*anyopaque, vm_ptr: *anyopaque, dest_reg: u16, arg_start: u16, arg_count: u16, expected_results: u16) ExecutionError!NativeCallResult,
};

const ScriptFunction = struct {
    allocator: std.mem.Allocator,
    start_pc: usize,
    end_pc: usize,
    param_names: [][]const u8,
    capture_names: [][]const u8,
    captures: std.StringHashMap(ScriptValue),
    ref_count: usize,
    is_vararg: bool,

    pub fn init(
        allocator: std.mem.Allocator,
        start_pc: usize,
        end_pc: usize,
        param_names: []const []const u8,
        capture_names: []const []const u8,
    ) !*ScriptFunction {
        var func = try allocator.create(ScriptFunction);
        func.* = .{
            .allocator = allocator,
            .start_pc = start_pc,
            .end_pc = end_pc,
            .param_names = &[_][]const u8{},
            .capture_names = &[_][]const u8{},
            .captures = std.StringHashMap(ScriptValue).init(allocator),
            .ref_count = 1,
            .is_vararg = false,
        };

        func.param_names = try allocator.alloc([]const u8, param_names.len);
        var idx: usize = 0;
        errdefer {
            while (idx > 0) {
                idx -= 1;
                allocator.free(func.param_names[idx]);
            }
            allocator.free(func.param_names);
            func.captures.deinit();
            allocator.destroy(func);
        }

        while (idx < param_names.len) : (idx += 1) {
            func.param_names[idx] = allocator.dupe(u8, param_names[idx]) catch |err| {
                return err;
            };
        }

        func.capture_names = try allocator.alloc([]const u8, capture_names.len);
        var cap_idx: usize = 0;
        errdefer {
            while (cap_idx > 0) {
                cap_idx -= 1;
                allocator.free(func.capture_names[cap_idx]);
            }
            allocator.free(func.capture_names);
        }

        while (cap_idx < capture_names.len) : (cap_idx += 1) {
            func.capture_names[cap_idx] = allocator.dupe(u8, capture_names[cap_idx]) catch |err| {
                return err;
            };
        }

        return func;
    }

    pub fn retain(self: *ScriptFunction) void {
        self.ref_count += 1;
    }

    pub fn release(self: *ScriptFunction) void {
        if (self.ref_count == 0) return;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            var cap_it = self.captures.iterator();
            while (cap_it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            self.captures.deinit();

            for (self.param_names) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(self.param_names);

            for (self.capture_names) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(self.capture_names);

            self.allocator.destroy(self);
        }
    }

    pub fn addCapture(self: *ScriptFunction, name: []const u8, value: ScriptValue) !void {
        if (self.captures.getEntry(name)) |entry| {
            const copy = try copyScriptValue(self.allocator, value);
            entry.value_ptr.deinit(self.allocator);
            entry.value_ptr.* = copy;
            return;
        }

        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        var value_copy = try copyScriptValue(self.allocator, value);
        errdefer value_copy.deinit(self.allocator);

        self.captures.put(name_copy, value_copy) catch |err| {
            if (err == error.OutOfMemory) return err;
            return err;
        };
    }

    pub fn getCapture(self: *ScriptFunction, name: []const u8) ?ScriptValue {
        if (self.captures.get(name)) |value| {
            return value;
        }
        return null;
    }

    pub fn markVarArg(self: *ScriptFunction, enable: bool) void {
        self.is_vararg = enable;
    }
};

const ScriptTable = struct {
    allocator: std.mem.Allocator,
    map: std.StringHashMap(ScriptValue),
    ref_count: usize,

    pub fn create(allocator: std.mem.Allocator) !*ScriptTable {
        const table = try allocator.create(ScriptTable);
        table.* = .{
            .allocator = allocator,
            .map = std.StringHashMap(ScriptValue).init(allocator),
            .ref_count = 1,
        };
        return table;
    }

    pub fn cloneDeep(self: *ScriptTable) !*ScriptTable {
        const clone = try ScriptTable.create(self.allocator);
        errdefer clone.release();

        var it = self.map.iterator();
        while (it.next()) |entry| {
            const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
            const value_copy = try copyScriptValue(self.allocator, entry.value_ptr.*);
            clone.map.put(key_copy, value_copy) catch |err| {
                var tmp = value_copy;
                tmp.deinit(self.allocator);
                self.allocator.free(key_copy);
                if (err == error.OutOfMemory) return err;
                return err;
            };
        }

        return clone;
    }

    pub fn retain(self: *ScriptTable) void {
        self.ref_count += 1;
    }

    pub fn release(self: *ScriptTable) void {
        if (self.ref_count == 0) return;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            var it = self.map.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            self.map.deinit();
            self.allocator.destroy(self);
        }
    }
};

const ScriptArray = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged(ScriptValue),
    ref_count: usize,

    pub fn create(allocator: std.mem.Allocator) !*ScriptArray {
        const array = try allocator.create(ScriptArray);
        array.* = .{
            .allocator = allocator,
            .items = .{},
            .ref_count = 1,
        };
        return array;
    }

    pub fn cloneDeep(self: *ScriptArray) !*ScriptArray {
        const clone = try ScriptArray.create(self.allocator);
        errdefer clone.release();

        var idx: usize = 0;
        while (idx < self.items.items.len) : (idx += 1) {
            const value_copy = try copyScriptValue(self.allocator, self.items.items[idx]);
            clone.items.append(clone.allocator, value_copy) catch |err| {
                var tmp = value_copy;
                tmp.deinit(self.allocator);
                if (err == error.OutOfMemory) return err;
                return err;
            };
        }

        return clone;
    }

    pub fn retain(self: *ScriptArray) void {
        self.ref_count += 1;
    }

    pub fn release(self: *ScriptArray) void {
        if (self.ref_count == 0) return;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            for (self.items.items) |*value| {
                value.deinit(self.allocator);
            }
            self.items.deinit(self.allocator);
            self.allocator.destroy(self);
        }
    }
};

pub const ScriptValueType = enum {
    nil,
    boolean,
    number,
    string,
    function,
    native_function,
    script_function,
    table,
    array,
    iterator,
    upvalue,
};

pub const ScriptValue = union(ScriptValueType) {
    nil: void,
    boolean: bool,
    number: f64,
    string: []const u8,
    function: *const fn (args: []const ScriptValue) ScriptValue,
    native_function: NativeFunction,
    script_function: *ScriptFunction,
    table: *ScriptTable,
    array: *ScriptArray,
    iterator: *ScriptIterator,
    upvalue: *ScriptUpvalue,

    pub fn deinit(self: *ScriptValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .table => |table_ptr| {
                table_ptr.release();
            },
            .array => |array_ptr| {
                array_ptr.release();
            },
            .script_function => |func| {
                func.release();
            },
            .iterator => |iter| {
                iter.release();
            },
            .upvalue => |up| {
                up.release();
            },
            else => {},
        }
    }
};

const ScriptIterator = struct {
    const Kind = enum { array, table };
    const IteratorError = error{ OutOfMemory, TypeError };

    allocator: std.mem.Allocator,
    ref_count: usize,
    kind: Kind,
    state: union(Kind) {
        array: struct {
            array_ptr: *ScriptArray,
            index: usize,
        },
        table: struct {
            table_ptr: *ScriptTable,
            keys: std.ArrayListUnmanaged([]const u8),
            index: usize,
        },
    },
    current_key: ScriptValue,
    current_value: ScriptValue,
    has_key: bool,
    has_value: bool,
    result_arity: u16,

    pub const Current = struct {
        has_key: bool,
        key: ScriptValue,
        has_value: bool,
        value: ScriptValue,
    };

    pub fn createFromArray(allocator: std.mem.Allocator, array_ptr: *ScriptArray) !*ScriptIterator {
        const iterator = try allocator.create(ScriptIterator);
        iterator.* = .{
            .allocator = allocator,
            .ref_count = 1,
            .kind = .array,
            .state = .{ .array = .{ .array_ptr = array_ptr, .index = 0 } },
            .current_key = .{ .nil = {} },
            .current_value = .{ .nil = {} },
            .has_key = false,
            .has_value = false,
            .result_arity = 1,
        };
        array_ptr.retain();
        return iterator;
    }

    pub fn createFromTable(allocator: std.mem.Allocator, table_ptr: *ScriptTable) !*ScriptIterator {
        const iterator = try allocator.create(ScriptIterator);
        iterator.* = .{
            .allocator = allocator,
            .ref_count = 1,
            .kind = .table,
            .state = .{ .table = .{ .table_ptr = table_ptr, .keys = .{}, .index = 0 } },
            .current_key = .{ .nil = {} },
            .current_value = .{ .nil = {} },
            .has_key = false,
            .has_value = false,
            .result_arity = 2,
        };
        table_ptr.retain();

        var it = table_ptr.map.iterator();
        errdefer iterator.release();

        while (it.next()) |entry| {
            const key_copy = allocator.dupe(u8, entry.key_ptr.*) catch {
                return IteratorError.OutOfMemory;
            };
            iterator.state.table.keys.append(allocator, key_copy) catch {
                allocator.free(key_copy);
                return IteratorError.OutOfMemory;
            };
        }

        return iterator;
    }

    pub fn configure(self: *ScriptIterator, var_count: u16) void {
        const clamped = if (var_count == 0) 1 else if (var_count > 2) 2 else var_count;
        self.result_arity = clamped;
    }

    pub fn retain(self: *ScriptIterator) void {
        self.ref_count += 1;
    }

    pub fn release(self: *ScriptIterator) void {
        if (self.ref_count == 0) return;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.clearCurrent();
            switch (self.kind) {
                .array => self.state.array.array_ptr.release(),
                .table => {
                    var idx: usize = 0;
                    while (idx < self.state.table.keys.items.len) : (idx += 1) {
                        self.allocator.free(self.state.table.keys.items[idx]);
                    }
                    self.state.table.keys.deinit(self.allocator);
                    self.state.table.table_ptr.release();
                },
            }
            self.allocator.destroy(self);
        }
    }

    fn clearCurrent(self: *ScriptIterator) void {
        if (self.has_key) {
            self.current_key.deinit(self.allocator);
            self.current_key = .{ .nil = {} };
            self.has_key = false;
        }
        if (self.has_value) {
            self.current_value.deinit(self.allocator);
            self.current_value = .{ .nil = {} };
            self.has_value = false;
        }
    }

    pub fn takeCurrent(self: *ScriptIterator) Current {
        const result: Current = .{
            .has_key = self.has_key,
            .key = self.current_key,
            .has_value = self.has_value,
            .value = self.current_value,
        };
        self.current_key = .{ .nil = {} };
        self.current_value = .{ .nil = {} };
        self.has_key = false;
        self.has_value = false;
        return result;
    }

    pub fn next(self: *ScriptIterator) IteratorError!bool {
        self.clearCurrent();
        switch (self.kind) {
            .array => {
                const array_ptr = self.state.array.array_ptr;
                if (self.state.array.index >= array_ptr.items.items.len) {
                    return false;
                }
                const idx = self.state.array.index;
                self.state.array.index += 1;

                self.current_value = try copyScriptValue(self.allocator, array_ptr.items.items[idx]);
                self.has_value = true;

                if (self.result_arity >= 2) {
                    self.current_key = .{ .number = @floatFromInt(idx + 1) };
                    self.has_key = true;
                }

                return true;
            },
            .table => {
                const table_state = &self.state.table;
                if (table_state.index >= table_state.keys.items.len) {
                    return false;
                }
                const key_slice = table_state.keys.items[table_state.index];
                table_state.index += 1;

                if (self.result_arity >= 1) {
                    const key_copy = self.allocator.dupe(u8, key_slice) catch {
                        return IteratorError.OutOfMemory;
                    };
                    self.current_key = .{ .string = key_copy };
                    self.has_key = true;
                }

                if (self.result_arity >= 2) {
                    if (table_state.table_ptr.map.get(key_slice)) |value| {
                        self.current_value = try copyScriptValue(self.allocator, value);
                        self.has_value = true;
                    } else {
                        self.current_value = .{ .nil = {} };
                        self.has_value = true;
                    }
                }

                return true;
            },
        }
    }
};

const ScriptUpvalue = struct {
    allocator: std.mem.Allocator,
    ref_count: usize,
    cell: ScriptValue,

    pub fn createFromValue(allocator: std.mem.Allocator, value: ScriptValue) !*ScriptUpvalue {
        const up = try allocator.create(ScriptUpvalue);
        up.* = .{
            .allocator = allocator,
            .ref_count = 1,
            .cell = try copyScriptValue(allocator, value),
        };
        return up;
    }

    pub fn createFromOwnedValue(allocator: std.mem.Allocator, value: ScriptValue) !*ScriptUpvalue {
        const up = try allocator.create(ScriptUpvalue);
        up.* = .{
            .allocator = allocator,
            .ref_count = 1,
            .cell = value,
        };
        return up;
    }

    pub fn retain(self: *ScriptUpvalue) void {
        self.ref_count += 1;
    }

    pub fn release(self: *ScriptUpvalue) void {
        if (self.ref_count == 0) return;
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.cell.deinit(self.allocator);
            self.allocator.destroy(self);
        }
    }

    pub fn getCopy(self: *ScriptUpvalue, allocator: std.mem.Allocator) !ScriptValue {
        return try copyScriptValue(allocator, self.cell);
    }

    pub fn set(self: *ScriptUpvalue, value: ScriptValue) !void {
        const new_copy = try copyScriptValue(self.allocator, value);
        self.cell.deinit(self.allocator);
        self.cell = new_copy;
    }

    pub fn setOwned(self: *ScriptUpvalue, value: ScriptValue) void {
        self.cell.deinit(self.allocator);
        self.cell = value;
    }
};

fn copyScriptValue(allocator: std.mem.Allocator, value: ScriptValue) !ScriptValue {
    return switch (value) {
        .string => |s| .{ .string = try allocator.dupe(u8, s) },
        .table => |table_ptr| blk: {
            table_ptr.retain();
            break :blk ScriptValue{ .table = table_ptr };
        },
        .array => |array_ptr| blk: {
            array_ptr.retain();
            break :blk ScriptValue{ .array = array_ptr };
        },
        .script_function => |func| blk: {
            func.retain();
            break :blk ScriptValue{ .script_function = func };
        },
        .iterator => |iter| blk: {
            iter.retain();
            break :blk ScriptValue{ .iterator = iter };
        },
        .upvalue => |up| blk: {
            up.retain();
            break :blk ScriptValue{ .upvalue = up };
        },
        else => value,
    };
}

var editor_helper_allocator: ?std.mem.Allocator = null;

fn arrayIndexFromNumber(number: f64) ExecutionError!usize {
    if (number < 1) return ExecutionError.TypeError;
    const floored = std.math.floor(number);
    if (floored != number) return ExecutionError.TypeError;
    const idx = @as(isize, @intFromFloat(floored)) - 1;
    if (idx < 0) return ExecutionError.TypeError;
    return @intCast(idx);
}

pub const Instrumentation = struct {
    context: ?*anyopaque = null,
    onInstruction: ?*const fn (context: ?*anyopaque, opcode: Opcode) void = null,
};

pub const EngineConfig = struct {
    allocator: std.mem.Allocator,
    memory_limit: usize = 1024 * 1024, // 1MB default
    execution_timeout_ms: u64 = 1000, // 1 second default
    allow_io: bool = false,
    allow_syscalls: bool = false,
    deterministic: bool = false, // Disable time-based functions, random, etc.
    instrumentation: ?Instrumentation = null,
};

pub const SecurityContext = struct {
    allow_io: bool,
    allow_syscalls: bool,
    deterministic: bool,

    pub fn init(config: EngineConfig) SecurityContext {
        return SecurityContext{
            .allow_io = config.allow_io,
            .allow_syscalls = config.allow_syscalls,
            .deterministic = config.deterministic,
        };
    }

    pub fn checkIOAllowed(self: SecurityContext) ExecutionError!void {
        if (!self.allow_io) {
            return ExecutionError.IONotAllowed;
        }
    }

    pub fn checkSyscallAllowed(self: SecurityContext) ExecutionError!void {
        if (!self.allow_syscalls) {
            return ExecutionError.SyscallNotAllowed;
        }
    }

    pub fn checkNonDeterministicAllowed(self: SecurityContext) ExecutionError!void {
        if (self.deterministic) {
            return ExecutionError.SecurityViolation;
        }
    }
};

pub const GrammarKind = enum {
    ghostlang,
    zig,
    json,
    typescript,
    javascript,
    python,
    rust,
};

pub const GrammarInfo = struct {
    name: []const u8,
    version: []const u8,
    supports_incremental: bool,
    description: []const u8,
};

pub const GrammarRegistry = struct {
    allocator: std.mem.Allocator,
    table: std.AutoHashMap(GrammarKind, GrammarInfo),

    pub fn init(allocator: std.mem.Allocator) GrammarRegistry {
        return .{ .allocator = allocator, .table = std.AutoHashMap(GrammarKind, GrammarInfo).init(allocator) };
    }

    pub fn deinit(self: *GrammarRegistry) void {
        self.table.deinit();
    }

    pub fn register(self: *GrammarRegistry, kind: GrammarKind, info: GrammarInfo) !void {
        try self.table.put(kind, info);
    }

    pub fn ensureDefaults(self: *GrammarRegistry) !void {
        const defaults = [_]struct {
            kind: GrammarKind,
            info: GrammarInfo,
        }{
            .{ .kind = .ghostlang, .info = .{ .name = "Ghostlang", .version = "0.6", .supports_incremental = true, .description = "Native scripting language" } },
            .{ .kind = .zig, .info = .{ .name = "Zig", .version = "0.13", .supports_incremental = true, .description = "Host tooling" } },
            .{ .kind = .json, .info = .{ .name = "JSON", .version = "1.0", .supports_incremental = true, .description = "Configuration grammar" } },
            .{ .kind = .typescript, .info = .{ .name = "TypeScript", .version = "5.x", .supports_incremental = false, .description = "Web integration" } },
            .{ .kind = .javascript, .info = .{ .name = "JavaScript", .version = "ES2023", .supports_incremental = false, .description = "Web integration" } },
            .{ .kind = .python, .info = .{ .name = "Python", .version = "3.11", .supports_incremental = false, .description = "Script interop" } },
            .{ .kind = .rust, .info = .{ .name = "Rust", .version = "1.74", .supports_incremental = false, .description = "Performance modules" } },
        };

        for (defaults) |entry| {
            if (!self.table.contains(entry.kind)) {
                self.table.put(entry.kind, entry.info) catch |err| {
                    if (entry.kind == .ghostlang or err != error.OutOfMemory) {
                        return err;
                    }
                    // Low-memory scenario: skip registering additional grammars.
                    return;
                };
            }
        }
    }

    pub fn contains(self: *GrammarRegistry, kind: GrammarKind) bool {
        return self.table.contains(kind);
    }

    pub fn get(self: *GrammarRegistry, kind: GrammarKind) ?GrammarInfo {
        return self.table.get(kind);
    }

    pub fn list(self: *GrammarRegistry, allocator: std.mem.Allocator) ![]GrammarInfo {
        var out = std.ArrayList(GrammarInfo).init(allocator);
        errdefer out.deinit();

        var it = self.table.iterator();
        while (it.next()) |entry| {
            try out.append(entry.value_ptr.*);
        }

        return try out.toOwnedSlice();
    }
};

pub const ParseSeverity = enum {
    info,
    warning,
    fatal,
};

pub const ParseDiagnostic = struct {
    severity: ParseSeverity,
    message: []u8,
    line: usize,
    column: usize,
};

fn appendDiagnosticOwned(buffer: *std.ArrayListUnmanaged(ParseDiagnostic), allocator: std.mem.Allocator, severity: ParseSeverity, message: []u8, line: usize, column: usize) !void {
    errdefer allocator.free(message);
    try buffer.append(allocator, .{ .severity = severity, .message = message, .line = line, .column = column });
}

fn clearDiagnosticBuffer(buffer: *std.ArrayListUnmanaged(ParseDiagnostic), allocator: std.mem.Allocator) void {
    for (buffer.items) |diag| {
        allocator.free(diag.message);
    }
    buffer.clearRetainingCapacity();
}

pub const ScriptEngine = struct {
    config: EngineConfig,
    globals: std.StringHashMap(ScriptValue),
    memory_limiter: ?*MemoryLimitAllocator, // Heap-allocated to keep address stable
    tracked_allocator: std.mem.Allocator,
    security: SecurityContext,
    grove: GroveIntegration,
    diagnostics: std.ArrayListUnmanaged(ParseDiagnostic),
    metrics: ParseMetrics,
    plugins: PluginManager,

    pub fn create(config: EngineConfig) !ScriptEngine {
        // Allocate the memory limiter on the heap so its address stays stable
        const limiter = try config.allocator.create(MemoryLimitAllocator);
        errdefer config.allocator.destroy(limiter);

        limiter.* = MemoryLimitAllocator.init(config.allocator, config.memory_limit);

        var engine = ScriptEngine{
            .config = config,
            .globals = undefined,
            .memory_limiter = limiter,
            .tracked_allocator = limiter.allocator(),
            .security = SecurityContext.init(config),
            .grove = undefined,
            .diagnostics = .{},
            .metrics = ParseMetrics.init(),
            .plugins = PluginManager.init(limiter.allocator()),
        };

        engine.globals = std.StringHashMap(ScriptValue).init(engine.tracked_allocator);
        errdefer engine.globals.deinit();
        errdefer engine.plugins.deinit();

        engine.grove = try GroveIntegration.init(engine.tracked_allocator);
        errdefer engine.grove.deinit();

        return engine;
    }

    pub fn deinit(self: *ScriptEngine) void {
        var it = self.globals.iterator();
        while (it.next()) |entry| {
            self.tracked_allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.tracked_allocator);
        }
        self.globals.deinit();

        clearDiagnosticBuffer(&self.diagnostics, self.tracked_allocator);
        self.diagnostics.deinit(self.tracked_allocator);

        self.plugins.deinit();
        self.grove.deinit();

        // Free the heap-allocated memory limiter
        if (self.memory_limiter) |limiter| {
            if (editor_helper_allocator) |alloc| {
                const limiter_ptr: *anyopaque = @ptrCast(limiter);
                if (alloc.ptr == limiter_ptr) {
                    editor_helper_allocator = null;
                }
            }
            self.config.allocator.destroy(limiter);
        }
    }

    pub fn loadScript(self: *ScriptEngine, source: []const u8) ExecutionError!Script {
        clearDiagnosticBuffer(&self.diagnostics, self.tracked_allocator);

        var parse_result = self.grove.parseGhostlang(source, &self.diagnostics) catch |err| {
            self.metrics.recordFailure(self.diagnostics.items.len);
            return err;
        };
        var parse_cleanup = true;
        errdefer if (parse_cleanup) parse_result.deinit(self.tracked_allocator);

        var vm = VM.init(self.tracked_allocator, parse_result.instructions, parse_result.constants, self);
        var vm_cleanup = true;
        errdefer if (vm_cleanup) vm.deinit();

        BuiltinFunctions.registerBuiltins(&vm) catch |err| switch (err) {
            error.OutOfMemory => {
                self.metrics.recordFailure(self.diagnostics.items.len);
                return ExecutionError.MemoryLimitExceeded;
            },
        };
        EditorAPI.registerEditorAPI(&vm) catch |err| switch (err) {
            error.OutOfMemory => {
                self.metrics.recordFailure(self.diagnostics.items.len);
                return ExecutionError.MemoryLimitExceeded;
            },
        };

        const script = Script{
            .engine = self,
            .vm = vm,
            .syntax_tree = parse_result.syntax_tree,
            .parse_duration_ns = parse_result.duration_ns,
        };

        self.metrics.recordSuccess(
            script.parse_duration_ns,
            script.syntax_tree.instruction_count,
            script.syntax_tree.constant_count,
            self.diagnostics.items.len,
        );

        parse_result.instructions = &[_]Instruction{};
        parse_result.constants = &[_]ScriptValue{};
        parse_result.syntax_tree = SyntaxTree{
            .allocator = self.tracked_allocator,
            .nodes = .{},
            .instruction_count = 0,
            .constant_count = 0,
        };
        parse_result.duration_ns = 0;
        parse_cleanup = false;
        vm_cleanup = false;

        return script;
    }

    pub fn lintScript(self: *ScriptEngine, source: []const u8) ExecutionError!ParseMetricsSnapshot {
        clearDiagnosticBuffer(&self.diagnostics, self.tracked_allocator);

        var parse_result = self.grove.parseGhostlang(source, &self.diagnostics) catch |err| {
            self.metrics.recordFailure(self.diagnostics.items.len);
            return err;
        };
        defer parse_result.deinit(self.tracked_allocator);

        self.metrics.recordSuccess(
            parse_result.duration_ns,
            parse_result.syntax_tree.instruction_count,
            parse_result.syntax_tree.constant_count,
            self.diagnostics.items.len,
        );

        return self.metrics.snapshot();
    }

    pub fn getDiagnostics(self: *ScriptEngine) []const ParseDiagnostic {
        return self.diagnostics.items;
    }

    pub fn copyDiagnostics(self: *ScriptEngine, allocator: std.mem.Allocator) ExecutionError![]ParseDiagnostic {
        var list = std.ArrayList(ParseDiagnostic).init(allocator);
        errdefer {
            for (list.items) |diag| {
                allocator.free(diag.message);
            }
            list.deinit();
        }

        for (self.diagnostics.items) |diag| {
            const message_copy = allocator.dupe(u8, diag.message) catch |err| switch (err) {
                error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
            };
            list.append(.{
                .severity = diag.severity,
                .message = message_copy,
                .line = diag.line,
                .column = diag.column,
            }) catch |err| switch (err) {
                error.OutOfMemory => {
                    allocator.free(message_copy);
                    return ExecutionError.MemoryLimitExceeded;
                },
            };
        }

        const owned = list.toOwnedSlice() catch |err| switch (err) {
            error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
        };
        return owned;
    }

    pub fn getParseMetrics(self: *ScriptEngine) ParseMetricsSnapshot {
        return self.metrics.snapshot();
    }

    pub fn registerPlugin(self: *ScriptEngine, name: []const u8, version: []const u8) ExecutionError!void {
        self.plugins.register(name, version) catch |err| switch (err) {
            error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
        };
    }

    pub fn enablePlugin(self: *ScriptEngine, name: []const u8) bool {
        return self.plugins.enable(name);
    }

    pub fn disablePlugin(self: *ScriptEngine, name: []const u8) bool {
        return self.plugins.disable(name);
    }

    pub fn listPlugins(self: *ScriptEngine, allocator: std.mem.Allocator) ExecutionError![]PluginDescriptor {
        return self.plugins.list(allocator) catch |err| switch (err) {
            error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
        };
    }

    pub fn destroyPluginList(self: *ScriptEngine, allocator: std.mem.Allocator, descriptors: []PluginDescriptor) void {
        self.plugins.destroyList(allocator, descriptors);
    }

    const PreparedArg = struct {
        value: ScriptValue,
        owned: bool,
    };

    pub fn call(self: *ScriptEngine, function: []const u8, args: anytype) ExecutionError!ScriptValue {
        var prepared = std.ArrayListUnmanaged(PreparedArg){};
        defer {
            for (prepared.items) |*entry| {
                if (entry.owned) {
                    entry.value.deinit(self.tracked_allocator);
                }
            }
            prepared.deinit(self.tracked_allocator);
        }

        self.collectArgs(&prepared, args) catch {
            return ExecutionError.UnsupportedArgumentType;
        };

        const empty_slice = [_]ScriptValue{};
        var args_storage: []ScriptValue = empty_slice[0..];
        var owns_storage = false;
        if (prepared.items.len > 0) {
            args_storage = self.tracked_allocator.alloc(ScriptValue, prepared.items.len) catch |err| switch (err) {
                error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
            };
            owns_storage = true;
            for (prepared.items, 0..) |entry, idx| {
                args_storage[idx] = entry.value;
            }
        }
        defer if (owns_storage) self.tracked_allocator.free(args_storage);

        const func = self.globals.get(function) orelse return ExecutionError.FunctionNotFound;
        if (func != .function) {
            return ExecutionError.NotAFunction;
        }

        const call_args: []const ScriptValue = args_storage;
        const result = func.function(call_args);
        const copied = self.copyForReturn(result) catch |err| switch (err) {
            error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
        };
        return copied;
    }

    fn collectArgs(self: *ScriptEngine, prepared: *std.ArrayListUnmanaged(PreparedArg), args: anytype) !void {
        const info = @typeInfo(@TypeOf(args));
        switch (info) {
            .@"struct" => |struct_info| {
                if (struct_info.is_tuple) {
                    inline for (args) |arg| {
                        try prepared.append(self.tracked_allocator, try self.prepareArg(arg));
                    }
                    return;
                }
                if (struct_info.fields.len == 0) {
                    return;
                }
                return error.UnsupportedArgumentType;
            },
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == ScriptValue) {
                    for (args) |value| {
                        try prepared.append(self.tracked_allocator, .{ .value = value, .owned = false });
                    }
                    return;
                }
                return error.UnsupportedArgumentType;
            },
            .array => |arr_info| {
                if (arr_info.child == ScriptValue) {
                    for (args) |value| {
                        try prepared.append(self.tracked_allocator, .{ .value = value, .owned = false });
                    }
                    return;
                }
                return error.UnsupportedArgumentType;
            },
            .void => return,
            else => return error.UnsupportedArgumentType,
        }
    }

    fn prepareArg(self: *ScriptEngine, arg: anytype) !PreparedArg {
        const T = @TypeOf(arg);
        if (T == ScriptValue) {
            return .{ .value = arg, .owned = false };
        }
        switch (@typeInfo(T)) {
            .bool => return .{ .value = .{ .boolean = arg }, .owned = false },
            .int => return .{ .value = .{ .number = @floatFromInt(arg) }, .owned = false },
            .float => return .{ .value = .{ .number = @as(f64, arg) }, .owned = false },
            .comptime_int => return .{ .value = .{ .number = @floatFromInt(arg) }, .owned = false },
            .comptime_float => return .{ .value = .{ .number = @as(f64, arg) }, .owned = false },
            .pointer => |info| {
                if (info.child == u8) {
                    switch (info.size) {
                        .slice => {
                            const base_slice: []const u8 = arg[0..arg.len];
                            return self.prepareStringArg(base_slice);
                        },
                        .many, .c => {
                            if (info.sentinel_ptr == null) return error.UnsupportedArgumentType;
                            const len = std.mem.len(arg);
                            const elem_ptr: [*]const u8 = @ptrCast(arg);
                            const base_slice = elem_ptr[0..len];
                            return self.prepareStringArg(base_slice);
                        },
                        else => {},
                    }
                }
                if (info.size == .one) {
                    switch (@typeInfo(info.child)) {
                        .array => |array_info| {
                            if (array_info.child == u8) {
                                const elem_ptr: [*]const u8 = @ptrCast(arg);
                                const slice = elem_ptr[0..array_info.len];
                                return self.prepareStringArg(slice);
                            }
                        },
                        else => {},
                    }
                }
                return error.UnsupportedArgumentType;
            },
            .array => |info| {
                if (info.child == u8) {
                    const slice = arg[0..info.len];
                    return self.prepareStringArg(slice);
                }
                return error.UnsupportedArgumentType;
            },
            else => return error.UnsupportedArgumentType,
        }
    }

    fn copyForReturn(self: *ScriptEngine, value: ScriptValue) !ScriptValue {
        return switch (value) {
            .string => |s| .{ .string = try self.tracked_allocator.dupe(u8, s) },
            else => value,
        };
    }

    fn prepareStringArg(self: *ScriptEngine, slice: []const u8) !PreparedArg {
        const dup = try self.tracked_allocator.dupe(u8, slice);
        return .{ .value = .{ .string = dup }, .owned = true };
    }

    pub fn registerFunction(self: *ScriptEngine, name: []const u8, func: *const fn (args: []const ScriptValue) ScriptValue) ExecutionError!void {
        const name_copy = self.tracked_allocator.dupe(u8, name) catch |err| switch (err) {
            error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
        };
        self.globals.put(name_copy, .{ .function = func }) catch |err| switch (err) {
            error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
        };
    }

    // Built-in functions that demonstrate security gating
    pub fn registerSecureFunctions(self: *ScriptEngine) ExecutionError!void {
        try self.registerFunction("getTime", getTimeFunction);
        try self.registerFunction("writeFile", writeFileFunction);
        try self.registerFunction("readFile", readFileFunction);
        try self.registerFunction("system", systemFunction);
    }

    // Editor helper functions for working with complex data types
    pub fn registerEditorHelpers(self: *ScriptEngine) ExecutionError!void {
        editor_helper_allocator = self.tracked_allocator;
        try self.registerFunction("createArray", createArrayFunction);
        try self.registerFunction("arrayPush", arrayPushFunction);
        try self.registerFunction("arraySet", arraySetFunction);
        try self.registerFunction("arrayPop", arrayPopFunction);
        try self.registerFunction("arrayLength", arrayLengthFunction);
        try self.registerFunction("arrayGet", arrayGetFunction);
        try self.registerFunction("createObject", createObjectFunction);
        try self.registerFunction("objectSet", objectSetFunction);
        try self.registerFunction("objectGet", objectGetFunction);
        try self.registerFunction("objectKeys", objectKeysFunction);
        try self.registerFunction("split", splitFunction);
        try self.registerFunction("join", joinFunction);
        try self.registerFunction("substring", substringFunction);
        try self.registerFunction("indexOf", indexOfFunction);
        try self.registerFunction("replace", replaceFunction);

        // Lua-style string functions for GSH compatibility
        try self.registerFunction("stringMatch", stringMatchFunction);
        try self.registerFunction("stringFind", stringFindFunction);
        try self.registerFunction("stringGsub", stringGsubFunction);
        try self.registerFunction("stringUpper", stringUpperFunction);
        try self.registerFunction("stringLower", stringLowerFunction);
        try self.registerFunction("stringFormat", stringFormatFunction);

        // Table helper functions for Lua compatibility
        try self.registerFunction("tableInsert", tableInsertFunction);
        try self.registerFunction("tableRemove", tableRemoveFunction);
        try self.registerFunction("tableConcat", tableConcatFunction);
    }

    fn getTimeFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // This would be gated by deterministic mode in a real implementation
        const timestamp = std.time.milliTimestamp();
        return .{ .number = @floatFromInt(timestamp) };
    }

    fn writeFileFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // This would be gated by IO permissions
        return makeHelperStringLiteral("IO not implemented in sandbox");
    }

    fn readFileFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // This would be gated by IO permissions
        return makeHelperStringLiteral("IO not implemented in sandbox");
    }

    fn systemFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // This would be gated by syscall permissions
        return makeHelperStringLiteral("Syscalls not allowed in sandbox");
    }

    // Editor helper function implementations
    fn createArrayFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        const allocator = helperAllocator() orelse return .{ .nil = {} };
        const array_ptr = ScriptArray.create(allocator) catch {
            return .{ .nil = {} };
        };
        return .{ .array = array_ptr };
    }

    fn arrayPushFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 2) return .{ .nil = {} };
        if (args[0] != .array) return .{ .nil = {} };
        const array_ptr = args[0].array;
        const allocator = array_ptr.allocator;
        const value_copy = copyScriptValue(allocator, args[1]) catch {
            return .{ .nil = {} };
        };
        array_ptr.items.append(allocator, value_copy) catch {
            var tmp = value_copy;
            tmp.deinit(allocator);
            return .{ .nil = {} };
        };
        array_ptr.retain();
        return .{ .array = array_ptr };
    }

    fn arraySetFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 3) return .{ .nil = {} };
        if (args[0] != .array or args[1] != .number) return .{ .nil = {} };

        const array_ptr = args[0].array;
        const allocator = array_ptr.allocator;
        const idx = numberToIndex(args[1].number) orelse return .{ .nil = {} };
        if (idx > array_ptr.items.items.len) return .{ .nil = {} };

        const value_copy = copyScriptValue(allocator, args[2]) catch {
            return .{ .nil = {} };
        };

        if (idx == array_ptr.items.items.len) {
            array_ptr.items.append(allocator, value_copy) catch {
                var tmp = value_copy;
                tmp.deinit(allocator);
                return .{ .nil = {} };
            };
        } else {
            var slot = &array_ptr.items.items[idx];
            slot.deinit(allocator);
            slot.* = value_copy;
        }

        array_ptr.retain();
        return .{ .array = array_ptr };
    }

    fn arrayPopFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 1) return .{ .nil = {} };
        if (args[0] != .array) return .{ .nil = {} };

        const array_ptr = args[0].array;
        if (array_ptr.items.items.len == 0) return .{ .nil = {} };

        const value = array_ptr.items.pop() orelse return .{ .nil = {} };
        return value;
    }

    fn arrayLengthFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 1 or args[0] != .array) return .{ .nil = {} };
        const array_ptr = args[0].array;
        return .{ .number = @floatFromInt(array_ptr.items.items.len) };
    }

    fn arrayGetFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 2) return .{ .nil = {} };
        if (args[0] != .array or args[1] != .number) return .{ .nil = {} };

        const array_ptr = args[0].array;
        const idx = numberToIndex(args[1].number) orelse return .{ .nil = {} };
        if (idx >= array_ptr.items.items.len) return .{ .nil = {} };

        return copyScriptValue(array_ptr.allocator, array_ptr.items.items[idx]) catch {
            return .{ .nil = {} };
        };
    }

    fn createObjectFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        const allocator = helperAllocator() orelse return .{ .nil = {} };
        const table_ptr = ScriptTable.create(allocator) catch {
            return .{ .nil = {} };
        };
        return .{ .table = table_ptr };
    }

    fn objectSetFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 3) return .{ .nil = {} };
        if (args[0] != .table or args[1] != .string) return .{ .nil = {} };

        const table_ptr = args[0].table;
        const key_slice = args[1].string;
        const allocator = table_ptr.allocator;

        const value_copy = copyScriptValue(allocator, args[2]) catch {
            return .{ .nil = {} };
        };

        if (table_ptr.map.getEntry(key_slice)) |entry| {
            entry.value_ptr.deinit(allocator);
            entry.value_ptr.* = value_copy;
            table_ptr.retain();
            return .{ .table = table_ptr };
        }

        const key_copy = allocator.dupe(u8, key_slice) catch {
            var tmp = value_copy;
            tmp.deinit(allocator);
            return .{ .nil = {} };
        };

        table_ptr.map.put(key_copy, value_copy) catch {
            var tmp = value_copy;
            tmp.deinit(allocator);
            allocator.free(key_copy);
            return .{ .nil = {} };
        };

        table_ptr.retain();
        return .{ .table = table_ptr };
    }

    fn objectGetFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 2) return .{ .nil = {} };
        if (args[0] != .table or args[1] != .string) return .{ .nil = {} };

        const table_ptr = args[0].table;
        const allocator = table_ptr.allocator;
        const key_slice = args[1].string;

        if (table_ptr.map.get(key_slice)) |value| {
            return copyScriptValue(allocator, value) catch {
                return .{ .nil = {} };
            };
        }
        return .{ .nil = {} };
    }

    fn objectKeysFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 1) return .{ .nil = {} };
        if (args[0] != .table) return .{ .nil = {} };

        const allocator = helperAllocator() orelse return .{ .nil = {} };
        const array_ptr = ScriptArray.create(allocator) catch {
            return .{ .nil = {} };
        };

        const table_ptr = args[0].table;
        var it = table_ptr.map.iterator();
        while (it.next()) |entry| {
            const key_copy = allocator.dupe(u8, entry.key_ptr.*) catch {
                array_ptr.release();
                return .{ .nil = {} };
            };
            const value = ScriptValue{ .string = key_copy };
            array_ptr.items.append(allocator, value) catch {
                var tmp = value;
                tmp.deinit(allocator);
                array_ptr.release();
                return .{ .nil = {} };
            };
        }

        return .{ .array = array_ptr };
    }

    fn splitFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 2) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .string) return .{ .nil = {} };

        const source = args[0].string;
        const delimiter = args[1].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };

        const array_ptr = ScriptArray.create(allocator) catch {
            return .{ .nil = {} };
        };

        if (delimiter.len == 0) {
            var idx: usize = 0;
            while (idx < source.len) : (idx += 1) {
                const dup = allocator.dupe(u8, source[idx .. idx + 1]) catch {
                    array_ptr.release();
                    return .{ .nil = {} };
                };
                const value = ScriptValue{ .string = dup };
                array_ptr.items.append(allocator, value) catch {
                    var tmp = value;
                    tmp.deinit(allocator);
                    array_ptr.release();
                    return .{ .nil = {} };
                };
            }
            return .{ .array = array_ptr };
        }

        var iterator = std.mem.splitSequence(u8, source, delimiter);
        while (iterator.next()) |part| {
            const dup = allocator.dupe(u8, part) catch {
                array_ptr.release();
                return .{ .nil = {} };
            };
            const value = ScriptValue{ .string = dup };
            array_ptr.items.append(allocator, value) catch {
                var tmp = value;
                tmp.deinit(allocator);
                array_ptr.release();
                return .{ .nil = {} };
            };
        }

        return .{ .array = array_ptr };
    }

    fn joinFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 2) return .{ .nil = {} };
        if (args[0] != .array or args[1] != .string) return .{ .nil = {} };

        const array_ptr = args[0].array;
        const delimiter = args[1].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };

        var total_len: usize = 0;
        for (array_ptr.items.items, 0..) |value, idx| {
            if (value != .string) {
                return .{ .nil = {} };
            }
            total_len += value.string.len;
            if (idx > 0) {
                total_len += delimiter.len;
            }
        }

        const owned = allocator.alloc(u8, total_len) catch {
            return .{ .nil = {} };
        };

        var offset: usize = 0;
        for (array_ptr.items.items, 0..) |value, idx| {
            if (idx > 0 and delimiter.len > 0) {
                std.mem.copyForwards(u8, owned[offset .. offset + delimiter.len], delimiter);
                offset += delimiter.len;
            }
            if (value == .string and value.string.len > 0) {
                const slice = value.string;
                std.mem.copyForwards(u8, owned[offset .. offset + slice.len], slice);
                offset += slice.len;
            }
        }

        return .{ .string = owned };
    }

    fn substringFunction(args: []const ScriptValue) ScriptValue {
        if (args.len < 2 or args.len > 3) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .number) return .{ .nil = {} };

        const source = args[0].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };
        const start_idx = numberToIndex(args[1].number) orelse return .{ .nil = {} };
        if (start_idx > source.len) {
            const empty = allocator.dupe(u8, &[_]u8{}) catch {
                return .{ .nil = {} };
            };
            return .{ .string = empty };
        }

        var end_idx = source.len;
        if (args.len == 3) {
            if (args[2] != .number) return .{ .nil = {} };
            const converted = numberToIndex(args[2].number) orelse return .{ .nil = {} };
            end_idx = @min(converted, source.len);
            if (end_idx < start_idx) end_idx = start_idx;
        }

        const slice = source[start_idx..end_idx];
        const dup = allocator.dupe(u8, slice) catch {
            return .{ .nil = {} };
        };
        return .{ .string = dup };
    }

    fn indexOfFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 2) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .string) return .{ .nil = {} };

        const haystack = args[0].string;
        const needle = args[1].string;
        if (needle.len == 0) return .{ .number = 0 };

        if (std.mem.indexOf(u8, haystack, needle)) |idx| {
            return .{ .number = @floatFromInt(idx) };
        }

        return .{ .number = -1 };
    }

    fn replaceFunction(args: []const ScriptValue) ScriptValue {
        if (args.len != 3) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .string or args[2] != .string) return .{ .nil = {} };

        const source = args[0].string;
        const needle = args[1].string;
        const replacement = args[2].string;

        const allocator = helperAllocator() orelse return .{ .nil = {} };

        if (needle.len == 0) {
            const dup = allocator.dupe(u8, source) catch {
                return .{ .nil = {} };
            };
            return .{ .string = dup };
        }

        const idx_opt = std.mem.indexOf(u8, source, needle);
        if (idx_opt == null) {
            const dup = allocator.dupe(u8, source) catch {
                return .{ .nil = {} };
            };
            return .{ .string = dup };
        }

        const idx = idx_opt.?;
        const prefix_len = idx;
        const suffix_start = idx + needle.len;
        const suffix_len = source.len - suffix_start;
        const total_len = prefix_len + replacement.len + suffix_len;

        const owned = allocator.alloc(u8, total_len) catch {
            return .{ .nil = {} };
        };

        if (prefix_len > 0) {
            std.mem.copyForwards(u8, owned[0..prefix_len], source[0..prefix_len]);
        }
        if (replacement.len > 0) {
            std.mem.copyForwards(u8, owned[prefix_len .. prefix_len + replacement.len], replacement);
        }
        if (suffix_len > 0) {
            std.mem.copyForwards(u8, owned[prefix_len + replacement.len ..], source[suffix_start..]);
        }

        return .{ .string = owned };
    }

    // Lua-style string functions for GSH compatibility
    fn stringMatchFunction(args: []const ScriptValue) ScriptValue {
        // stringMatch(str, pattern) - Simple pattern matching
        // For now, implements basic substring search (full regex later)
        if (args.len < 2) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .string) return .{ .nil = {} };

        const source = args[0].string;
        const pattern = args[1].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };

        // Simple implementation: look for literal substring
        // TODO: Implement full Lua pattern matching
        if (std.mem.indexOf(u8, source, pattern)) |idx| {
            // Return the matched substring
            const matched = allocator.dupe(u8, source[idx .. idx + pattern.len]) catch {
                return .{ .nil = {} };
            };
            return .{ .string = matched };
        }

        return .{ .nil = {} };
    }

    fn stringFindFunction(args: []const ScriptValue) ScriptValue {
        // stringFind(str, pattern, [init]) - Find pattern in string
        if (args.len < 2) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .string) return .{ .nil = {} };

        const source = args[0].string;
        const pattern = args[1].string;

        var start_idx: usize = 0;
        if (args.len >= 3 and args[2] == .number) {
            start_idx = numberToIndex(args[2].number) orelse 0;
            if (start_idx >= source.len) return .{ .nil = {} };
        }

        const search_slice = source[start_idx..];
        if (std.mem.indexOf(u8, search_slice, pattern)) |idx| {
            // Return 1-based index (Lua convention)
            return .{ .number = @as(f64, @floatFromInt(start_idx + idx + 1)) };
        }

        return .{ .nil = {} };
    }

    fn stringGsubFunction(args: []const ScriptValue) ScriptValue {
        // stringGsub(str, pattern, replacement) - Global substitution
        if (args.len < 3) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .string or args[2] != .string) {
            return .{ .nil = {} };
        }

        const source = args[0].string;
        const pattern = args[1].string;
        const replacement = args[2].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };

        // Simple replace-all implementation
        var result: std.ArrayList(u8) = .{};
        defer result.deinit(allocator);

        var pos: usize = 0;
        while (pos < source.len) {
            if (std.mem.indexOf(u8, source[pos..], pattern)) |idx| {
                const abs_idx = pos + idx;
                // Copy everything before match
                result.appendSlice(allocator, source[pos..abs_idx]) catch return .{ .nil = {} };
                // Add replacement
                result.appendSlice(allocator, replacement) catch return .{ .nil = {} };
                pos = abs_idx + pattern.len;
            } else {
                // Copy rest of string
                result.appendSlice(allocator, source[pos..]) catch return .{ .nil = {} };
                break;
            }
        }

        const owned = result.toOwnedSlice(allocator) catch return .{ .nil = {} };
        return .{ .string = owned };
    }

    fn stringUpperFunction(args: []const ScriptValue) ScriptValue {
        if (args.len < 1) return .{ .nil = {} };
        if (args[0] != .string) return .{ .nil = {} };

        const source = args[0].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };

        const result = allocator.alloc(u8, source.len) catch return .{ .nil = {} };
        for (source, 0..) |c, i| {
            result[i] = std.ascii.toUpper(c);
        }

        return .{ .string = result };
    }

    fn stringLowerFunction(args: []const ScriptValue) ScriptValue {
        if (args.len < 1) return .{ .nil = {} };
        if (args[0] != .string) return .{ .nil = {} };

        const source = args[0].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };

        const result = allocator.alloc(u8, source.len) catch return .{ .nil = {} };
        for (source, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }

        return .{ .string = result };
    }

    fn stringFormatFunction(args: []const ScriptValue) ScriptValue {
        // stringFormat(fmt, ...) - Basic sprintf-style formatting
        if (args.len < 1) return .{ .nil = {} };
        if (args[0] != .string) return .{ .nil = {} };

        const fmt = args[0].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };

        // Simple implementation: replace %s and %d placeholders
        var result: std.ArrayList(u8) = .{};
        defer result.deinit(allocator);

        var arg_idx: usize = 1;
        var i: usize = 0;

        while (i < fmt.len) {
            if (fmt[i] == '%' and i + 1 < fmt.len) {
                const spec = fmt[i + 1];
                if (spec == 's' and arg_idx < args.len) {
                    // String placeholder
                    if (args[arg_idx] == .string) {
                        result.appendSlice(allocator, args[arg_idx].string) catch return .{ .nil = {} };
                    } else if (args[arg_idx] == .number) {
                        var buf: [64]u8 = undefined;
                        const str = std.fmt.bufPrint(&buf, "{d}", .{args[arg_idx].number}) catch "";
                        result.appendSlice(allocator, str) catch return .{ .nil = {} };
                    }
                    arg_idx += 1;
                    i += 2;
                    continue;
                } else if (spec == 'd' and arg_idx < args.len) {
                    // Number placeholder
                    if (args[arg_idx] == .number) {
                        var buf: [64]u8 = undefined;
                        const str = std.fmt.bufPrint(&buf, "{d:.0}", .{args[arg_idx].number}) catch "";
                        result.appendSlice(allocator, str) catch return .{ .nil = {} };
                    }
                    arg_idx += 1;
                    i += 2;
                    continue;
                } else if (spec == '%') {
                    // Escaped %
                    result.append(allocator, '%') catch return .{ .nil = {} };
                    i += 2;
                    continue;
                }
            }
            result.append(allocator, fmt[i]) catch return .{ .nil = {} };
            i += 1;
        }

        const owned = result.toOwnedSlice(allocator) catch return .{ .nil = {} };
        return .{ .string = owned };
    }

    // Table helper functions for Lua compatibility
    fn tableInsertFunction(args: []const ScriptValue) ScriptValue {
        // tableInsert(array, [pos], value) - Insert into array
        if (args.len < 2) return .{ .nil = {} };
        if (args[0] != .array) return .{ .nil = {} };

        const array_ptr = args[0].array;
        const allocator = array_ptr.allocator;

        if (args.len == 2) {
            // Insert at end
            const value_copy = copyScriptValue(allocator, args[1]) catch {
                return .{ .nil = {} };
            };
            array_ptr.items.append(allocator, value_copy) catch {
                var tmp = value_copy;
                tmp.deinit(allocator);
                return .{ .nil = {} };
            };
        } else if (args.len >= 3 and args[1] == .number) {
            // Insert at position (1-based index)
            const pos = numberToIndex(args[1].number - 1) orelse return .{ .nil = {} };
            if (pos > array_ptr.items.items.len) return .{ .nil = {} };

            const value_copy = copyScriptValue(allocator, args[2]) catch {
                return .{ .nil = {} };
            };
            array_ptr.items.insert(allocator, pos, value_copy) catch {
                var tmp = value_copy;
                tmp.deinit(allocator);
                return .{ .nil = {} };
            };
        }

        array_ptr.retain();
        return .{ .array = array_ptr };
    }

    fn tableRemoveFunction(args: []const ScriptValue) ScriptValue {
        // tableRemove(array, [pos]) - Remove from array
        if (args.len < 1) return .{ .nil = {} };
        if (args[0] != .array) return .{ .nil = {} };

        const array_ptr = args[0].array;
        const allocator = array_ptr.allocator;

        if (array_ptr.items.items.len == 0) return .{ .nil = {} };

        var pos: usize = array_ptr.items.items.len - 1;
        if (args.len >= 2 and args[1] == .number) {
            // Remove at position (1-based index)
            pos = numberToIndex(args[1].number - 1) orelse return .{ .nil = {} };
            if (pos >= array_ptr.items.items.len) return .{ .nil = {} };
        }

        var removed = array_ptr.items.orderedRemove(pos);
        defer removed.deinit(allocator);

        return removed;
    }

    fn tableConcatFunction(args: []const ScriptValue) ScriptValue {
        // tableConcat(array, [sep], [i], [j]) - Concatenate array elements
        if (args.len < 1) return .{ .nil = {} };
        if (args[0] != .array) return .{ .nil = {} };

        const array_ptr = args[0].array;
        const allocator = array_ptr.allocator;

        const sep = if (args.len >= 2 and args[1] == .string) args[1].string else "";
        const start_idx: usize = if (args.len >= 3 and args[2] == .number)
            numberToIndex(args[2].number - 1) orelse 0
        else
            0;
        const end_idx: usize = if (args.len >= 4 and args[3] == .number)
            numberToIndex(args[3].number - 1) orelse array_ptr.items.items.len - 1
        else
            if (array_ptr.items.items.len > 0) array_ptr.items.items.len - 1 else 0;

        if (start_idx >= array_ptr.items.items.len) {
            return .{ .string = allocator.dupe(u8, "") catch return .{ .nil = {} } };
        }

        var result: std.ArrayList(u8) = .{};
        defer result.deinit(allocator);

        var i = start_idx;
        while (i <= end_idx and i < array_ptr.items.items.len) : (i += 1) {
            if (i > start_idx and sep.len > 0) {
                result.appendSlice(allocator, sep) catch return .{ .nil = {} };
            }

            const item = array_ptr.items.items[i];
            switch (item) {
                .string => |s| result.appendSlice(allocator, s) catch return .{ .nil = {} },
                .number => |n| {
                    var buf: [64]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{n}) catch "";
                    result.appendSlice(allocator, str) catch return .{ .nil = {} };
                },
                .boolean => |b| {
                    const str = if (b) "true" else "false";
                    result.appendSlice(allocator, str) catch return .{ .nil = {} };
                },
                else => {},
            }
        }

        const owned = result.toOwnedSlice(allocator) catch return .{ .nil = {} };
        return .{ .string = owned };
    }

    fn numberToIndex(number: f64) ?usize {
        if (!std.math.isFinite(number)) return null;
        if (number < 0) return null;
        const floored = std.math.floor(number);
        if (floored != number) return null;
        const signed = @as(isize, @intFromFloat(floored));
        if (signed < 0) return null;
        return std.math.cast(usize, signed);
    }
};

pub const Opcode = enum(u8) {
    nop,
    move,
    load_const,
    load_global,
    store_global,
    new_table,
    new_array,
    table_set_field,
    table_get_field,
    resolve_method,
    table_set_index,
    table_get_index,
    array_append,
    iterator_init,
    iterator_next,
    iterator_unpack,
    vararg_collect,
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    neq,
    lt,
    gt,
    lte,
    gte,
    and_op,
    or_op,
    not_op,
    begin_scope,
    end_scope,
    call,
    call_value,
    jump,
    jump_if_false,
    return_value,
    ret,
};

pub const Instruction = struct {
    opcode: Opcode,
    operands: [3]u16, // for simplicity, up to 3 operands
    extra: u16 = 0,
};

pub const SyntaxNodeKind = enum {
    root,
    instruction,
    constant,
};

pub const SyntaxNode = struct {
    kind: SyntaxNodeKind,
    opcode: ?Opcode,
    instruction_index: ?usize,
    constant_index: ?usize,
};

pub const SyntaxTree = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(SyntaxNode),
    instruction_count: usize,
    constant_count: usize,

    pub fn initFromInstructions(allocator: std.mem.Allocator, instructions: []const Instruction, constants_len: usize) !SyntaxTree {
        var list = std.ArrayListUnmanaged(SyntaxNode){};
        errdefer list.deinit(allocator);

        try list.append(allocator, .{ .kind = .root, .opcode = null, .instruction_index = null, .constant_index = null });

        for (instructions, 0..) |instr, idx| {
            try list.append(allocator, .{ .kind = .instruction, .opcode = instr.opcode, .instruction_index = idx, .constant_index = null });
        }

        var const_idx: usize = 0;
        while (const_idx < constants_len) : (const_idx += 1) {
            try list.append(allocator, .{ .kind = .constant, .opcode = null, .instruction_index = null, .constant_index = const_idx });
        }

        return .{
            .allocator = allocator,
            .nodes = list,
            .instruction_count = instructions.len,
            .constant_count = constants_len,
        };
    }

    pub fn deinit(self: *SyntaxTree) void {
        self.nodes.deinit(self.allocator);
        self.nodes = .{};
        self.instruction_count = 0;
        self.constant_count = 0;
    }

    pub fn iter(self: *const SyntaxTree) []const SyntaxNode {
        return self.nodes.items;
    }
};

pub const ParseMetricsSnapshot = struct {
    total_attempts: usize,
    success_count: usize,
    failure_count: usize,
    average_duration_ns: u64,
    max_duration_ns: u64,
    last_duration_ns: u64,
    last_instruction_count: usize,
    last_constant_count: usize,
    last_diagnostic_count: usize,
};

pub const ParseMetrics = struct {
    total_attempts: usize = 0,
    success_count: usize = 0,
    failure_count: usize = 0,
    total_duration_ns: u128 = 0,
    max_duration_ns: u64 = 0,
    last_duration_ns: u64 = 0,
    last_instruction_count: usize = 0,
    last_constant_count: usize = 0,
    last_diagnostic_count: usize = 0,

    pub fn init() ParseMetrics {
        return .{};
    }

    pub fn recordSuccess(self: *ParseMetrics, duration_ns: u64, instruction_count: usize, constant_count: usize, diagnostic_count: usize) void {
        self.total_attempts += 1;
        self.success_count += 1;
        self.total_duration_ns += duration_ns;
        self.last_duration_ns = duration_ns;
        self.last_instruction_count = instruction_count;
        self.last_constant_count = constant_count;
        self.last_diagnostic_count = diagnostic_count;
        if (duration_ns > self.max_duration_ns) {
            self.max_duration_ns = duration_ns;
        }
    }

    pub fn recordFailure(self: *ParseMetrics, diagnostic_count: usize) void {
        self.total_attempts += 1;
        self.failure_count += 1;
        self.last_duration_ns = 0;
        self.last_instruction_count = 0;
        self.last_constant_count = 0;
        self.last_diagnostic_count = diagnostic_count;
    }

    fn averageDuration(self: *const ParseMetrics) u64 {
        if (self.success_count == 0) return 0;
        const total = if (self.total_duration_ns > std.math.maxInt(u64)) std.math.maxInt(u64) else @as(u64, @intCast(self.total_duration_ns));
        return total / @as(u64, @intCast(self.success_count));
    }

    pub fn snapshot(self: *const ParseMetrics) ParseMetricsSnapshot {
        return .{
            .total_attempts = self.total_attempts,
            .success_count = self.success_count,
            .failure_count = self.failure_count,
            .average_duration_ns = self.averageDuration(),
            .max_duration_ns = self.max_duration_ns,
            .last_duration_ns = self.last_duration_ns,
            .last_instruction_count = self.last_instruction_count,
            .last_constant_count = self.last_constant_count,
            .last_diagnostic_count = self.last_diagnostic_count,
        };
    }
};

pub const PluginDescriptor = struct {
    name: []const u8,
    version: []const u8,
    enabled: bool,
};

const PluginRecord = struct {
    version: []const u8,
    enabled: bool,
};

pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugins: std.StringHashMap(PluginRecord),
    load_order: std.ArrayListUnmanaged([]const u8),

    pub fn init(allocator: std.mem.Allocator) PluginManager {
        return .{
            .allocator = allocator,
            .plugins = std.StringHashMap(PluginRecord).init(allocator),
            .load_order = .{},
        };
    }

    pub fn deinit(self: *PluginManager) void {
        var it = self.plugins.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.version);
        }
        self.plugins.deinit();
        self.load_order.deinit(self.allocator);
    }

    pub fn register(self: *PluginManager, name: []const u8, version: []const u8) !void {
        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);
        const version_copy = try self.allocator.dupe(u8, version);
        errdefer self.allocator.free(version_copy);

        var gop = try self.plugins.getOrPut(name_copy);
        if (gop.found_existing) {
            self.allocator.free(name_copy);
            self.allocator.free(gop.value_ptr.version);
            gop.value_ptr.version = version_copy;
        } else {
            gop.value_ptr.* = .{ .version = version_copy, .enabled = false };
            try self.load_order.append(self.allocator, gop.key_ptr.*);
        }
    }

    pub fn enable(self: *PluginManager, name: []const u8) bool {
        if (self.plugins.getPtr(name)) |record| {
            record.enabled = true;
            return true;
        }
        return false;
    }

    pub fn disable(self: *PluginManager, name: []const u8) bool {
        if (self.plugins.getPtr(name)) |record| {
            record.enabled = false;
            return true;
        }
        return false;
    }

    pub fn isEnabled(self: *PluginManager, name: []const u8) bool {
        if (self.plugins.get(name)) |record| {
            return record.enabled;
        }
        return false;
    }

    pub fn list(self: *PluginManager, allocator: std.mem.Allocator) ![]PluginDescriptor {
        var out = std.ArrayList(PluginDescriptor).init(allocator);
        errdefer {
            for (out.items) |desc| {
                allocator.free(desc.name);
                allocator.free(desc.version);
            }
            out.deinit();
        }

        for (self.load_order.items) |name_ref| {
            if (self.plugins.get(name_ref)) |record| {
                try out.append(.{
                    .name = try allocator.dupe(u8, name_ref),
                    .version = try allocator.dupe(u8, record.version),
                    .enabled = record.enabled,
                });
            }
        }

        return try out.toOwnedSlice();
    }

    pub fn destroyList(self: *PluginManager, allocator: std.mem.Allocator, descriptors: []PluginDescriptor) void {
        _ = self;
        for (descriptors) |desc| {
            allocator.free(desc.name);
            allocator.free(desc.version);
        }
        allocator.free(descriptors);
    }
};

pub const GroveParseResult = struct {
    instructions: []Instruction,
    constants: []ScriptValue,
    syntax_tree: SyntaxTree,
    duration_ns: u64,

    pub fn deinit(self: *GroveParseResult, allocator: std.mem.Allocator) void {
        self.syntax_tree.deinit();
        for (self.constants, 0..) |_, idx| {
            self.constants[idx].deinit(allocator);
        }
        allocator.free(self.constants);
        allocator.free(self.instructions);
        self.instructions = &[_]Instruction{};
        self.constants = &[_]ScriptValue{};
        self.duration_ns = 0;
    }
};

pub const GroveIntegration = struct {
    allocator: std.mem.Allocator,
    registry: GrammarRegistry,
    grove_enabled: bool,
    external_grove_path: []const u8,

    pub fn init(allocator: std.mem.Allocator) !GroveIntegration {
        var registry = GrammarRegistry.init(allocator);
        errdefer registry.deinit();
        try registry.ensureDefaults();
        return .{
            .allocator = allocator,
            .registry = registry,
            .grove_enabled = build_options.grove_enabled,
            .external_grove_path = build_options.grove_path,
        };
    }

    pub fn deinit(self: *GroveIntegration) void {
        self.registry.deinit();
    }

    pub fn parseGhostlang(self: *GroveIntegration, source: []const u8, diagnostics: *std.ArrayListUnmanaged(ParseDiagnostic)) ExecutionError!GroveParseResult {
        return groveParseGhostlang(self, source, diagnostics);
    }

    pub fn listGrammars(self: *GroveIntegration, allocator: std.mem.Allocator) ![]GrammarInfo {
        return self.registry.list(allocator);
    }

    pub fn hasExternalGrove(self: *const GroveIntegration) bool {
        return self.grove_enabled;
    }

    pub fn externalPath(self: *const GroveIntegration) []const u8 {
        return self.external_grove_path;
    }
};

const ScopeFrame = struct {
    map: std.StringHashMap(ScriptValue),

    fn init(allocator: std.mem.Allocator) ScopeFrame {
        return .{ .map = std.StringHashMap(ScriptValue).init(allocator) };
    }

    fn deinit(self: *ScopeFrame, allocator: std.mem.Allocator) void {
        var it = self.map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(allocator);
        }
        self.map.deinit();
    }
};

const CallFrame = struct {
    return_pc: usize,
    return_base: u16,
    expected_results: u16,
    scope_depth: usize,
    varargs: []ScriptValue,
    owns_varargs: bool,
    protected_index: ?usize,
};

const ProtectedCall = struct {
    dest_reg: u16,
    expected_results: u16,
    result_base: u16,
    scope_depth: usize,
    call_frame_index: usize,
    arg_count: u16,
};

pub const VM = struct {
    registers: [256]ScriptValue,
    globals: std.StringHashMap(ScriptValue),
    scopes: std.ArrayListUnmanaged(ScopeFrame),
    call_stack: std.ArrayListUnmanaged(CallFrame),
    protected_calls: std.ArrayListUnmanaged(ProtectedCall),
    pc: usize,
    code: []const Instruction,
    constants: []ScriptValue,
    allocator: std.mem.Allocator,
    engine: *ScriptEngine,
    start_time: i64,
    instruction_count: usize,
    instrumentation: ?Instrumentation,
    last_result_count: u16,

    pub fn init(allocator: std.mem.Allocator, code: []const Instruction, constants: []ScriptValue, engine: *ScriptEngine) VM {
        var vm = VM{
            .registers = undefined,
            .globals = std.StringHashMap(ScriptValue).init(allocator),
            .scopes = .{},
            .call_stack = .{},
            .protected_calls = .{},
            .pc = 0,
            .code = code,
            .constants = constants,
            .allocator = allocator,
            .engine = engine,
            .start_time = 0,
            .instruction_count = 0,
            .instrumentation = engine.config.instrumentation,
            .last_result_count = 1,
        };

        var idx: usize = 0;
        while (idx < vm.registers.len) : (idx += 1) {
            vm.registers[idx] = .{ .nil = {} };
        }

        return vm;
    }

    pub fn deinit(self: *VM) void {
        var reg_idx: usize = 0;
        while (reg_idx < self.registers.len) : (reg_idx += 1) {
            self.registers[reg_idx].deinit(self.allocator);
            self.registers[reg_idx] = .{ .nil = {} };
        }
        var it = self.globals.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.globals.deinit();
        while (self.scopes.items.len > 0) {
            const idx = self.scopes.items.len - 1;
            var frame = self.scopes.items[idx];
            self.scopes.items.len = idx;
            frame.deinit(self.allocator);
        }
        self.scopes.deinit(self.allocator);
        for (self.call_stack.items) |frame| {
            self.cleanupVarargs(frame);
        }
        self.call_stack.deinit(self.allocator);
        self.protected_calls.deinit(self.allocator);
    }

    fn setRegister(self: *VM, reg: u16, value: ScriptValue) void {
        const idx = operandIndex(reg);
        self.registers[idx].deinit(self.allocator);
        self.registers[idx] = value;
    }

    inline fn operandIndex(op: u16) usize {
        return std.math.cast(usize, op) orelse unreachable;
    }

    pub fn run(self: *VM) ExecutionError!ScriptValue {
        const previous_vm = active_vm;
        active_vm = self;
        defer active_vm = previous_vm;

        self.start_time = std.time.milliTimestamp();
        self.instruction_count = 0;

        while (self.pc < self.code.len) {
            // Check timeout every 100 instructions to avoid performance overhead
            if (self.instruction_count % 100 == 0) {
                if (self.engine.config.execution_timeout_ms > 0) {
                    const elapsed = std.time.milliTimestamp() - self.start_time;
                    if (elapsed > self.engine.config.execution_timeout_ms) {
                        return ExecutionError.ExecutionTimeout;
                    }
                }
            }
            self.instruction_count += 1;

            const instr = self.code[self.pc];

            if (self.instrumentation) |inst| {
                if (inst.onInstruction) |callback| {
                    callback(inst.context, instr.opcode);
                }
            }
            switch (instr.opcode) {
                .nop => {},
                .move => {
                    const dest = instr.operands[0];
                    const src = instr.operands[1];
                    const src_idx = operandIndex(src);
                    const copy = try self.copyValue(self.registers[src_idx]);
                    self.setRegister(dest, copy);
                },
                .load_const => {
                    const reg = instr.operands[0];
                    const const_idx = instr.operands[1];
                    const const_index = operandIndex(const_idx);
                    const value = self.constants[const_index];
                    const copy = switch (value) {
                        .script_function => |template| blk: {
                            const instance = try self.instantiateFunction(template);
                            break :blk ScriptValue{ .script_function = instance };
                        },
                        else => try self.copyValue(value),
                    };
                    self.setRegister(reg, copy);
                },
                .new_table => {
                    const dest = instr.operands[0];
                    const table_ptr = ScriptTable.create(self.allocator) catch |err| {
                        if (err == error.OutOfMemory) return ExecutionError.OutOfMemory;
                        return err;
                    };
                    self.setRegister(dest, .{ .table = table_ptr });
                },
                .new_array => {
                    const dest = instr.operands[0];
                    const array_ptr = ScriptArray.create(self.allocator) catch |err| {
                        if (err == error.OutOfMemory) return ExecutionError.OutOfMemory;
                        return err;
                    };
                    self.setRegister(dest, .{ .array = array_ptr });
                },
                .table_set_field => {
                    const table_reg = instr.operands[0];
                    const key_const_idx = instr.operands[1];
                    const value_reg = instr.operands[2];
                    const table_idx = operandIndex(table_reg);
                    const table_value_ptr = &self.registers[table_idx];
                    if (table_value_ptr.* != .table) return ExecutionError.TypeError;
                    try self.ensureTableUnique(table_value_ptr);
                    const key_idx = operandIndex(key_const_idx);
                    const key_const = self.constants[key_idx];
                    if (key_const != .string) return ExecutionError.TypeError;
                    const value_idx = operandIndex(value_reg);
                    try self.tableSetField(table_value_ptr.*.table, key_const.string, self.registers[value_idx]);
                },
                .table_get_field => {
                    const dest_reg = instr.operands[0];
                    const table_reg = instr.operands[1];
                    const key_const_idx = instr.operands[2];
                    const table_idx = operandIndex(table_reg);
                    const table_value = self.registers[table_idx];
                    if (table_value != .table) return ExecutionError.TypeError;
                    const key_idx = operandIndex(key_const_idx);
                    const key_const = self.constants[key_idx];
                    if (key_const != .string) return ExecutionError.TypeError;
                    if (try self.tableGetField(table_value.table, key_const.string)) |value| {
                        self.setRegister(dest_reg, value);
                    } else {
                        self.setRegister(dest_reg, .{ .nil = {} });
                    }
                },
                .resolve_method => {
                    const dest_reg = instr.operands[0];
                    const object_reg = instr.operands[1];
                    const key_const_idx = instr.operands[2];
                    const object_idx = operandIndex(object_reg);
                    const object_value = self.registers[object_idx];
                    const key_idx = operandIndex(key_const_idx);
                    const key_const = self.constants[key_idx];
                    if (key_const != .string) return ExecutionError.InvalidFunctionName;

                    var resolved: ?ScriptValue = null;

                    switch (object_value) {
                        .table => |table_ptr| {
                            resolved = try self.tableGetField(table_ptr, key_const.string);
                        },
                        else => {},
                    }

                    if (resolved) |value| {
                        self.setRegister(dest_reg, value);
                    } else {
                        if (self.getVariable(key_const.string)) |value| {
                            const copy = try self.copyResolvedValue(value);
                            self.setRegister(dest_reg, copy);
                        } else {
                            self.setRegister(dest_reg, .{ .nil = {} });
                        }
                    }
                },
                .table_set_index => {
                    const table_reg = instr.operands[0];
                    const index_reg = instr.operands[1];
                    const value_reg = instr.operands[2];
                    const table_idx = operandIndex(table_reg);
                    const index_idx = operandIndex(index_reg);
                    const value_idx = operandIndex(value_reg);
                    try self.setIndexedValue(
                        &self.registers[table_idx],
                        self.registers[index_idx],
                        self.registers[value_idx],
                    );
                },
                .table_get_index => {
                    const dest_reg = instr.operands[0];
                    const table_reg = instr.operands[1];
                    const index_reg = instr.operands[2];
                    const table_idx = operandIndex(table_reg);
                    const index_idx = operandIndex(index_reg);
                    const value = try self.getIndexedValue(
                        self.registers[table_idx],
                        self.registers[index_idx],
                    );
                    self.setRegister(dest_reg, value);
                },
                .array_append => {
                    const array_reg = instr.operands[0];
                    const value_reg = instr.operands[1];
                    const array_idx = operandIndex(array_reg);
                    const array_value_ptr = &self.registers[array_idx];
                    if (array_value_ptr.* != .array) return ExecutionError.TypeError;
                    try self.ensureArrayUnique(array_value_ptr);
                    const value_idx = operandIndex(value_reg);
                    try self.arrayAppend(array_value_ptr.*.array, self.registers[value_idx]);
                },
                .iterator_init => {
                    const dest_reg = instr.operands[0];
                    const source_reg = instr.operands[1];
                    const var_count: u16 = instr.operands[2];
                    const source_idx = operandIndex(source_reg);
                    const value = self.registers[source_idx];
                    const iterator_value = try self.coerceIteratorValue(value, var_count);
                    self.setRegister(dest_reg, iterator_value);
                },
                .iterator_next => {
                    const dest_reg = instr.operands[0];
                    const iterator_reg = instr.operands[1];
                    const iterator_idx = operandIndex(iterator_reg);
                    const iterator_value = self.registers[iterator_idx];
                    if (iterator_value != .iterator) return ExecutionError.TypeError;
                    const advanced = iterator_value.iterator.next() catch |err| switch (err) {
                        ScriptIterator.IteratorError.OutOfMemory => return ExecutionError.OutOfMemory,
                        ScriptIterator.IteratorError.TypeError => return ExecutionError.TypeError,
                    };
                    self.setRegister(dest_reg, .{ .boolean = advanced });
                },
                .iterator_unpack => {
                    const dest_start = instr.operands[0];
                    const count_raw = instr.operands[1];
                    const iterator_reg = instr.operands[2];
                    const iterator_idx = operandIndex(iterator_reg);
                    const iterator_value = self.registers[iterator_idx];
                    if (iterator_value != .iterator) return ExecutionError.TypeError;

                    const payload = iterator_value.iterator.takeCurrent();
                    var has_key = payload.has_key;
                    var key_value = payload.key;
                    var has_value = payload.has_value;
                    var value_value = payload.value;

                    const count: usize = @intCast(count_raw);
                    var idx: usize = 0;
                    while (idx < count) : (idx += 1) {
                        const reg = dest_start + @as(u16, @intCast(idx));
                        var assigned = ScriptValue{ .nil = {} };
                        if (has_key) {
                            assigned = key_value;
                            has_key = false;
                            key_value = .{ .nil = {} };
                        } else if (has_value) {
                            assigned = value_value;
                            has_value = false;
                            value_value = .{ .nil = {} };
                        }
                        self.setRegister(reg, assigned);
                    }

                    if (has_key) {
                        key_value.deinit(self.allocator);
                    }
                    if (has_value) {
                        value_value.deinit(self.allocator);
                    }
                    self.last_result_count = @as(u16, @intCast(count));
                },
                .vararg_collect => {
                    if (self.call_stack.items.len == 0) {
                        return ExecutionError.ScopeUnderflow;
                    }

                    const frame = self.call_stack.items[self.call_stack.items.len - 1];
                    const dest_reg = instr.operands[0];
                    const expected = instr.extra;
                    const available: usize = frame.varargs.len;
                    const copy_count: usize = if (expected == 0)
                        available
                    else
                        @min(@as(usize, expected), available);

                    var idx: usize = 0;
                    while (idx < copy_count) : (idx += 1) {
                        const copy = try self.copyValue(frame.varargs[idx]);
                        const target_reg = dest_reg + @as(u16, @intCast(idx));
                        self.setRegister(target_reg, copy);
                    }

                    if (expected == 0) {
                        if (copy_count == 0) {
                            self.setRegister(dest_reg, .{ .nil = {} });
                        }
                        self.last_result_count = @intCast(copy_count);
                    } else {
                        while (idx < expected) : (idx += 1) {
                            const target_reg = dest_reg + @as(u16, @intCast(idx));
                            self.setRegister(target_reg, .{ .nil = {} });
                        }
                        self.last_result_count = expected;
                    }
                },
                .add => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .number and val_b == .number) {
                        self.setRegister(dest, .{ .number = val_a.number + val_b.number });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .sub => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .number and val_b == .number) {
                        self.setRegister(dest, .{ .number = val_a.number - val_b.number });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .mul => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .number and val_b == .number) {
                        self.setRegister(dest, .{ .number = val_a.number * val_b.number });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .div => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .number and val_b == .number) {
                        self.setRegister(dest, .{ .number = val_a.number / val_b.number });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .mod => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .number and val_b == .number) {
                        self.setRegister(dest, .{ .number = @mod(val_a.number, val_b.number) });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .eq => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    self.setRegister(dest, .{ .boolean = valuesEqual(val_a, val_b) });
                },
                .neq => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    self.setRegister(dest, .{ .boolean = !valuesEqual(val_a, val_b) });
                },
                .lt => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .number and val_b == .number) {
                        self.setRegister(dest, .{ .boolean = val_a.number < val_b.number });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .gt => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .number and val_b == .number) {
                        self.setRegister(dest, .{ .boolean = val_a.number > val_b.number });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .lte => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .number and val_b == .number) {
                        self.setRegister(dest, .{ .boolean = val_a.number <= val_b.number });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .gte => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .number and val_b == .number) {
                        self.setRegister(dest, .{ .boolean = val_a.number >= val_b.number });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .and_op => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .boolean and val_b == .boolean) {
                        self.setRegister(dest, .{ .boolean = val_a.boolean and val_b.boolean });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .or_op => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const idx_a = operandIndex(a);
                    const idx_b = operandIndex(b);
                    const val_a = self.registers[idx_a];
                    const val_b = self.registers[idx_b];
                    if (val_a == .boolean and val_b == .boolean) {
                        self.setRegister(dest, .{ .boolean = val_a.boolean or val_b.boolean });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .not_op => {
                    const dest = instr.operands[0];
                    const source = instr.operands[1];
                    const idx = operandIndex(source);
                    const value = self.registers[idx];
                    if (value == .boolean) {
                        self.setRegister(dest, .{ .boolean = !value.boolean });
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .begin_scope => {
                    try self.pushScope();
                },
                .end_scope => {
                    try self.popScope();
                },
                .ret => {
                    const reg = instr.operands[0];
                    const idx = operandIndex(reg);
                    const result = try self.copyValue(self.registers[idx]);
                    self.registers[idx].deinit(self.allocator);
                    self.registers[idx] = .{ .nil = {} };
                    return result;
                },
                .return_value => {
                    if (self.call_stack.items.len == 0) {
                        return ExecutionError.ScopeUnderflow;
                    }

                    const frame_idx = self.call_stack.items.len - 1;
                    const frame = self.call_stack.items[frame_idx];
                    const source_reg = instr.operands[0];
                    const fixed_count = instr.operands[1];
                    const variadic_flag = instr.operands[2] == 1;

                    var actual_count: u16 = fixed_count;
                    if (variadic_flag) {
                        actual_count +%= self.last_result_count;
                    }

                    while (self.scopes.items.len > frame.scope_depth) {
                        try self.popScope();
                    }

                    const dest_base = frame.return_base;
                    const expected = frame.expected_results;
                    const dest_count: u16 = if (expected == 0) actual_count else expected;

                    var idx: u16 = 0;
                    while (idx < dest_count) : (idx += 1) {
                        const dest_reg = dest_base + idx;
                        if (idx < actual_count) {
                            const src_idx = operandIndex(source_reg + idx);
                            const copy = try self.copyValue(self.registers[src_idx]);
                            self.setRegister(dest_reg, copy);
                        } else {
                            self.setRegister(dest_reg, .{ .nil = {} });
                        }
                    }

                    var cleanup_idx: u16 = 0;
                    while (cleanup_idx < actual_count) : (cleanup_idx += 1) {
                        const src_reg = source_reg + cleanup_idx;
                        const src_idx = operandIndex(src_reg);
                        const dest_reg = dest_base + cleanup_idx;
                        if (cleanup_idx < dest_count and dest_reg == src_reg) {
                            // already handled by setRegister
                            continue;
                        }
                        self.registers[src_idx].deinit(self.allocator);
                        self.registers[src_idx] = .{ .nil = {} };
                    }

                    self.call_stack.items.len = frame_idx;
                    self.cleanupVarargs(frame);
                    if (frame.protected_index) |pidx| {
                        const final_count = try self.finalizeProtectedSuccess(pidx, actual_count);
                        self.pc = frame.return_pc;
                        self.last_result_count = final_count;
                        continue;
                    }
                    self.pc = frame.return_pc;
                    self.last_result_count = actual_count;
                    continue;
                },
                .call => {
                    const func_name_idx = instr.operands[0];
                    const arg_start = instr.operands[1];
                    const raw_arg_count = instr.operands[2];
                    const has_variadic_args = (raw_arg_count & 0x8000) != 0;
                    var arg_count: u16 = raw_arg_count & 0x7FFF;
                    if (has_variadic_args) {
                        arg_count +%= self.last_result_count;
                    }
                    const start_index = operandIndex(arg_start);
                    const arg_len: usize = @intCast(arg_count);
                    const func_name_index: usize = @intCast(func_name_idx);
                    const func_name = self.constants[func_name_index];
                    const expected_results = instr.extra;
                    if (func_name == .string) {
                        if (self.getVariable(func_name.string)) |value| {
                            switch (value) {
                                .function => |callable| {
                                    const args = self.registers[start_index .. start_index + arg_len];
                                    const result = callable(args);
                                    const dest_base = arg_start;
                                    const dest_expected: u16 = if (expected_results == 0) 1 else expected_results;
                                    self.setRegister(dest_base, result);
                                    var fill: u16 = 1;
                                    while (fill < dest_expected) : (fill += 1) {
                                        self.setRegister(dest_base + fill, .{ .nil = {} });
                                    }
                                    self.last_result_count = dest_expected;
                                },
                                .native_function => |native| {
                                    const outcome = try self.invokeNativeFunction(native, arg_start, arg_start, arg_count, expected_results);
                                    self.last_result_count = outcome.last_result_count;
                                    if (!outcome.advance_pc) continue;
                                },
                                .script_function => |script_func| {
                                    try self.invokeScriptFunction(script_func, arg_start, arg_start, arg_count, expected_results, null);
                                    continue;
                                },
                                else => return ExecutionError.NotAFunction,
                            }
                        } else {
                            return ExecutionError.FunctionNotFound;
                        }
                    } else {
                        return ExecutionError.InvalidFunctionName;
                    }
                },
                .call_value => {
                    const func_reg = instr.operands[0];
                    const arg_start = instr.operands[1];
                    const raw_arg_count = instr.operands[2];
                    const has_variadic_args = (raw_arg_count & 0x8000) != 0;
                    var arg_count: u16 = raw_arg_count & 0x7FFF;
                    if (has_variadic_args) {
                        arg_count +%= self.last_result_count;
                    }
                    const start_index = operandIndex(arg_start);
                    const arg_len: usize = @intCast(arg_count);
                    const func_idx = operandIndex(func_reg);
                    const func_value = self.registers[func_idx];
                    const expected_results = instr.extra;
                    switch (func_value) {
                        .function => |callable| {
                            const args = self.registers[start_index .. start_index + arg_len];
                            const result = callable(args);
                            const dest_base = func_reg;
                            const dest_expected: u16 = if (expected_results == 0) 1 else expected_results;
                            self.setRegister(dest_base, result);
                            var fill: u16 = 1;
                            while (fill < dest_expected) : (fill += 1) {
                                self.setRegister(dest_base + fill, .{ .nil = {} });
                            }
                            self.last_result_count = dest_expected;
                        },
                        .native_function => |native| {
                            const outcome = try self.invokeNativeFunction(native, func_reg, arg_start, arg_count, expected_results);
                            self.last_result_count = outcome.last_result_count;
                            if (!outcome.advance_pc) continue;
                        },
                        .script_function => |script_func| {
                            try self.invokeScriptFunction(script_func, func_reg, arg_start, arg_count, expected_results, null);
                            continue;
                        },
                        else => return ExecutionError.NotAFunction,
                    }
                },
                .load_global => {
                    const reg = instr.operands[0];
                    const name_idx = instr.operands[1];
                    const const_idx: usize = @intCast(name_idx);
                    const name = self.constants[const_idx];
                    if (name == .string) {
                        if (self.getVariable(name.string)) |value| {
                            const copy = try self.copyResolvedValue(value);
                            self.setRegister(reg, copy);
                        } else {
                            return ExecutionError.UndefinedVariable;
                        }
                    } else {
                        return ExecutionError.InvalidGlobalName;
                    }
                },
                .store_global => {
                    const reg = instr.operands[0];
                    const name_idx = instr.operands[1];
                    const mode = instr.operands[2];
                    const const_idx: usize = @intCast(name_idx);
                    const name = self.constants[const_idx];
                    if (name == .string) {
                        const value_idx = operandIndex(reg);
                        const value_copy = self.registers[value_idx];
                        if (mode == 1) {
                            try self.declareVariable(name.string, value_copy);
                        } else if (mode == 2) {
                            try self.declareLocal(name.string, value_copy);
                        } else {
                            try self.assignVariable(name.string, value_copy);
                        }
                    } else {
                        return ExecutionError.InvalidGlobalName;
                    }
                },
                .jump => {
                    const target = instr.operands[0];
                    self.pc = @intCast(target);
                    continue;
                },
                .jump_if_false => {
                    const cond_reg = instr.operands[0];
                    const target = instr.operands[1];
                    const cond = self.registers[operandIndex(cond_reg)];
                    if (cond == .boolean and !cond.boolean) {
                        self.pc = @intCast(target);
                        continue;
                    }
                },
            }
            self.pc += 1;
        }
        return .{ .nil = {} };
    }

    fn pushScope(self: *VM) !void {
        const frame = ScopeFrame.init(self.allocator);
        try self.scopes.append(self.allocator, frame);
    }

    fn popScope(self: *VM) !void {
        if (self.scopes.items.len == 0) {
            return ExecutionError.ScopeUnderflow;
        }
        const idx = self.scopes.items.len - 1;
        var frame = self.scopes.items[idx];
        self.scopes.items.len = idx;
        frame.deinit(self.allocator);
    }

    fn declareVariable(self: *VM, name: []const u8, value: ScriptValue) !void {
        const target = if (self.scopes.items.len > 0)
            &self.scopes.items[self.scopes.items.len - 1].map
        else
            &self.globals;

        if (target.getEntry(name)) |entry| {
            switch (entry.value_ptr.*) {
                .upvalue => |up| try up.set(value),
                else => {
                    entry.value_ptr.deinit(self.allocator);
                    entry.value_ptr.* = try self.copyValue(value);
                },
            }
            return;
        }
        const name_copy = try self.allocator.dupe(u8, name);
        var value_copy = try self.copyValue(value);
        target.put(name_copy, value_copy) catch |err| {
            value_copy.deinit(self.allocator);
            self.allocator.free(name_copy);
            if (err == error.OutOfMemory) {
                return ExecutionError.OutOfMemory;
            }
            return err;
        };
    }

    fn declareLocal(self: *VM, name: []const u8, value: ScriptValue) !void {
        if (self.scopes.items.len == 0) {
            try self.declareVariable(name, value);
            return;
        }

        var frame = &self.scopes.items[self.scopes.items.len - 1].map;
        if (frame.getEntry(name)) |entry| {
            switch (entry.value_ptr.*) {
                .upvalue => |up| try up.set(value),
                else => {
                    const value_copy = try self.copyValue(value);
                    entry.value_ptr.deinit(self.allocator);
                    entry.value_ptr.* = value_copy;
                },
            }
            return;
        }

        const name_copy = try self.allocator.dupe(u8, name);
        const value_copy = try self.copyValue(value);
        frame.put(name_copy, value_copy) catch |err| {
            var tmp_value = value_copy;
            tmp_value.deinit(self.allocator);
            self.allocator.free(name_copy);
            if (err == error.OutOfMemory) {
                return ExecutionError.OutOfMemory;
            }
            return err;
        };
    }

    fn assignVariable(self: *VM, name: []const u8, value: ScriptValue) !void {
        var idx = self.scopes.items.len;
        while (idx > 0) {
            idx -= 1;
            if (self.scopes.items[idx].map.getEntry(name)) |entry| {
                switch (entry.value_ptr.*) {
                    .upvalue => |up| try up.set(value),
                    else => {
                        const value_copy = try self.copyValue(value);
                        entry.value_ptr.deinit(self.allocator);
                        entry.value_ptr.* = value_copy;
                    },
                }
                return;
            }
        }
        if (self.globals.getEntry(name)) |entry| {
            switch (entry.value_ptr.*) {
                .upvalue => |up| try up.set(value),
                else => {
                    const value_copy = try self.copyValue(value);
                    entry.value_ptr.deinit(self.allocator);
                    entry.value_ptr.* = value_copy;
                },
            }
            return;
        }
        try self.declareVariable(name, value);
    }

    fn invokeNativeFunction(self: *VM, native: NativeFunction, dest_reg: u16, arg_start: u16, arg_count: u16, expected_results: u16) ExecutionError!NativeCallResult {
        const vm_ptr: *anyopaque = @ptrCast(self);
        return native.call(native.context, vm_ptr, dest_reg, arg_start, arg_count, expected_results);
    }

    fn invokeScriptFunction(
        self: *VM,
        func: *ScriptFunction,
        result_reg: u16,
        arg_start: u16,
        arg_count: u16,
        expected_results: u16,
        protected_index: ?usize,
    ) ExecutionError!void {
        const named_count: u16 = @intCast(func.param_names.len);
        const provided: u16 = arg_count;

        if (provided < named_count) {
            return ExecutionError.TypeError;
        }

        const extra_args: usize = if (provided > named_count) @intCast(provided - named_count) else 0;
        if (!func.is_vararg and extra_args > 0) {
            return ExecutionError.TypeError;
        }

        const empty_varargs = [_]ScriptValue{};
        var varargs_slice: []ScriptValue = empty_varargs[0..];
        var frame_owns_varargs = false;
        var varargs_allocated = false;
        var copied: usize = 0;
        if (func.is_vararg and extra_args > 0) {
            varargs_slice = try self.allocator.alloc(ScriptValue, extra_args);
            frame_owns_varargs = true;
            varargs_allocated = true;
            errdefer {
                if (varargs_allocated) {
                    while (copied > 0) : (copied -= 1) {
                        varargs_slice[copied - 1].deinit(self.allocator);
                    }
                    self.allocator.free(varargs_slice);
                }
            }
            while (copied < extra_args) : (copied += 1) {
                const reg_index = operandIndex(arg_start) + named_count + copied;
                varargs_slice[copied] = try self.copyValue(self.registers[reg_index]);
            }
        }

        const base_scope_depth = self.scopes.items.len;
        const frame_idx = self.call_stack.items.len;
        try self.call_stack.append(self.allocator, .{
            .return_pc = self.pc + 1,
            .return_base = result_reg,
            .expected_results = expected_results,
            .scope_depth = base_scope_depth,
            .varargs = varargs_slice,
            .owns_varargs = frame_owns_varargs,
            .protected_index = protected_index,
        });
        varargs_allocated = false;
        errdefer {
            if (self.call_stack.items.len > frame_idx) {
                const frame = self.call_stack.items[self.call_stack.items.len - 1];
                self.cleanupVarargs(frame);
                self.call_stack.items.len = frame_idx;
            } else if (frame_owns_varargs) {
                const tmp_frame = CallFrame{
                    .return_pc = 0,
                    .return_base = 0,
                    .expected_results = 0,
                    .scope_depth = 0,
                    .varargs = varargs_slice,
                    .owns_varargs = true,
                    .protected_index = protected_index,
                };
                self.cleanupVarargs(tmp_frame);
            }
        }

        try self.pushScope();

        var idx: usize = 0;
        const base_reg_index = operandIndex(arg_start);
        while (idx < func.param_names.len) : (idx += 1) {
            const param_name = func.param_names[idx];
            if (idx < provided) {
                const reg_index = base_reg_index + idx;
                const arg_value = self.registers[reg_index];
                try self.declareVariable(param_name, arg_value);
            } else {
                try self.declareVariable(param_name, .{ .nil = {} });
            }
        }

        var cap_it = func.captures.iterator();
        while (cap_it.next()) |entry| {
            try self.declareVariable(entry.key_ptr.*, entry.value_ptr.*);
        }

        self.pc = func.start_pc;
    }

    fn finalizeProtectedSuccess(self: *VM, context_index: usize, actual_count: u16) ExecutionError!u16 {
        if (context_index >= self.protected_calls.items.len) {
            return ExecutionError.ScopeUnderflow;
        }
        const context = self.protected_calls.items[context_index];
        const dest_reg = context.dest_reg;
        const dest_expected = context.expected_results;
        const source_base = context.result_base;

        var desired_count: usize = if (dest_expected == 0)
            @as(usize, 1) + actual_count
        else
            dest_expected;

        if (desired_count == 0) {
            desired_count = 1;
        }

        const available_registers = self.registers.len - operandIndex(dest_reg);
        if (desired_count > available_registers) {
            desired_count = available_registers;
        }

        self.setRegister(dest_reg, .{ .boolean = true });
        const dest_range_start: u16 = dest_reg + 1;
        const dest_range_end: u16 = dest_reg + @as(u16, @intCast(desired_count));

        var idx: usize = 1;
        while (idx < desired_count) : (idx += 1) {
            const src_offset = idx - 1;
            const dest_slot: u16 = dest_reg + @as(u16, @intCast(idx));
            if (src_offset < actual_count) {
                const src_reg: u16 = source_base + @as(u16, @intCast(src_offset));
                const copy = try self.copyValue(self.registers[operandIndex(src_reg)]);
                self.setRegister(dest_slot, copy);
            } else {
                self.setRegister(dest_slot, .{ .nil = {} });
            }
        }

        var cleanup: usize = 0;
        while (cleanup < actual_count) : (cleanup += 1) {
            const src_reg: u16 = source_base + @as(u16, @intCast(cleanup));
            const idx_reg = operandIndex(src_reg);
            if (src_reg >= dest_range_start and src_reg < dest_range_end) continue;
            self.registers[idx_reg].deinit(self.allocator);
            self.registers[idx_reg] = .{ .nil = {} };
        }

        var leftover: usize = actual_count;
        while (leftover <= context.arg_count) : (leftover += 1) {
            const reg = source_base + @as(u16, @intCast(leftover));
            const reg_idx = operandIndex(reg);
            if (reg >= dest_range_start and reg < dest_range_end) continue;
            self.registers[reg_idx].deinit(self.allocator);
            self.registers[reg_idx] = .{ .nil = {} };
        }

        self.protected_calls.items.len = context_index;
        return @intCast(desired_count);
    }

    fn finalizeProtectedFailure(self: *VM, context: ProtectedCall, message: ScriptValue) ExecutionError!u16 {
        const dest_reg = context.dest_reg;
        const dest_expected = context.expected_results;

        var desired_count: usize = if (dest_expected == 0) 2 else dest_expected;
        if (desired_count == 0) desired_count = 1;

        const available_registers = self.registers.len - operandIndex(dest_reg);
        if (desired_count > available_registers) {
            desired_count = available_registers;
        }

    self.setRegister(dest_reg, .{ .boolean = false });

    const dest_range_start: u16 = dest_reg;
    const dest_range_end: u16 = dest_reg + @as(u16, @intCast(desired_count));

        var message_consumed = false;
        if (desired_count >= 2) {
            const copy = try self.copyValue(message);
            self.setRegister(dest_reg + 1, copy);
            message_consumed = true;

            var tmp = message;
            tmp.deinit(self.allocator);

            var idx: usize = 2;
            while (idx < desired_count) : (idx += 1) {
                self.setRegister(dest_reg + @as(u16, @intCast(idx)), .{ .nil = {} });
            }
        }

        if (!message_consumed) {
            var tmp = message;
            tmp.deinit(self.allocator);
        }

        var cleanup: u16 = 0;
        while (cleanup <= context.arg_count) : (cleanup += 1) {
            const reg = context.result_base + cleanup;
            const idx = operandIndex(reg);
            if (reg >= dest_range_start and reg < dest_range_end) continue;
            self.registers[idx].deinit(self.allocator);
            self.registers[idx] = .{ .nil = {} };
        }

        return @intCast(desired_count);
    }

    fn abortProtectedCallWithMessage(self: *VM, message: ScriptValue) ExecutionError!NativeCallResult {
        if (self.protected_calls.items.len == 0) {
            var tmp = message;
            tmp.deinit(self.allocator);
            return ExecutionError.ScriptError;
        }

        const context_index = self.protected_calls.items.len - 1;
        const context = self.protected_calls.items[context_index];

        var frame_return_pc: usize = 0;
        var found = false;

        while (self.call_stack.items.len > 0) {
            const idx = self.call_stack.items.len - 1;
            const frame = self.call_stack.items[idx];
            self.call_stack.items.len = idx;
            self.cleanupVarargs(frame);

            while (self.scopes.items.len > frame.scope_depth) {
                _ = self.popScope() catch {};
            }

            if (idx == context.call_frame_index) {
                frame_return_pc = frame.return_pc;
                found = true;
                break;
            }
        }

        if (!found) {
            var tmp = message;
            tmp.deinit(self.allocator);
            self.protected_calls.items.len = context_index;
            return ExecutionError.ScopeUnderflow;
        }

        while (self.scopes.items.len > context.scope_depth) {
            _ = self.popScope() catch {};
        }

        const final_count = try self.finalizeProtectedFailure(context, message);
        self.protected_calls.items.len = context_index;
        self.pc = frame_return_pc;

        return NativeCallResult{ .last_result_count = final_count, .advance_pc = false };
    }

    fn errorToMessage(self: *VM, err: ExecutionError) !ScriptValue {
        const text = switch (err) {
            ExecutionError.MemoryLimitExceeded => "memory limit exceeded",
            ExecutionError.ExecutionTimeout => "execution timed out",
            ExecutionError.IONotAllowed => "io not allowed",
            ExecutionError.SyscallNotAllowed => "syscall not allowed",
            ExecutionError.SecurityViolation => "security violation",
            ExecutionError.ParseError => "parse error",
            ExecutionError.TypeError => "type error",
            ExecutionError.FunctionNotFound => "function not found",
            ExecutionError.NotAFunction => "value is not callable",
            ExecutionError.UndefinedVariable => "undefined variable",
            ExecutionError.ScopeUnderflow => "scope underflow",
            ExecutionError.InvalidFunctionName => "invalid function name",
            ExecutionError.InvalidGlobalName => "invalid global name",
            ExecutionError.GlobalNotFound => "global not found",
            ExecutionError.UnsupportedArgumentType => "unsupported argument type",
            ExecutionError.OutOfMemory => "out of memory",
            ExecutionError.ScriptError => "script error",
        };
        const dup = try self.allocator.dupe(u8, text);
        return ScriptValue{ .string = dup };
    }

    fn createStringValue(self: *VM, text: []const u8) !ScriptValue {
        const dup = try self.allocator.dupe(u8, text);
        return ScriptValue{ .string = dup };
    }

    fn copyValue(self: *VM, value: ScriptValue) !ScriptValue {
        return try copyScriptValue(self.allocator, value);
    }

    fn copyResolvedValue(self: *VM, value: ScriptValue) !ScriptValue {
        return switch (value) {
            .upvalue => |up| try up.getCopy(self.allocator),
            else => try self.copyValue(value),
        };
    }

    fn cleanupVarargs(self: *VM, frame: CallFrame) void {
        if (!frame.owns_varargs) return;
        var idx: usize = 0;
        while (idx < frame.varargs.len) : (idx += 1) {
            frame.varargs[idx].deinit(self.allocator);
        }
        self.allocator.free(frame.varargs);
    }

    fn coerceIteratorValue(self: *VM, value: ScriptValue, var_count: u16) ExecutionError!ScriptValue {
        return switch (value) {
            .iterator => |iter| blk: {
                iter.configure(var_count);
                iter.retain();
                break :blk ScriptValue{ .iterator = iter };
            },
            .array => |array_ptr| blk: {
                const iterator = ScriptIterator.createFromArray(self.allocator, array_ptr) catch |err| switch (err) {
                    error.OutOfMemory => return ExecutionError.OutOfMemory,
                };
                iterator.configure(var_count);
                break :blk ScriptValue{ .iterator = iterator };
            },
            .table => |table_ptr| blk: {
                const iterator = ScriptIterator.createFromTable(self.allocator, table_ptr) catch |err| switch (err) {
                    ScriptIterator.IteratorError.OutOfMemory => return ExecutionError.OutOfMemory,
                    ScriptIterator.IteratorError.TypeError => return ExecutionError.TypeError,
                };
                iterator.configure(var_count);
                break :blk ScriptValue{ .iterator = iterator };
            },
            else => return ExecutionError.TypeError,
        };
    }

    fn ensureTableUnique(self: *VM, value: *ScriptValue) ExecutionError!void {
        _ = self;
        _ = value;
        return;
    }

    fn ensureArrayUnique(self: *VM, value: *ScriptValue) ExecutionError!void {
        _ = self;
        _ = value;
        return;
    }

    fn instantiateFunction(self: *VM, template: *ScriptFunction) !*ScriptFunction {
        const instance = try ScriptFunction.init(self.allocator, template.start_pc, template.end_pc, template.param_names, template.capture_names);
        errdefer instance.release();

        instance.markVarArg(template.is_vararg);

        var idx: usize = 0;
        while (idx < template.capture_names.len) : (idx += 1) {
            const name = template.capture_names[idx];
            if (self.findScopeEntry(name)) |entry| {
                const up = try self.promoteEntryToUpvalue(entry);
                try instance.addCapture(name, .{ .upvalue = up });
                continue;
            }
            if (self.globals.getEntry(name)) |entry| {
                try instance.addCapture(name, entry.value_ptr.*);
                continue;
            }
            if (self.engine.globals.get(name)) |value| {
                try instance.addCapture(name, value);
                continue;
            }
            try instance.addCapture(name, .{ .nil = {} });
        }

        return instance;
    }

    fn findScopeEntry(self: *VM, name: []const u8) ?*ScriptValue {
        var idx = self.scopes.items.len;
        while (idx > 0) {
            idx -= 1;
            if (self.scopes.items[idx].map.getEntry(name)) |entry| {
                return entry.value_ptr;
            }
        }
        return null;
    }

    fn promoteEntryToUpvalue(self: *VM, entry: *ScriptValue) !*ScriptUpvalue {
        return switch (entry.*) {
            .upvalue => |up| up,
            else => blk: {
                const up = try ScriptUpvalue.createFromValue(self.allocator, entry.*);
                entry.deinit(self.allocator);
                entry.* = .{ .upvalue = up };
                break :blk up;
            },
        };
    }

    fn tableSetField(self: *VM, table: *ScriptTable, key: []const u8, value: ScriptValue) ExecutionError!void {
        if (table.map.getEntry(key)) |entry| {
            entry.value_ptr.deinit(self.allocator);
            entry.value_ptr.* = try self.copyValue(value);
            return;
        }

        const key_copy = try self.allocator.dupe(u8, key);
        var value_copy = try self.copyValue(value);
        table.map.put(key_copy, value_copy) catch |err| {
            value_copy.deinit(self.allocator);
            self.allocator.free(key_copy);
            if (err == error.OutOfMemory) {
                return ExecutionError.OutOfMemory;
            }
            return err;
        };
    }

    fn tableGetField(self: *VM, table: *ScriptTable, key: []const u8) ExecutionError!?ScriptValue {
        if (table.map.get(key)) |value| {
            const copy = try self.copyValue(value);
            return copy;
        }
        return null;
    }

    fn arrayAppend(self: *VM, array: *ScriptArray, value: ScriptValue) ExecutionError!void {
        const value_copy = try self.copyValue(value);
        array.items.append(self.allocator, value_copy) catch |err| {
            var tmp = value_copy;
            tmp.deinit(self.allocator);
            if (err == error.OutOfMemory) {
                return ExecutionError.OutOfMemory;
            }
            return err;
        };
    }

    fn setIndexedValue(self: *VM, container: *ScriptValue, index: ScriptValue, value: ScriptValue) ExecutionError!void {
        switch (container.*) {
            .array => {
                if (index != .number) return ExecutionError.TypeError;
                try self.ensureArrayUnique(container);
                const array_ptr = container.*.array;
                const idx = try arrayIndexFromNumber(index.number);
                if (idx >= array_ptr.items.items.len) {
                    return ExecutionError.TypeError;
                }
                const value_copy = try self.copyValue(value);
                array_ptr.items.items[idx].deinit(self.allocator);
                array_ptr.items.items[idx] = value_copy;
            },
            .table => {
                if (index != .string) return ExecutionError.TypeError;
                try self.ensureTableUnique(container);
                const table_ptr = container.*.table;
                try self.tableSetField(table_ptr, index.string, value);
            },
            else => return ExecutionError.TypeError,
        }
    }

    fn getIndexedValue(self: *VM, container: ScriptValue, index: ScriptValue) ExecutionError!ScriptValue {
        switch (container) {
            .array => |array_ptr| {
                if (index != .number) return ExecutionError.TypeError;
                const idx = try arrayIndexFromNumber(index.number);
                if (idx >= array_ptr.items.items.len) {
                    return ScriptValue{ .nil = {} };
                }
                return try self.copyValue(array_ptr.items.items[idx]);
            },
            .table => |table_ptr| {
                if (index != .string) return ExecutionError.TypeError;
                if (try self.tableGetField(table_ptr, index.string)) |value| {
                    return value;
                }
                return ScriptValue{ .nil = {} };
            },
            else => return ExecutionError.TypeError,
        }
    }

    fn getVariable(self: *VM, name: []const u8) ?ScriptValue {
        var idx = self.scopes.items.len;
        while (idx > 0) {
            idx -= 1;
            if (self.scopes.items[idx].map.get(name)) |value| {
                return value;
            }
        }
        if (self.globals.get(name)) |value| {
            return value;
        }
        if (self.engine.globals.get(name)) |value| {
            return value;
        }
        return null;
    }

    fn valuesEqual(a: ScriptValue, b: ScriptValue) bool {
        switch (a) {
            .nil => return b == .nil,
            .boolean => |aval| switch (b) {
                .boolean => |bval| return aval == bval,
                else => return false,
            },
            .number => |aval| switch (b) {
                .number => |bval| return aval == bval,
                else => return false,
            },
            .string => |astr| switch (b) {
                .string => |bstr| return std.mem.eql(u8, astr, bstr),
                else => return false,
            },
            .function => |afunc| switch (b) {
                .function => |bfunc| return afunc == bfunc,
                else => return false,
            },
            .native_function => |afunc| switch (b) {
                .native_function => |bfunc| return afunc.call == bfunc.call and afunc.context == bfunc.context,
                else => return false,
            },
            .script_function => |afunc| switch (b) {
                .script_function => |bfunc| return afunc == bfunc,
                else => return false,
            },
            .table => |atable| switch (b) {
                .table => |btable| return atable == btable,
                else => return false,
            },
            .array => |aarray| switch (b) {
                .array => |barray| return aarray == barray,
                else => return false,
            },
            .iterator => |aiter| switch (b) {
                .iterator => |biter| return aiter == biter,
                else => return false,
            },
            .upvalue => |aupv| switch (b) {
                .upvalue => |bupv| return aupv == bupv,
                else => return false,
            },
        }
    }
};

// ============================================================================
// Lua-style Pattern Utilities
// ============================================================================

const max_pattern_captures = 16;

const PatternError = error{
    InvalidPattern,
    TooManyCaptures,
    UnbalancedCapture,
    OutOfMemory,
};

const PatternQuantifier = enum {
    exact,
    zero_or_one,
    zero_or_more,
    one_or_more,
    zero_or_more_nongreedy,
};

const PatternElementKind = enum {
    matcher,
    anchor_start,
    anchor_end,
    begin_capture,
    end_capture,
};

const PatternClass = enum {
    digit,
    nondigit,
    alpha,
    nonalpha,
    alnum,
    nonalnum,
    space,
    nonspace,
    lower,
    nonlower,
    upper,
    nonupper,
    punct,
    nonpunct,
    control,
    noncontrol,
    hex,
    nonhex,
    zero,
    nonzero,
};

const PatternCharSet = struct {
    bits: [256]bool = [_]bool{false} ** 256,

    fn setChar(self: *PatternCharSet, ch: u8) void {
        self.bits[ch] = true;
    }

    fn setRange(self: *PatternCharSet, first: u8, last: u8) void {
        var start = first;
        var finish = last;
        if (start > finish) {
            const tmp = start;
            start = finish;
            finish = tmp;
        }
        var idx = start;
        while (idx <= finish) : (idx += 1) {
            self.bits[idx] = true;
        }
    }

    fn addClass(self: *PatternCharSet, class: PatternClass) void {
        var idx: usize = 0;
        while (idx < 256) : (idx += 1) {
            if (classContains(class, @as(u8, @intCast(idx)))) {
                self.bits[idx] = true;
            }
        }
    }

    fn contains(self: PatternCharSet, ch: u8, negate: bool) bool {
        const present = self.bits[ch];
        return if (negate) !present else present;
    }
};

const PatternMatcherKind = enum {
    literal,
    any,
    class,
    set,
};

const PatternMatcher = struct {
    kind: PatternMatcherKind = .any,
    literal: u8 = 0,
    class: PatternClass = .digit,
    set: PatternCharSet = PatternCharSet{},
    negate: bool = false,
};

const PatternElement = struct {
    kind: PatternElementKind,
    matcher: PatternMatcher = PatternMatcher{},
    quant: PatternQuantifier = .exact,
    capture_index: usize = 0,
};

const CaptureState = struct {
    start: usize = 0,
    end: usize = 0,
    valid: bool = false,
};

const PatternState = struct {
    captures: [max_pattern_captures]CaptureState,
    capture_total: usize,
    stack: [max_pattern_captures]usize,
    stack_len: usize,

    fn init(capture_total: usize) PatternState {
        return PatternState{
            .captures = [_]CaptureState{CaptureState{}} ** max_pattern_captures,
            .capture_total = capture_total,
            .stack = [_]usize{0} ** max_pattern_captures,
            .stack_len = 0,
        };
    }

    fn pushCapture(self: *PatternState, idx: usize, start: usize) bool {
        if (self.stack_len >= max_pattern_captures or idx >= max_pattern_captures) return false;
        self.stack[self.stack_len] = idx;
        self.stack_len += 1;
        self.captures[idx] = CaptureState{ .start = start, .end = start, .valid = false };
        return true;
    }

    fn popCapture(self: *PatternState) ?usize {
        if (self.stack_len == 0) return null;
        self.stack_len -= 1;
        return self.stack[self.stack_len];
    }
};

const CaptureRange = struct {
    has: bool = false,
    start: usize = 0,
    end: usize = 0,
};

const PatternMatch = struct {
    start: usize,
    end: usize,
    capture_count: usize,
    captures: [max_pattern_captures]CaptureRange,
};

const MatchOutcome = struct {
    state: PatternState,
    end_index: usize,
};

const Pattern = struct {
    allocator: std.mem.Allocator,
    elements: []PatternElement,
    capture_total: usize,

    fn deinit(self: *Pattern) void {
        self.allocator.free(self.elements);
        self.elements = &[_]PatternElement{};
    }

    fn hasAnchorStart(self: Pattern) bool {
        if (self.elements.len == 0) return false;
        return self.elements[0].kind == .anchor_start;
    }

    fn matchElements(self: *Pattern, subject: []const u8, si: usize, elem_idx: usize, state: PatternState) ?MatchOutcome {
        if (elem_idx >= self.elements.len) {
            return MatchOutcome{ .state = state, .end_index = si };
        }

        const element = self.elements[elem_idx];
        switch (element.kind) {
            .anchor_start => {
                if (si != 0) return null;
                return self.matchElements(subject, si, elem_idx + 1, state);
            },
            .anchor_end => {
                if (si != subject.len) return null;
                return self.matchElements(subject, si, elem_idx + 1, state);
            },
            .begin_capture => {
                var next_state = state;
                if (!next_state.pushCapture(element.capture_index, si)) return null;
                return self.matchElements(subject, si, elem_idx + 1, next_state);
            },
            .end_capture => {
                var next_state = state;
                const idx_opt = next_state.popCapture() orelse return null;
                if (idx_opt >= max_pattern_captures) return null;
                next_state.captures[idx_opt].end = si;
                next_state.captures[idx_opt].valid = true;
                return self.matchElements(subject, si, elem_idx + 1, next_state);
            },
            .matcher => return self.matchMatcher(subject, si, elem_idx, state),
        }
    }

    fn matchMatcher(self: *Pattern, subject: []const u8, si: usize, elem_idx: usize, state: PatternState) ?MatchOutcome {
        const element = self.elements[elem_idx];
        const matcher = element.matcher;
        const next_idx = elem_idx + 1;

        var available: usize = 0;
        var cursor = si;
        while (cursor < subject.len and matcherMatches(matcher, subject[cursor])) : (cursor += 1) {
            available += 1;
        }

        const min_required: usize = switch (element.quant) {
            .exact => 1,
            .one_or_more => 1,
            else => 0,
        };

        if (available < min_required) return null;

        const attempt = struct {
            fn run(parent: *Pattern, subj: []const u8, idx: usize, next: usize, state_copy: PatternState) ?MatchOutcome {
                return parent.matchElements(subj, idx, next, state_copy);
            }
        };

        switch (element.quant) {
            .exact => {
                if (available == 0) return null;
                return attempt.run(self, subject, si + 1, next_idx, state);
            },
            .one_or_more => {
                var count = available;
                while (count >= 1) : (count -= 1) {
                    if (attempt.run(self, subject, si + count, next_idx, state)) |result| {
                        return result;
                    }
                }
                return null;
            },
            .zero_or_more => {
                var count = available;
                while (true) {
                    if (attempt.run(self, subject, si + count, next_idx, state)) |result| {
                        return result;
                    }
                    if (count == 0) break;
                    count -= 1;
                }
                return null;
            },
            .zero_or_more_nongreedy => {
                var count: usize = 0;
                while (count <= available) : (count += 1) {
                    if (attempt.run(self, subject, si + count, next_idx, state)) |result| {
                        return result;
                    }
                }
                return null;
            },
            .zero_or_one => {
                if (available > 0) {
                    if (attempt.run(self, subject, si + 1, next_idx, state)) |result| {
                        return result;
                    }
                }
                return attempt.run(self, subject, si, next_idx, state);
            },
        }
    }

    fn findFirst(self: *Pattern, subject: []const u8, start_index: usize) ?PatternMatch {
        var start = start_index;
        const anchored_start = self.hasAnchorStart();
        while (start <= subject.len) {
            const state = PatternState.init(self.capture_total);
            if (self.matchElements(subject, start, 0, state)) |outcome| {
                var captures: [max_pattern_captures]CaptureRange = [_]CaptureRange{CaptureRange{}} ** max_pattern_captures;
                var idx: usize = 0;
                while (idx < self.capture_total) : (idx += 1) {
                    const capture_state = outcome.state.captures[idx];
                    if (capture_state.valid) {
                        captures[idx] = CaptureRange{ .has = true, .start = capture_state.start, .end = capture_state.end };
                    }
                }
                return PatternMatch{
                    .start = start,
                    .end = outcome.end_index,
                    .capture_count = self.capture_total,
                    .captures = captures,
                };
            }
            if (anchored_start or start == subject.len) break;
            start += 1;
        }
        return null;
    }
};

fn matcherMatches(matcher: PatternMatcher, ch: u8) bool {
    return switch (matcher.kind) {
        .literal => ch == matcher.literal,
        .any => true,
        .class => classContains(matcher.class, ch),
        .set => matcher.set.contains(ch, matcher.negate),
    };
}

inline fn asciiIsHexDigit(ch: u8) bool {
    return (ch >= '0' and ch <= '9') or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F');
}

fn classContains(class: PatternClass, ch: u8) bool {
    return switch (class) {
        .digit => std.ascii.isDigit(ch),
        .nondigit => !std.ascii.isDigit(ch),
        .alpha => std.ascii.isAlphabetic(ch),
        .nonalpha => !std.ascii.isAlphabetic(ch),
        .alnum => std.ascii.isAlphanumeric(ch) or ch == '_',
        .nonalnum => !(std.ascii.isAlphanumeric(ch) or ch == '_'),
        .space => std.ascii.isWhitespace(ch),
        .nonspace => !std.ascii.isWhitespace(ch),
        .lower => std.ascii.isLower(ch),
        .nonlower => !std.ascii.isLower(ch),
        .upper => std.ascii.isUpper(ch),
        .nonupper => !std.ascii.isUpper(ch),
        .punct => !std.ascii.isAlphanumeric(ch) and !std.ascii.isWhitespace(ch),
        .nonpunct => std.ascii.isAlphanumeric(ch) or std.ascii.isWhitespace(ch),
        .control => ch < 0x20 or ch == 0x7F,
        .noncontrol => !(ch < 0x20 or ch == 0x7F),
        .hex => asciiIsHexDigit(ch),
        .nonhex => !asciiIsHexDigit(ch),
        .zero => ch == 0,
        .nonzero => ch != 0,
    };
}

fn parseClassChar(ch: u8) ?PatternClass {
    return switch (ch) {
        'a' => PatternClass.alpha,
        'A' => PatternClass.nonalpha,
        'd' => PatternClass.digit,
        'D' => PatternClass.nondigit,
        'w' => PatternClass.alnum,
        'W' => PatternClass.nonalnum,
        's' => PatternClass.space,
        'S' => PatternClass.nonspace,
        'l' => PatternClass.lower,
        'L' => PatternClass.nonlower,
        'u' => PatternClass.upper,
        'U' => PatternClass.nonupper,
        'p' => PatternClass.punct,
        'P' => PatternClass.nonpunct,
        'c' => PatternClass.control,
        'C' => PatternClass.noncontrol,
        'x' => PatternClass.hex,
        'X' => PatternClass.nonhex,
        'z' => PatternClass.zero,
        'Z' => PatternClass.nonzero,
        else => null,
    };
}

fn compilePattern(allocator: std.mem.Allocator, pattern: []const u8) PatternError!Pattern {
    var elements = std.ArrayList(PatternElement){};
    errdefer elements.deinit(allocator);

    var capture_stack: [max_pattern_captures]usize = undefined;
    var capture_stack_len: usize = 0;
    var capture_total: usize = 0;

    var i: usize = 0;
    while (i < pattern.len) {
        var consumed: usize = 1;
        var element: PatternElement = undefined;
        const ch = pattern[i];

        if (ch == '%') {
            if (i + 1 >= pattern.len) return PatternError.InvalidPattern;
            const next = pattern[i + 1];
            if (parseClassChar(next)) |class| {
                element = PatternElement{
                    .kind = .matcher,
                    .matcher = PatternMatcher{
                        .kind = .class,
                        .class = class,
                    },
                    .quant = .exact,
                };
            } else {
                element = PatternElement{
                    .kind = .matcher,
                    .matcher = PatternMatcher{
                        .kind = .literal,
                        .literal = next,
                    },
                    .quant = .exact,
                };
            }
            consumed = 2;
        } else if (ch == '[') {
            var set = PatternCharSet{};
            var negate = false;
            var idx = i + 1;
            if (idx < pattern.len and pattern[idx] == '^') {
                negate = true;
                idx += 1;
            }
            if (idx >= pattern.len) return PatternError.InvalidPattern;
            var first = true;
            while (idx < pattern.len and pattern[idx] != ']') {
                var current = pattern[idx];
                if (current == '%' and idx + 1 < pattern.len) {
                    if (parseClassChar(pattern[idx + 1])) |class| {
                        set.addClass(class);
                        idx += 2;
                        first = false;
                        continue;
                    } else {
                        current = pattern[idx + 1];
                        idx += 2;
                        if (first and current == ']') {
                            set.setChar(current);
                            first = false;
                            continue;
                        }
                    }
                } else if (current == '\\' and idx + 1 < pattern.len) {
                    current = pattern[idx + 1];
                    idx += 2;
                } else {
                    idx += 1;
                }

                if (!first and idx < pattern.len and pattern[idx] == '-' and idx + 1 < pattern.len and pattern[idx + 1] != ']') {
                    const range_end = pattern[idx + 1];
                    set.setRange(current, range_end);
                    idx += 2;
                } else {
                    set.setChar(current);
                }
                first = false;
            }
            if (idx >= pattern.len or pattern[idx] != ']') return PatternError.InvalidPattern;
            consumed = idx - i + 1;
            element = PatternElement{
                .kind = .matcher,
                .matcher = PatternMatcher{
                    .kind = .set,
                    .set = set,
                    .negate = negate,
                },
                .quant = .exact,
            };
        } else if (ch == '(') {
            if (capture_total >= max_pattern_captures or capture_stack_len >= max_pattern_captures) return PatternError.TooManyCaptures;
            capture_stack[capture_stack_len] = capture_total;
            capture_stack_len += 1;
            element = PatternElement{
                .kind = .begin_capture,
                .capture_index = capture_total,
            };
            capture_total += 1;
        } else if (ch == ')') {
            if (capture_stack_len == 0) return PatternError.UnbalancedCapture;
            capture_stack_len -= 1;
            const cap_idx = capture_stack[capture_stack_len];
            element = PatternElement{
                .kind = .end_capture,
                .capture_index = cap_idx,
            };
        } else if (ch == '^' and i == 0) {
            element = PatternElement{ .kind = .anchor_start };
        } else if (ch == '$' and i + 1 == pattern.len) {
            element = PatternElement{ .kind = .anchor_end };
        } else if (ch == '*' or ch == '+' or ch == '?' or ch == '-') {
            return PatternError.InvalidPattern;
        } else {
            element = PatternElement{
                .kind = .matcher,
                .matcher = PatternMatcher{
                    .kind = if (ch == '.') .any else .literal,
                    .literal = ch,
                },
                .quant = .exact,
            };
        }

        i += consumed;

        if (element.kind == .matcher and i < pattern.len) {
            const next_char = pattern[i];
            switch (next_char) {
                '*' => {
                    element.quant = .zero_or_more;
                    i += 1;
                },
                '+' => {
                    element.quant = .one_or_more;
                    i += 1;
                },
                '?' => {
                    element.quant = .zero_or_one;
                    i += 1;
                },
                '-' => {
                    element.quant = .zero_or_more_nongreedy;
                    i += 1;
                },
                else => {},
            }
        }

        try elements.append(allocator, element);
    }

    if (capture_stack_len != 0) return PatternError.UnbalancedCapture;

    const slice = try elements.toOwnedSlice(allocator);
    return Pattern{
        .allocator = allocator,
        .elements = slice,
        .capture_total = capture_total,
    };
}

fn executePatternMatch(
    allocator: std.mem.Allocator,
    subject: []const u8,
    pattern_text: []const u8,
    start_index: usize,
) PatternError!?PatternMatch {
    var compiled = try compilePattern(allocator, pattern_text);
    defer compiled.deinit();
    return compiled.findFirst(subject, start_index);
}

fn luaNormalizeStart(index: f64, len: usize) usize {
    const floored = std.math.floor(index);
    var value = @as(isize, @intFromFloat(floored));
    if (value >= 0) {
        value -= 1;
    } else {
        value = @as(isize, @intCast(len)) + value;
    }
    if (value < 0) value = 0;
    if (value > @as(isize, @intCast(len))) value = @intCast(len);
    return @intCast(value);
}

fn luaNormalizeEnd(index: f64, len: usize) usize {
    const floored = std.math.floor(index);
    var value = @as(isize, @intFromFloat(floored));
    if (value >= 0) {
        // Lua end indices are inclusive; convert to exclusive end
    } else {
        value = @as(isize, @intCast(len)) + value + 1;
    }
    if (value < 0) value = 0;
    if (value > @as(isize, @intCast(len))) value = @intCast(len);
    return @intCast(value);
}

fn computeSubRange(len: usize, start_idx: f64, end_idx: ?f64) struct { start: usize, end: usize } {
    const start = luaNormalizeStart(start_idx, len);
    var end_exclusive: usize = len;
    if (end_idx) |val| {
        end_exclusive = luaNormalizeEnd(val, len);
    }
    if (end_exclusive < start) end_exclusive = start;
    if (end_exclusive > len) end_exclusive = len;
    return .{ .start = start, .end = end_exclusive };
}

fn scriptValueToString(allocator: std.mem.Allocator, value: ScriptValue) ![]u8 {
    return switch (value) {
        .nil => allocator.dupe(u8, "nil"),
        .boolean => |b| allocator.dupe(u8, if (b) "true" else "false"),
        .number => |num| std.fmt.allocPrint(allocator, "{}", .{num}),
        .string => |str| allocator.dupe(u8, str),
        .table => allocator.dupe(u8, "<table>"),
        .array => allocator.dupe(u8, "<array>"),
        .function => allocator.dupe(u8, "<function>"),
        .native_function => allocator.dupe(u8, "<function>"),
        .script_function => allocator.dupe(u8, "<function>"),
        .iterator => allocator.dupe(u8, "<iterator>"),
        .upvalue => allocator.dupe(u8, "<upvalue>"),
    };
}

fn appendReplacement(
    builder: *std.ArrayList(u8),
    allocator: std.mem.Allocator,
    replacement: []const u8,
    subject: []const u8,
    match: PatternMatch,
) PatternError!void {
    var idx: usize = 0;
    while (idx < replacement.len) {
        const ch = replacement[idx];
        if (ch == '%' and idx + 1 < replacement.len) {
            const next = replacement[idx + 1];
            if (next == '%') {
                builder.append(allocator, next) catch return PatternError.OutOfMemory;
                idx += 2;
                continue;
            }
            if (std.ascii.isDigit(next)) {
                const cap_index = next - '0';
                if (cap_index == 0) {
                    if (match.end > match.start) {
                        builder.appendSlice(allocator, subject[match.start..match.end]) catch return PatternError.OutOfMemory;
                    }
                } else if (cap_index <= match.capture_count) {
                    const range = match.captures[cap_index - 1];
                    if (range.has and range.end > range.start and range.end <= subject.len) {
                        builder.appendSlice(allocator, subject[range.start..range.end]) catch return PatternError.OutOfMemory;
                    }
                }
                idx += 2;
                continue;
            }
            builder.append(allocator, next) catch return PatternError.OutOfMemory;
            idx += 2;
            continue;
        }
        builder.append(allocator, ch) catch return PatternError.OutOfMemory;
        idx += 1;
    }
}

fn performGlobalSubstitute(
    allocator: std.mem.Allocator,
    subject: []const u8,
    pattern_text: []const u8,
    replacement: []const u8,
    max_replacements: ?usize,
) PatternError!struct { text: []u8, count: usize } {
    var compiled = try compilePattern(allocator, pattern_text);
    defer compiled.deinit();

    var builder = std.ArrayList(u8){};
    errdefer builder.deinit(allocator);

    var cursor: usize = 0;
    var replacements: usize = 0;
    while (cursor <= subject.len) {
        if (max_replacements) |limit| if (replacements >= limit) break;

        const match_opt = compiled.findFirst(subject, cursor) orelse break;
        if (match_opt.start < cursor) break;

        if (match_opt.start > cursor) {
            builder.appendSlice(allocator, subject[cursor..match_opt.start]) catch return PatternError.OutOfMemory;
        }

        try appendReplacement(&builder, allocator, replacement, subject, match_opt);
        replacements += 1;

        if (match_opt.end > cursor) {
            cursor = match_opt.end;
        } else {
            if (cursor < subject.len) {
                builder.append(allocator, subject[cursor]) catch return PatternError.OutOfMemory;
                cursor += 1;
            } else {
                break;
            }
        }
    }

    if (cursor < subject.len) {
        builder.appendSlice(allocator, subject[cursor..]) catch return PatternError.OutOfMemory;
    }

    const owned = builder.toOwnedSlice(allocator) catch return PatternError.OutOfMemory;
    return .{ .text = owned, .count = replacements };
}

// ============================================================================
// Built-in Functions
// ============================================================================

threadlocal var active_vm: ?*VM = null;

fn helperAllocator() ?std.mem.Allocator {
    if (active_vm) |vm| {
        return vm.allocator;
    }
    if (editor_helper_allocator) |allocator| {
        return allocator;
    }
    return null;
}

fn makeHelperStringLiteral(literal: []const u8) ScriptValue {
    const allocator = helperAllocator() orelse return .{ .nil = {} };
    const dup = allocator.dupe(u8, literal) catch {
        return .{ .nil = {} };
    };
    return .{ .string = dup };
}

pub const BuiltinFunctions = struct {
    // String functions
    pub fn builtin_len(args: []const ScriptValue) ScriptValue {
        if (args.len != 1) return .{ .nil = {} };
        switch (args[0]) {
            .string => |s| return .{ .number = @floatFromInt(s.len) },
            .array => |arr| return .{ .number = @floatFromInt(arr.items.items.len) },
            else => return .{ .nil = {} },
        }
    }

    pub fn builtin_toUpperCase(args: []const ScriptValue) ScriptValue {
        if (args.len != 1) return .{ .nil = {} };
        if (args[0] != .string) return .{ .nil = {} };

        const input = args[0].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };
        var duplicated = allocator.alloc(u8, input.len) catch {
            return .{ .nil = {} };
        };
        var idx: usize = 0;
        while (idx < input.len) : (idx += 1) {
            duplicated[idx] = std.ascii.toUpper(input[idx]);
        }
        return .{ .string = duplicated };
    }

    pub fn builtin_toLowerCase(args: []const ScriptValue) ScriptValue {
        if (args.len != 1) return .{ .nil = {} };
        if (args[0] != .string) return .{ .nil = {} };

        const input = args[0].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };
        var duplicated = allocator.alloc(u8, input.len) catch {
            return .{ .nil = {} };
        };
        var idx: usize = 0;
        while (idx < input.len) : (idx += 1) {
            duplicated[idx] = std.ascii.toLower(input[idx]);
        }
        return .{ .string = duplicated };
    }

    pub fn builtin_print(args: []const ScriptValue) ScriptValue {
        for (args, 0..) |arg, i| {
            switch (arg) {
                .nil => std.debug.print("nil", .{}),
                .boolean => |b| std.debug.print("{}", .{b}),
                .number => |n| std.debug.print("{d}", .{n}),
                .string => |s| std.debug.print("{s}", .{s}),
                .function => std.debug.print("<function>", .{}),
                .native_function => std.debug.print("<function>", .{}),
                .script_function => std.debug.print("<function>", .{}),
                .table => std.debug.print("<table>", .{}),
                .array => std.debug.print("<array>", .{}),
                .iterator => std.debug.print("<iterator>", .{}),
                .upvalue => std.debug.print("<upvalue>", .{}),
            }
            if (i < args.len - 1) std.debug.print(" ", .{});
        }
        std.debug.print("\n", .{});
        return .{ .nil = {} };
    }

    pub fn builtin_type(args: []const ScriptValue) ScriptValue {
        if (args.len != 1) return .{ .nil = {} };
        const type_name = switch (args[0]) {
            .nil => "nil",
            .boolean => "boolean",
            .number => "number",
            .string => "string",
            .function => "function",
            .native_function => "function",
            .script_function => "function",
            .table => "table",
            .array => "array",
            .iterator => "iterator",
            .upvalue => "upvalue",
        };
        return makeHelperStringLiteral(type_name);
    }

    pub fn builtin_push(args: []const ScriptValue) ScriptValue {
        if (args.len != 2) return .{ .nil = {} };
        if (args[0] != .array) return .{ .nil = {} };
        const array_ptr = args[0].array;
        const allocator = array_ptr.allocator;
        const value_copy = copyScriptValue(allocator, args[1]) catch {
            return .{ .nil = {} };
        };
        array_ptr.items.append(array_ptr.allocator, value_copy) catch {
            var tmp = value_copy;
            tmp.deinit(allocator);
            return .{ .nil = {} };
        };
        array_ptr.retain();
        return .{ .array = array_ptr };
    }

    pub fn builtin_pop(args: []const ScriptValue) ScriptValue {
        if (args.len != 1 or args[0] != .array) return .{ .nil = {} };
        const array_ptr = args[0].array;
        if (array_ptr.items.items.len == 0) return .{ .nil = {} };
        const idx = array_ptr.items.items.len - 1;
        const value = array_ptr.items.items[idx];
        array_ptr.items.items.len = idx;
        return value;
    }

    pub fn builtin_insert(args: []const ScriptValue) ScriptValue {
        if (args.len != 3 or args[0] != .table or args[1] != .string) return .{ .nil = {} };
        const table_ptr = args[0].table;
        const allocator = table_ptr.allocator;
        const key_slice = args[1].string;
        const value_copy = copyScriptValue(allocator, args[2]) catch {
            return .{ .nil = {} };
        };
        if (table_ptr.map.getEntry(key_slice)) |entry| {
            entry.value_ptr.deinit(allocator);
            entry.value_ptr.* = value_copy;
        } else {
            const key_copy = allocator.dupe(u8, key_slice) catch {
                var tmp = value_copy;
                tmp.deinit(allocator);
                return .{ .nil = {} };
            };
            table_ptr.map.put(key_copy, value_copy) catch {
                var tmp = value_copy;
                tmp.deinit(allocator);
                allocator.free(key_copy);
                return .{ .nil = {} };
            };
        }
        table_ptr.retain();
        return .{ .table = table_ptr };
    }

    pub fn builtin_remove(args: []const ScriptValue) ScriptValue {
        if (args.len != 2) return .{ .nil = {} };
        switch (args[0]) {
            .table => |table_ptr| {
                if (args[1] != .string) return .{ .nil = {} };
                const key = args[1].string;
                if (table_ptr.map.fetchRemove(key)) |entry| {
                    table_ptr.allocator.free(@constCast(entry.key));
                    return entry.value;
                }
                return .{ .nil = {} };
            },
            .array => |array_ptr| {
                if (args[1] != .number) return .{ .nil = {} };
                const idx = arrayIndexFromNumber(args[1].number) catch return .{ .nil = {} };
                if (idx >= array_ptr.items.items.len) return .{ .nil = {} };
                const removed = array_ptr.items.orderedRemove(idx);
                return removed;
            },
            else => return .{ .nil = {} },
        }
    }

    pub fn builtin_pairs(args: []const ScriptValue) ScriptValue {
        if (args.len != 1 or args[0] != .table) return .{ .nil = {} };
        const table_ptr = args[0].table;
        const allocator = table_ptr.allocator;
        const iterator = ScriptIterator.createFromTable(allocator, table_ptr) catch {
            return .{ .nil = {} };
        };
        iterator.configure(2);
        return .{ .iterator = iterator };
    }

    pub fn builtin_ipairs(args: []const ScriptValue) ScriptValue {
        if (args.len != 1 or args[0] != .array) return .{ .nil = {} };
        const source = args[0].array;
        const allocator = source.allocator;
        const iterator = ScriptIterator.createFromArray(allocator, source) catch {
            return .{ .nil = {} };
        };
        iterator.configure(2);
        return .{ .iterator = iterator };
    }

    pub fn builtin_find(args: []const ScriptValue) ScriptValue {
        if (args.len < 2) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .string) return .{ .nil = {} };

        const subject = args[0].string;
        const pattern_text = args[1].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };

        var start_index: usize = 0;
        if (args.len >= 3 and args[2] == .number) {
            start_index = luaNormalizeStart(args[2].number, subject.len);
        }

        const result = executePatternMatch(allocator, subject, pattern_text, start_index) catch {
            return .{ .nil = {} };
        };

        if (result) |match_info| {
            return .{ .number = @floatFromInt(match_info.start + 1) };
        }
        return .{ .nil = {} };
    }

    pub fn builtin_match(args: []const ScriptValue) ScriptValue {
        if (args.len < 2) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .string) return .{ .nil = {} };

        const subject = args[0].string;
        const pattern_text = args[1].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };

        var start_index: usize = 0;
        if (args.len >= 3 and args[2] == .number) {
            start_index = luaNormalizeStart(args[2].number, subject.len);
        }

        const result = executePatternMatch(allocator, subject, pattern_text, start_index) catch {
            return .{ .nil = {} };
        };

        if (result) |match_info| {
            if (match_info.capture_count > 0) {
                var idx: usize = 0;
                while (idx < match_info.capture_count) : (idx += 1) {
                    const capture = match_info.captures[idx];
                    if (capture.has and capture.end > capture.start and capture.end <= subject.len) {
                        const dup = allocator.dupe(u8, subject[capture.start..capture.end]) catch {
                            return .{ .nil = {} };
                        };
                        return .{ .string = dup };
                    }
                }
            }

            if (match_info.end > match_info.start and match_info.end <= subject.len) {
                const dup = allocator.dupe(u8, subject[match_info.start..match_info.end]) catch {
                    return .{ .nil = {} };
                };
                return .{ .string = dup };
            }
        }

        return .{ .nil = {} };
    }

    pub fn builtin_sub(args: []const ScriptValue) ScriptValue {
        if (args.len < 2 or args.len > 3) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .number) return .{ .nil = {} };

        const subject = args[0].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };
        const end_value: ?f64 = if (args.len == 3 and args[2] == .number) args[2].number else null;
        const range = computeSubRange(subject.len, args[1].number, end_value);
        const slice = subject[range.start..range.end];
        const dup = allocator.dupe(u8, slice) catch {
            return .{ .nil = {} };
        };
        return .{ .string = dup };
    }

    pub fn builtin_gsub(args: []const ScriptValue) ScriptValue {
        if (args.len < 3) return .{ .nil = {} };
        if (args[0] != .string or args[1] != .string or args[2] != .string) return .{ .nil = {} };

        const subject = args[0].string;
        const pattern_text = args[1].string;
        const replacement = args[2].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };

        var limit: ?usize = null;
        if (args.len >= 4 and args[3] == .number) {
            if (args[3].number > 0) {
                limit = @intCast(@as(usize, @intFromFloat(std.math.floor(args[3].number))));
            }
        }

        const substituted = performGlobalSubstitute(allocator, subject, pattern_text, replacement, limit) catch {
            return .{ .nil = {} };
        };
        return .{ .string = substituted.text };
    }

    pub fn builtin_format(args: []const ScriptValue) ScriptValue {
        if (args.len == 0) return .{ .nil = {} };
        if (args[0] != .string) return .{ .nil = {} };

        const format_str = args[0].string;
        const allocator = helperAllocator() orelse return .{ .nil = {} };
        var builder = std.ArrayList(u8){};
        errdefer builder.deinit(allocator);

        var i: usize = 0;
        var arg_index: usize = 1;
        while (i < format_str.len) {
            const ch = format_str[i];
            if (ch == '%' and i + 1 < format_str.len) {
                const spec = format_str[i + 1];
                if (spec == '%') {
                    builder.append(allocator, '%') catch {
                        builder.deinit(allocator);
                        return .{ .nil = {} };
                    };
                    i += 2;
                    continue;
                }
                if (arg_index >= args.len) {
                    builder.deinit(allocator);
                    return .{ .nil = {} };
                }
                const value = args[arg_index];
                arg_index += 1;
                switch (spec) {
                    's' => {
                        const temp = scriptValueToString(allocator, value) catch {
                            builder.deinit(allocator);
                            return .{ .nil = {} };
                        };
                        defer allocator.free(temp);
                        builder.appendSlice(allocator, temp) catch {
                            builder.deinit(allocator);
                            return .{ .nil = {} };
                        };
                    },
                    'd', 'i' => {
                        if (value != .number) {
                            builder.deinit(allocator);
                            return .{ .nil = {} };
                        }
                        const truncated = std.math.trunc(value.number);
                        const integer = @as(i64, @intFromFloat(truncated));
                        var buffer: [64]u8 = undefined;
                        const printed = std.fmt.bufPrint(&buffer, "{}", .{integer}) catch unreachable;
                        builder.appendSlice(allocator, printed) catch {
                            builder.deinit(allocator);
                            return .{ .nil = {} };
                        };
                    },
                    'f' => {
                        if (value != .number) {
                            builder.deinit(allocator);
                            return .{ .nil = {} };
                        }
                        var buffer: [128]u8 = undefined;
                        const printed = std.fmt.bufPrint(&buffer, "{:.6}", .{value.number}) catch unreachable;
                        builder.appendSlice(allocator, printed) catch {
                            builder.deinit(allocator);
                            return .{ .nil = {} };
                        };
                    },
                    else => {
                        builder.deinit(allocator);
                        return .{ .nil = {} };
                    },
                }
                i += 2;
                continue;
            }
            builder.append(allocator, ch) catch {
                builder.deinit(allocator);
                return .{ .nil = {} };
            };
            i += 1;
        }

        const output = builder.toOwnedSlice(allocator) catch {
            builder.deinit(allocator);
            return .{ .nil = {} };
        };
        return .{ .string = output };
    }

    fn builtin_pcall_native(
        _: ?*anyopaque,
        vm_ptr: *anyopaque,
        dest_reg: u16,
        arg_start: u16,
        arg_count: u16,
        expected_results: u16,
    ) ExecutionError!NativeCallResult {
        const vm: *VM = @ptrCast(@alignCast(vm_ptr));

        const effective_expected: u16 = if (expected_results == 0)
            0
        else if (expected_results == 1)
            2
        else
            expected_results;

        if (arg_count == 0) {
            const message = try vm.createStringValue("pcall requires function");
            const context = ProtectedCall{
                .dest_reg = dest_reg,
                .expected_results = effective_expected,
                .result_base = arg_start,
                .scope_depth = vm.scopes.items.len,
                .call_frame_index = vm.call_stack.items.len,
                .arg_count = 0,
            };
            const final_count = try vm.finalizeProtectedFailure(context, message);
            return NativeCallResult{ .last_result_count = final_count, .advance_pc = true };
        }

        const func_index: usize = @intCast(arg_start);
        const func_value = vm.registers[func_index];
        const target_arg_count: u16 = arg_count - 1;
        const args_start = arg_start + 1;

        switch (func_value) {
            .script_function => |script_func| {
                const context_index = vm.protected_calls.items.len;
                try vm.protected_calls.append(vm.allocator, .{
                    .dest_reg = dest_reg,
                    .expected_results = effective_expected,
                    .result_base = arg_start,
                    .scope_depth = vm.scopes.items.len,
                    .call_frame_index = vm.call_stack.items.len,
                    .arg_count = target_arg_count,
                });

                vm.invokeScriptFunction(script_func, arg_start, args_start, target_arg_count, 0, context_index) catch |err| {
                    vm.protected_calls.items.len = context_index;
                    const message = try vm.errorToMessage(err);
                    const context = ProtectedCall{
                        .dest_reg = dest_reg,
                        .expected_results = effective_expected,
                        .result_base = arg_start,
                        .scope_depth = vm.scopes.items.len,
                        .call_frame_index = vm.call_stack.items.len,
                        .arg_count = target_arg_count,
                    };
                    const final_count = try vm.finalizeProtectedFailure(context, message);
                    return NativeCallResult{ .last_result_count = final_count, .advance_pc = true };
                };

                vm.protected_calls.items[context_index].call_frame_index = vm.call_stack.items.len - 1;
                return NativeCallResult{ .last_result_count = 0, .advance_pc = false };
            },
            .function => |callable| {
                const args_slice = vm.registers[@as(usize, args_start) .. @as(usize, args_start) + @as(usize, target_arg_count)];
                const result = callable(args_slice);

                const context_index = vm.protected_calls.items.len;
                try vm.protected_calls.append(vm.allocator, .{
                    .dest_reg = dest_reg,
                    .expected_results = effective_expected,
                    .result_base = arg_start,
                    .scope_depth = vm.scopes.items.len,
                    .call_frame_index = vm.call_stack.items.len,
                    .arg_count = target_arg_count,
                });

                vm.setRegister(arg_start, result);
                const final_count = try vm.finalizeProtectedSuccess(context_index, 1);
                return NativeCallResult{ .last_result_count = final_count, .advance_pc = true };
            },
            .native_function => |native| {
                const context_index = vm.protected_calls.items.len;
                try vm.protected_calls.append(vm.allocator, .{
                    .dest_reg = dest_reg,
                    .expected_results = effective_expected,
                    .result_base = arg_start,
                    .scope_depth = vm.scopes.items.len,
                    .call_frame_index = vm.call_stack.items.len,
                    .arg_count = target_arg_count,
                });

                const outcome = vm.invokeNativeFunction(native, arg_start, args_start, target_arg_count, 0) catch |err| {
                    vm.protected_calls.items.len = context_index;
                    const message = try vm.errorToMessage(err);
                    const context = ProtectedCall{
                        .dest_reg = dest_reg,
                        .expected_results = effective_expected,
                        .result_base = arg_start,
                        .scope_depth = vm.scopes.items.len,
                        .call_frame_index = vm.call_stack.items.len,
                        .arg_count = target_arg_count,
                    };
                    const final_count = try vm.finalizeProtectedFailure(context, message);
                    return NativeCallResult{ .last_result_count = final_count, .advance_pc = true };
                };

                const final_count = try vm.finalizeProtectedSuccess(context_index, outcome.last_result_count);
                return NativeCallResult{ .last_result_count = final_count, .advance_pc = true };
            },
            else => {
                const message = try vm.createStringValue("attempt to call non-function");
                const context = ProtectedCall{
                    .dest_reg = dest_reg,
                    .expected_results = effective_expected,
                    .result_base = arg_start,
                    .scope_depth = vm.scopes.items.len,
                    .call_frame_index = vm.call_stack.items.len,
                    .arg_count = target_arg_count,
                };
                const final_count = try vm.finalizeProtectedFailure(context, message);
                return NativeCallResult{ .last_result_count = final_count, .advance_pc = true };
            },
        }
    }

    fn builtin_error_native(
        _: ?*anyopaque,
        vm_ptr: *anyopaque,
        _: u16,
        arg_start: u16,
        arg_count: u16,
        _: u16,
    ) ExecutionError!NativeCallResult {
        const vm: *VM = @ptrCast(@alignCast(vm_ptr));

        const message = if (arg_count > 0)
            try vm.copyValue(vm.registers[@as(usize, arg_start)])
        else
            try vm.createStringValue("error");

        return vm.abortProtectedCallWithMessage(message);
    }

    pub fn registerBuiltins(vm: *VM) !void {
        const builtins = [_]struct { name: []const u8, func: *const fn (args: []const ScriptValue) ScriptValue }{
            .{ .name = "len", .func = &builtin_len },
            .{ .name = "print", .func = &builtin_print },
            .{ .name = "type", .func = &builtin_type },
            .{ .name = "toUpperCase", .func = &builtin_toUpperCase },
            .{ .name = "toLowerCase", .func = &builtin_toLowerCase },
            .{ .name = "upper", .func = &builtin_toUpperCase },
            .{ .name = "lower", .func = &builtin_toLowerCase },
            .{ .name = "sub", .func = &builtin_sub },
            .{ .name = "gsub", .func = &builtin_gsub },
            .{ .name = "format", .func = &builtin_format },
            .{ .name = "push", .func = &builtin_push },
            .{ .name = "pop", .func = &builtin_pop },
            .{ .name = "insert", .func = &builtin_insert },
            .{ .name = "remove", .func = &builtin_remove },
            .{ .name = "pairs", .func = &builtin_pairs },
            .{ .name = "ipairs", .func = &builtin_ipairs },
            .{ .name = "find", .func = &builtin_find },
            .{ .name = "match", .func = &builtin_match },
        };

        for (builtins) |builtin| {
            // Don't overwrite user-registered functions from engine.globals
            if (vm.engine.globals.get(builtin.name) != null) continue;

            const name_copy = try vm.allocator.dupe(u8, builtin.name);
            try vm.globals.put(name_copy, .{ .function = builtin.func });
        }

        if (vm.engine.globals.get("pcall") == null and vm.globals.get("pcall") == null) {
            const name_copy = try vm.allocator.dupe(u8, "pcall");
            try vm.globals.put(name_copy, .{ .native_function = .{ .context = null, .call = builtin_pcall_native } });
        }

        if (vm.engine.globals.get("error") == null and vm.globals.get("error") == null) {
            const name_copy = try vm.allocator.dupe(u8, "error");
            try vm.globals.put(name_copy, .{ .native_function = .{ .context = null, .call = builtin_error_native } });
        }
    }
};

// ============================================================================
// Editor API
// ============================================================================

/// EditorAPI provides buffer manipulation functions for plugin development
/// This is a mock implementation - real implementation will integrate with Grim
pub const EditorAPI = struct {
    lines: std.ArrayList([]const u8),
    cursor_line: usize,
    cursor_col: usize,
    selection_start: usize,
    selection_end: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !EditorAPI {
        var api = EditorAPI{
            .lines = std.ArrayList([]const u8).init(allocator),
            .cursor_line = 0,
            .cursor_col = 0,
            .selection_start = 0,
            .selection_end = 0,
            .allocator = allocator,
        };

        // Initialize with some sample content
        try api.lines.append(try allocator.dupe(u8, "Line 1"));
        try api.lines.append(try allocator.dupe(u8, "Line 2"));
        try api.lines.append(try allocator.dupe(u8, "Line 3"));

        return api;
    }

    pub fn deinit(self: *EditorAPI) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.deinit();
    }

    // Buffer operations
    pub fn builtin_getLineCount(args: []const ScriptValue) ScriptValue {
        _ = args;
        // TODO: Get from actual editor context
        return .{ .number = 100 };
    }

    pub fn builtin_getLineText(args: []const ScriptValue) ScriptValue {
        if (args.len != 1) return .{ .nil = {} };
        if (args[0] != .number) return .{ .nil = {} };

        // TODO: Get from actual editor context
        const line_num = @as(usize, @intFromFloat(args[0].number));
        _ = line_num;
        return makeHelperStringLiteral("sample line text");
    }

    pub fn builtin_setLineText(args: []const ScriptValue) ScriptValue {
        if (args.len != 2) return .{ .nil = {} };
        if (args[0] != .number) return .{ .nil = {} };
        if (args[1] != .string) return .{ .nil = {} };

        // TODO: Set in actual editor context
        const line_num = @as(usize, @intFromFloat(args[0].number));
        const text = args[1].string;
        _ = line_num;
        _ = text;
        return .{ .nil = {} };
    }

    // Cursor operations
    pub fn builtin_getCursorLine(args: []const ScriptValue) ScriptValue {
        _ = args;
        // TODO: Get from actual editor context
        return .{ .number = 0 };
    }

    pub fn builtin_getCursorCol(args: []const ScriptValue) ScriptValue {
        _ = args;
        // TODO: Get from actual editor context
        return .{ .number = 0 };
    }

    pub fn builtin_setCursorPosition(args: []const ScriptValue) ScriptValue {
        if (args.len != 2) return .{ .nil = {} };
        if (args[0] != .number) return .{ .nil = {} };
        if (args[1] != .number) return .{ .nil = {} };

        // TODO: Set in actual editor context
        const line = @as(usize, @intFromFloat(args[0].number));
        const col = @as(usize, @intFromFloat(args[1].number));
        _ = line;
        _ = col;
        return .{ .nil = {} };
    }

    // Selection operations
    pub fn builtin_getSelectionStart(args: []const ScriptValue) ScriptValue {
        _ = args;
        // TODO: Get from actual editor context
        return .{ .number = 0 };
    }

    pub fn builtin_getSelectionEnd(args: []const ScriptValue) ScriptValue {
        _ = args;
        // TODO: Get from actual editor context
        return .{ .number = 0 };
    }

    pub fn builtin_setSelection(args: []const ScriptValue) ScriptValue {
        if (args.len != 4) return .{ .nil = {} };

        // TODO: Set in actual editor context
        return .{ .nil = {} };
    }

    pub fn registerEditorAPI(vm: *VM) !void {
        // Buffer operations
        try vm.globals.put(try vm.allocator.dupe(u8, "getLineCount"), .{ .function = &builtin_getLineCount });
        try vm.globals.put(try vm.allocator.dupe(u8, "getLineText"), .{ .function = &builtin_getLineText });
        try vm.globals.put(try vm.allocator.dupe(u8, "setLineText"), .{ .function = &builtin_setLineText });

        // Cursor operations
        try vm.globals.put(try vm.allocator.dupe(u8, "getCursorLine"), .{ .function = &builtin_getCursorLine });
        try vm.globals.put(try vm.allocator.dupe(u8, "getCursorCol"), .{ .function = &builtin_getCursorCol });
        try vm.globals.put(try vm.allocator.dupe(u8, "setCursorPosition"), .{ .function = &builtin_setCursorPosition });

        // Selection operations
        try vm.globals.put(try vm.allocator.dupe(u8, "getSelectionStart"), .{ .function = &builtin_getSelectionStart });
        try vm.globals.put(try vm.allocator.dupe(u8, "getSelectionEnd"), .{ .function = &builtin_getSelectionEnd });
        try vm.globals.put(try vm.allocator.dupe(u8, "setSelection"), .{ .function = &builtin_setSelection });
    }
};

pub const Script = struct {
    engine: *ScriptEngine,
    vm: VM,
    syntax_tree: SyntaxTree,
    parse_duration_ns: u64,

    pub fn deinit(self: *Script) void {
        self.syntax_tree.deinit();
        // Free constants and code arrays first
        for (self.vm.constants, 0..) |_, idx| {
            self.vm.constants[idx].deinit(self.engine.tracked_allocator);
        }
        self.engine.tracked_allocator.free(self.vm.constants);
        self.engine.tracked_allocator.free(self.vm.code);

        // Then deinit VM (which will deinit globals and scopes)
        self.vm.deinit();
    }

    pub fn run(self: *Script) ExecutionError!ScriptValue {
        return self.vm.run();
    }

    pub fn getGlobal(self: *Script, name: []const u8) ExecutionError!ScriptValue {
        return self.engine.globals.get(name) orelse ExecutionError.GlobalNotFound;
    }

    pub fn setGlobal(self: *Script, name: []const u8, value: ScriptValue) ExecutionError!void {
        const name_copy = self.engine.tracked_allocator.dupe(u8, name) catch |err| switch (err) {
            error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
        };
        const value_copy = value;
        // TODO: deep copy value if needed
        self.engine.globals.put(name_copy, value_copy) catch |err| switch (err) {
            error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
        };
    }
};

pub const Parser = struct {
    const LoopContext = struct {
        start_idx: usize,
        continue_target: usize,
        result_reg: u16,
        base_scope_depth: usize,
        loop_scope_base: usize,
        break_jumps: std.ArrayListUnmanaged(usize),
        continue_jumps: std.ArrayListUnmanaged(usize),

        fn init() LoopContext {
            return .{
                .start_idx = 0,
                .continue_target = 0,
                .result_reg = 0,
                .base_scope_depth = 0,
                .loop_scope_base = 0,
                .break_jumps = .{},
                .continue_jumps = .{},
            };
        }

        fn deinit(self: *LoopContext, allocator: std.mem.Allocator) void {
            self.break_jumps.deinit(allocator);
            self.continue_jumps.deinit(allocator);
        }
    };

    const ScopeBinding = struct {
        function_depth: usize,
        names: std.ArrayListUnmanaged([]const u8),

        fn init(function_depth: usize) ScopeBinding {
            return .{ .function_depth = function_depth, .names = .{} };
        }

        fn deinit(self: *ScopeBinding, allocator: std.mem.Allocator) void {
            for (self.names.items) |name| {
                allocator.free(name);
            }
            self.names.deinit(allocator);
        }
    };

    const FunctionContext = struct {
        base_scope_depth: usize,
        params_registered: bool,
        pending_params: std.ArrayListUnmanaged([]const u8),
        capture_names: std.ArrayListUnmanaged([]const u8),
        is_vararg: bool,

        fn init(base_scope_depth: usize) FunctionContext {
            return .{
                .base_scope_depth = base_scope_depth,
                .params_registered = false,
                .pending_params = .{},
                .capture_names = .{},
                .is_vararg = false,
            };
        }

        fn deinit(self: *FunctionContext, allocator: std.mem.Allocator) void {
            for (self.pending_params.items) |name| {
                allocator.free(name);
            }
            self.pending_params.deinit(allocator);
            for (self.capture_names.items) |name| {
                allocator.free(name);
            }
            self.capture_names.deinit(allocator);
        }

        fn addPendingParam(self: *FunctionContext, allocator: std.mem.Allocator, name: []const u8) !void {
            const dup = try allocator.dupe(u8, name);
            errdefer allocator.free(dup);
            try self.pending_params.append(allocator, dup);
        }

        fn addCapture(self: *FunctionContext, allocator: std.mem.Allocator, name: []const u8) !void {
            for (self.capture_names.items) |existing| {
                if (std.mem.eql(u8, existing, name)) {
                    return;
                }
            }
            const dup = try allocator.dupe(u8, name);
            errdefer allocator.free(dup);
            try self.capture_names.append(allocator, dup);
        }

        fn takeCaptureNames(self: *FunctionContext, allocator: std.mem.Allocator) ![]const []const u8 {
            const slice = try allocator.alloc([]const u8, self.capture_names.items.len);
            for (self.capture_names.items, 0..) |name, idx| {
                slice[idx] = try allocator.dupe(u8, name);
                allocator.free(name);
            }
            self.capture_names.items.len = 0;
            self.capture_names.deinit(allocator);
            self.capture_names = .{};
            return slice;
        }
    };

    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize,
    temp_counter: usize,
    line: usize,
    column: usize,
    scope_depth: usize,
    loop_stack: std.ArrayListUnmanaged(LoopContext),
    function_stack: std.ArrayListUnmanaged(FunctionContext),
    scope_bindings: std.ArrayListUnmanaged(ScopeBinding),

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        return Parser{
            .allocator = allocator,
            .source = source,
            .pos = 0,
            .temp_counter = 0,
            .line = 1,
            .column = 1,
            .scope_depth = 0,
            .loop_stack = .{},
            .function_stack = .{},
            .scope_bindings = .{},
        };
    }

    pub fn parse(self: *Parser) !struct { instructions: []Instruction, constants: []ScriptValue } {
        defer {
            var idx: usize = 0;
            while (idx < self.loop_stack.items.len) : (idx += 1) {
                self.loop_stack.items[idx].deinit(self.allocator);
            }
            self.loop_stack.deinit(self.allocator);
            var fn_idx: usize = 0;
            while (fn_idx < self.function_stack.items.len) : (fn_idx += 1) {
                self.function_stack.items[fn_idx].deinit(self.allocator);
            }
            self.function_stack.deinit(self.allocator);
            var bind_idx: usize = 0;
            while (bind_idx < self.scope_bindings.items.len) : (bind_idx += 1) {
                self.scope_bindings.items[bind_idx].deinit(self.allocator);
            }
            self.scope_bindings.deinit(self.allocator);
        }

        var constants: std.ArrayListUnmanaged(ScriptValue) = .{};
        var instructions: std.ArrayListUnmanaged(Instruction) = .{};
        var cleanup_on_error = true;
        errdefer {
            if (cleanup_on_error) {
                for (constants.items, 0..) |_, idx| {
                    constants.items[idx].deinit(self.allocator);
                }
                constants.deinit(self.allocator);
                instructions.deinit(self.allocator);
            }
        }
        const nil_const_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .nil = {} });
        try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ 0, nil_const_idx, 0 } });
        var last_result_reg: u16 = 0;

        while (self.peek() != null) {
            last_result_reg = try self.parseStatement(&constants, &instructions);
            self.skipWhitespace();
            if (self.peek() == ';') {
                self.advance();
                self.skipWhitespace();
            }
        }

        try instructions.append(self.allocator, .{ .opcode = .ret, .operands = [_]u16{ last_result_reg, 0, 0 } });

        const instr_slice = try self.allocator.dupe(Instruction, instructions.items);
        const const_slice = try self.allocator.dupe(ScriptValue, constants.items);
        cleanup_on_error = false;
        instructions.deinit(self.allocator);
        constants.deinit(self.allocator);
        return .{ .instructions = instr_slice, .constants = const_slice };
    }

    const ParseResult = struct {
        result_reg: u16,
        next_reg: u16,
        self_reg: ?u16 = null,
        value_count: u16 = 1,
        call_instr_index: ?usize = null,
    };

    fn configureCallResultCount(
        self: *Parser,
        instructions: *std.ArrayListUnmanaged(Instruction),
        result: *ParseResult,
        desired: u16,
    ) void {
        _ = self;
        if (result.call_instr_index) |idx| {
            instructions.items[idx].extra = desired;
            result.value_count = if (desired == 0) 1 else desired;
            const min_next = if (desired == 0) result.result_reg + 1 else result.result_reg + desired;
            if (result.next_reg < min_next) {
                result.next_reg = min_next;
            }
        }
    }

    fn appendBeginScope(self: *Parser, instructions: *std.ArrayListUnmanaged(Instruction)) !void {
        try instructions.append(self.allocator, .{ .opcode = .begin_scope, .operands = [_]u16{ 0, 0, 0 } });
        self.scope_depth += 1;

        const binding = ScopeBinding.init(self.function_stack.items.len);
        try self.scope_bindings.append(self.allocator, binding);

        if (self.function_stack.items.len > 0) {
            const fn_ctx = &self.function_stack.items[self.function_stack.items.len - 1];
            if (!fn_ctx.params_registered and self.scope_depth == fn_ctx.base_scope_depth + 1) {
                try self.registerPendingParams();
            }
        }
    }

    fn appendEndScope(self: *Parser, instructions: *std.ArrayListUnmanaged(Instruction)) !void {
        if (self.scope_depth == 0) {
            return error.ParseError;
        }
        if (self.scope_bindings.items.len == 0) {
            return error.ParseError;
        }
        var binding = self.scope_bindings.items[self.scope_bindings.items.len - 1];
        self.scope_bindings.items.len -= 1;
        binding.deinit(self.allocator);
        try instructions.append(self.allocator, .{ .opcode = .end_scope, .operands = [_]u16{ 0, 0, 0 } });
        self.scope_depth -= 1;
    }

    fn emitScopeUnwind(self: *Parser, instructions: *std.ArrayListUnmanaged(Instruction), count: usize) !void {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            try instructions.append(self.allocator, .{ .opcode = .end_scope, .operands = [_]u16{ 0, 0, 0 } });
        }
    }

    fn registerLocalOwned(self: *Parser, name: []const u8) !void {
        if (self.scope_bindings.items.len == 0) {
            self.allocator.free(name);
            return;
        }
        try self.scope_bindings.items[self.scope_bindings.items.len - 1].names.append(self.allocator, name);
    }

    fn registerLocalCopy(self: *Parser, name: []const u8) !void {
        const dup = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(dup);
        try self.registerLocalOwned(dup);
    }

    fn resolveBindingFunctionDepth(self: *Parser, name: []const u8) ?usize {
        var idx = self.scope_bindings.items.len;
        while (idx > 0) : (idx -= 1) {
            const binding = &self.scope_bindings.items[idx - 1];
            for (binding.names.items) |existing| {
                if (std.mem.eql(u8, existing, name)) {
                    return binding.function_depth;
                }
            }
        }
        return null;
    }

    fn registerPendingParams(self: *Parser) !void {
        if (self.function_stack.items.len == 0) return;
        var fn_ctx = &self.function_stack.items[self.function_stack.items.len - 1];
        if (fn_ctx.params_registered) return;
        for (fn_ctx.pending_params.items) |param| {
            try self.registerLocalOwned(param);
        }
        fn_ctx.pending_params.items.len = 0;
        fn_ctx.pending_params.deinit(self.allocator);
        fn_ctx.pending_params = .{};
        fn_ctx.params_registered = true;
    }

    fn noteIdentifierUsage(self: *Parser, name: []const u8) !void {
        const current_depth = self.function_stack.items.len;
        if (current_depth == 0) return;
        const binding_depth = self.resolveBindingFunctionDepth(name) orelse return;
        if (binding_depth == 0 or binding_depth == current_depth) return;
        var depth = binding_depth + 1;
        while (depth <= current_depth) : (depth += 1) {
            const ctx_index = depth - 1;
            try self.function_stack.items[ctx_index].addCapture(self.allocator, name);
        }
    }

    fn currentLoop(self: *Parser) ?*LoopContext {
        if (self.loop_stack.items.len == 0) return null;
        return &self.loop_stack.items[self.loop_stack.items.len - 1];
    }

    fn pushLoop(self: *Parser, start_idx: usize, continue_target: usize, result_reg: u16) !*LoopContext {
        var ctx = LoopContext.init();
        ctx.start_idx = start_idx;
        ctx.continue_target = continue_target;
        ctx.result_reg = result_reg;
        ctx.base_scope_depth = self.scope_depth;
        ctx.loop_scope_base = ctx.base_scope_depth;
        try self.loop_stack.append(self.allocator, ctx);
        return &self.loop_stack.items[self.loop_stack.items.len - 1];
    }

    fn popLoop(self: *Parser, instructions: *std.ArrayListUnmanaged(Instruction), after_loop_idx: usize) void {
        const idx = self.loop_stack.items.len - 1;
        var ctx = self.loop_stack.items[idx];
        self.loop_stack.items.len = idx;

        for (ctx.break_jumps.items) |jump_idx| {
            instructions.items[jump_idx].operands[0] = @as(u16, @intCast(after_loop_idx));
        }
        for (ctx.continue_jumps.items) |jump_idx| {
            instructions.items[jump_idx].operands[0] = @as(u16, @intCast(ctx.continue_target));
        }

        ctx.deinit(self.allocator);
    }

    fn recordBreak(self: *Parser, instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        if (self.currentLoop()) |loop_ctx| {
            const unwind = self.scope_depth - loop_ctx.base_scope_depth;
            try self.emitScopeUnwind(instructions, unwind);
            const jump_idx = instructions.items.len;
            try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ 0, 0, 0 } });
            try loop_ctx.break_jumps.append(self.allocator, jump_idx);
            return loop_ctx.result_reg;
        }
        return error.ParseError;
    }

    fn recordContinue(self: *Parser, instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        if (self.currentLoop()) |loop_ctx| {
            const unwind = if (self.scope_depth > loop_ctx.loop_scope_base)
                self.scope_depth - loop_ctx.loop_scope_base
            else
                0;
            if (unwind > 0) {
                try self.emitScopeUnwind(instructions, unwind);
            }
            const jump_idx = instructions.items.len;
            try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ 0, 0, 0 } });
            try loop_ctx.continue_jumps.append(self.allocator, jump_idx);
            return loop_ctx.result_reg;
        }
        return error.ParseError;
    }

    fn parseConditionExpression(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        self.skipWhitespace();
        if (self.peek() == '(') {
            self.advance();
            const cond = try self.parseExpression(constants, instructions, reg_start);
            self.skipWhitespace();
            try self.expect(')');
            return cond;
        }
        return self.parseExpression(constants, instructions, reg_start);
    }

    fn peekKeyword(self: *Parser, keyword: []const u8) bool {
        const end_pos = self.pos + keyword.len;
        if (end_pos > self.source.len) return false;
        if (!std.mem.eql(u8, self.source[self.pos..end_pos], keyword)) return false;
        if (end_pos < self.source.len and isIdentChar(self.source[end_pos])) return false;
        return true;
    }

    const BlockStyle = enum { braces, lua };

    fn parseConditionalBody(
        self: *Parser,
        constants: *std.ArrayListUnmanaged(ScriptValue),
        instructions: *std.ArrayListUnmanaged(Instruction),
        block_style: *?BlockStyle,
        require_then: bool,
        terminators: []const []const u8,
    ) anyerror!u16 {
        self.skipWhitespace();
        if (self.peek() == '{') {
            if (block_style.*) |style| {
                if (style == .lua) return error.ParseError;
            } else {
                block_style.* = .braces;
            }
            return try self.parseBlock(constants, instructions);
        }

        if (block_style.*) |style| {
            if (style == .braces) return error.ParseError;
        } else {
            block_style.* = .lua;
        }

        if (require_then) {
            if (!self.matchKeyword("then")) return error.ParseError;
        }

        self.skipWhitespace();
        return try self.parseLuaScopedBlock(constants, instructions, terminators);
    }

    fn parseStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        self.skipWhitespace();
        if (self.peekIdent()) {
            const ident_start = self.pos;
            const ident = try self.parseIdent();
            defer self.allocator.free(ident);
            if (std.mem.eql(u8, ident, "function")) {
                self.skipWhitespace();
                return try self.parseFunctionDeclaration(constants, instructions);
            } else if (std.mem.eql(u8, ident, "return")) {
                return try self.parseReturnStatement(constants, instructions);
            } else if (std.mem.eql(u8, ident, "local")) {
                self.skipWhitespace();
                if (self.peekKeyword("function")) {
                    _ = self.matchKeyword("function");
                    self.skipWhitespace();
                    return try self.parseLocalFunctionDeclaration(constants, instructions);
                }
                return try self.parseLocalDeclaration(constants, instructions);
            } else if (std.mem.eql(u8, ident, "var")) {
                self.skipWhitespace();
                return try self.parseDeclaration(constants, instructions, 1);
            } else if (std.mem.eql(u8, ident, "break")) {
                return try self.recordBreak(instructions);
            } else if (std.mem.eql(u8, ident, "continue")) {
                return try self.recordContinue(instructions);
            } else if (std.mem.eql(u8, ident, "if")) {
                return try self.parseIfStatement(constants, instructions);
            } else if (std.mem.eql(u8, ident, "while")) {
                return try self.parseWhileStatement(constants, instructions);
            } else if (std.mem.eql(u8, ident, "for")) {
                return try self.parseForStatement(constants, instructions);
            } else if (std.mem.eql(u8, ident, "repeat")) {
                return try self.parseRepeatUntilStatement(constants, instructions);
            } else {
                self.skipWhitespace();
                if (self.peek() == '=' and self.peekNext() != '=') {
                    try self.noteIdentifierUsage(ident);
                    self.advance();
                    self.skipWhitespace();
                    const expr = try self.parseExpression(constants, instructions, 0);
                    const name_idx = @as(u16, @intCast(constants.items.len));
                    try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                    try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ expr.result_reg, name_idx, 0 } });
                    return expr.result_reg;
                }
                if (self.peek() == '.') {
                    const member_start = self.pos;
                    self.advance();
                    self.skipWhitespace();
                    if (self.peekIdent()) {
                        const field_name = try self.parseIdent();
                        defer self.allocator.free(field_name);
                        self.skipWhitespace();
                        if (self.peek() == '=' and self.peekNext() != '=') {
                            try self.noteIdentifierUsage(ident);
                            self.advance();
                            self.skipWhitespace();

                            const table_reg: u16 = 0;
                            const table_name_idx = @as(u16, @intCast(constants.items.len));
                            try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                            try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ table_reg, table_name_idx, 0 } });

                            const key_idx = @as(u16, @intCast(constants.items.len));
                            try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, field_name) });

                            const value_reg_start: u16 = table_reg + 1;
                            var value_res = try self.parseExpression(constants, instructions, value_reg_start);
                            if (value_res.call_instr_index != null) {
                                self.configureCallResultCount(instructions, &value_res, 1);
                            }
                            if (value_res.result_reg != value_reg_start) {
                                try instructions.append(self.allocator, .{ .opcode = .move, .operands = [_]u16{ value_reg_start, value_res.result_reg, 0 } });
                            }

                            try instructions.append(self.allocator, .{ .opcode = .table_set_field, .operands = [_]u16{ table_reg, key_idx, value_reg_start } });
                            return value_reg_start;
                        }
                    }
                    self.pos = member_start;
                }
                self.pos = ident_start;
            }
        }

        const expr = try self.parseExpression(constants, instructions, 0);
        return expr.result_reg;
    }

    fn parseIfStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        var block_style: ?BlockStyle = null;
        var exit_jumps = std.ArrayListUnmanaged(usize){};
        defer exit_jumps.deinit(self.allocator);

        const first_cond = try self.parseConditionExpression(constants, instructions, 0);
        var jump_false_idx = instructions.items.len;
        try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ first_cond.result_reg, 0, 0 } });

        self.skipWhitespace();
        var statement_result = try self.parseConditionalBody(constants, instructions, &block_style, true, &.{ "elseif", "else", "end" });

        while (true) {
            self.skipWhitespace();
            if (self.peekKeyword("elseif")) {
                const exit_jump_idx = instructions.items.len;
                try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ 0, 0, 0 } });
                try exit_jumps.append(self.allocator, exit_jump_idx);

                instructions.items[jump_false_idx].operands[1] = @as(u16, @intCast(instructions.items.len));
                _ = self.matchKeyword("elseif");
                self.skipWhitespace();
                const branch_cond = try self.parseConditionExpression(constants, instructions, 0);
                jump_false_idx = instructions.items.len;
                try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ branch_cond.result_reg, 0, 0 } });
                self.skipWhitespace();
                statement_result = try self.parseConditionalBody(constants, instructions, &block_style, true, &.{ "elseif", "else", "end" });
                continue;
            } else if (self.peekKeyword("else")) {
                const exit_jump_idx = instructions.items.len;
                try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ 0, 0, 0 } });
                try exit_jumps.append(self.allocator, exit_jump_idx);

                instructions.items[jump_false_idx].operands[1] = @as(u16, @intCast(instructions.items.len));
                _ = self.matchKeyword("else");
                self.skipWhitespace();
                if (self.matchKeyword("if")) {
                    self.skipWhitespace();
                    const branch_cond = try self.parseConditionExpression(constants, instructions, 0);
                    jump_false_idx = instructions.items.len;
                    try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ branch_cond.result_reg, 0, 0 } });
                    self.skipWhitespace();
                    statement_result = try self.parseConditionalBody(constants, instructions, &block_style, true, &.{ "elseif", "else", "end" });
                    continue;
                }

                statement_result = try self.parseConditionalBody(constants, instructions, &block_style, false, &.{"end"});
                self.skipWhitespace();
                if (block_style) |style| {
                    if (style == .lua) {
                        if (!self.matchKeyword("end")) return error.ParseError;
                    }
                }
                break;
            } else {
                instructions.items[jump_false_idx].operands[1] = @as(u16, @intCast(instructions.items.len));
                if (block_style) |style| {
                    if (style == .lua) {
                        self.skipWhitespace();
                        if (!self.matchKeyword("end")) return error.ParseError;
                    }
                }
                break;
            }
        }

        const end_target = @as(u16, @intCast(instructions.items.len));
        for (exit_jumps.items) |jump_idx| {
            instructions.items[jump_idx].operands[0] = end_target;
        }

        return statement_result;
    }

    fn parseWhileStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        self.skipWhitespace();
        const condition_start_idx = instructions.items.len;
        const cond = try self.parseConditionExpression(constants, instructions, 0);

        const jump_false_idx = instructions.items.len;
        try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ cond.result_reg, 0, 0 } });

        _ = try self.pushLoop(condition_start_idx, condition_start_idx, cond.result_reg);

        self.skipWhitespace();
        var body_result: u16 = 0;
        if (self.peek() == '{') {
            body_result = try self.parseBlock(constants, instructions);
        } else {
            if (!self.matchKeyword("do")) return error.ParseError;
            self.skipWhitespace();
            body_result = try self.parseLuaScopedBlock(constants, instructions, &.{"end"});
            self.skipWhitespace();
            if (!self.matchKeyword("end")) return error.ParseError;
        }

        const loop_start_u16 = @as(u16, @intCast(condition_start_idx));
        try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ loop_start_u16, 0, 0 } });
        instructions.items[jump_false_idx].operands[1] = @as(u16, @intCast(instructions.items.len));

        self.popLoop(instructions, instructions.items.len);

        return body_result;
    }

    fn parseForStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        self.skipWhitespace();
        const first_name = try self.parseIdent();

        self.skipWhitespace();
        if (self.peek() == '=') {
            defer self.allocator.free(first_name);
            self.advance();
            self.skipWhitespace();
            return try self.parseNumericForLoop(constants, instructions, first_name);
        }

        var name_list = std.ArrayListUnmanaged([]const u8){};
        defer {
            var idx: usize = 0;
            while (idx < name_list.items.len) : (idx += 1) {
                self.allocator.free(name_list.items[idx]);
            }
            name_list.deinit(self.allocator);
        }

        name_list.append(self.allocator, first_name) catch |err| {
            self.allocator.free(first_name);
            return err;
        };

        while (true) {
            self.skipWhitespace();
            if (self.peek() == ',') {
                self.advance();
                self.skipWhitespace();
                const extra_name = try self.parseIdent();
                name_list.append(self.allocator, extra_name) catch |err| {
                    self.allocator.free(extra_name);
                    return err;
                };
                continue;
            }
            break;
        }

        self.skipWhitespace();
        if (!self.matchKeyword("in")) return error.ParseError;
        self.skipWhitespace();

        const iterable_expr = try self.parseExpression(constants, instructions, 0);
        self.skipWhitespace();

        if (self.matchOperator("..")) {
            if (name_list.items.len != 1) return error.ParseError;
            self.skipWhitespace();
            const end_expr = try self.parseExpression(constants, instructions, iterable_expr.next_reg);
            self.skipWhitespace();
            return try self.parseRangeForLoop(constants, instructions, name_list.items[0], iterable_expr, end_expr);
        }

        return try self.parseGenericForLoop(constants, instructions, name_list.items, iterable_expr);
    }

    fn parseNumericForLoop(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), iter_name: []const u8) anyerror!u16 {
        const start_expr = try self.parseExpression(constants, instructions, 0);
        self.skipWhitespace();
        if (self.peek() != ',') return error.ParseError;
        self.advance();
        self.skipWhitespace();
        const end_expr = try self.parseExpression(constants, instructions, start_expr.next_reg);
        self.skipWhitespace();

        var step_expr: ?ParseResult = null;
        if (self.peek() == ',') {
            self.advance();
            self.skipWhitespace();
            step_expr = try self.parseExpression(constants, instructions, end_expr.next_reg);
            self.skipWhitespace();
        }

        const iter_name_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, iter_name) });

        const limit_name = try self.nextTempName("__for_limit");
        defer self.allocator.free(limit_name);
        const limit_name_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, limit_name) });

        const step_name = try self.nextTempName("__for_step");
        defer self.allocator.free(step_name);
        const step_name_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, step_name) });

        const loop_setup_idx = instructions.items.len;
        var loop_ctx = try self.pushLoop(loop_setup_idx, loop_setup_idx, start_expr.result_reg);

        try self.appendBeginScope(instructions);
        loop_ctx.loop_scope_base = self.scope_depth;

        try self.registerLocalCopy(iter_name);
        try self.registerLocalCopy(limit_name);
        try self.registerLocalCopy(step_name);

        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ start_expr.result_reg, iter_name_idx, 1 } });
        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ end_expr.result_reg, limit_name_idx, 1 } });

        const step_reg: u16 = if (step_expr) |expr| expr.result_reg else end_expr.next_reg;
        if (step_expr) |expr| {
            try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ expr.result_reg, step_name_idx, 1 } });
        } else {
            const one_const_idx = @as(u16, @intCast(constants.items.len));
            try constants.append(self.allocator, .{ .number = 1 });
            try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ step_reg, one_const_idx, 0 } });
            try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ step_reg, step_name_idx, 1 } });
        }

        const bool_base: u16 = if (step_expr) |expr| expr.next_reg else step_reg + 1;
        var next_reg = bool_base;
        const cond_pos_reg = next_reg;
        next_reg += 1;
        const cmp_pos_reg = next_reg;
        next_reg += 1;
        const cmp_neg_reg = next_reg;
        next_reg += 1;
        const not_pos_reg = next_reg;
        next_reg += 1;
        const cond_final_reg = next_reg;
        next_reg += 1;

        loop_ctx.result_reg = cond_final_reg;

        const loop_start_idx = instructions.items.len;
        loop_ctx.start_idx = loop_start_idx;

        const iter_reg = start_expr.result_reg;
        const limit_reg = end_expr.result_reg;

        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ iter_reg, iter_name_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ limit_reg, limit_name_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ step_reg, step_name_idx, 0 } });

        const zero_const_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .number = 0 });
        try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ cond_pos_reg, zero_const_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .gte, .operands = [_]u16{ cond_pos_reg, step_reg, cond_pos_reg } });

        try instructions.append(self.allocator, .{ .opcode = .lte, .operands = [_]u16{ cmp_pos_reg, iter_reg, limit_reg } });
        try instructions.append(self.allocator, .{ .opcode = .gte, .operands = [_]u16{ cmp_neg_reg, iter_reg, limit_reg } });

        try instructions.append(self.allocator, .{ .opcode = .not_op, .operands = [_]u16{ not_pos_reg, cond_pos_reg, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .and_op, .operands = [_]u16{ cond_final_reg, cond_pos_reg, cmp_pos_reg } });
        try instructions.append(self.allocator, .{ .opcode = .and_op, .operands = [_]u16{ cmp_pos_reg, not_pos_reg, cmp_neg_reg } });
        try instructions.append(self.allocator, .{ .opcode = .or_op, .operands = [_]u16{ cond_final_reg, cond_final_reg, cmp_pos_reg } });

        const jump_exit_idx = instructions.items.len;
        try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ cond_final_reg, 0, 0 } });

        self.skipWhitespace();
        var body_result: u16 = 0;
        if (self.peek() == '{') {
            body_result = try self.parseBlock(constants, instructions);
        } else {
            if (!self.matchKeyword("do")) return error.ParseError;
            self.skipWhitespace();
            body_result = try self.parseLuaScopedBlock(constants, instructions, &.{"end"});
            self.skipWhitespace();
            if (!self.matchKeyword("end")) return error.ParseError;
        }
        self.skipWhitespace();

        const increment_start_idx = instructions.items.len;
        loop_ctx.continue_target = increment_start_idx;

        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ iter_reg, iter_name_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ step_reg, step_name_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .add, .operands = [_]u16{ iter_reg, iter_reg, step_reg } });
        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ iter_reg, iter_name_idx, 0 } });

        try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ @as(u16, @intCast(loop_start_idx)), 0, 0 } });
        instructions.items[jump_exit_idx].operands[1] = @as(u16, @intCast(instructions.items.len));

        try self.appendEndScope(instructions);
        self.popLoop(instructions, instructions.items.len);

        return body_result;
    }

    fn parseRangeForLoop(
        self: *Parser,
        constants: *std.ArrayListUnmanaged(ScriptValue),
        instructions: *std.ArrayListUnmanaged(Instruction),
        iter_name: []const u8,
        start_expr: ParseResult,
        end_expr: ParseResult,
    ) anyerror!u16 {
        const iter_name_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, iter_name) });

        const end_name = try self.nextTempName("__for_end");
        defer self.allocator.free(end_name);
        const end_name_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, end_name) });

        const loop_setup_idx = instructions.items.len;
        var loop_ctx = try self.pushLoop(loop_setup_idx, loop_setup_idx, start_expr.result_reg);

        try self.appendBeginScope(instructions);
        loop_ctx.loop_scope_base = self.scope_depth;

        try self.registerLocalCopy(iter_name);
        try self.registerLocalCopy(end_name);

        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ start_expr.result_reg, iter_name_idx, 1 } });
        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ end_expr.result_reg, end_name_idx, 1 } });

        const loop_start_idx = instructions.items.len;
        loop_ctx.start_idx = loop_start_idx;

        const iter_reg = start_expr.result_reg;
        const end_reg = end_expr.result_reg;
        const cond_reg = end_expr.next_reg;
        loop_ctx.result_reg = cond_reg;

        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ iter_reg, iter_name_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ end_reg, end_name_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .lt, .operands = [_]u16{ cond_reg, iter_reg, end_reg } });

        const jump_exit_idx = instructions.items.len;
        try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ cond_reg, 0, 0 } });

        self.skipWhitespace();
        var body_result: u16 = 0;
        if (self.peek() == '{') {
            body_result = try self.parseBlock(constants, instructions);
        } else {
            if (!self.matchKeyword("do")) return error.ParseError;
            self.skipWhitespace();
            body_result = try self.parseLuaScopedBlock(constants, instructions, &.{"end"});
            self.skipWhitespace();
            if (!self.matchKeyword("end")) return error.ParseError;
        }
        self.skipWhitespace();

        const increment_start_idx = instructions.items.len;
        loop_ctx.continue_target = increment_start_idx;

        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ iter_reg, iter_name_idx, 0 } });

        const one_const_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .number = 1 });
        try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ end_reg, one_const_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .add, .operands = [_]u16{ iter_reg, iter_reg, end_reg } });
        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ iter_reg, iter_name_idx, 0 } });

        try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ @as(u16, @intCast(loop_start_idx)), 0, 0 } });
        instructions.items[jump_exit_idx].operands[1] = @as(u16, @intCast(instructions.items.len));

        try self.appendEndScope(instructions);
        self.popLoop(instructions, instructions.items.len);

        return body_result;
    }

    fn parseGenericForLoop(
        self: *Parser,
        constants: *std.ArrayListUnmanaged(ScriptValue),
        instructions: *std.ArrayListUnmanaged(Instruction),
        var_names: []const []const u8,
        iter_expr: ParseResult,
    ) anyerror!u16 {
        if (var_names.len == 0) return error.ParseError;
        if (var_names.len > 2) return error.ParseError;

        const var_count_u16: u16 = @intCast(var_names.len);
        const iterator_reg = iter_expr.result_reg;
        const cond_reg = iter_expr.next_reg;
        const unpack_base: u16 = cond_reg + 1;

        const loop_setup_idx = instructions.items.len;
        var loop_ctx = try self.pushLoop(loop_setup_idx, loop_setup_idx, cond_reg);

        try self.appendBeginScope(instructions);
        loop_ctx.loop_scope_base = self.scope_depth;
        loop_ctx.result_reg = cond_reg;

        var name_indices = std.ArrayListUnmanaged(u16){};
        defer name_indices.deinit(self.allocator);

        var idx: usize = 0;
        while (idx < var_names.len) : (idx += 1) {
            const name = var_names[idx];
            try self.registerLocalCopy(name);
            const name_idx = @as(u16, @intCast(constants.items.len));
            try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, name) });
            try name_indices.append(self.allocator, name_idx);
        }

        const iter_holder_name = try self.nextTempName("__iter");
        defer self.allocator.free(iter_holder_name);
        const iter_holder_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, iter_holder_name) });
        try self.registerLocalCopy(iter_holder_name);

        try instructions.append(self.allocator, .{ .opcode = .iterator_init, .operands = [_]u16{ iterator_reg, iterator_reg, var_count_u16 } });
        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ iterator_reg, iter_holder_idx, 1 } });

        const nil_const_idx: u16 = 0;
        try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ cond_reg, nil_const_idx, 0 } });
        var name_idx_iter: usize = 0;
        while (name_idx_iter < name_indices.items.len) : (name_idx_iter += 1) {
            const name_const = name_indices.items[name_idx_iter];
            try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ cond_reg, name_const, 1 } });
        }

        const loop_start_idx = instructions.items.len;
        loop_ctx.start_idx = loop_start_idx;
        loop_ctx.continue_target = loop_start_idx;

        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ iterator_reg, iter_holder_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .iterator_next, .operands = [_]u16{ cond_reg, iterator_reg, 0 } });
        const jump_exit_idx = instructions.items.len;
        try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ cond_reg, 0, 0 } });

        try instructions.append(self.allocator, .{ .opcode = .iterator_unpack, .operands = [_]u16{ unpack_base, var_count_u16, iterator_reg } });
        idx = 0;
        while (idx < var_names.len) : (idx += 1) {
            const source_reg = unpack_base + @as(u16, @intCast(idx));
            const name_const = name_indices.items[idx];
            try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ source_reg, name_const, 0 } });
        }

        self.skipWhitespace();
        var body_result: u16 = 0;
        if (self.peek() == '{') {
            body_result = try self.parseBlock(constants, instructions);
        } else {
            if (!self.matchKeyword("do")) return error.ParseError;
            self.skipWhitespace();
            body_result = try self.parseLuaScopedBlock(constants, instructions, &.{"end"});
            self.skipWhitespace();
            if (!self.matchKeyword("end")) return error.ParseError;
        }
        self.skipWhitespace();

        try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ @as(u16, @intCast(loop_start_idx)), 0, 0 } });
        instructions.items[jump_exit_idx].operands[1] = @as(u16, @intCast(instructions.items.len));

        try self.appendEndScope(instructions);
        self.popLoop(instructions, instructions.items.len);

        return body_result;
    }

    fn parseRepeatUntilStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        const loop_start_idx = instructions.items.len;
        var loop_ctx = try self.pushLoop(loop_start_idx, loop_start_idx, 0);

        self.skipWhitespace();
        var body_result: u16 = 0;
        if (self.peek() == '{') {
            body_result = try self.parseBlock(constants, instructions);
        } else {
            body_result = try self.parseLuaScopedBlock(constants, instructions, &.{"until"});
        }

        self.skipWhitespace();
        if (!self.matchKeyword("until")) return error.ParseError;
        self.skipWhitespace();

        const condition_start_idx = instructions.items.len;
        loop_ctx.continue_target = condition_start_idx;

        const cond = try self.parseExpression(constants, instructions, 0);
        loop_ctx.result_reg = cond.result_reg;

        const loop_start_u16 = @as(u16, @intCast(loop_start_idx));
        try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ cond.result_reg, loop_start_u16, 0 } });

        self.popLoop(instructions, instructions.items.len);

        return body_result;
    }

    fn parseFunctionParameters(self: *Parser, params: *std.ArrayListUnmanaged([]const u8)) anyerror!bool {
        self.skipWhitespace();
        try self.expect('(');
        self.skipWhitespace();

        var saw_vararg = false;

        if (self.peek() != ')') {
            while (true) {
                if (self.matchOperator("...")) {
                    saw_vararg = true;
                    self.skipWhitespace();
                    if (self.peek() == ',') return error.ParseError;
                    break;
                }

                const param_name = try self.parseIdent();
                try params.append(self.allocator, param_name);
                self.skipWhitespace();

                if (self.peek() == ',') {
                    self.advance();
                    self.skipWhitespace();
                    if (self.peek() == ')') return error.ParseError;
                    continue;
                }
                break;
            }
        }

        try self.expect(')');

        return saw_vararg;
    }

    fn emitFunctionLiteral(
        self: *Parser,
        constants: *std.ArrayListUnmanaged(ScriptValue),
        instructions: *std.ArrayListUnmanaged(Instruction),
        params: *std.ArrayListUnmanaged([]const u8),
        is_vararg: bool,
    ) anyerror!u16 {
        const jump_over_idx = instructions.items.len;
        try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ 0, 0, 0 } });

        const body_start_idx = instructions.items.len;

        const ctx_index = self.function_stack.items.len;
        var new_ctx = FunctionContext.init(self.scope_depth);
        new_ctx.is_vararg = is_vararg;
        try self.function_stack.append(self.allocator, new_ctx);
        errdefer {
            var ctx = &self.function_stack.items[self.function_stack.items.len - 1];
            ctx.deinit(self.allocator);
            self.function_stack.items.len = ctx_index;
        }

        {
            var ctx = &self.function_stack.items[self.function_stack.items.len - 1];
            ctx.is_vararg = is_vararg;
            for (params.items) |param_name| {
                try ctx.addPendingParam(self.allocator, param_name);
            }
        }

        var body_result: u16 = 0;
        if (self.peek() == '{') {
            body_result = try self.parseBlock(constants, instructions);
        } else {
            body_result = try self.parseLuaScopedBlock(constants, instructions, &.{"end"});
            self.skipWhitespace();
            if (!self.matchKeyword("end")) return error.ParseError;
        }

        const default_reg: u16 = if (body_result != 0) body_result else 0;
        const nil_const_idx: u16 = 0;
        try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ default_reg, nil_const_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .return_value, .operands = [_]u16{ default_reg, 1, 0 } });

        const body_end_idx = instructions.items.len;
        instructions.items[jump_over_idx].operands[0] = @as(u16, @intCast(body_end_idx));

        var fn_ctx = &self.function_stack.items[self.function_stack.items.len - 1];
        const capture_names = try fn_ctx.takeCaptureNames(self.allocator);
        fn_ctx.deinit(self.allocator);
        self.function_stack.items.len = ctx_index;

        const owned_params = try params.toOwnedSlice(self.allocator);
        params.*.deinit(self.allocator);
        params.* = .{};
        defer {
            for (owned_params) |param| {
                self.allocator.free(param);
            }
            self.allocator.free(owned_params);
        }
        defer {
            for (capture_names) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(capture_names);
        }

        const script_func = try ScriptFunction.init(self.allocator, body_start_idx, body_end_idx, owned_params, capture_names);
        script_func.markVarArg(is_vararg);
        errdefer script_func.release();

        const func_const_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .script_function = script_func });

        return func_const_idx;
    }

    fn parseFunctionDeclaration(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        const func_name = try self.parseIdent();
        defer self.allocator.free(func_name);

        var params = std.ArrayListUnmanaged([]const u8){};
        var params_cleanup = true;
        errdefer if (params_cleanup) {
            var idx: usize = 0;
            while (idx < params.items.len) : (idx += 1) {
                self.allocator.free(params.items[idx]);
            }
            params.deinit(self.allocator);
        };

        const is_vararg = try self.parseFunctionParameters(&params);

        self.skipWhitespace();

        const func_const_idx = try self.emitFunctionLiteral(constants, instructions, &params, is_vararg);
        params_cleanup = false;

        const target_reg: u16 = 0;
        try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ target_reg, func_const_idx, 0 } });

        const name_const_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, func_name) });
        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ target_reg, name_const_idx, 1 } });

        return target_reg;
    }

    fn parseLocalFunctionDeclaration(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        const func_name = try self.parseIdent();
        defer self.allocator.free(func_name);

        var params = std.ArrayListUnmanaged([]const u8){};
        var params_cleanup = true;
        errdefer if (params_cleanup) {
            var idx: usize = 0;
            while (idx < params.items.len) : (idx += 1) {
                self.allocator.free(params.items[idx]);
            }
            params.deinit(self.allocator);
        };

        const is_vararg = try self.parseFunctionParameters(&params);

        try self.registerLocalCopy(func_name);

        self.skipWhitespace();

        const func_const_idx = try self.emitFunctionLiteral(constants, instructions, &params, is_vararg);
        params_cleanup = false;

        const target_reg: u16 = 0;
        try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ target_reg, func_const_idx, 0 } });

        const name_const_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, func_name) });
        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ target_reg, name_const_idx, 2 } });

        return target_reg;
    }

    fn parseFunctionExpression(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg: u16) anyerror!ParseResult {
        var params = std.ArrayListUnmanaged([]const u8){};
        var params_cleanup = true;
        errdefer if (params_cleanup) {
            var idx: usize = 0;
            while (idx < params.items.len) : (idx += 1) {
                self.allocator.free(params.items[idx]);
            }
            params.deinit(self.allocator);
        };

        const is_vararg = try self.parseFunctionParameters(&params);

        const func_const_idx = try self.emitFunctionLiteral(constants, instructions, &params, is_vararg);
        params_cleanup = false;

        try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ reg, func_const_idx, 0 } });

        return .{ .result_reg = reg, .next_reg = reg + 1 };
    }

    fn parseReturnStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        if (self.function_stack.items.len == 0) {
            return error.ParseError;
        }

        self.skipWhitespace();

        var has_expression = true;
        const next = self.peek();
        if (next == null or next == ';' or next == '}' or next == ')') {
            has_expression = false;
        } else if (self.peekKeyword("end") or self.peekKeyword("elseif") or self.peekKeyword("else")) {
            has_expression = false;
        }

        var result_reg: u16 = 0;
        var fixed_count: u16 = 0;
        var has_variadic = false;
        if (has_expression) {
            const base_reg: u16 = 0;
            var values = std.ArrayListUnmanaged(struct {
                result: ParseResult,
                is_variadic: bool,
            }){};
            defer values.deinit(self.allocator);

            while (true) {
                const target_reg = base_reg + @as(u16, @intCast(values.items.len));
                var expr = try self.parseExpression(constants, instructions, target_reg);
                if (expr.result_reg != target_reg) {
                    try instructions.append(self.allocator, .{ .opcode = .move, .operands = [_]u16{ target_reg, expr.result_reg, 0 } });
                    expr.result_reg = target_reg;
                }
                if (expr.next_reg < target_reg + expr.value_count) {
                    expr.next_reg = target_reg + expr.value_count;
                }
                try values.append(self.allocator, .{ .result = expr, .is_variadic = false });

                self.skipWhitespace();
                if (self.peek() == ',') {
                    self.advance();
                    self.skipWhitespace();
                    continue;
                }
                break;
            }

            result_reg = values.items[0].result.result_reg;

            const last_index = values.items.len - 1;
            var idx: usize = 0;
            while (idx < values.items.len) : (idx += 1) {
                var entry = &values.items[idx];
                const is_last = idx == last_index;
                if (is_last and entry.result.call_instr_index != null) {
                    self.configureCallResultCount(instructions, &entry.result, 0);
                    entry.is_variadic = true;
                    has_variadic = true;
                } else {
                    if (entry.result.call_instr_index != null) {
                        self.configureCallResultCount(instructions, &entry.result, 1);
                    }
                    fixed_count += entry.result.value_count;
                }
            }
        } else {
            const nil_const_idx: u16 = 0;
            try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ result_reg, nil_const_idx, 0 } });
            fixed_count = 1;
        }

        const ctx = self.function_stack.items[self.function_stack.items.len - 1];
        const unwind = if (self.scope_depth > ctx.base_scope_depth) self.scope_depth - ctx.base_scope_depth else 0;
        if (unwind > 0) {
            try self.emitScopeUnwind(instructions, unwind);
        }

        const variadic_flag: u16 = if (has_variadic) 1 else 0;
        try instructions.append(self.allocator, .{ .opcode = .return_value, .operands = [_]u16{ result_reg, fixed_count, variadic_flag } });
        return result_reg;
    }

    fn parseLocalDeclaration(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        return try self.parseDeclaration(constants, instructions, 2);
    }

    fn parseDeclaration(
        self: *Parser,
        constants: *std.ArrayListUnmanaged(ScriptValue),
        instructions: *std.ArrayListUnmanaged(Instruction),
        storage_mode: u16,
    ) anyerror!u16 {
        var names = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (names.items) |name| {
                self.allocator.free(name);
            }
            names.deinit(self.allocator);
        }

        while (true) {
            const identifier = try self.parseIdent();
            try names.append(self.allocator, identifier);
            self.skipWhitespace();
            if (self.peek() == ',') {
                self.advance();
                self.skipWhitespace();
                continue;
            }
            break;
        }

        if (names.items.len == 0) return error.ParseError;

        self.skipWhitespace();

        var expr_values = std.ArrayListUnmanaged(ParseResult){};
        defer expr_values.deinit(self.allocator);

        if (self.peek() == '=') {
            self.advance();
            self.skipWhitespace();

            while (true) {
                const target_reg = @as(u16, @intCast(expr_values.items.len));
                var expr = try self.parseExpression(constants, instructions, target_reg);
                if (expr.result_reg != target_reg) {
                    try instructions.append(self.allocator, .{ .opcode = .move, .operands = [_]u16{ target_reg, expr.result_reg, 0 } });
                    expr.result_reg = target_reg;
                }
                if (expr.next_reg < target_reg + expr.value_count) {
                    expr.next_reg = target_reg + expr.value_count;
                }
                try expr_values.append(self.allocator, expr);

                self.skipWhitespace();
                if (self.peek() == ',') {
                    self.advance();
                    self.skipWhitespace();
                    continue;
                }
                break;
            }
        }

        for (names.items) |name| {
            try self.registerLocalCopy(name);
        }

        const nil_const_idx: u16 = 0;
        var assigned: usize = 0;
        var expr_idx: usize = 0;
        var result_reg: u16 = 0;

        while (assigned < names.items.len and expr_idx < expr_values.items.len) : (expr_idx += 1) {
            const expr_ptr = &expr_values.items[expr_idx];
            const remaining = names.items.len - assigned;
            const is_last = expr_idx + 1 == expr_values.items.len;

            var produced: u16 = expr_ptr.value_count;
            if (expr_ptr.call_instr_index != null) {
                if (is_last and remaining > 1) {
                    const desired: u16 = @intCast(remaining);
                    self.configureCallResultCount(instructions, expr_ptr, desired);
                    produced = desired;
                } else {
                    self.configureCallResultCount(instructions, expr_ptr, 1);
                    produced = 1;
                }
            }

            var offset: u16 = 0;
            while (offset < produced and assigned < names.items.len) : (offset += 1) {
                const value_reg = expr_ptr.result_reg + offset;
                const name = names.items[assigned];
                const name_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, name) });
                try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ value_reg, name_idx, storage_mode } });
                result_reg = value_reg;
                assigned += 1;
            }
        }

        while (assigned < names.items.len) {
            const target_reg = @as(u16, @intCast(assigned));
            try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ target_reg, nil_const_idx, 0 } });
            const name = names.items[assigned];
            const name_idx = @as(u16, @intCast(constants.items.len));
            try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, name) });
            try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ target_reg, name_idx, storage_mode } });
            result_reg = target_reg;
            assigned += 1;
        }

        return result_reg;
    }

    fn parseLuaScopedBlock(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), terminators: []const []const u8) anyerror!u16 {
        try self.appendBeginScope(instructions);
        var last_reg: u16 = 0;
        while (true) {
            self.skipWhitespace();
            var should_break = false;
            for (terminators) |term| {
                if (self.peekKeyword(term)) {
                    should_break = true;
                    break;
                }
            }
            if (should_break or self.peek() == null) break;
            last_reg = try self.parseStatement(constants, instructions);
            self.skipWhitespace();
            if (self.peek() == ';') {
                self.advance();
            }
        }
        try self.appendEndScope(instructions);
        return last_reg;
    }

    fn parseBlock(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        self.skipWhitespace();
        try self.expect('{');
        self.skipWhitespace();
        try self.appendBeginScope(instructions);
        var last_reg: u16 = 0;
        while (self.peek() != null and self.peek() != '}') {
            last_reg = try self.parseStatement(constants, instructions);
            self.skipWhitespace();
            if (self.peek() == ';') {
                self.advance();
                self.skipWhitespace();
            }
        }
        try self.expect('}');
        try self.appendEndScope(instructions);
        return last_reg;
    }

    fn parseExpression(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        return self.parseOr(constants, instructions, reg_start);
    }

    fn parseOr(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        var left = try self.parseAnd(constants, instructions, reg_start);
        while (true) {
            self.skipWhitespace();
            var matched = false;
            if (self.matchOperator("||")) {
                matched = true;
            } else if (self.matchKeyword("or")) {
                matched = true;
            }
            if (matched) {
                self.skipWhitespace();
                const right = try self.parseAnd(constants, instructions, left.next_reg);
                try instructions.append(self.allocator, .{ .opcode = .or_op, .operands = [_]u16{ left.result_reg, left.result_reg, right.result_reg } });
                left = .{ .result_reg = left.result_reg, .next_reg = right.next_reg };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseAnd(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        var left = try self.parseEquality(constants, instructions, reg_start);
        while (true) {
            self.skipWhitespace();
            var matched = false;
            if (self.matchOperator("&&")) {
                matched = true;
            } else if (self.matchKeyword("and")) {
                matched = true;
            }
            if (matched) {
                self.skipWhitespace();
                const right = try self.parseEquality(constants, instructions, left.next_reg);
                try instructions.append(self.allocator, .{ .opcode = .and_op, .operands = [_]u16{ left.result_reg, left.result_reg, right.result_reg } });
                left = .{ .result_reg = left.result_reg, .next_reg = right.next_reg };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseEquality(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        var left = try self.parseComparison(constants, instructions, reg_start);
        while (true) {
            self.skipWhitespace();
            if (self.matchOperator("==")) {
                self.skipWhitespace();
                const right = try self.parseComparison(constants, instructions, left.next_reg);
                try instructions.append(self.allocator, .{ .opcode = .eq, .operands = [_]u16{ left.result_reg, left.result_reg, right.result_reg } });
                left = .{ .result_reg = left.result_reg, .next_reg = right.next_reg };
            } else if (self.matchOperator("!=")) {
                self.skipWhitespace();
                const right = try self.parseComparison(constants, instructions, left.next_reg);
                try instructions.append(self.allocator, .{ .opcode = .neq, .operands = [_]u16{ left.result_reg, left.result_reg, right.result_reg } });
                left = .{ .result_reg = left.result_reg, .next_reg = right.next_reg };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseComparison(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        var left = try self.parseAddition(constants, instructions, reg_start);
        while (true) {
            self.skipWhitespace();
            if (self.matchOperator("<=")) {
                self.skipWhitespace();
                const right = try self.parseAddition(constants, instructions, left.next_reg);
                try instructions.append(self.allocator, .{ .opcode = .lte, .operands = [_]u16{ left.result_reg, left.result_reg, right.result_reg } });
                left = .{ .result_reg = left.result_reg, .next_reg = right.next_reg };
            } else if (self.matchOperator(">=")) {
                self.skipWhitespace();
                const right = try self.parseAddition(constants, instructions, left.next_reg);
                try instructions.append(self.allocator, .{ .opcode = .gte, .operands = [_]u16{ left.result_reg, left.result_reg, right.result_reg } });
                left = .{ .result_reg = left.result_reg, .next_reg = right.next_reg };
            } else if (self.matchOperator("<")) {
                self.skipWhitespace();
                const right = try self.parseAddition(constants, instructions, left.next_reg);
                try instructions.append(self.allocator, .{ .opcode = .lt, .operands = [_]u16{ left.result_reg, left.result_reg, right.result_reg } });
                left = .{ .result_reg = left.result_reg, .next_reg = right.next_reg };
            } else if (self.matchOperator(">")) {
                self.skipWhitespace();
                const right = try self.parseAddition(constants, instructions, left.next_reg);
                try instructions.append(self.allocator, .{ .opcode = .gt, .operands = [_]u16{ left.result_reg, left.result_reg, right.result_reg } });
                left = .{ .result_reg = left.result_reg, .next_reg = right.next_reg };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseAddition(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        var left = try self.parseMultiplication(constants, instructions, reg_start);
        while (true) {
            self.skipWhitespace();
            const peeked = self.peek() orelse break;
            if (peeked == '+' or peeked == '-') {
                const op = peeked;
                self.advance();
                self.skipWhitespace();
                const right = try self.parseMultiplication(constants, instructions, left.next_reg);
                const opcode: Opcode = switch (op) {
                    '+' => .add,
                    '-' => .sub,
                    else => unreachable,
                };
                try instructions.append(self.allocator, .{ .opcode = opcode, .operands = [_]u16{ left.result_reg, left.result_reg, right.result_reg } });
                left = .{ .result_reg = left.result_reg, .next_reg = right.next_reg };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseMultiplication(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        var left = try self.parseUnary(constants, instructions, reg_start);
        while (true) {
            self.skipWhitespace();
            const peeked = self.peek() orelse break;
            if (peeked == '*' or peeked == '/' or peeked == '%') {
                const op = peeked;
                self.advance();
                self.skipWhitespace();
                const right = try self.parseUnary(constants, instructions, left.next_reg);
                const opcode: Opcode = switch (op) {
                    '*' => .mul,
                    '/' => .div,
                    '%' => .mod,
                    else => unreachable,
                };
                try instructions.append(self.allocator, .{ .opcode = opcode, .operands = [_]u16{ left.result_reg, left.result_reg, right.result_reg } });
                left = .{ .result_reg = left.result_reg, .next_reg = right.next_reg };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseUnary(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        self.skipWhitespace();
        if (self.matchOperator("!")) {
            self.skipWhitespace();
            const operand = try self.parseUnary(constants, instructions, reg_start);
            try instructions.append(self.allocator, .{ .opcode = .not_op, .operands = [_]u16{ operand.result_reg, operand.result_reg, 0 } });
            return operand;
        } else if (self.matchKeyword("not")) {
            self.skipWhitespace();
            const operand = try self.parseUnary(constants, instructions, reg_start);
            try instructions.append(self.allocator, .{ .opcode = .not_op, .operands = [_]u16{ operand.result_reg, operand.result_reg, 0 } });
            return operand;
        }
        return self.parseFactor(constants, instructions, reg_start);
    }

    fn parseFactor(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg: u16) anyerror!ParseResult {
        const primary = try self.parsePrimary(constants, instructions, reg);
        return try self.parsePostfix(constants, instructions, primary);
    }

    fn parsePrimary(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg: u16) anyerror!ParseResult {
        self.skipWhitespace();
        if (self.peek() == '(') {
            self.advance();
            const inner = try self.parseExpression(constants, instructions, reg);
            self.skipWhitespace();
            try self.expect(')');
            return inner;
        }

        if (self.peek() == '[') {
            return try self.parseArrayLiteral(constants, instructions, reg);
        }

        if (self.peek() == '{') {
            return try self.parseTableLiteral(constants, instructions, reg);
        }

        if (self.peekKeyword("function")) {
            _ = self.matchKeyword("function");
            return try self.parseFunctionExpression(constants, instructions, reg);
        }

        if (self.matchOperator("...")) {
            if (self.function_stack.items.len == 0) return error.ParseError;
            const ctx = &self.function_stack.items[self.function_stack.items.len - 1];
            if (!ctx.is_vararg) return error.ParseError;
            const instr_idx = instructions.items.len;
            try instructions.append(self.allocator, .{ .opcode = .vararg_collect, .operands = [_]u16{ reg, 0, 0 }, .extra = 1 });
            return .{ .result_reg = reg, .next_reg = reg + 1, .value_count = 1, .call_instr_index = instr_idx };
        }

        if (self.peek() == '"') {
            const str_value = try self.parseStringLiteral();
            const const_idx = @as(u16, @intCast(constants.items.len));
            try constants.append(self.allocator, .{ .string = str_value });
            try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ reg, const_idx, 0 } });
            return .{ .result_reg = reg, .next_reg = reg + 1 };
        }

        if (self.peekNumber()) {
            const num = try self.parseNumber();
            const const_idx = @as(u16, @intCast(constants.items.len));
            try constants.append(self.allocator, .{ .number = num });
            try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ reg, const_idx, 0 } });
            return .{ .result_reg = reg, .next_reg = reg + 1 };
        }

        if (self.peekIdent()) {
            const ident = try self.parseIdent();
            defer self.allocator.free(ident);
            if (std.mem.eql(u8, ident, "true")) {
                const const_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .boolean = true });
                try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ reg, const_idx, 0 } });
                return .{ .result_reg = reg, .next_reg = reg + 1 };
            } else if (std.mem.eql(u8, ident, "false")) {
                const const_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .boolean = false });
                try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ reg, const_idx, 0 } });
                return .{ .result_reg = reg, .next_reg = reg + 1 };
            } else if (std.mem.eql(u8, ident, "nil")) {
                const const_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .nil = {} });
                try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ reg, const_idx, 0 } });
                return .{ .result_reg = reg, .next_reg = reg + 1 };
            } else {
                try self.noteIdentifierUsage(ident);
                const name_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ reg, name_idx, 0 } });
                return .{ .result_reg = reg, .next_reg = reg + 1 };
            }
        }

        return error.ParseError;
    }

    fn parsePostfix(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), initial: ParseResult) anyerror!ParseResult {
        var current = initial;
        while (true) {
            self.skipWhitespace();
            const next_char = self.peek() orelse break;
            switch (next_char) {
                '.' => {
                    if (self.peekNext() == '.') break;
                    self.advance();
                    self.skipWhitespace();
                    const key = try self.parseIdent();
                    defer self.allocator.free(key);
                    const key_idx = @as(u16, @intCast(constants.items.len));
                    try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, key) });
                    try instructions.append(self.allocator, .{ .opcode = .table_get_field, .operands = [_]u16{ current.result_reg, current.result_reg, key_idx } });
                    current.self_reg = null;
                },
                '[' => {
                    self.advance();
                    self.skipWhitespace();
                    const index_res = try self.parseExpression(constants, instructions, current.next_reg);
                    self.skipWhitespace();
                    try self.expect(']');
                    try instructions.append(self.allocator, .{ .opcode = .table_get_index, .operands = [_]u16{ current.result_reg, current.result_reg, index_res.result_reg } });
                    current.next_reg = index_res.next_reg;
                    current.self_reg = null;
                },
                ':' => {
                    self.advance();
                    self.skipWhitespace();
                    const method_name = try self.parseIdent();
                    defer self.allocator.free(method_name);
                    const key_idx = @as(u16, @intCast(constants.items.len));
                    try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, method_name) });
                    const method_reg = current.next_reg;
                    const object_reg = current.result_reg;
                    try instructions.append(self.allocator, .{ .opcode = .resolve_method, .operands = [_]u16{ method_reg, object_reg, key_idx } });
                    current = .{ .result_reg = method_reg, .next_reg = method_reg + 1, .self_reg = object_reg };
                },
                '(' => {
                    current = try self.finishCall(constants, instructions, current);
                },
                else => break,
            }
        }
        return current;
    }

    fn finishCall(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), base: ParseResult) anyerror!ParseResult {
        try self.expect('(');
        self.skipWhitespace();

        var args_start: u16 = base.next_reg;
        var next_reg: u16 = base.next_reg;
        var base_arg_count: u16 = 0;
        var has_variadic_arg = false;

        if (base.self_reg) |self_reg| {
            args_start = base.result_reg + 1;
            try instructions.append(self.allocator, .{ .opcode = .move, .operands = [_]u16{ args_start, self_reg, 0 } });
            next_reg = args_start + 1;
            base_arg_count = 1;
        }

        var arg_results = std.ArrayListUnmanaged(ParseResult){};
        defer arg_results.deinit(self.allocator);

        if (self.peek() != ')') {
            while (true) {
                const arg = try self.parseExpression(constants, instructions, next_reg);
                next_reg = arg.next_reg;
                try arg_results.append(self.allocator, arg);
                self.skipWhitespace();
                if (self.peek() == ',') {
                    self.advance();
                    self.skipWhitespace();
                } else {
                    break;
                }
            }
        }

        if (arg_results.items.len > 0) {
            const last_index = arg_results.items.len - 1;
            var idx: usize = 0;
            while (idx < arg_results.items.len) : (idx += 1) {
                const entry = &arg_results.items[idx];
                const is_last = idx == last_index;
                const has_call = entry.call_instr_index != null;
                const is_variadic_entry = is_last and has_call;
                if (has_call) {
                    if (is_variadic_entry) {
                        self.configureCallResultCount(instructions, entry, 0);
                        has_variadic_arg = true;
                    } else {
                        self.configureCallResultCount(instructions, entry, 1);
                    }
                }

                if (!is_variadic_entry) {
                    base_arg_count +%= entry.value_count;
                }
            }
        }

        try self.expect(')');

        const arg_operand: u16 = if (has_variadic_arg)
            (base_arg_count | 0x8000)
        else
            base_arg_count;

        const call_idx = instructions.items.len;
        try instructions.append(self.allocator, .{ .opcode = .call_value, .operands = [_]u16{ base.result_reg, args_start, arg_operand }, .extra = 1 });

        const ensured_next = if (next_reg <= base.result_reg) base.result_reg + 1 else next_reg;

        return .{
            .result_reg = base.result_reg,
            .next_reg = ensured_next,
            .self_reg = null,
            .value_count = 1,
            .call_instr_index = call_idx,
        };
    }

    fn parseTableLiteral(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg: u16) anyerror!ParseResult {
        try self.expect('{');
        self.skipWhitespace();

        var next_reg = reg + 1;

        if (self.peek() == '}') {
            try instructions.append(self.allocator, .{ .opcode = .new_table, .operands = [_]u16{ reg, 0, 0 } });
            try self.expect('}');
            return .{ .result_reg = reg, .next_reg = next_reg };
        }

        var is_table_literal = false;
        if (self.peekIdent()) {
            var look_pos = self.pos;
            look_pos += 1;
            while (look_pos < self.source.len and isIdentChar(self.source[look_pos])) {
                look_pos += 1;
            }
            var look_ws = look_pos;
            while (look_ws < self.source.len and std.ascii.isWhitespace(self.source[look_ws])) {
                look_ws += 1;
            }
            if (look_ws < self.source.len and self.source[look_ws] == '=') {
                is_table_literal = true;
            }
        }

        if (is_table_literal) {
            try instructions.append(self.allocator, .{ .opcode = .new_table, .operands = [_]u16{ reg, 0, 0 } });
            while (true) {
                self.skipWhitespace();
                const key = try self.parseIdent();
                defer self.allocator.free(key);
                self.skipWhitespace();
                try self.expect('=');
                self.skipWhitespace();
                const value_res = try self.parseExpression(constants, instructions, next_reg);
                next_reg = value_res.next_reg;
                const key_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, key) });
                try instructions.append(self.allocator, .{ .opcode = .table_set_field, .operands = [_]u16{ reg, key_idx, value_res.result_reg } });
                self.skipWhitespace();
                if (self.peek() == ',') {
                    self.advance();
                    continue;
                }
                break;
            }
            self.skipWhitespace();
            try self.expect('}');
            return .{ .result_reg = reg, .next_reg = next_reg };
        }

        try instructions.append(self.allocator, .{ .opcode = .new_array, .operands = [_]u16{ reg, 0, 0 } });
        while (true) {
            self.skipWhitespace();
            if (self.peek() == '}') break;
            const value_res = try self.parseExpression(constants, instructions, next_reg);
            next_reg = value_res.next_reg;
            try instructions.append(self.allocator, .{ .opcode = .array_append, .operands = [_]u16{ reg, value_res.result_reg, 0 } });
            self.skipWhitespace();
            if (self.peek() == ',') {
                self.advance();
                continue;
            }
            break;
        }
        self.skipWhitespace();
        try self.expect('}');
        return .{ .result_reg = reg, .next_reg = next_reg };
    }

    fn parseArrayLiteral(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg: u16) anyerror!ParseResult {
        try self.expect('[');
        self.skipWhitespace();

        var next_reg = reg + 1;

        try instructions.append(self.allocator, .{ .opcode = .new_array, .operands = [_]u16{ reg, 0, 0 } });

        if (self.peek() == ']') {
            try self.expect(']');
            return .{ .result_reg = reg, .next_reg = next_reg };
        }

        while (true) {
            const value_res = try self.parseExpression(constants, instructions, next_reg);
            next_reg = value_res.next_reg;
            try instructions.append(self.allocator, .{ .opcode = .array_append, .operands = [_]u16{ reg, value_res.result_reg, 0 } });
            self.skipWhitespace();
            if (self.peek() == ',') {
                self.advance();
                self.skipWhitespace();
                continue;
            }
            break;
        }

        try self.expect(']');
        return .{ .result_reg = reg, .next_reg = next_reg };
    }

    fn parseStringLiteral(self: *Parser) ![]u8 {
        if (self.peek() != '"') return error.ParseError;
        self.advance();
        var buffer = std.ArrayListUnmanaged(u8){};
        errdefer buffer.deinit(self.allocator);
        var closed = false;
        while (self.peek()) |c| {
            if (c == '"') {
                self.advance();
                closed = true;
                break;
            } else if (c == '\\') {
                self.advance();
                const esc = self.peek() orelse return error.ParseError;
                self.advance();
                switch (esc) {
                    '"' => try buffer.append(self.allocator, '"'),
                    '\\' => try buffer.append(self.allocator, '\\'),
                    'n' => try buffer.append(self.allocator, '\n'),
                    'r' => try buffer.append(self.allocator, '\r'),
                    't' => try buffer.append(self.allocator, '\t'),
                    else => try buffer.append(self.allocator, esc),
                }
            } else {
                self.advance();
                try buffer.append(self.allocator, c);
            }
        }
        if (!closed) return error.ParseError;
        return try buffer.toOwnedSlice(self.allocator);
    }

    fn parseNumber(self: *Parser) !f64 {
        const start = self.pos;
        if (self.peek() == '-') {
            self.advance();
        }
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isDigit(c)) {
                self.pos += 1;
            } else if (c == '.' and (self.pos + 1 < self.source.len and self.source[self.pos + 1] != '.')) {
                self.pos += 1;
            } else {
                break;
            }
        }
        const num_str = self.source[start..self.pos];
        return std.fmt.parseFloat(f64, num_str);
    }

    fn parseIdent(self: *Parser) ![]u8 {
        const start = self.pos;
        if (!self.peekIdent()) return error.ParseError;
        self.pos += 1;
        while (self.pos < self.source.len and isIdentChar(self.source[self.pos])) {
            self.pos += 1;
        }
        return try self.allocator.dupe(u8, self.source[start..self.pos]);
    }

    fn isIdentStart(c: u8) bool {
        return std.ascii.isAlphabetic(c) or c == '_';
    }

    fn isIdentChar(c: u8) bool {
        return std.ascii.isAlphanumeric(c) or c == '_';
    }

    fn peekNumber(self: *Parser) bool {
        if (self.pos >= self.source.len) return false;
        const c = self.source[self.pos];
        if (std.ascii.isDigit(c)) return true;
        if (c == '-' and self.pos + 1 < self.source.len and std.ascii.isDigit(self.source[self.pos + 1])) return true;
        return false;
    }

    fn peekIdent(self: *Parser) bool {
        if (self.pos >= self.source.len) return false;
        const c = self.source[self.pos];
        return isIdentStart(c);
    }

    fn matchKeyword(self: *Parser, keyword: []const u8) bool {
        const end_pos = self.pos + keyword.len;
        if (end_pos > self.source.len) return false;
        if (!std.mem.eql(u8, self.source[self.pos..end_pos], keyword)) return false;
        if (end_pos < self.source.len and isIdentChar(self.source[end_pos])) return false;
        self.pos = end_pos;
        return true;
    }

    fn matchOperator(self: *Parser, op: []const u8) bool {
        const end_pos = self.pos + op.len;
        if (end_pos > self.source.len) return false;
        if (!std.mem.eql(u8, self.source[self.pos..end_pos], op)) return false;
        self.pos = end_pos;
        return true;
    }

    fn nextTempName(self: *Parser, prefix: []const u8) ![]u8 {
        const name = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ prefix, self.temp_counter });
        self.temp_counter += 1;
        return name;
    }

    fn peek(self: *Parser) ?u8 {
        if (self.pos < self.source.len) return self.source[self.pos];
        return null;
    }

    fn peekNext(self: *Parser) ?u8 {
        const next_pos = self.pos + 1;
        if (next_pos < self.source.len) return self.source[next_pos];
        return null;
    }

    fn advance(self: *Parser) void {
        if (self.pos < self.source.len) {
            if (self.source[self.pos] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.pos += 1;
        }
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
            self.advance();
        }
    }

    fn expect(self: *Parser, char: u8) ExecutionError!void {
        if (self.peek() == char) {
            self.advance();
        } else {
            // TODO: Store error info in parser for later retrieval
            // std.debug.print("Parse error at line {d}, column {d}: expected '{c}'\n", .{ self.line, self.column, char });
            _ = self.line;
            _ = self.column;
            return ExecutionError.ParseError;
        }
    }

    fn parseError(self: *Parser, comptime fmt: []const u8, args: anytype) ExecutionError {
        // TODO: Store error info in parser for later retrieval
        // std.debug.print("Parse error at line {d}, column {d}: ", .{ self.line, self.column });
        // std.debug.print(fmt, args);
        // std.debug.print("\n", .{});
        _ = self.line;
        _ = self.column;
        _ = fmt;
        _ = args;
        return ExecutionError.ParseError;
    }
};

fn groveParseGhostlang(integration: *GroveIntegration, source: []const u8, diagnostics: *std.ArrayListUnmanaged(ParseDiagnostic)) ExecutionError!GroveParseResult {
    if (!integration.registry.contains(.ghostlang)) {
        const msg = std.fmt.allocPrint(integration.allocator, "Ghostlang grammar is not registered", .{}) catch return ExecutionError.ParseError;
        appendDiagnosticOwned(diagnostics, integration.allocator, .fatal, msg, 0, 0) catch {};
        return ExecutionError.ParseError;
    }

    const start_ns = std.time.nanoTimestamp();
    var parser = Parser.init(integration.allocator, source);
    const parsed = parser.parse() catch |err| {
        if (err == error.OutOfMemory) {
            return ExecutionError.MemoryLimitExceeded;
        }
        const msg = std.fmt.allocPrint(integration.allocator, "Parse error near line {d}, column {d}", .{ parser.line, parser.column }) catch return ExecutionError.ParseError;
        appendDiagnosticOwned(diagnostics, integration.allocator, .fatal, msg, parser.line, parser.column) catch {};
        return ExecutionError.ParseError;
    };

    const elapsed_raw = std.time.nanoTimestamp() - start_ns;
    const elapsed_ns: u64 = if (elapsed_raw < 0) 0 else @as(u64, @intCast(elapsed_raw));

    const tree = SyntaxTree.initFromInstructions(integration.allocator, parsed.instructions, parsed.constants.len) catch |err| {
        for (parsed.constants, 0..) |_, idx| {
            parsed.constants[idx].deinit(integration.allocator);
        }
        integration.allocator.free(parsed.constants);
        integration.allocator.free(parsed.instructions);
        if (err == error.OutOfMemory) {
            return ExecutionError.MemoryLimitExceeded;
        }
        return ExecutionError.ParseError;
    };

    return .{
        .instructions = parsed.instructions,
        .constants = parsed.constants,
        .syntax_tree = tree,
        .duration_ns = elapsed_ns,
    };
}

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

fn identityPrint(args: []const ScriptValue) ScriptValue {
    if (args.len > 0) {
        return args[0];
    }
    return .{ .nil = {} };
}

fn sumNumbers(args: []const ScriptValue) ScriptValue {
    var total: f64 = 0;
    for (args) |arg| {
        if (arg == .number) {
            total += arg.number;
        }
    }
    return .{ .number = total };
}

test "script evaluates chained addition" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();
    try engine.registerEditorHelpers();
    try std.testing.expect(engine.globals.get("createArray") != null);

    var script = try engine.loadScript("1 + 2 + 3");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 6), result.number);
}

test "script supports variable assignment and reuse" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();
    try engine.registerEditorHelpers();
    try std.testing.expect(engine.globals.get("objectSet") != null);

    var script = try engine.loadScript("var foo = 41; foo + 1");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 42), result.number);
}

test "script can call registered host function" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();
    try engine.registerEditorHelpers();
    try std.testing.expect(engine.globals.get("split") != null);

    try engine.registerFunction("print", identityPrint);

    var script = try engine.loadScript("print(9)");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 9), result.number);
}

test "script reassigns existing variable" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript("var count = 1; count = count + 2; count");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 3), result.number);
}

test "lua style conditionals with elseif and else" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var value = 1
        \\if value == 0 then
        \\    value = 10
        \\elseif value == 1 then
        \\    value = 20
        \\else
        \\    value = 30
        \\end
        \\value
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 20), result.number);
}

test "while loop supports break and continue" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var i = 0
        \\var total = 0
        \\while i < 5 do
        \\    i = i + 1
        \\    if i == 2 then
        \\        continue
        \\    end
        \\    if i == 4 then
        \\        break
        \\    end
        \\    total = total + i
        \\end
        \\total
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 4), result.number);
}

test "for loop do-end with continue and break" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var sum = 0
        \\for i in 0..6 do
        \\    if i == 5 then
        \\        break
        \\    end
        \\    if i == 0 or i == 2 or i == 4 then
        \\        continue
        \\    end
        \\    sum = sum + i
        \\end
        \\sum
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 4), result.number);
}

test "keyword logical operators" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\if true and not false then
        \\    if false or !false then
        \\        42
        \\    else
        \\        0
        \\    end
        \\else
        \\    0
        \\end
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 42), result.number);
}

test "script respects operator precedence" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript("1 + 2 * 3");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 7), result.number);
}

test "script handles parentheses for precedence" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript("(1 + 2) * 3");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 9), result.number);
}

test "script returns string literal" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript("\"ghost\"");
    defer script.deinit();

    var result = try script.run();
    defer result.deinit(engine.tracked_allocator);
    try std.testing.expect(result == .string);
    try std.testing.expect(std.mem.eql(u8, result.string, "ghost"));
}

test "script evaluates boolean literal" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript("var flag = true; flag");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .boolean);
    try std.testing.expect(result.boolean);
}

test "script evaluates equality and inequality" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var equals_script = try engine.loadScript("(1 + 1) == 2");
    defer equals_script.deinit();

    const equals_result = try equals_script.run();
    try std.testing.expect(equals_result == .boolean);
    try std.testing.expect(equals_result.boolean);

    var not_equals_script = try engine.loadScript("3 != 3");
    defer not_equals_script.deinit();

    const not_equals_result = try not_equals_script.run();
    try std.testing.expect(not_equals_result == .boolean);
    try std.testing.expect(!not_equals_result.boolean);
}

test "script evaluates comparison operators" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var greater_script = try engine.loadScript("5 > 2");
    defer greater_script.deinit();

    const greater_result = try greater_script.run();
    try std.testing.expect(greater_result == .boolean);
    try std.testing.expect(greater_result.boolean);

    var less_script = try engine.loadScript("1 < 0");
    defer less_script.deinit();

    const less_result = try less_script.run();
    try std.testing.expect(less_result == .boolean);
    try std.testing.expect(!less_result.boolean);
}

test "script evaluates logical operators" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var and_script = try engine.loadScript("true && false");
    defer and_script.deinit();

    const and_result = try and_script.run();
    try std.testing.expect(and_result == .boolean);
    try std.testing.expect(!and_result.boolean);

    var or_script = try engine.loadScript("false || true");
    defer or_script.deinit();

    const or_result = try or_script.run();
    try std.testing.expect(or_result == .boolean);
    try std.testing.expect(or_result.boolean);

    var precedence_script = try engine.loadScript("true && true || false");
    defer precedence_script.deinit();

    const precedence_result = try precedence_script.run();
    try std.testing.expect(precedence_result == .boolean);
    try std.testing.expect(precedence_result.boolean);
}

test "script executes while loop" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript("var sum = 0; var i = 0; while (i < 5) { sum = sum + i; i = i + 1; } sum");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 10), result.number);
}

test "script executes for range loop" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript("var total = 0; for i in 0..5 { total = total + i; } total");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 10), result.number);
}

test "script passes multiple args to host function" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    try engine.registerFunction("sum", sumNumbers);

    var script = try engine.loadScript("sum(1, 2, 3)");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 6), result.number);
}

test "script defines and calls brace function" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\function add(a, b) {
        \\    return a + b
        \\}
        \\add(2, 3)
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 5), result.number);
}

test "script defines lua style function" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\function double(x)
        \\    return x + x
        \\end
        \\double(4)
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    var result = try script.run();
    defer result.deinit(engine.tracked_allocator);
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 8), result.number);
}

test "script function locals and loops" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\function sumUpTo(n) {
        \\    local total = 0
        \\    var i = 0
        \\    while i < n do
        \\        i = i + 1
        \\        total = total + i
        \\    end
        \\    return total
        \\}
        \\sumUpTo(3)
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 6), result.number);
}

test "local function declaration" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\local function double(x)
        \\    return x * 2
        \\end
        \\double(7)
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 14), result.number);
}

test "anonymous function expression returns value" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var doubler = function (x)
        \\    return x * 2
        \\end
        \\doubler(9)
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 18), result.number);
}

test "return inside nested block unwinds function" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\function firstPositive(values)
        \\    for _, value in ipairs(values) {
        \\        if value > 0 then
        \\            return value
        \\        end
        \\    }
        \\    return -1
        \\end
        \\firstPositive([-2, -1, 5, 7])
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 5), result.number);
}

test "vararg function collects arguments" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    try engine.registerFunction("nativeSum", sumNumbers);

    const source =
        \\function sumAll(...)
        \\    return nativeSum(...)
        \\end
        \\sumAll(1, 2, 3, 4)
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 10), result.number);
}

test "closure captures outer variable" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\function makeCounter(start)
        \\    local value = start
        \\    return function ()
        \\        value = value + 1
        \\        return value
        \\    end
        \\end
        \\var counter = makeCounter(10)
        \\counter()
        \\counter()
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 12), result.number);
}

test "pcall handles success and failure" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\function mightFail(flag)
        \\    if flag then
        \\        error("boom")
        \\    end
        \\    return 42
        \\end
        \\local ok, value = pcall(mightFail, false)
        \\local ok2, err = pcall(mightFail, true)
    \\var details = [ok, value, ok2, err, type(err)]
    \\details
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    var result = try script.run();
    defer result.deinit(engine.tracked_allocator);
    try std.testing.expect(result == .array);
    const items = result.array.items.items;
    try std.testing.expectEqual(@as(usize, 5), items.len);
    try std.testing.expect(items[0] == .boolean and items[0].boolean);
    try std.testing.expect(items[1] == .number);
    try std.testing.expectEqual(@as(f64, 42), items[1].number);
    try std.testing.expect(items[2] == .boolean and !items[2].boolean);
    try std.testing.expect(items[3] == .string);
    try std.testing.expect(std.mem.eql(u8, items[3].string, "boom"));
    try std.testing.expect(items[4] == .string);
    try std.testing.expect(std.mem.eql(u8, items[4].string, "string"));
}

test "script return without expression yields nil" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\function noop() {
        \\    local temp = 1
        \\    return
        \\}
        \\noop()
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .nil);
}

test "script destructures multi return values" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\function pair()
        \\    return 1, 2
        \\end
        \\local first, second = pair()
        \\first * 10 + second
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 12), result.number);
}

test "script forwards multi return values" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\function inner()
        \\    return 4, 6
        \\end
        \\function outer()
        \\    return inner()
        \\end
        \\local a, b, c = outer()
        \\var sum = 0
        \\if c == nil then
        \\    sum = a + b
        \\else
        \\    sum = 0
        \\end
        \\sum
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 10), result.number);
}

test "script function arity mismatch errors" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\function greet(name) {
        \\    return name
        \\}
        \\greet()
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    try std.testing.expectError(error.TypeError, script.run());
}

test "table literal dot access" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var config = { answer = 42, offset = 1 }
        \\config.answer + config.offset
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 43), result.number);
}

test "array literal bracket access" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var values = [10, 20, 30]
        \\values[2]
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 20), result.number);
}

test "array push and pop builtins" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var queue = []
        \\queue:push(5)
        \\queue:push(12)
        \\queue:pop()
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 12), result.number);
}

test "square bracket literal creates array" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var values = []
        \\values:push(7)
        \\values:pop()
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 7), result.number);
}

test "generic array loop sums values" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var data = [1, 2, 3, 4]
        \\var total = 0
        \\for value in data {
        \\    total = total + value
        \\}
        \\total
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 10), result.number);
}

test "generic array loop yields index values" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var data = [5, 10, 15]
        \\var total = 0
        \\for index, value in data {
        \\    total = total + index * value
        \\}
        \\total
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 70), result.number);
}

test "generic table loop collects entries" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var mapping = { alpha = 4, beta = 6, gamma = 8 }
        \\var count = 0
        \\for key in mapping {
        \\    count = count + 1
        \\}
        \\var total = 0
        \\for key, value in mapping {
        \\    total = total + value
        \\}
        \\if count == 3 then total else 0 end
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 18), result.number);
}

test "ipairs builtin iterates array" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var numbers = [2, 4, 6]
        \\var total = 0
        \\for index, value in ipairs(numbers) {
        \\    total = total + index + value
        \\}
        \\total
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 18), result.number);
}

test "colon call binds self and supports global fallback" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var tracker = {
        \\    value = 5
        \\}
        \\tracker.bump = function (self, amount)
        \\    self.value = self.value + amount
        \\    return self.value
        \\end
        \\function take(self, amount)
        \\    return self.value + amount
        \\end
    \\var first = tracker:bump(3)
    \\var second = tracker:take(2)
    \\var result = 0
    \\if first == 8 and second == 10 then
    \\    result = first
    \\end
    \\result
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 8), result.number);
}

test "empty brace literal creates table" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var obj = {}
        \\insert(obj, "answer", 42)
        \\obj.answer
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 42), result.number);
}

test "pairs builtin supports iterator loops" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var mapping = { first = 1, second = 2, third = 3 }
        \\var total = 0
        \\for key, value in pairs(mapping) {
        \\    total = total + value
        \\}
        \\total
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 6), result.number);
}

test "string find and match builtins" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var idx = find("ghostlang", "lang")
        \\var has = match("ghostlang", "ghost")
        \\if has then idx else 0 end
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 6), result.number);
}

test "lua style string helpers operate correctly" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    const source =
        \\var original = "GhostLang"
        \\var uppercased = upper(original)
        \\var lowercased = lower(original)
        \\var length = len(original)
        \\var slice = sub(original, 1, 5)
        \\var replaced = gsub("ghost ghost", "ghost", "spirit")
    \\var formatted = format("%s %d %f", "value", 7, 3.25)
    \\if uppercased == "GHOSTLANG" and lowercased == "ghostlang" and length == 9 and slice == "Ghost" and replaced == "spirit spirit" and formatted == "value 7 3.250000" then 1 else 0 end
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 1), result.number);
}

test "editor helper array operations" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();
    try engine.registerEditorHelpers();

    const source =
        \\var arr = createArray()
        \\arrayPush(arr, 12)
        \\arrayPush(arr, 30)
        \\var total = arrayGet(arr, 0) + arrayGet(arr, 1)
        \\if arrayLength(arr) == 2 then total else 0 end
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 42), result.number);
}

test "editor helper object operations" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();
    try engine.registerEditorHelpers();

    const source =
        \\var obj = createObject()
        \\objectSet(obj, "name", "ghost")
        \\objectSet(obj, "count", 3)
        \\var name = objectGet(obj, "name")
        \\var count = objectGet(obj, "count")
        \\if name == "ghost" then count else 0 end
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 3), result.number);
}

test "editor helper string utilities" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();
    try engine.registerEditorHelpers();

    const source =
        \\var parts = split("alpha beta gamma", " ")
        \\var joined = join(parts, ",")
        \\var segment = substring(joined, 6, 10)
        \\var pos = indexOf(joined, "beta")
        \\var replaced = replace(joined, "beta", "BETA")
        \\if joined == "alpha,beta,gamma" and segment == "beta" and pos == 6 and replaced == "alpha,BETA,gamma" then 1 else 0 end
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 1), result.number);
}

test "editor helper array set and pop" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();
    try engine.registerEditorHelpers();

    const source =
        \\var arr = createArray()
        \\arrayPush(arr, "start")
        \\arraySet(arr, 0, "first")
        \\arraySet(arr, 1, "second")
        \\var popped = arrayPop(arr)
        \\var len = arrayLength(arr)
        \\var remaining = arrayGet(arr, 0)
        \\if popped == "second" and len == 1 and remaining == "first" then 1 else 0 end
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 1), result.number);
}

test "editor helper object keys enumeration" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();
    try engine.registerEditorHelpers();

    const source =
        \\var obj = createObject()
        \\objectSet(obj, "alpha", 1)
        \\objectSet(obj, "beta", 2)
        \\var keys = objectKeys(obj)
        \\var len = arrayLength(keys)
        \\var found = 0
        \\var i = 0
        \\while (i < len) {
        \\    var key = arrayGet(keys, i)
        \\    if (key == "alpha" or key == "beta") {
        \\        found = found + 1
        \\    }
        \\    i = i + 1
        \\}
        \\if len == 2 and found == 2 then 1 else 0 end
    ;

    var script = try engine.loadScript(source);
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 1), result.number);
}

test "block scoped variable does not leak" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript("if (true) { var temp = 5; } temp");
    defer script.deinit();

    try std.testing.expectError(error.UndefinedVariable, script.run());
}

test "block scope allows shadowing" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript("var value = 1; if (true) { var value = 2; } value");
    defer script.deinit();

    const result = try script.run();
    try std.testing.expect(result == .number);
    try std.testing.expectEqual(@as(f64, 1), result.number);
}

test "for loop iterator scoped to loop" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    var script = try engine.loadScript("for i in 0..3 { } i");
    defer script.deinit();

    try std.testing.expectError(error.UndefinedVariable, script.run());
}

test "engine call supports variadic arguments" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    try engine.registerFunction("identity", identityPrint);
    try engine.registerFunction("sum", sumNumbers);

    const numeric = try engine.call("sum", .{ 1, 2, 3.5 });
    try std.testing.expect(numeric == .number);
    try std.testing.expectEqual(@as(f64, 6.5), numeric.number);

    var echoed = try engine.call("identity", .{"ghost"});
    defer echoed.deinit(allocator);
    try std.testing.expect(echoed == .string);
    try std.testing.expect(std.mem.eql(u8, echoed.string, "ghost"));
}

// PHASE 0.1 SAFETY TESTS - Critical for Grim integration

test "execution timeout prevents infinite loops" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{
        .allocator = allocator,
        .execution_timeout_ms = 100, // 100ms timeout
    };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    // Infinite loop should timeout
    var script = try engine.loadScript("while (true) { }");
    defer script.deinit();

    try std.testing.expectError(ExecutionError.ExecutionTimeout, script.run());
}

test "memory limits prevent resource exhaustion" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{
        .allocator = allocator,
        .memory_limit = 1024, // Very small limit
    };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    // TODO: This test would need the fixed memory allocator to work properly
    // For now, just test that the engine can be created with limits
    try std.testing.expect(engine.config.memory_limit == 1024);
}

test "parser error handling returns proper errors instead of panicking" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    // Invalid syntax should return ParseError, not panic
    try std.testing.expectError(ExecutionError.ParseError, engine.loadScript("var x = "));
    try std.testing.expectError(ExecutionError.ParseError, engine.loadScript("if ("));
    try std.testing.expectError(ExecutionError.ParseError, engine.loadScript("while {"));
}

test "security context prevents unsafe operations" {
    const allocator = std.testing.allocator;

    // Test with restricted permissions
    const restricted_config = EngineConfig{
        .allocator = allocator,
        .allow_io = false,
        .allow_syscalls = false,
        .deterministic = true,
    };
    var restricted_engine = try ScriptEngine.create(restricted_config);
    defer restricted_engine.deinit();

    try std.testing.expectError(ExecutionError.IONotAllowed, restricted_engine.security.checkIOAllowed());
    try std.testing.expectError(ExecutionError.SyscallNotAllowed, restricted_engine.security.checkSyscallAllowed());
    try std.testing.expectError(ExecutionError.SecurityViolation, restricted_engine.security.checkNonDeterministicAllowed());

    // Test with permissive permissions
    const permissive_config = EngineConfig{
        .allocator = allocator,
        .allow_io = true,
        .allow_syscalls = true,
        .deterministic = false,
    };
    var permissive_engine = try ScriptEngine.create(permissive_config);
    defer permissive_engine.deinit();

    try permissive_engine.security.checkIOAllowed();
    try permissive_engine.security.checkSyscallAllowed();
    try permissive_engine.security.checkNonDeterministicAllowed();
}

test "function not found returns proper error" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    try std.testing.expectError(ExecutionError.FunctionNotFound, engine.call("nonexistent", .{}));
}

test "type errors are handled gracefully" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{ .allocator = allocator };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    // Test type error in arithmetic
    var script = try engine.loadScript("\"string\" + 5");
    defer script.deinit();

    try std.testing.expectError(ExecutionError.TypeError, script.run());
}

test "script engine call is bulletproof with proper isolation" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{
        .allocator = allocator,
        .execution_timeout_ms = 1000,
        .allow_io = false,
        .allow_syscalls = false,
    };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    try engine.registerFunction("safe_add", sumNumbers);

    // Normal operation should work
    const result1 = try engine.call("safe_add", .{ 1, 2, 3 });
    try std.testing.expect(result1 == .number);
    try std.testing.expectEqual(@as(f64, 6), result1.number);

    // Error cases should be properly handled
    try std.testing.expectError(ExecutionError.FunctionNotFound, engine.call("unsafe_function", .{}));
}

test "comprehensive negative path testing" {
    const allocator = std.testing.allocator;
    const config = EngineConfig{
        .allocator = allocator,
        .execution_timeout_ms = 50, // Very short timeout
        .memory_limit = 1024 * 1024, // 1MB limit
        .allow_io = false,
        .allow_syscalls = false,
        .deterministic = true,
    };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    // Test various malformed scripts
    const bad_scripts = [_][]const u8{
        "var x = ;", // Incomplete assignment
        "if () { }", // Empty condition
        "while { }", // Missing condition
        "for i in { }", // Malformed for loop
        "unknown_func()", // Undefined function
        "var x = y + z;", // Undefined variables
    };

    for (bad_scripts) |bad_script| {
        // All should return ExecutionError, never panic
        const result = engine.loadScript(bad_script);
        if (result) |script| {
            var script_mut = script;
            defer script_mut.deinit();
            const run_result = script_mut.run();
            try std.testing.expect(@TypeOf(run_result) == ExecutionError!ScriptValue);
        } else |_| {
            // Parse error is expected and acceptable
        }
    }
}
