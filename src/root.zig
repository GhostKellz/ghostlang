const std = @import("std");

// By convention, root.zig is the root source file when making a library.

pub const ScriptError = error{
    ParseError,
    RuntimeError,
    ExecutionTimeout,
    InstructionLimitExceeded,
    UnexpectedToken,
    UnexpectedEOF,
    InvalidSyntax,
    UndefinedVariable,
    TypeError,
    StackOverflow,
    OutOfMemory,
};

// Debug information for error reporting
pub const ErrorContext = struct {
    line: u32 = 0,
    column: u32 = 0,
    instruction_pointer: u32 = 0,
    source_snippet: ?[]const u8 = null,
    function_name: ?[]const u8 = null,

    pub fn format(self: ErrorContext, comptime fmt: []const u8, options: anytype, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (self.function_name) |name| {
            try writer.print("in function '{s}' ", .{name});
        }
        try writer.print("at line {}, column {} (instruction {})", .{self.line, self.column, self.instruction_pointer});
        if (self.source_snippet) |snippet| {
            try writer.print("\n  -> {s}", .{snippet});
        }
    }
};

// Stack trace entry
pub const StackFrame = struct {
    function_name: []const u8,
    line: u32,
    column: u32,
    instruction_pointer: u32,
};

// Debug context for runtime tracking
pub const DebugContext = struct {
    call_stack: std.ArrayListUnmanaged(StackFrame) = .{},
    allocator: std.mem.Allocator,
    current_line: u32 = 1,
    current_column: u32 = 1,
    source_lines: ?std.ArrayList([]const u8) = null,

    pub fn init(allocator: std.mem.Allocator) DebugContext {
        return DebugContext{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DebugContext) void {
        self.call_stack.deinit(self.allocator);
        if (self.source_lines) |*lines| {
            for (lines.items) |line| {
                self.allocator.free(line);
            }
            lines.deinit(self.allocator);
        }
    }

    pub fn pushFrame(self: *DebugContext, name: []const u8, line: u32, column: u32, ip: u32) !void {
        try self.call_stack.append(self.allocator, .{
            .function_name = name,
            .line = line,
            .column = column,
            .instruction_pointer = ip,
        });
    }

    pub fn popFrame(self: *DebugContext) void {
        if (self.call_stack.items.len > 0) {
            _ = self.call_stack.pop();
        }
    }

    pub fn getCurrentContext(self: *DebugContext, ip: u32) ErrorContext {
        return ErrorContext{
            .line = self.current_line,
            .column = self.current_column,
            .instruction_pointer = ip,
            .source_snippet = self.getCurrentSourceLine(),
            .function_name = self.getCurrentFunctionName(),
        };
    }

    fn getCurrentSourceLine(self: *DebugContext) ?[]const u8 {
        if (self.source_lines) |lines| {
            if (self.current_line > 0 and self.current_line <= lines.items.len) {
                return lines.items[self.current_line - 1];
            }
        }
        return null;
    }

    fn getCurrentFunctionName(self: *DebugContext) ?[]const u8 {
        if (self.call_stack.items.len > 0) {
            return self.call_stack.items[self.call_stack.items.len - 1].function_name;
        }
        return null;
    }

    pub fn printStackTrace(self: *DebugContext, writer: anytype) !void {
        try writer.print("Stack trace:\n");
        var i: usize = self.call_stack.items.len;
        while (i > 0) {
            i -= 1;
            const frame = self.call_stack.items[i];
            try writer.print("  {}: in '{s}' at line {}, column {} (instruction {})\n",
                .{self.call_stack.items.len - i - 1, frame.function_name, frame.line, frame.column, frame.instruction_pointer});
        }
    }
};

pub const ScriptValueType = enum {
    nil,
    boolean,
    number,
    string,
    function,
    closure,
    table,
    owned_string,
    array,
    userdata,
};

pub const Closure = struct {
    function_id: u16,
    upvalues: []ScriptValue,

    pub fn deinit(self: *Closure, allocator: std.mem.Allocator) void {
        for (self.upvalues) |*upval| {
            upval.deinit(allocator);
        }
        allocator.free(self.upvalues);
    }
};

pub const UserData = struct {
    ptr: *anyopaque,
    type_name: []const u8,
    deinit_fn: ?*const fn (ptr: *anyopaque, allocator: std.mem.Allocator) void,

    pub fn create(comptime T: type, data: T, allocator: std.mem.Allocator) !UserData {
        const ptr = try allocator.create(T);
        ptr.* = data;
        return UserData{
            .ptr = ptr,
            .type_name = @typeName(T),
            .deinit_fn = struct {
                fn deinit(p: *anyopaque, alloc: std.mem.Allocator) void {
                    const typed_ptr: *T = @ptrCast(@alignCast(p));
                    alloc.destroy(typed_ptr);
                }
            }.deinit,
        };
    }

    pub fn get(self: UserData, comptime T: type) !*T {
        if (!std.mem.eql(u8, self.type_name, @typeName(T))) {
            return error.TypeError;
        }
        return @ptrCast(@alignCast(self.ptr));
    }
};

pub const ScriptValue = union(ScriptValueType) {
    nil: void,
    boolean: bool,
    number: f64,
    string: []const u8,
    function: *const fn (args: []const ScriptValue) ScriptValue,
    closure: Closure,
    table: std.StringHashMap(ScriptValue),
    owned_string: []const u8, // For strings that need to be freed
    array: std.ArrayList(ScriptValue),
    userdata: UserData,

    pub fn deinit(self: *ScriptValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .owned_string => |s| allocator.free(s),
            .closure => |*c| c.deinit(allocator),
            .table => |*t| {
                var it = t.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                t.deinit();
            },
            .array => |*a| {
                // Safe array cleanup - skip items that could be corrupt
                for (a.items) |*item| {
                    // Minimal validation by checking if the pattern looks reasonable
                    const item_ptr = @as([*]u8, @ptrCast(item));
                    const first_byte = item_ptr[0];

                    // If the first byte (enum tag) is suspiciously large, skip it
                    if (first_byte > 10) { // ScriptValueType has fewer than 10 variants
                        std.debug.print("Warning: Potentially corrupt array item (tag={}), skipping cleanup\n", .{first_byte});
                        continue;
                    }

                    // Cleanup based on known safe patterns
                    switch (item.*) {
                        .owned_string => |s| allocator.free(s),
                        .array => |*nested| nested.deinit(allocator),
                        .table => |*t| {
                            var it = t.iterator();
                            while (it.next()) |entry| {
                                allocator.free(entry.key_ptr.*);
                                entry.value_ptr.deinit(allocator);
                            }
                            t.deinit();
                        },
                        .userdata => |*ud| {
                            if (ud.deinit_fn) |deinit_fn| {
                                deinit_fn(ud.ptr, allocator);
                            }
                        },
                        // Skip cleanup for simple values that don't allocate
                        else => {},
                    }
                }
                a.deinit(allocator);
            },
            .userdata => |*ud| {
                if (ud.deinit_fn) |deinit_fn| {
                    deinit_fn(ud.ptr, allocator);
                }
            },
            .string => {}, // Don't free shared constant strings
            else => {},
        }
    }

    pub fn copy(self: ScriptValue, allocator: std.mem.Allocator) !ScriptValue {
        switch (self) {
            .string => |s| return .{ .owned_string = try allocator.dupe(u8, s) },
            .owned_string => |s| return .{ .owned_string = try allocator.dupe(u8, s) },
            .table => |t| {
                var new_table = std.StringHashMap(ScriptValue).init(allocator);
                var it = t.iterator();
                while (it.next()) |entry| {
                    const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                    const value_copy = try entry.value_ptr.copy(allocator);
                    try new_table.put(key_copy, value_copy);
                }
                return .{ .table = new_table };
            },
            .array => |a| {
                var new_array: std.ArrayList(ScriptValue) = .{};
                for (a.items) |item| {
                    const item_copy = try item.copy(allocator);
                    try new_array.append(allocator, item_copy);
                }
                return .{ .array = new_array };
            },
            .userdata => return error.CannotCopyUserData, // Userdata cannot be deep copied
            else => return self, // numbers, booleans, nil, functions don't need copying
        }
    }

    // Safe value storage helper
    pub fn safeStore(value: ScriptValue, allocator: std.mem.Allocator) !ScriptValue {
        // For values that go into containers (arrays/tables), ensure they're properly owned
        return switch (value) {
            .number, .boolean, .nil, .function, .userdata => value, // Safe to store directly
            .string => |s| .{ .owned_string = try allocator.dupe(u8, s) }, // Convert to owned
            .owned_string, .array, .table, .closure => try value.copy(allocator), // Deep copy
        };
    }
};

pub const EngineConfig = struct {
    allocator: std.mem.Allocator,
    memory_limit: usize = 1024 * 1024, // 1MB default
    execution_timeout_ms: u64 = 1000, // 1 second default
    allow_io: bool = false,
    allow_syscalls: bool = false,
};

pub const ScriptEngine = struct {
    config: EngineConfig,
    globals: std.StringHashMap(ScriptValue),

    pub fn create(config: EngineConfig) !ScriptEngine {
        const globals = std.StringHashMap(ScriptValue).init(config.allocator);
        return ScriptEngine{
            .config = config,
            .globals = globals,
        };
    }

    pub fn deinit(self: *ScriptEngine) void {
        var it = self.globals.iterator();
        while (it.next()) |entry| {
            self.config.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.config.allocator);
        }
        self.globals.deinit();
    }

    pub fn loadScript(self: *ScriptEngine, source: []const u8) !Script {
        var parser = Parser.init(self.config.allocator, source);
        const parsed = parser.parse() catch |err| {
            std.debug.print("Failed to parse script: {}\n", .{err});
            return err;
        };

        const vm = VM.init(self.config.allocator, parsed.instructions, parsed.constants, parsed.functions, self);
        return Script{
            .engine = self,
            .vm = vm,
        };
    }

    pub fn call(self: *ScriptEngine, function: []const u8, args: anytype) !ScriptValue {
        _ = args; // TODO: implement
        if (self.globals.get(function)) |func| {
            switch (func) {
                .function => |f| return f(&.{}), // empty args for now
                else => return error.NotAFunction,
            }
        }
        return error.FunctionNotFound;
    }

    pub fn registerFunction(self: *ScriptEngine, name: []const u8, func: *const fn (args: []const ScriptValue) ScriptValue) !void {
        const name_copy = try self.config.allocator.dupe(u8, name);
        try self.globals.put(name_copy, .{ .function = func });
    }

    // Enhanced FFI: Register a module with multiple functions
    pub fn registerModule(self: *ScriptEngine, module_name: []const u8, functions: anytype) !void {
        const info = @typeInfo(@TypeOf(functions));
        if (info != .@"struct") @compileError("functions must be a struct");

        inline for (info.@"struct".fields) |field| {
            const func = @field(functions, field.name);
            const full_name = try std.fmt.allocPrint(self.config.allocator, "{s}.{s}", .{module_name, field.name});
            defer self.config.allocator.free(full_name);
            try self.registerFunction(full_name, func);
        }
    }

    // Enhanced FFI: Type-safe argument helpers
    pub const ArgHelper = struct {
        args: []const ScriptValue,

        pub fn getString(self: ArgHelper, index: usize) ![]const u8 {
            if (index >= self.args.len) return error.ArgumentMissing;
            return switch (self.args[index]) {
                .string => |s| s,
                .owned_string => |s| s,
                else => error.TypeError,
            };
        }

        pub fn getNumber(self: ArgHelper, index: usize) !f64 {
            if (index >= self.args.len) return error.ArgumentMissing;
            return switch (self.args[index]) {
                .number => |n| n,
                else => error.TypeError,
            };
        }

        pub fn getBoolean(self: ArgHelper, index: usize) !bool {
            if (index >= self.args.len) return error.ArgumentMissing;
            return switch (self.args[index]) {
                .boolean => |b| b,
                else => error.TypeError,
            };
        }

        pub fn getArray(self: ArgHelper, index: usize) !std.ArrayList(ScriptValue) {
            if (index >= self.args.len) return error.ArgumentMissing;
            return switch (self.args[index]) {
                .array => |a| a,
                else => error.TypeError,
            };
        }

        pub fn getUserData(self: ArgHelper, comptime T: type, index: usize) !*T {
            if (index >= self.args.len) return error.ArgumentMissing;
            return switch (self.args[index]) {
                .userdata => |ud| ud.get(T),
                else => error.TypeError,
            };
        }
    };
};

pub const Opcode = enum(u8) {
    nop,
    load_const,
    load_global,
    store_global,
    load_local,
    store_local,
    declare_local, // Declare a new local variable
    add,
    sub,
    mul,
    div,
    mod,
    eq,
    ne,
    lt,
    le,
    gt,
    ge,
    logical_and,
    logical_or,
    logical_not,
    new_table,
    get_table,
    set_table,
    call,
    call_closure,
    closure,
    jump,
    jump_if_false,
    jump_if_true,
    ret,
    require_module,
    concat,
    strlen,
    substr,
    str_upper,
    str_lower,
    str_find,
    for_init,
    for_loop,
    for_in_init,
    for_in_next,
    while_loop,
    file_read,
    file_write,
    file_exists,
    file_delete,
    new_array,
    array_get,
    array_set,
    array_push,
    array_len,
};

pub const Instruction = struct {
    opcode: Opcode,
    operands: [3]u16, // for simplicity, up to 3 operands
};

pub const FunctionInfo = struct {
    name: []const u8,
    param_count: u8,
    local_count: u8,
    instructions: []const Instruction,
    constants: []const ScriptValue,

    pub fn deinit(self: *const FunctionInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.instructions);
        for (self.constants) |*constant| {
            var mut_constant = constant.*;
            mut_constant.deinit(allocator);
        }
        allocator.free(self.constants);
    }
};

pub const VM = struct {
    registers: [256]ScriptValue,
    locals: [256]ScriptValue,
    local_names: [256][]const u8, // Track local variable names
    local_count: u16, // Number of active locals
    globals: std.StringHashMap(ScriptValue),
    pc: usize,
    code: []const Instruction,
    constants: []const ScriptValue,
    functions: []const FunctionInfo,
    allocator: std.mem.Allocator,
    engine: *ScriptEngine,
    instruction_count: u64, // Track executed instructions for timeout
    start_time: i64, // Execution start time in milliseconds
    debug_context: DebugContext, // Debug information for error reporting

    pub fn init(allocator: std.mem.Allocator, code: []const Instruction, constants: []const ScriptValue, functions: []const FunctionInfo, engine: *ScriptEngine) VM {
        var vm = VM{
            .registers = undefined,
            .locals = undefined,
            .local_names = undefined,
            .local_count = 0,
            .globals = std.StringHashMap(ScriptValue).init(allocator),
            .pc = 0,
            .code = code,
            .constants = constants,
            .functions = functions,
            .allocator = allocator,
            .engine = engine,
            .instruction_count = 0,
            .start_time = std.time.milliTimestamp(),
            .debug_context = DebugContext.init(allocator),
        };

        // Initialize registers and locals to nil
        for (&vm.registers) |*reg| {
            reg.* = .{ .nil = {} };
        }
        for (&vm.locals) |*local| {
            local.* = .{ .nil = {} };
        }
        for (&vm.local_names) |*name| {
            name.* = "";
        }

        return vm;
    }

    // Find local variable by name, returns index or null
    fn findLocal(self: *VM, name: []const u8) ?u16 {
        var i: u16 = 0;
        while (i < self.local_count) : (i += 1) {
            if (std.mem.eql(u8, self.local_names[i], name)) {
                return i;
            }
        }
        return null;
    }

    // Add a new local variable
    fn addLocal(self: *VM, name: []const u8) !u16 {
        if (self.local_count >= 256) return error.TooManyLocals;
        const index = self.local_count;
        self.local_names[index] = name; // Note: should be a constant string from parser
        self.locals[index] = .{ .nil = {} };
        self.local_count += 1;
        return index;
    }

    pub fn deinit(self: *VM) void {
        // Clean up registers
        for (&self.registers) |*reg| {
            reg.deinit(self.allocator);
        }

        // Clean up locals
        for (&self.locals) |*local| {
            local.deinit(self.allocator);
        }

        // Clean up globals
        var it = self.globals.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit(self.allocator);
        }
        self.globals.deinit();

        // Clean up functions
        for (self.functions) |*func| {
            func.deinit(self.allocator);
        }

        // Clean up debug context
        self.debug_context.deinit();
    }

    // Helper function to print runtime errors with debug context
    fn reportError(self: *VM, error_type: ScriptError, message: []const u8) ScriptError {
        const error_ctx = self.debug_context.getCurrentContext(@intCast(self.pc));
        std.debug.print("Runtime error: {s} {any}\n", .{message, error_ctx});
        // Simplified error output for compatibility
        std.debug.print("(Stack trace disabled for compatibility)\n", .{});
        return error_type;
    }

    pub fn run(self: *VM) !ScriptValue {
        while (self.pc < self.code.len) {
            // Track execution for debugging
            self.debug_context.current_line += 1; // Simple line tracking approximation

            // Check for execution timeout
            const current_time = std.time.milliTimestamp();
            if (current_time - self.start_time > @as(i64, @intCast(self.engine.config.execution_timeout_ms))) {
                return error.ExecutionTimeout;
            }

            // Check for instruction limit (basic prevention of infinite loops)
            self.instruction_count += 1;
            if (self.instruction_count > 1000000) { // 1M instructions max
                return error.InstructionLimitExceeded;
            }

            const instr = self.code[self.pc];
            switch (instr.opcode) {
                .nop => {},
                .load_const => {
                    const reg = instr.operands[0];
                    const const_idx = instr.operands[1];
                    // Clean up the destination register before overwriting
                    self.registers[reg].deinit(self.allocator);
                    // For strings, we need to share references to constants to avoid unnecessary copying
                    // Only copy if the value needs to be mutable
                    switch (self.constants[const_idx]) {
                        .string => |s| {
                            // Share the constant string reference instead of copying
                            self.registers[reg] = .{ .string = s };
                        },
                        else => {
                            self.registers[reg] = self.constants[const_idx];
                        },
                    }
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
                        return error.TypeError;
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
                        return error.TypeError;
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
                        return error.TypeError;
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
                        return error.TypeError;
                    }
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
                        if (self.engine.globals.get(func_name.string)) |global| {
                            if (global == .function) {
                                const args = self.registers[arg_start .. arg_start + arg_count];
                                const result = global.function(args);
                                self.registers[arg_start] = result; // store result in first arg register or something
                            } else {
                                return error.NotAFunction;
                            }
                        } else {
                            return error.FunctionNotFound;
                        }
                    } else {
                        return error.InvalidFunctionName;
                    }
                },
                .load_global => {
                    const reg = instr.operands[0];
                    const name_idx = instr.operands[1];
                    const name = self.constants[name_idx];
                    if (name == .string) {
                        // Check locals first, then globals, then engine globals
                        if (self.findLocal(name.string)) |local_idx| {
                            self.registers[reg] = self.locals[local_idx];
                        } else if (self.globals.get(name.string)) |value| {
                            self.registers[reg] = value;
                        } else if (self.engine.globals.get(name.string)) |value| {
                            self.registers[reg] = value;
                        } else {
                            var msg_buf: [256]u8 = undefined;
                            const msg = std.fmt.bufPrint(&msg_buf, "Undefined variable '{s}'", .{name.string}) catch "Undefined variable";
                            return self.reportError(ScriptError.UndefinedVariable, msg);
                        }
                    } else {
                        return error.InvalidGlobalName;
                    }
                },
                .store_global => {
                    const reg = instr.operands[0];
                    const name_idx = instr.operands[1];
                    const name = self.constants[name_idx];
                    if (name == .string) {
                        const value_copy = self.registers[reg];

                        // Check if it's a local variable first
                        if (self.findLocal(name.string)) |local_idx| {
                            // Update local variable
                            self.locals[local_idx].deinit(self.allocator);
                            self.locals[local_idx] = value_copy;
                        } else {
                            // Check if global already exists to avoid duplicate key allocation
                            if (self.globals.getPtr(name.string)) |existing_value| {
                                // Update existing value
                                existing_value.deinit(self.allocator);
                                existing_value.* = value_copy;
                            } else {
                                // Create new global
                                const name_copy = try self.allocator.dupe(u8, name.string);
                                try self.globals.put(name_copy, value_copy);
                            }
                        }
                    } else {
                        return error.InvalidGlobalName;
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

                    // Handle both boolean and number conditions (Lua-like truthiness)
                    var is_false = false;
                    switch (cond) {
                        .boolean => |b| is_false = !b,
                        .number => |n| is_false = (n == 0),
                        .nil => is_false = true,
                        else => is_false = false,
                    }

                    if (is_false) {
                        self.pc = @intCast(target);
                        continue;
                    }
                },
                .jump_if_true => {
                    const cond_reg = instr.operands[0];
                    const target = instr.operands[1];
                    const cond = self.registers[cond_reg];

                    var is_true = false;
                    switch (cond) {
                        .boolean => |b| is_true = b,
                        .number => |n| is_true = (n != 0),
                        .nil => is_true = false,
                        else => is_true = true,
                    }

                    if (is_true) {
                        self.pc = @intCast(target);
                        continue;
                    }
                },
                .eq => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];

                    var result = false;
                    if (val_a == .number and val_b == .number) {
                        result = val_a.number == val_b.number;
                    } else if (val_a == .boolean and val_b == .boolean) {
                        result = val_a.boolean == val_b.boolean;
                    } else if (val_a == .nil and val_b == .nil) {
                        result = true;
                    }

                    self.registers[dest] = .{ .boolean = result };
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
                        return error.TypeError;
                    }
                },
                .le => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .boolean = val_a.number <= val_b.number };
                    } else {
                        return error.TypeError;
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
                        return error.TypeError;
                    }
                },
                .ge => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];
                    if (val_a == .number and val_b == .number) {
                        self.registers[dest] = .{ .boolean = val_a.number >= val_b.number };
                    } else {
                        return error.TypeError;
                    }
                },
                .logical_and => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];

                    // Lua-style truthiness: only false and nil are falsy
                    var a_truthy = true;
                    var b_truthy = true;

                    switch (val_a) {
                        .boolean => |bool_val| a_truthy = bool_val,
                        .nil => a_truthy = false,
                        .number => |n| a_truthy = (n != 0),
                        else => a_truthy = true,
                    }

                    switch (val_b) {
                        .boolean => |bool_val| b_truthy = bool_val,
                        .nil => b_truthy = false,
                        .number => |n| b_truthy = (n != 0),
                        else => b_truthy = true,
                    }

                    self.registers[dest] = .{ .boolean = a_truthy and b_truthy };
                },
                .logical_or => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];

                    // Lua-style truthiness: only false and nil are falsy
                    var a_truthy = true;
                    var b_truthy = true;

                    switch (val_a) {
                        .boolean => |bool_val| a_truthy = bool_val,
                        .nil => a_truthy = false,
                        .number => |n| a_truthy = (n != 0),
                        else => a_truthy = true,
                    }

                    switch (val_b) {
                        .boolean => |bool_val| b_truthy = bool_val,
                        .nil => b_truthy = false,
                        .number => |n| b_truthy = (n != 0),
                        else => b_truthy = true,
                    }

                    self.registers[dest] = .{ .boolean = a_truthy or b_truthy };
                },
                .logical_not => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const val_a = self.registers[a];

                    // Lua-style truthiness: only false and nil are falsy
                    var a_truthy = true;
                    switch (val_a) {
                        .boolean => |bool_val| a_truthy = bool_val,
                        .nil => a_truthy = false,
                        .number => |n| a_truthy = (n != 0),
                        else => a_truthy = true,
                    }

                    self.registers[dest] = .{ .boolean = !a_truthy };
                },
                .ne => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];

                    var result = true;
                    if (val_a == .number and val_b == .number) {
                        result = val_a.number != val_b.number;
                    } else if (val_a == .boolean and val_b == .boolean) {
                        result = val_a.boolean != val_b.boolean;
                    } else if (val_a == .nil and val_b == .nil) {
                        result = false;
                    }

                    self.registers[dest] = .{ .boolean = result };
                },
                .new_table => {
                    const dest = instr.operands[0];
                    // Clean up the destination register before overwriting
                    self.registers[dest].deinit(self.allocator);
                    const table = std.StringHashMap(ScriptValue).init(self.allocator);
                    self.registers[dest] = .{ .table = table };
                },
                .get_table => {
                    const dest = instr.operands[0];
                    const table_reg = instr.operands[1];
                    const key_reg = instr.operands[2];

                    const table_val = self.registers[table_reg];
                    const key_val = self.registers[key_reg];

                    if (table_val == .table and key_val == .string) {
                        if (table_val.table.get(key_val.string)) |value| {
                            self.registers[dest] = value;
                        } else {
                            self.registers[dest] = .{ .nil = {} };
                        }
                    } else {
                        return error.TypeError;
                    }
                },
                .set_table => {
                    const table_reg = instr.operands[0];
                    const key_reg = instr.operands[1];
                    const value_reg = instr.operands[2];

                    var table_val = &self.registers[table_reg];
                    const key_val = self.registers[key_reg];
                    const value_val = self.registers[value_reg];

                    if (table_val.* == .table and key_val == .string) {
                        const key_copy = try self.allocator.dupe(u8, key_val.string);
                        try table_val.table.put(key_copy, value_val);
                    } else {
                        return error.TypeError;
                    }
                },
                .load_local => {
                    const reg = instr.operands[0];
                    const local_idx = instr.operands[1];
                    // Clean up the destination register before overwriting
                    self.registers[reg].deinit(self.allocator);
                    // Use safeStore to handle ownership properly
                    self.registers[reg] = try ScriptValue.safeStore(self.locals[local_idx], self.allocator);
                },
                .store_local => {
                    const reg = instr.operands[0];
                    const local_idx = instr.operands[1];
                    // Clean up the old local value before overwriting
                    self.locals[local_idx].deinit(self.allocator);
                    // Use safeStore to handle ownership properly
                    self.locals[local_idx] = try ScriptValue.safeStore(self.registers[reg], self.allocator);
                },
                .declare_local => {
                    const name_idx = instr.operands[0];
                    const value_reg = instr.operands[1];
                    const name = self.constants[name_idx];
                    if (name == .string) {
                        const local_idx = try self.addLocal(name.string);
                        // Use safeStore to handle ownership properly
                        self.locals[local_idx] = try ScriptValue.safeStore(self.registers[value_reg], self.allocator);
                    } else {
                        return error.InvalidLocalName;
                    }
                },
                .closure => {
                    const dest_reg = instr.operands[0];
                    const func_id = instr.operands[1];
                    const upval_count = instr.operands[2];

                    // Create closure with upvalues
                    const upvalues = try self.allocator.alloc(ScriptValue, upval_count);
                    for (0..upval_count) |i| {
                        upvalues[i] = self.registers[i]; // simplified - should capture specific variables
                    }

                    self.registers[dest_reg] = .{ .closure = .{
                        .function_id = func_id,
                        .upvalues = upvalues,
                    }};
                },
                .call_closure => {
                    const closure_reg = instr.operands[0];
                    const arg_start = instr.operands[1];
                    const arg_count = instr.operands[2];

                    const closure_val = self.registers[closure_reg];
                    if (closure_val == .closure) {
                        const closure = closure_val.closure;
                        const func = self.functions[closure.function_id];

                        // Set up parameters as locals
                        for (0..func.param_count) |i| {
                            if (i < arg_count) {
                                self.locals[i] = self.registers[arg_start + i];
                            } else {
                                self.locals[i] = .{ .nil = {} };
                            }
                        }

                        // Create a new VM to execute the function (without shared data)
                        var func_vm = VM{
                            .registers = undefined,
                            .locals = undefined,
                            .local_names = undefined,
                            .local_count = 0,
                            .globals = std.StringHashMap(ScriptValue).init(self.allocator),
                            .pc = 0,
                            .code = func.instructions,
                            .constants = func.constants,
                            .functions = &[_]FunctionInfo{}, // empty functions to avoid double-free
                            .allocator = self.allocator,
                            .engine = self.engine,
                            .instruction_count = 0,
                            .start_time = self.start_time, // Inherit parent's start time
                            .debug_context = DebugContext.init(self.allocator),
                        };

                        // Initialize registers and locals
                        for (&func_vm.registers) |*reg| {
                            reg.* = .{ .nil = {} };
                        }
                        for (&func_vm.locals) |*local| {
                            local.* = .{ .nil = {} };
                        }
                        for (&func_vm.local_names) |*name| {
                            name.* = "";
                        }

                        defer {
                            // Only deinit globals, not shared data
                            var it = func_vm.globals.iterator();
                            while (it.next()) |entry| {
                                self.allocator.free(entry.key_ptr.*);
                                entry.value_ptr.deinit(self.allocator);
                            }
                            func_vm.globals.deinit();
                        }

                        // Copy locals to the function VM
                        func_vm.locals = self.locals;

                        // Execute the function
                        const result = try func_vm.run();
                        self.registers[closure_reg] = result;
                    } else if (closure_val == .function) {
                        // Handle built-in functions
                        const args = self.registers[arg_start .. arg_start + arg_count];
                        const result = closure_val.function(args);
                        self.registers[closure_reg] = result;
                    } else {
                        return error.NotAFunction;
                    }
                },
                .require_module => {
                    const dest_reg = instr.operands[0];
                    const filename_idx = instr.operands[1];
                    const filename = self.constants[filename_idx];

                    if (filename == .string) {
                        // Clean up the destination register before overwriting
                        self.registers[dest_reg].deinit(self.allocator);

                        // Try to load the actual .gza file
                        if (std.fs.cwd().readFileAlloc(filename.string, self.allocator, .unlimited)) |file_content| {
                            defer self.allocator.free(file_content);

                            // TODO: Parse and execute the loaded script content
                            // For now, create a module table with the file content as a string
                            var module_table = std.StringHashMap(ScriptValue).init(self.allocator);
                            const content_key = try self.allocator.dupe(u8, "content");
                            const content_value = try self.allocator.dupe(u8, file_content);
                            try module_table.put(content_key, .{ .owned_string = content_value });

                            self.registers[dest_reg] = .{ .table = module_table };
                        } else |err| {
                            switch (err) {
                                error.FileNotFound => {
                                    // If file doesn't exist, create a basic module table
                                    var module_table = std.StringHashMap(ScriptValue).init(self.allocator);
                                    const version_key = try self.allocator.dupe(u8, "version");
                                    try module_table.put(version_key, .{ .owned_string = try self.allocator.dupe(u8, "1.0.0") });
                                    self.registers[dest_reg] = .{ .table = module_table };
                                },
                                else => {
                                    // For other errors, return nil
                                    self.registers[dest_reg] = .{ .nil = {} };
                                },
                            }
                        }
                    } else {
                        return error.InvalidModuleName;
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
                        return error.TypeError;
                    }
                },
                .concat => {
                    const dest = instr.operands[0];
                    const a = instr.operands[1];
                    const b = instr.operands[2];
                    const val_a = self.registers[a];
                    const val_b = self.registers[b];

                    if ((val_a == .string or val_a == .owned_string) and (val_b == .string or val_b == .owned_string)) {
                        // Clean up the destination register before overwriting
                        self.registers[dest].deinit(self.allocator);
                        const str_a = switch (val_a) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };
                        const str_b = switch (val_b) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };
                        const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{str_a, str_b});
                        self.registers[dest] = .{ .owned_string = result };
                    } else {
                        return error.TypeError;
                    }
                },
                .strlen => {
                    const dest = instr.operands[0];
                    const str_reg = instr.operands[1];
                    const str_val = self.registers[str_reg];

                    if (str_val == .string or str_val == .owned_string) {
                        const str = switch (str_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };
                        self.registers[dest] = .{ .number = @floatFromInt(str.len) };
                    } else {
                        return error.TypeError;
                    }
                },
                .substr => {
                    const dest = instr.operands[0];
                    const str_reg = instr.operands[1];
                    const start_reg = instr.operands[2];
                    const str_val = self.registers[str_reg];
                    const start_val = self.registers[start_reg];

                    if ((str_val == .string or str_val == .owned_string) and start_val == .number) {
                        // Clean up the destination register before overwriting
                        self.registers[dest].deinit(self.allocator);
                        const str = switch (str_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };
                        const start_idx = @max(0, @min(@as(usize, @intFromFloat(start_val.number)), str.len));
                        const substr = str[start_idx..];
                        const result = try self.allocator.dupe(u8, substr);
                        self.registers[dest] = .{ .owned_string = result };
                    } else {
                        return error.TypeError;
                    }
                },
                .str_upper => {
                    const dest = instr.operands[0];
                    const str_reg = instr.operands[1];
                    const str_val = self.registers[str_reg];

                    if (str_val == .string or str_val == .owned_string) {
                        // Clean up the destination register before overwriting
                        self.registers[dest].deinit(self.allocator);
                        const str = switch (str_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };
                        const upper_str = try self.allocator.alloc(u8, str.len);
                        for (str, 0..) |char, i| {
                            upper_str[i] = std.ascii.toUpper(char);
                        }
                        self.registers[dest] = .{ .owned_string = upper_str };
                    } else {
                        return error.TypeError;
                    }
                },
                .str_lower => {
                    const dest = instr.operands[0];
                    const str_reg = instr.operands[1];
                    const str_val = self.registers[str_reg];

                    if (str_val == .string or str_val == .owned_string) {
                        // Clean up the destination register before overwriting
                        self.registers[dest].deinit(self.allocator);
                        const str = switch (str_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };
                        const lower_str = try self.allocator.alloc(u8, str.len);
                        for (str, 0..) |char, i| {
                            lower_str[i] = std.ascii.toLower(char);
                        }
                        self.registers[dest] = .{ .owned_string = lower_str };
                    } else {
                        return error.TypeError;
                    }
                },
                .str_find => {
                    const dest = instr.operands[0];
                    const haystack_reg = instr.operands[1];
                    const needle_reg = instr.operands[2];
                    const haystack_val = self.registers[haystack_reg];
                    const needle_val = self.registers[needle_reg];

                    if ((haystack_val == .string or haystack_val == .owned_string) and
                        (needle_val == .string or needle_val == .owned_string)) {
                        self.registers[dest].deinit(self.allocator);

                        const haystack = switch (haystack_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };
                        const needle = switch (needle_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };

                        // Simple string find implementation
                        if (std.mem.indexOf(u8, haystack, needle)) |index| {
                            self.registers[dest] = .{ .number = @floatFromInt(index) };
                        } else {
                            self.registers[dest] = .{ .number = -1 };
                        }
                    } else {
                        return error.TypeError;
                    }
                },
                .for_init => {
                    const iter_reg = instr.operands[0];
                    const start_reg = instr.operands[1];
                    const end_reg = instr.operands[2];
                    const start_val = self.registers[start_reg];
                    const end_val = self.registers[end_reg];

                    if (start_val == .number and end_val == .number) {
                        self.registers[iter_reg] = start_val;
                    } else {
                        return error.TypeError;
                    }
                },
                .for_loop => {
                    const iter_reg = instr.operands[0];
                    const end_reg = instr.operands[1];
                    const jump_target = instr.operands[2];
                    const iter_val = self.registers[iter_reg];
                    const end_val = self.registers[end_reg];

                    if (iter_val == .number and end_val == .number) {
                        // First check if we should continue (iterator < end)
                        if (iter_val.number <= end_val.number) {
                            // Increment for next iteration
                            self.registers[iter_reg] = .{ .number = iter_val.number + 1 };
                            self.pc = @intCast(jump_target);
                            continue;
                        }
                        // Exit loop - fall through
                    } else {
                        return error.TypeError;
                    }
                },
                .for_in_init => {
                    const state_reg = instr.operands[0];
                    const table_reg = instr.operands[1];
                    const table_val = self.registers[table_reg];

                    if (table_val == .table) {
                        // Initialize iterator state (store table reference)
                        self.registers[state_reg] = .{ .number = 0 }; // Simple index-based iteration for now
                    } else {
                        return error.TypeError;
                    }
                },
                .for_in_next => {
                    const state_reg = instr.operands[0];
                    const table_reg = instr.operands[1];
                    const jump_target = instr.operands[2];
                    const table_val = self.registers[table_reg];
                    const state_val = self.registers[state_reg];

                    if (table_val == .table and state_val == .number) {
                        // For simplicity, we'll skip actual table iteration for now
                        // In a full implementation, this would iterate through table entries
                        // For now, just exit the loop
                        _ = jump_target; // TODO: Implement proper table iteration
                    } else {
                        return error.TypeError;
                    }
                },
                .while_loop => {
                    const cond_reg = instr.operands[0];
                    const jump_target = instr.operands[1];
                    const cond = self.registers[cond_reg];

                    var is_true = false;
                    switch (cond) {
                        .boolean => |b| is_true = b,
                        .number => |n| is_true = (n != 0),
                        .nil => is_true = false,
                        else => is_true = true,
                    }

                    if (is_true) {
                        self.pc = @intCast(jump_target);
                        continue;
                    }
                    // Exit loop - fall through
                },
                .file_read => {
                    const dest_reg = instr.operands[0];
                    const filename_reg = instr.operands[1];
                    const filename_val = self.registers[filename_reg];

                    if (filename_val == .string or filename_val == .owned_string) {
                        // Clean up the destination register before overwriting
                        self.registers[dest_reg].deinit(self.allocator);

                        const filename = switch (filename_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };

                        // Read file contents
                        const file_content = std.fs.cwd().readFileAlloc(filename, self.allocator, .unlimited) catch |err| switch (err) {
                            error.FileNotFound => try self.allocator.dupe(u8, ""),
                            error.AccessDenied => try self.allocator.dupe(u8, ""),
                            else => try self.allocator.dupe(u8, ""),
                        };
                        self.registers[dest_reg] = .{ .owned_string = file_content };
                    } else {
                        return error.TypeError;
                    }
                },
                .file_write => {
                    const filename_reg = instr.operands[0];
                    const content_reg = instr.operands[1];
                    const result_reg = instr.operands[2];
                    const filename_val = self.registers[filename_reg];
                    const content_val = self.registers[content_reg];

                    if ((filename_val == .string or filename_val == .owned_string) and (content_val == .string or content_val == .owned_string)) {
                        // Clean up the result register before overwriting
                        self.registers[result_reg].deinit(self.allocator);

                        const filename = switch (filename_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };
                        const content = switch (content_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };

                        // Write file contents
                        const success = blk: {
                            std.fs.cwd().writeFile(.{ .sub_path = filename, .data = content }) catch {
                                break :blk false;
                            };
                            break :blk true;
                        };
                        self.registers[result_reg] = .{ .boolean = success };
                    } else {
                        return error.TypeError;
                    }
                },
                .file_exists => {
                    const dest_reg = instr.operands[0];
                    const filename_reg = instr.operands[1];
                    const filename_val = self.registers[filename_reg];

                    if (filename_val == .string or filename_val == .owned_string) {
                        // Clean up the destination register before overwriting
                        self.registers[dest_reg].deinit(self.allocator);

                        const filename = switch (filename_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };

                        // Check if file exists
                        const exists = blk: {
                            std.fs.cwd().access(filename, .{}) catch {
                                break :blk false;
                            };
                            break :blk true;
                        };
                        self.registers[dest_reg] = .{ .boolean = exists };
                    } else {
                        return error.TypeError;
                    }
                },
                .file_delete => {
                    const filename_reg = instr.operands[0];
                    const result_reg = instr.operands[1];
                    const filename_val = self.registers[filename_reg];

                    if (filename_val == .string or filename_val == .owned_string) {
                        // Clean up the result register before overwriting
                        self.registers[result_reg].deinit(self.allocator);

                        const filename = switch (filename_val) {
                            .string => |s| s,
                            .owned_string => |s| s,
                            else => unreachable,
                        };

                        // Delete file
                        const success = blk: {
                            std.fs.cwd().deleteFile(filename) catch {
                                break :blk false;
                            };
                            break :blk true;
                        };
                        self.registers[result_reg] = .{ .boolean = success };
                    } else {
                        return error.TypeError;
                    }
                },
                .new_array => {
                    const dest_reg = instr.operands[0];
                    // Clean up the destination register before overwriting
                    self.registers[dest_reg].deinit(self.allocator);
                    const array: std.ArrayList(ScriptValue) = .{};
                    self.registers[dest_reg] = .{ .array = array };
                },
                .array_get => {
                    const dest_reg = instr.operands[0];
                    const array_reg = instr.operands[1];
                    const index_reg = instr.operands[2];
                    const array_val = self.registers[array_reg];
                    const index_val = self.registers[index_reg];

                    if (array_val == .array and index_val == .number) {
                        const index = @as(usize, @intFromFloat(index_val.number));
                        if (index < array_val.array.items.len) {
                            self.registers[dest_reg].deinit(self.allocator);
                            const item = array_val.array.items[index];
                            // Validate item isn't corrupted before switching on it
                            const item_ptr = @as([*]const u8, @ptrCast(&item));
                            const tag_byte = item_ptr[0];
                            if (tag_byte > 10) {
                                std.debug.print("Warning: Corrupted array item at index {} (tag={}), returning nil\n", .{index, tag_byte});
                                self.registers[dest_reg] = .{ .nil = {} };
                            } else {
                                switch (item) {
                                    .number, .boolean, .nil => self.registers[dest_reg] = item,
                                    else => self.registers[dest_reg] = try item.copy(self.allocator),
                                }
                            }
                        } else {
                            self.registers[dest_reg].deinit(self.allocator);
                            self.registers[dest_reg] = .{ .nil = {} };
                        }
                    } else {
                        return error.TypeError;
                    }
                },
                .array_set => {
                    const array_reg = instr.operands[0];
                    const index_reg = instr.operands[1];
                    const value_reg = instr.operands[2];
                    var array_val = &self.registers[array_reg];
                    const index_val = self.registers[index_reg];
                    const value_val = self.registers[value_reg];

                    if (array_val.* == .array and index_val == .number) {
                        const index = @as(usize, @intFromFloat(index_val.number));
                        if (index < array_val.array.items.len) {
                            // Check for corruption before deinit
                            const item_ptr = @as([*]const u8, @ptrCast(&array_val.array.items[index]));
                            const tag_byte = item_ptr[0];
                            if (tag_byte <= 10) {
                                array_val.array.items[index].deinit(self.allocator);
                            }
                            array_val.array.items[index] = try ScriptValue.safeStore(value_val, self.allocator);
                        } else if (index == array_val.array.items.len) {
                            // Allow appending to end
                            const safe_value = try ScriptValue.safeStore(value_val, self.allocator);
                            try array_val.array.append(self.allocator, safe_value);
                        }
                        // Ignore out-of-bounds assignments beyond end+1
                    } else {
                        return error.TypeError;
                    }
                },
                .array_push => {
                    const array_reg = instr.operands[0];
                    const value_reg = instr.operands[1];
                    var array_val = &self.registers[array_reg];
                    const value_val = self.registers[value_reg];

                    if (array_val.* == .array) {
                        const safe_value = try ScriptValue.safeStore(value_val, self.allocator);
                        try array_val.array.append(self.allocator, safe_value);
                    } else {
                        return error.TypeError;
                    }
                },
                .array_len => {
                    const dest_reg = instr.operands[0];
                    const array_reg = instr.operands[1];
                    const array_val = self.registers[array_reg];

                    if (array_val == .array) {
                        self.registers[dest_reg] = .{ .number = @floatFromInt(array_val.array.items.len) };
                    } else {
                        return error.TypeError;
                    }
                },
            }
            self.pc += 1;
        }
        return .{ .nil = {} };
    }
};

pub const Script = struct {
    engine: *ScriptEngine,
    vm: VM,

    pub fn deinit(self: *Script) void {
        self.vm.deinit();

        // Clean up constants - all string constants need to be freed
        for (self.vm.constants) |*constant| {
            switch (constant.*) {
                .string => |s| self.engine.config.allocator.free(s),
                .owned_string => |s| self.engine.config.allocator.free(s),
                else => {},
            }
        }
        self.engine.config.allocator.free(self.vm.constants);
        self.engine.config.allocator.free(self.vm.code);
        self.engine.config.allocator.free(self.vm.functions);
    }

    pub fn run(self: *Script) !ScriptValue {
        return self.vm.run();
    }

    pub fn getGlobal(self: *Script, name: []const u8) !ScriptValue {
        return self.engine.globals.get(name) orelse error.GlobalNotFound;
    }

    pub fn setGlobal(self: *Script, name: []const u8, value: ScriptValue) !void {
        const name_copy = try self.engine.config.allocator.dupe(u8, name);
        const value_copy = value;
        // TODO: deep copy value if needed
        try self.engine.globals.put(name_copy, value_copy);
    }
};

pub const ParseError = struct {
    message: []const u8,
    line: usize,
    column: usize,
    position: usize,
};

pub const Parser = struct {
    allocator: std.mem.Allocator,
    source: []const u8,
    pos: usize,
    line: usize,
    column: usize,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Parser {
        return Parser{
            .allocator = allocator,
            .source = source,
            .pos = 0,
            .line = 1,
            .column = 1,
        };
    }

    pub fn parse(self: *Parser) !struct { instructions: []Instruction, constants: []ScriptValue, functions: []FunctionInfo } {
        var constants: std.ArrayListUnmanaged(ScriptValue) = .{};
        defer constants.deinit(self.allocator);
        var instructions: std.ArrayListUnmanaged(Instruction) = .{};
        defer instructions.deinit(self.allocator);
        var functions: std.ArrayListUnmanaged(FunctionInfo) = .{};
        defer functions.deinit(self.allocator);
        var last_result_reg: u16 = 0;

        while (self.peek() != null) {
            last_result_reg = try self.parseStatement(&constants, &instructions, &functions);
            if (self.peek() == ';') {
                self.advance();
                self.skipWhitespace();
            } else if (self.peek() == null) {
                break;
            } else {
                break; // allow missing ;
            }
        }

        try instructions.append(self.allocator, .{ .opcode = .ret, .operands = [_]u16{last_result_reg, 0, 0} });

        const instr_slice = try self.allocator.dupe(Instruction, instructions.items);
        const const_slice = try self.allocator.dupe(ScriptValue, constants.items);
        const func_slice = try self.allocator.dupe(FunctionInfo, functions.items);
        return .{ .instructions = instr_slice, .constants = const_slice, .functions = func_slice };
    }

    fn parseStatement(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), functions: *std.ArrayListUnmanaged(FunctionInfo)) !u16 {
        self.skipWhitespace();
        if (self.peekIdent()) {
            // Look ahead to see if this is a keyword or just a variable
            const saved_pos = self.pos;
            const ident = try self.parseIdent();
            defer self.allocator.free(ident);

            if (std.mem.eql(u8, ident, "var")) {
                // var ident = expr (global variable)
                self.skipWhitespace();
                const var_name = try self.parseIdent();
                defer self.allocator.free(var_name);
                self.skipWhitespace();
                try self.expect('=');
                self.skipWhitespace();
                const expr_reg = try self.parseExpression(constants, instructions, 0);
                // store to global
                const name_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, var_name) });
                try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{expr_reg, name_idx, 0} });
                return 0;
            } else if (std.mem.eql(u8, ident, "local")) {
                // local ident = expr (local variable)
                self.skipWhitespace();
                const var_name = try self.parseIdent();
                defer self.allocator.free(var_name);
                self.skipWhitespace();
                try self.expect('=');
                self.skipWhitespace();
                const expr_reg = try self.parseExpression(constants, instructions, 0);

                // Declare proper local variable
                const name_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, var_name) });
                try instructions.append(self.allocator, .{ .opcode = .declare_local, .operands = [_]u16{name_idx, expr_reg, 0} });
                return 0;
            } else if (std.mem.eql(u8, ident, "if")) {
                // if expr { statements }
                self.skipWhitespace();
                try self.expect('(');
                self.skipWhitespace();
                const cond_reg = try self.parseExpression(constants, instructions, 0);
                self.skipWhitespace();
                try self.expect(')');
                self.skipWhitespace();
                try self.expect('{');

                // Jump to else block if condition is false
                var jump_to_else_idx = instructions.items.len;
                try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{cond_reg, 0, 0} }); // will patch later

                // Parse if body
                self.skipWhitespace();
                while (self.peek() != '}') {
                    _ = try self.parseStatement(constants, instructions, functions);
                    self.skipWhitespace();
                }
                try self.expect('}');

                // Jump over else block
                const jump_over_else_idx = instructions.items.len;
                try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{0, 0, 0} }); // will patch later

                // Patch the jump_if_false target (start of else block)
                const else_start = @as(u16, @intCast(instructions.items.len));
                instructions.items[jump_to_else_idx].operands[1] = else_start;

                // Handle elseif and else clauses
                var jump_patches: std.ArrayList(usize) = .{};
                defer jump_patches.deinit(self.allocator);
                try jump_patches.append(self.allocator, jump_over_else_idx);

                self.skipWhitespace();
                while (self.peekKeyword("elseif")) {
                    // Patch the previous jump_if_false to jump here
                    const elseif_start = @as(u16, @intCast(instructions.items.len));
                    instructions.items[jump_to_else_idx].operands[1] = elseif_start;

                    // Parse elseif condition
                    try self.expectKeyword("elseif");
                    self.skipWhitespace();
                    try self.expect('(');
                    self.skipWhitespace();
                    const elseif_cond_reg = try self.parseExpression(constants, instructions, 0);
                    self.skipWhitespace();
                    try self.expect(')');
                    self.skipWhitespace();
                    try self.expect('{');

                    // Jump to next condition if false
                    const next_jump_idx = instructions.items.len;
                    try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{elseif_cond_reg, 0, 0} });

                    // Parse elseif body
                    self.skipWhitespace();
                    while (self.peek() != '}') {
                        _ = try self.parseStatement(constants, instructions, functions);
                        self.skipWhitespace();
                    }
                    try self.expect('}');

                    // Jump over remaining elseif/else blocks
                    const skip_rest_idx = instructions.items.len;
                    try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{0, 0, 0} });
                    try jump_patches.append(self.allocator, skip_rest_idx);

                    // Update jump target for next iteration
                    jump_to_else_idx = next_jump_idx;
                    self.skipWhitespace();
                }

                // Handle final else clause
                if (self.peekKeyword("else")) {
                    // Patch the last jump_if_false to jump here
                    const final_else_start = @as(u16, @intCast(instructions.items.len));
                    instructions.items[jump_to_else_idx].operands[1] = final_else_start;

                    try self.expectKeyword("else");
                    self.skipWhitespace();
                    try self.expect('{');
                    self.skipWhitespace();
                    while (self.peek() != '}') {
                        _ = try self.parseStatement(constants, instructions, functions);
                        self.skipWhitespace();
                    }
                    try self.expect('}');
                } else {
                    // No else clause, patch jump_if_false to end
                    const end_pos = @as(u16, @intCast(instructions.items.len));
                    instructions.items[jump_to_else_idx].operands[1] = end_pos;
                }

                // Patch all jumps that skip to the end
                const after_all = @as(u16, @intCast(instructions.items.len));
                for (jump_patches.items) |patch_idx| {
                    instructions.items[patch_idx].operands[0] = after_all;
                }

                return 0;
            } else if (std.mem.eql(u8, ident, "return")) {
                // return expr
                self.skipWhitespace();
                const expr_reg = try self.parseExpression(constants, instructions, 0);
                try instructions.append(self.allocator, .{ .opcode = .ret, .operands = [_]u16{expr_reg, 0, 0} });
                return expr_reg;
            } else if (std.mem.eql(u8, ident, "require")) {
                // require "filename"
                self.skipWhitespace();
                try self.expect('(');
                self.skipWhitespace();
                try self.expect('"');

                const start = self.pos;
                while (self.pos < self.source.len and self.source[self.pos] != '"') {
                    self.pos += 1;
                }
                const filename = self.source[start..self.pos];
                try self.expect('"');
                try self.expect(')');

                // Use the new require_module opcode
                const module_reg: u16 = 0;
                const filename_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, filename) });
                try instructions.append(self.allocator, .{ .opcode = .require_module, .operands = [_]u16{module_reg, filename_idx, 0} });

                return module_reg;
            } else if (std.mem.eql(u8, ident, "for")) {
                // for i = start, end do ... end
                self.skipWhitespace();
                const var_name = try self.parseIdent();
                defer self.allocator.free(var_name);
                self.skipWhitespace();
                try self.expect('=');
                self.skipWhitespace();

                const start_reg = try self.parseExpression(constants, instructions, 0);
                self.skipWhitespace();
                try self.expect(',');
                self.skipWhitespace();
                const end_reg = try self.parseExpression(constants, instructions, 1);
                self.skipWhitespace();
                try self.expectKeyword("do");

                // Initialize loop variable
                const iter_reg: u16 = 2;
                try instructions.append(self.allocator, .{ .opcode = .for_init, .operands = [_]u16{iter_reg, start_reg, end_reg} });

                // Store iterator variable as local/global
                const var_name_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, var_name) });
                try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{iter_reg, var_name_idx, 0} });

                // Mark loop start
                const loop_start = @as(u16, @intCast(instructions.items.len));

                // Update the global variable with current iterator value at the start of each iteration
                try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{iter_reg, var_name_idx, 0} });

                // Parse loop body
                while (!self.peekKeyword("end")) {
                    _ = try self.parseStatement(constants, instructions, functions);
                    self.skipWhitespace();
                }
                try self.expectKeyword("end");

                // Add for_loop instruction (increment and check)
                try instructions.append(self.allocator, .{ .opcode = .for_loop, .operands = [_]u16{iter_reg, end_reg, loop_start} });

                return 0;
            } else if (std.mem.eql(u8, ident, "while")) {
                // while condition do ... end
                self.skipWhitespace();

                // Mark condition evaluation start
                const cond_start = @as(u16, @intCast(instructions.items.len));

                const cond_reg = try self.parseExpression(constants, instructions, 0);
                self.skipWhitespace();
                try self.expectKeyword("do");

                // Jump out of loop if condition is false
                const jump_out_idx = instructions.items.len;
                try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{cond_reg, 0, 0} }); // will patch later

                // Parse loop body
                while (!self.peekKeyword("end")) {
                    _ = try self.parseStatement(constants, instructions, functions);
                    self.skipWhitespace();
                }
                try self.expectKeyword("end");

                // Jump back to condition evaluation
                try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{cond_start, 0, 0} });

                // Patch the jump_if_false target (end of loop)
                const loop_end = @as(u16, @intCast(instructions.items.len));
                instructions.items[jump_out_idx].operands[1] = loop_end;

                return 0;
            } else if (std.mem.eql(u8, ident, "function")) {
                // function name(param1, param2) ... end
                self.skipWhitespace();
                const func_name = try self.parseIdent();
                defer self.allocator.free(func_name);

                self.skipWhitespace();
                try self.expect('(');
                self.skipWhitespace();

                // Parse parameters
                var param_count: u8 = 0;
                while (self.peek() != ')') {
                    if (param_count > 0) {
                        try self.expect(',');
                        self.skipWhitespace();
                    }
                    const param_name = try self.parseIdent();
                    defer self.allocator.free(param_name);
                    param_count += 1;
                    self.skipWhitespace();
                }
                try self.expect(')');
                self.skipWhitespace();

                // Parse function body
                var func_instructions: std.ArrayListUnmanaged(Instruction) = .{};
                defer func_instructions.deinit(self.allocator);
                var func_constants: std.ArrayListUnmanaged(ScriptValue) = .{};
                defer func_constants.deinit(self.allocator);

                while (!self.peekKeyword("end")) {
                    _ = try self.parseStatement(&func_constants, &func_instructions, functions);
                    self.skipWhitespace();
                }
                try self.expectKeyword("end");

                // Add return instruction if not present
                if (func_instructions.items.len == 0 or func_instructions.items[func_instructions.items.len - 1].opcode != .ret) {
                    try func_instructions.append(self.allocator, .{ .opcode = .ret, .operands = [_]u16{0, 0, 0} });
                }

                // Create function info
                const func_info = FunctionInfo{
                    .name = try self.allocator.dupe(u8, func_name),
                    .param_count = param_count,
                    .local_count = param_count, // simplified
                    .instructions = try self.allocator.dupe(Instruction, func_instructions.items),
                    .constants = try self.allocator.dupe(ScriptValue, func_constants.items),
                };

                const func_id = @as(u16, @intCast(functions.items.len));
                try functions.append(self.allocator, func_info);

                // Create closure and store as global
                const closure_reg: u16 = 0;
                try instructions.append(self.allocator, .{ .opcode = .closure, .operands = [_]u16{closure_reg, func_id, 0} });

                const name_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, func_name) });
                try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{closure_reg, name_idx, 0} });

                return 0;
            } else {
                // Check if it looks like a function call (has opening parenthesis)
                self.skipWhitespace();
                if (self.peek() == '(') {
                    // assume function call - first load the function, then call it
                    try self.expect('(');
                    self.skipWhitespace();

                    // Parse arguments (simplified - just handle first argument for now)
                    var arg_count: u16 = 0;
                    var first_arg_reg: u16 = 0;

                    if (self.peek() != ')') {
                        first_arg_reg = try self.parseExpression(constants, instructions, 0);
                        arg_count = 1;

                        // Skip additional arguments for now
                        while (self.peek() == ',') {
                            self.advance(); // skip comma
                            self.skipWhitespace();
                            _ = try self.parseExpression(constants, instructions, arg_count);
                            arg_count += 1;
                        }
                    }

                    try self.expect(')');

                    // Load the function into a register
                    const func_reg: u16 = 10; // use a high register to avoid conflicts
                    const func_name_idx = @as(u16, @intCast(constants.items.len));
                    try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                    try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{func_reg, func_name_idx, 0} });

                    // Try calling as closure first, fall back to built-in function call
                    try instructions.append(self.allocator, .{ .opcode = .call_closure, .operands = [_]u16{func_reg, first_arg_reg, arg_count} });

                    return func_reg; // return the register that will contain the result
                } else {
                    // Check if this is an assignment or array assignment
                    self.skipWhitespace();
                    if (self.peek() == '[') {
                        // Array assignment: arr[index] = value
                        self.advance(); // consume '['

                        // Load the array variable
                        const array_name_idx = @as(u16, @intCast(constants.items.len));
                        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                        const array_reg: u16 = 1;
                        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{array_reg, array_name_idx, 0} });

                        // Parse the index
                        const index_reg: u16 = 2;
                        _ = try self.parseExpression(constants, instructions, index_reg);

                        try self.expect(']');
                        self.skipWhitespace();
                        try self.expect('=');
                        self.skipWhitespace();

                        // Parse the value to assign
                        const value_reg: u16 = 3;
                        _ = try self.parseExpression(constants, instructions, value_reg);

                        // Generate array_set instruction
                        try instructions.append(self.allocator, .{ .opcode = .array_set, .operands = [_]u16{array_reg, index_reg, value_reg} });
                        return 0;
                    } else if (self.peek() == '=') {
                        // Regular assignment: var = expr
                        try self.expect('=');
                        self.skipWhitespace();
                        const expr_reg = try self.parseExpression(constants, instructions, 0);

                        // Store to global (simplified)
                        const name_idx = @as(u16, @intCast(constants.items.len));
                        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                        try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{expr_reg, name_idx, 0} });
                        return 0;
                    } else {
                        // Not a keyword or function call - restore position and parse as expression
                        self.pos = saved_pos;
                        const result_reg = try self.parseExpression(constants, instructions, 0);
                        return result_reg;
                    }
                }
            }
        } else {
            // expression statement
            const result_reg = try self.parseExpression(constants, instructions, 0);
            return result_reg;
        }
    }

    fn parseExpression(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg_start: u16) anyerror!u16 {
        var left_reg = try self.parseTerm(constants, instructions, reg_start);
        var next_reg: u16 = reg_start + 1;

        self.skipWhitespace(); // Skip whitespace after left operand

        while (self.peek()) |c| {
            if (c == '+') {
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, next_reg);
                next_reg += 1;
                const result_reg = next_reg;
                next_reg += 1;
                try instructions.append(self.allocator, .{ .opcode = .add, .operands = [_]u16{result_reg, left_reg, right_reg} });
                left_reg = result_reg;
                self.skipWhitespace();
            } else if (c == '-') {
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, next_reg);
                next_reg += 1;
                const result_reg = next_reg;
                next_reg += 1;
                try instructions.append(self.allocator, .{ .opcode = .sub, .operands = [_]u16{result_reg, left_reg, right_reg} });
                left_reg = result_reg;
                self.skipWhitespace();
            } else if (c == '=' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                // == operator
                self.advance();
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, next_reg);
                next_reg += 1;
                const result_reg = next_reg;
                next_reg += 1;
                try instructions.append(self.allocator, .{ .opcode = .eq, .operands = [_]u16{result_reg, left_reg, right_reg} });
                left_reg = result_reg;
                self.skipWhitespace();
            } else if (c == '!' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                // != operator
                self.advance();
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                const result_reg = reg_start + 2;
                try instructions.append(self.allocator, .{ .opcode = .ne, .operands = [_]u16{result_reg, left_reg, right_reg} });
                return result_reg;
            } else if (c == '<') {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                    // <= operator
                    self.advance();
                    self.advance();
                    self.skipWhitespace();
                    const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                    const result_reg = reg_start + 2;
                    try instructions.append(self.allocator, .{ .opcode = .le, .operands = [_]u16{result_reg, left_reg, right_reg} });
                    return result_reg;
                } else {
                    // < operator
                    self.advance();
                    self.skipWhitespace();
                    const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                    const result_reg = reg_start + 2;
                    try instructions.append(self.allocator, .{ .opcode = .lt, .operands = [_]u16{result_reg, left_reg, right_reg} });
                    return result_reg;
                }
            } else if (c == '>') {
                if (self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                    // >= operator
                    self.advance();
                    self.advance();
                    self.skipWhitespace();
                    const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                    const result_reg = reg_start + 2;
                    try instructions.append(self.allocator, .{ .opcode = .ge, .operands = [_]u16{result_reg, left_reg, right_reg} });
                    return result_reg;
                } else {
                    // > operator
                    self.advance();
                    self.skipWhitespace();
                    const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                    const result_reg = reg_start + 2;
                    try instructions.append(self.allocator, .{ .opcode = .gt, .operands = [_]u16{result_reg, left_reg, right_reg} });
                    return result_reg;
                }
            } else if (c == '.' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '.') {
                // .. operator for string concatenation
                self.advance();
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                const result_reg = reg_start + 2;
                try instructions.append(self.allocator, .{ .opcode = .concat, .operands = [_]u16{result_reg, left_reg, right_reg} });
                return result_reg;
            } else if (c == '%') {
                // % operator for modulo
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                const result_reg = reg_start + 2;
                try instructions.append(self.allocator, .{ .opcode = .mod, .operands = [_]u16{result_reg, left_reg, right_reg} });
                return result_reg;
            } else if (c == '&' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '&') {
                // && operator for logical and
                self.advance();
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                const result_reg = reg_start + 2;
                try instructions.append(self.allocator, .{ .opcode = .logical_and, .operands = [_]u16{result_reg, left_reg, right_reg} });
                return result_reg;
            } else if (c == '|' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '|') {
                // || operator for logical or
                self.advance();
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                const result_reg = reg_start + 2;
                try instructions.append(self.allocator, .{ .opcode = .logical_or, .operands = [_]u16{result_reg, left_reg, right_reg} });
                return result_reg;
            } else {
                break;
            }
        }

        return left_reg;
    }

    fn parseTerm(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg: u16) anyerror!u16 {
        if (self.peek() == '!') {
            // Logical NOT operator
            self.advance();
            self.skipWhitespace();
            const operand_reg = reg + 1;
            _ = try self.parseTerm(constants, instructions, operand_reg);
            try instructions.append(self.allocator, .{ .opcode = .logical_not, .operands = [_]u16{reg, operand_reg, 0} });
            return reg;
        } else if (self.peekNumber()) {
            const num = try self.parseNumber();
            const const_idx = @as(u16, @intCast(constants.items.len));
            try constants.append(self.allocator, .{ .number = num });
            try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{reg, const_idx, 0} });
            return reg;
        } else if (self.peek() == '"') {
            // String literal
            const str = try self.parseString();
            defer self.allocator.free(str);
            const const_idx = @as(u16, @intCast(constants.items.len));
            try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, str) });
            try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{reg, const_idx, 0} });
            return reg;
        } else if (self.peek() == '{') {
            // Table literal
            self.advance(); // consume '{'
            self.skipWhitespace();

            // Create empty table
            try instructions.append(self.allocator, .{ .opcode = .new_table, .operands = [_]u16{reg, 0, 0} });

            // Parse key-value pairs (simplified)
            while (self.peek() != '}') {
                // Parse key
                if (!self.peekIdent()) break;
                const key_name = try self.parseIdent();
                defer self.allocator.free(key_name);

                self.skipWhitespace();
                try self.expect('=');
                self.skipWhitespace();

                // Parse value
                const value_reg = reg + 1;
                _ = try self.parseExpression(constants, instructions, value_reg);

                // Store key-value pair
                const key_const_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, key_name) });
                const key_reg = reg + 2;
                try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{key_reg, key_const_idx, 0} });
                try instructions.append(self.allocator, .{ .opcode = .set_table, .operands = [_]u16{reg, key_reg, value_reg} });

                self.skipWhitespace();
                if (self.peek() == ',') {
                    self.advance();
                    self.skipWhitespace();
                } else {
                    break;
                }
            }

            try self.expect('}');
            return reg;
        } else if (self.peek() == '[') {
            // Array literal
            self.advance(); // consume '['
            self.skipWhitespace();

            // Create empty array
            try instructions.append(self.allocator, .{ .opcode = .new_array, .operands = [_]u16{reg, 0, 0} });

            // Parse array elements
            while (self.peek() != ']') {
                // Parse element value
                const value_reg = reg + 1;
                _ = try self.parseExpression(constants, instructions, value_reg);

                // Push to array
                try instructions.append(self.allocator, .{ .opcode = .array_push, .operands = [_]u16{reg, value_reg, 0} });

                self.skipWhitespace();
                if (self.peek() == ',') {
                    self.advance();
                    self.skipWhitespace();
                } else {
                    break;
                }
            }

            try self.expect(']');
            return reg;
        } else if (self.peekIdent()) {
            // For now, assume it's a function call like print(expr)
            const ident = try self.parseIdent();
            defer self.allocator.free(ident);
            if (std.mem.eql(u8, ident, "print")) {
                try self.expect('(');
                self.skipWhitespace();
                const arg_reg = try self.parseExpression(constants, instructions, reg + 1);
                try self.expect(')');
                // Add print call
                const print_const_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, "print") });
                try instructions.append(self.allocator, .{ .opcode = .call, .operands = [_]u16{print_const_idx, arg_reg, 1} });
            } else {
                // Check for property access (obj.property)
                if (self.peek() == '.') {
                    self.advance(); // consume '.'

                    if (!self.peekIdent()) {
                        std.debug.print("Parse error: expected property name after '.'\n", .{});
                        return ScriptError.UnexpectedToken;
                    }

                    const property = try self.parseIdent();
                    defer self.allocator.free(property);

                    // Load the object into a register
                    const obj_name_idx = @as(u16, @intCast(constants.items.len));
                    try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                    try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{reg, obj_name_idx, 0} });

                    // Load the property name into a constant
                    const prop_name_idx = @as(u16, @intCast(constants.items.len));
                    try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, property) });

                    // Check if this is a function call (obj.method())
                    if (self.peek() == '(') {
                        // This is a method call - handle it as a function call
                        self.advance(); // consume '('
                        self.skipWhitespace();

                        // Create the full method name (obj.method)
                        const full_name = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ident, property});
                        defer self.allocator.free(full_name);

                        // Parse arguments properly
                        var arg_count: u16 = 0;
                        var arg_reg = reg + 1;

                        while (self.peek() != ')') {
                            _ = try self.parseExpression(constants, instructions, arg_reg);
                            arg_count += 1;
                            arg_reg += 1;

                            self.skipWhitespace();
                            if (self.peek() == ',') {
                                self.advance(); // consume ','
                                self.skipWhitespace();
                            } else {
                                break;
                            }
                        }

                        try self.expect(')');

                        // Call the function
                        const func_name_idx = @as(u16, @intCast(constants.items.len));
                        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, full_name) });
                        try instructions.append(self.allocator, .{ .opcode = .call, .operands = [_]u16{func_name_idx, reg + 1, arg_count} });
                    } else {
                        // This is property access - use get_table opcode
                        const prop_reg = reg + 1;
                        try instructions.append(self.allocator, .{ .opcode = .load_const, .operands = [_]u16{prop_reg, prop_name_idx, 0} });
                        try instructions.append(self.allocator, .{ .opcode = .get_table, .operands = [_]u16{reg, reg, prop_reg} });
                    }

                    return reg;
                } else {
                    // Check for array indexing (var[index])
                    if (self.peek() == '[') {
                        self.advance(); // consume '['

                        // Load the array variable into a register
                        const array_name_idx = @as(u16, @intCast(constants.items.len));
                        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{reg, array_name_idx, 0} });

                        // Parse the index expression
                        const index_reg = reg + 1;
                        _ = try self.parseExpression(constants, instructions, index_reg);

                        try self.expect(']');

                        // Generate array_get instruction
                        try instructions.append(self.allocator, .{ .opcode = .array_get, .operands = [_]u16{reg, reg, index_reg} });
                        return reg;
                    } else {
                        // simple variable
                        const name_idx = @as(u16, @intCast(constants.items.len));
                        try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                        try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{reg, name_idx, 0} });
                        return reg;
                    }
                }
            }
        } else {
            std.debug.print("Parse error: unexpected token at position {d}\n", .{self.pos});
            return ScriptError.UnexpectedToken;
        }
        unreachable;
    }

    fn parseNumber(self: *Parser) !f64 {
        const start = self.pos;
        while (self.pos < self.source.len and (std.ascii.isDigit(self.source[self.pos]) or self.source[self.pos] == '.')) {
            self.pos += 1;
        }
        const num_str = self.source[start..self.pos];
        return std.fmt.parseFloat(f64, num_str);
    }

    fn parseIdent(self: *Parser) ![]u8 {
        const start = self.pos;
        while (self.pos < self.source.len and (std.ascii.isAlphabetic(self.source[self.pos]) or self.source[self.pos] == '_')) {
            self.pos += 1;
        }
        return try self.allocator.dupe(u8, self.source[start..self.pos]);
    }

    fn parseString(self: *Parser) ![]u8 {
        try self.expect('"');
        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\') {
                // Simple escape sequence handling
                self.pos += 1;
            }
            self.pos += 1;
        }
        const str = self.source[start..self.pos];
        try self.expect('"');
        return try self.allocator.dupe(u8, str);
    }

    fn peekNumber(self: *Parser) bool {
        return self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos]);
    }

    fn peekIdent(self: *Parser) bool {
        return self.pos < self.source.len and std.ascii.isAlphabetic(self.source[self.pos]);
    }

    fn peek(self: *Parser) ?u8 {
        if (self.pos < self.source.len) return self.source[self.pos];
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
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isWhitespace(c)) {
                self.advance();
            } else if (c == '-' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '-') {
                // Skip line comment
                self.advance(); // skip first -
                self.advance(); // skip second -
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.advance();
                }
                if (self.pos < self.source.len and self.source[self.pos] == '\n') {
                    self.advance(); // skip the newline
                }
            } else {
                break;
            }
        }
    }

    fn createError(self: *Parser, message: []const u8) ParseError {
        return ParseError{
            .message = message,
            .line = self.line,
            .column = self.column,
            .position = self.pos,
        };
    }

    fn expect(self: *Parser, char: u8) !void {
        if (self.peek() == char) {
            self.advance();
        } else {
            std.log.err("Parse error at line {}, column {}: expected '{}', found '{?c}'", .{self.line, self.column, char, self.peek()});
            return error.ParseError;
        }
    }

    fn peekKeyword(self: *Parser, keyword: []const u8) bool {
        const start = self.pos;
        defer self.pos = start; // reset position

        self.skipWhitespace();
        if (!self.peekIdent()) return false;

        const ident = self.parseIdent() catch return false;
        defer self.allocator.free(ident);
        return std.mem.eql(u8, ident, keyword);
    }

    fn expectKeyword(self: *Parser, keyword: []const u8) !void {
        self.skipWhitespace();
        const ident = self.parseIdent() catch {
            std.log.err("Parse error at line {}, column {}: expected keyword '{s}', found '{?c}'", .{self.line, self.column, keyword, self.peek()});
            return error.ParseError;
        };
        defer self.allocator.free(ident);
        if (!std.mem.eql(u8, ident, keyword)) {
            std.log.err("Parse error at line {}, column {}: expected keyword '{s}', found '{s}'", .{self.line, self.column, keyword, ident});
            return error.ParseError;
        }
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
