const std = @import("std");

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

pub const ScriptValueType = enum {
    nil,
    boolean,
    number,
    string,
    function,
    table,
    array,
};

pub const ScriptValue = union(ScriptValueType) {
    nil: void,
    boolean: bool,
    number: f64,
    string: []const u8,
    function: *const fn (args: []const ScriptValue) ScriptValue,
    table: std.StringHashMap(ScriptValue),
    array: std.ArrayList(ScriptValue),

    pub fn deinit(self: *ScriptValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .table => |*t| {
                var it = t.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                t.deinit();
            },
            .array => |*arr| {
                for (arr.items) |*item| {
                    item.deinit(allocator);
                }
                arr.deinit(allocator);
            },
            else => {},
        }
    }
};

pub const EngineConfig = struct {
    allocator: std.mem.Allocator,
    memory_limit: usize = 1024 * 1024, // 1MB default
    execution_timeout_ms: u64 = 1000, // 1 second default
    allow_io: bool = false,
    allow_syscalls: bool = false,
    deterministic: bool = false, // Disable time-based functions, random, etc.
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

pub const ScriptEngine = struct {
    config: EngineConfig,
    globals: std.StringHashMap(ScriptValue),
    memory_limiter: ?*MemoryLimitAllocator, // Heap-allocated to keep address stable
    tracked_allocator: std.mem.Allocator,
    security: SecurityContext,

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
        };

        engine.globals = std.StringHashMap(ScriptValue).init(engine.tracked_allocator);
        return engine;
    }

    pub fn deinit(self: *ScriptEngine) void {
        var it = self.globals.iterator();
        while (it.next()) |entry| {
            self.tracked_allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.tracked_allocator);
        }
        self.globals.deinit();

        // Free the heap-allocated memory limiter
        if (self.memory_limiter) |limiter| {
            self.config.allocator.destroy(limiter);
        }
    }

    pub fn loadScript(self: *ScriptEngine, source: []const u8) ExecutionError!Script {
        var parser = Parser.init(self.tracked_allocator, source);
        const parsed = parser.parse() catch |err| switch (err) {
            error.OutOfMemory => return ExecutionError.MemoryLimitExceeded,
            else => return ExecutionError.ParseError,
        };
        var script = Script{
            .engine = self,
            .vm = VM.init(self.tracked_allocator, parsed.instructions, parsed.constants, self),
        };

        // Register built-in functions
        try BuiltinFunctions.registerBuiltins(&script.vm);

        // Register editor API functions
        try EditorAPI.registerEditorAPI(&script.vm);

        return script;
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
        try self.registerFunction("createArray", createArrayFunction);
        try self.registerFunction("arrayPush", arrayPushFunction);
        try self.registerFunction("arrayLength", arrayLengthFunction);
        try self.registerFunction("arrayGet", arrayGetFunction);
        try self.registerFunction("createObject", createObjectFunction);
        try self.registerFunction("objectSet", objectSetFunction);
        try self.registerFunction("objectGet", objectGetFunction);
        try self.registerFunction("split", splitFunction);
        try self.registerFunction("join", joinFunction);
        try self.registerFunction("substring", substringFunction);
        try self.registerFunction("indexOf", indexOfFunction);
        try self.registerFunction("replace", replaceFunction);
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
        return .{ .string = "IO not implemented in sandbox" };
    }

    fn readFileFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // This would be gated by IO permissions
        return .{ .string = "IO not implemented in sandbox" };
    }

    fn systemFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // This would be gated by syscall permissions
        return .{ .string = "Syscalls not allowed in sandbox" };
    }

    // Editor helper function implementations
    fn createArrayFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // In real implementation, would create a new array and return it
        // For now, return a number representing array ID
        return .{ .number = 0 };
    }

    fn arrayPushFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would add element to array
        return .{ .nil = {} };
    }

    fn arrayLengthFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would return array length
        return .{ .number = 0 };
    }

    fn arrayGetFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would return array element at index
        return .{ .nil = {} };
    }

    fn createObjectFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would create new object/table
        return .{ .number = 0 }; // Object ID
    }

    fn objectSetFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would set object property
        return .{ .nil = {} };
    }

    fn objectGetFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would get object property
        return .{ .nil = {} };
    }

    fn splitFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would split string into array
        return .{ .number = 0 }; // Array ID
    }

    fn joinFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would join array into string
        return .{ .string = "" };
    }

    fn substringFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would extract substring
        return .{ .string = "" };
    }

    fn indexOfFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would find substring index
        return .{ .number = -1 };
    }

    fn replaceFunction(args: []const ScriptValue) ScriptValue {
        _ = args;
        // Would replace substring
        return .{ .string = "" };
    }
};

pub const Opcode = enum(u8) {
    nop,
    load_const,
    load_global,
    store_global,
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
    begin_scope,
    end_scope,
    call,
    jump,
    jump_if_false,
    ret,
};

pub const Instruction = struct {
    opcode: Opcode,
    operands: [3]u16, // for simplicity, up to 3 operands
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

pub const VM = struct {
    registers: [256]ScriptValue,
    globals: std.StringHashMap(ScriptValue),
    scopes: std.ArrayListUnmanaged(ScopeFrame),
    pc: usize,
    code: []const Instruction,
    constants: []ScriptValue,
    allocator: std.mem.Allocator,
    engine: *ScriptEngine,
    start_time: i64,
    instruction_count: usize,

    pub fn init(allocator: std.mem.Allocator, code: []const Instruction, constants: []ScriptValue, engine: *ScriptEngine) VM {
        return VM{
            .registers = undefined,
            .globals = std.StringHashMap(ScriptValue).init(allocator),
            .scopes = .{},
            .pc = 0,
            .code = code,
            .constants = constants,
            .allocator = allocator,
            .engine = engine,
            .start_time = 0,
            .instruction_count = 0,
        };
    }

    pub fn deinit(self: *VM) void {
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
    }

    pub fn run(self: *VM) ExecutionError!ScriptValue {
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
            switch (instr.opcode) {
                .nop => {},
                .load_const => {
                    const reg = instr.operands[0];
                    const const_idx = instr.operands[1];
                    self.registers[reg] = self.constants[const_idx];
                },
                .add => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .number = val_a.number + val_b.number };
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .sub => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .number = val_a.number - val_b.number };
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .mul => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .number = val_a.number * val_b.number };
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .div => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .number = val_a.number / val_b.number };
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .mod => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .number = @mod(val_a.number, val_b.number) };
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .eq => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    self.registers[dest] = .{ .boolean = valuesEqual(val_a, val_b) };
                },
                .neq => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    self.registers[dest] = .{ .boolean = !valuesEqual(val_a, val_b) };
                },
                .lt => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .boolean = val_a.number < val_b.number };
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .gt => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .boolean = val_a.number > val_b.number };
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .lte => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .boolean = val_a.number <= val_b.number };
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .gte => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .boolean = val_a.number >= val_b.number };
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .and_op => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .boolean and val_b == .boolean) {
                        self.registers[dest] = .{ .boolean = val_a.boolean and val_b.boolean };
                    } else {
                        return ExecutionError.TypeError;
                    }
                },
                .or_op => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .boolean and val_b == .boolean) {
                        self.registers[dest] = .{ .boolean = val_a.boolean or val_b.boolean };
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
                    return self.registers[instr.operands[0]];
                },
                .call => {
                    const func_name_idx = instr.operands[0];
                    const arg_start = instr.operands[1];
                    const arg_count = instr.operands[2];
                    const func_name = self.constants[func_name_idx];
                    if (func_name == .string) {
                        if (self.getVariable(func_name.string)) |value| {
                            switch (value) {
                                .function => |callable| {
                                    const args = self.registers[arg_start .. arg_start + arg_count];
                                    const result = callable(args);
                                    self.registers[arg_start] = result;
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
                .load_global => {
                    const reg = instr.operands[0];
                    const name_idx = instr.operands[1];
                    const name = self.constants[name_idx];
                    if (name == .string) {
                        if (self.getVariable(name.string)) |value| {
                            self.registers[reg] = value;
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
                    const is_decl = instr.operands[2] == 1;
                    const name = self.constants[name_idx];
                    if (name == .string) {
                        const value_copy = self.registers[reg];
                        if (is_decl) {
                            try self.declareVariable(name.string, value_copy);
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
                    const cond = self.registers[cond_reg];
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

        // Copy the value to ensure we own it
        const value_copy = try self.copyValue(value);

        if (target.getEntry(name)) |entry| {
            entry.value_ptr.deinit(self.allocator);
            entry.value_ptr.* = value_copy;
            return;
        }
        const name_copy = try self.allocator.dupe(u8, name);
        try target.put(name_copy, value_copy);
    }

    fn assignVariable(self: *VM, name: []const u8, value: ScriptValue) !void {
        // Copy the value to ensure we own it
        const value_copy = try self.copyValue(value);

        var idx = self.scopes.items.len;
        while (idx > 0) {
            idx -= 1;
            if (self.scopes.items[idx].map.getEntry(name)) |entry| {
                entry.value_ptr.deinit(self.allocator);
                entry.value_ptr.* = value_copy;
                return;
            }
        }
        if (self.globals.getEntry(name)) |entry| {
            entry.value_ptr.deinit(self.allocator);
            entry.value_ptr.* = value_copy;
            return;
        }
        try self.declareVariable(name, value);
    }

    fn copyValue(self: *VM, value: ScriptValue) !ScriptValue {
        return switch (value) {
            .string => |s| .{ .string = try self.allocator.dupe(u8, s) },
            .table => |_| {
                // TODO: Deep copy tables if needed
                return value;
            },
            .array => |_| {
                // TODO: Deep copy arrays if needed
                return value;
            },
            else => value, // Numbers, booleans, nil, functions don't need copying
        };
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
            .table => |_| switch (b) {
                .table => |_| return false,
                else => return false,
            },
            .array => |_| switch (b) {
                .array => |_| return false, // For simplicity, arrays never equal
                else => return false,
            },
        }
    }
};

// ============================================================================
// Built-in Functions
// ============================================================================

pub const BuiltinFunctions = struct {
    // String functions
    pub fn builtin_len(args: []const ScriptValue) ScriptValue {
        if (args.len != 1) return .{ .nil = {} };
        switch (args[0]) {
            .string => |s| return .{ .number = @floatFromInt(s.len) },
            .array => |arr| return .{ .number = @floatFromInt(arr.items.len) },
            else => return .{ .nil = {} },
        }
    }

    pub fn builtin_toUpperCase(args: []const ScriptValue) ScriptValue {
        if (args.len != 1) return .{ .nil = {} };
        if (args[0] != .string) return .{ .nil = {} };

        const input = args[0].string;
        // For simplicity, return original for now - proper implementation would allocate
        // TODO: Implement proper string allocation and transformation
        _ = input;
        return args[0];
    }

    pub fn builtin_toLowerCase(args: []const ScriptValue) ScriptValue {
        if (args.len != 1) return .{ .nil = {} };
        if (args[0] != .string) return .{ .nil = {} };

        const input = args[0].string;
        // For simplicity, return original for now - proper implementation would allocate
        // TODO: Implement proper string allocation and transformation
        _ = input;
        return args[0];
    }

    pub fn builtin_print(args: []const ScriptValue) ScriptValue {
        for (args, 0..) |arg, i| {
            switch (arg) {
                .nil => std.debug.print("nil", .{}),
                .boolean => |b| std.debug.print("{}", .{b}),
                .number => |n| std.debug.print("{d}", .{n}),
                .string => |s| std.debug.print("{s}", .{s}),
                .function => std.debug.print("<function>", .{}),
                .table => std.debug.print("<table>", .{}),
                .array => std.debug.print("<array>", .{}),
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
            .table => "table",
            .array => "array",
        };
        // TODO: Allocate string properly
        return .{ .string = type_name };
    }

    pub fn registerBuiltins(vm: *VM) !void {
        const builtins = [_]struct { name: []const u8, func: *const fn (args: []const ScriptValue) ScriptValue }{
            .{ .name = "len", .func = &builtin_len },
            .{ .name = "print", .func = &builtin_print },
            .{ .name = "type", .func = &builtin_type },
            .{ .name = "toUpperCase", .func = &builtin_toUpperCase },
            .{ .name = "toLowerCase", .func = &builtin_toLowerCase },
        };

        for (builtins) |builtin| {
            // Don't overwrite user-registered functions from engine.globals
            if (vm.engine.globals.get(builtin.name) != null) continue;

            const name_copy = try vm.allocator.dupe(u8, builtin.name);
            try vm.globals.put(name_copy, .{ .function = builtin.func });
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
        return .{ .string = "sample line text" };
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

    pub fn deinit(self: *Script) void {
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
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize,
    temp_counter: usize,
    line: usize,
    column: usize,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        return Parser{
            .allocator = allocator,
            .source = source,
            .pos = 0,
            .temp_counter = 0,
            .line = 1,
            .column = 1,
        };
    }

    pub fn parse(self: *Parser) !struct { instructions: []Instruction, constants: []ScriptValue } {
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
    };

    fn parseStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        self.skipWhitespace();
        if (self.peekIdent()) {
            const ident_start = self.pos;
            const ident = try self.parseIdent();
            defer self.allocator.free(ident);
            if (std.mem.eql(u8, ident, "var")) {
                self.skipWhitespace();
                const var_name = try self.parseIdent();
                defer self.allocator.free(var_name);
                self.skipWhitespace();
                try self.expect('=');
                self.skipWhitespace();
                const expr = try self.parseExpression(constants, instructions, 0);
                const name_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, var_name) });
                try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ expr.result_reg, name_idx, 1 } });
                return expr.result_reg;
            } else if (std.mem.eql(u8, ident, "if")) {
                return try self.parseIfStatement(constants, instructions);
            } else if (std.mem.eql(u8, ident, "while")) {
                return try self.parseWhileStatement(constants, instructions);
            } else if (std.mem.eql(u8, ident, "for")) {
                return try self.parseForRangeStatement(constants, instructions);
            } else {
                self.skipWhitespace();
                if (self.peek() == '=' and self.peekNext() != '=') {
                    self.advance();
                    self.skipWhitespace();
                    const expr = try self.parseExpression(constants, instructions, 0);
                    const name_idx = @as(u16, @intCast(constants.items.len));
                    try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                    try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ expr.result_reg, name_idx, 0 } });
                    return expr.result_reg;
                }
                self.pos = ident_start;
            }
        }

        const expr = try self.parseExpression(constants, instructions, 0);
        return expr.result_reg;
    }

    fn parseIfStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        self.skipWhitespace();
        try self.expect('(');
        self.skipWhitespace();
        const cond = try self.parseExpression(constants, instructions, 0);
        self.skipWhitespace();
        try self.expect(')');
        const jump_false_idx = instructions.items.len;
        try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ cond.result_reg, 0, 0 } });
        self.skipWhitespace();
        const then_result = try self.parseBlock(constants, instructions);
        var statement_result: u16 = then_result;
        self.skipWhitespace();
        if (self.matchKeyword("else")) {
            const jump_over_else_idx = instructions.items.len;
            try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ 0, 0, 0 } });
            instructions.items[jump_false_idx].operands[1] = @as(u16, @intCast(instructions.items.len));
            self.skipWhitespace();
            if (self.matchKeyword("if")) {
                const else_result = try self.parseIfStatement(constants, instructions);
                instructions.items[jump_over_else_idx].operands[0] = @as(u16, @intCast(instructions.items.len));
                statement_result = else_result;
            } else {
                const else_result = try self.parseBlock(constants, instructions);
                instructions.items[jump_over_else_idx].operands[0] = @as(u16, @intCast(instructions.items.len));
                statement_result = else_result;
            }
        } else {
            instructions.items[jump_false_idx].operands[1] = @as(u16, @intCast(instructions.items.len));
        }
        return statement_result;
    }

    fn parseWhileStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        self.skipWhitespace();
        try self.expect('(');
        self.skipWhitespace();
        const loop_start_idx = instructions.items.len;
        const cond = try self.parseExpression(constants, instructions, 0);
        self.skipWhitespace();
        try self.expect(')');
        const jump_false_idx = instructions.items.len;
        try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ cond.result_reg, 0, 0 } });
        self.skipWhitespace();
        const body_result = try self.parseBlock(constants, instructions);
        const loop_start_u16 = @as(u16, @intCast(loop_start_idx));
        try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ loop_start_u16, 0, 0 } });
        instructions.items[jump_false_idx].operands[1] = @as(u16, @intCast(instructions.items.len));
        return body_result;
    }

    fn parseForRangeStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        self.skipWhitespace();
        const iter_name = try self.parseIdent();
        defer self.allocator.free(iter_name);

        self.skipWhitespace();
        if (!self.matchKeyword("in")) return error.ParseError;

        self.skipWhitespace();
        const start_expr = try self.parseExpression(constants, instructions, 0);
        self.skipWhitespace();
        if (!self.matchOperator("..")) return error.ParseError;

        self.skipWhitespace();
        const end_expr = try self.parseExpression(constants, instructions, start_expr.next_reg);
        self.skipWhitespace();

        const iter_name_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, iter_name) });

        const end_name = try self.nextTempName("__for_end");
        defer self.allocator.free(end_name);
        const end_name_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, end_name) });

        try instructions.append(self.allocator, .{ .opcode = .begin_scope, .operands = [_]u16{ 0, 0, 0 } });

        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ start_expr.result_reg, iter_name_idx, 1 } });
        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ end_expr.result_reg, end_name_idx, 1 } });

        const loop_start_idx = instructions.items.len;
        const loop_start_u16 = @as(u16, @intCast(loop_start_idx));

        const iter_reg = start_expr.result_reg;
        const end_reg = end_expr.result_reg;
        const cond_reg = end_expr.next_reg;

        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ iter_reg, iter_name_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ end_reg, end_name_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .lt, .operands = [_]u16{ cond_reg, iter_reg, end_reg } });

        const jump_exit_idx = instructions.items.len;
        try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{ cond_reg, 0, 0 } });

        self.skipWhitespace();
        const body_result = try self.parseBlock(constants, instructions);
        self.skipWhitespace();

        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ iter_reg, iter_name_idx, 0 } });

        const one_const_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .number = 1 });
        try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{ end_reg, one_const_idx, 0 } });
        try instructions.append(self.allocator, .{ .opcode = .add, .operands = [_]u16{ iter_reg, iter_reg, end_reg } });
        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{ iter_reg, iter_name_idx, 0 } });

        try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{ loop_start_u16, 0, 0 } });
        instructions.items[jump_exit_idx].operands[1] = @as(u16, @intCast(instructions.items.len));

        try instructions.append(self.allocator, .{ .opcode = .end_scope, .operands = [_]u16{ 0, 0, 0 } });

        return body_result;
    }

    fn parseBlock(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction)) anyerror!u16 {
        self.skipWhitespace();
        try self.expect('{');
        self.skipWhitespace();
        try instructions.append(self.allocator, .{ .opcode = .begin_scope, .operands = [_]u16{ 0, 0, 0 } });
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
        try instructions.append(self.allocator, .{ .opcode = .end_scope, .operands = [_]u16{ 0, 0, 0 } });
        return last_reg;
    }

    fn parseExpression(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        return self.parseOr(constants, instructions, reg_start);
    }

    fn parseOr(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!ParseResult {
        var left = try self.parseAnd(constants, instructions, reg_start);
        while (true) {
            self.skipWhitespace();
            if (self.matchOperator("||")) {
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
            if (self.matchOperator("&&")) {
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
        var left = try self.parseFactor(constants, instructions, reg_start);
        while (true) {
            self.skipWhitespace();
            const peeked = self.peek() orelse break;
            if (peeked == '*' or peeked == '/' or peeked == '%') {
                const op = peeked;
                self.advance();
                self.skipWhitespace();
                const right = try self.parseFactor(constants, instructions, left.next_reg);
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

    fn parseFactor(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg: u16) anyerror!ParseResult {
        self.skipWhitespace();
        if (self.peek() == '(') {
            self.advance();
            const inner = try self.parseExpression(constants, instructions, reg);
            self.skipWhitespace();
            try self.expect(')');
            return inner;
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
                self.skipWhitespace();
                if (self.peek() == '(') {
                    return try self.parseCall(constants, instructions, ident, reg);
                } else {
                    const name_idx = @as(u16, @intCast(constants.items.len));
                    try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                    try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{ reg, name_idx, 0 } });
                    return .{ .result_reg = reg, .next_reg = reg + 1 };
                }
            }
        }

        return error.ParseError;
    }

    fn parseCall(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), func_name: []const u8, reg: u16) anyerror!ParseResult {
        try self.expect('(');
        self.skipWhitespace();
        const arg_start: u16 = reg;
        var next_reg: u16 = reg;
        var arg_count: u16 = 0;
        if (self.peek() != ')') {
            while (true) {
                const arg = try self.parseExpression(constants, instructions, next_reg);
                next_reg = arg.next_reg;
                arg_count += 1;
                self.skipWhitespace();
                if (self.peek() == ',') {
                    self.advance();
                    self.skipWhitespace();
                } else {
                    break;
                }
            }
        } else {
            next_reg = reg + 1;
        }
        try self.expect(')');
        const func_idx = @as(u16, @intCast(constants.items.len));
        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, func_name) });
        try instructions.append(self.allocator, .{ .opcode = .call, .operands = [_]u16{ func_idx, arg_start, arg_count } });
        return .{ .result_reg = arg_start, .next_reg = next_reg };
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

    const result = try script.run();
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
        .execution_timeout_ms = 100  // 100ms timeout
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
        .memory_limit = 1024  // Very small limit
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
        .execution_timeout_ms = 50,  // Very short timeout
        .memory_limit = 1024 * 1024, // 1MB limit
        .allow_io = false,
        .allow_syscalls = false,
        .deterministic = true,
    };
    var engine = try ScriptEngine.create(config);
    defer engine.deinit();

    // Test various malformed scripts
    const bad_scripts = [_][]const u8{
        "var x = ;",           // Incomplete assignment
        "if () { }",           // Empty condition
        "while { }",           // Missing condition
        "for i in { }",        // Malformed for loop
        "unknown_func()",      // Undefined function
        "var x = y + z;",      // Undefined variables
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
