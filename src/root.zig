const std = @import("std");

// By convention, root.zig is the root source file when making a library.

pub const ScriptValueType = enum {
    nil,
    boolean,
    number,
    string,
    function,
    closure,
    table,
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

pub const ScriptValue = union(ScriptValueType) {
    nil: void,
    boolean: bool,
    number: f64,
    string: []const u8,
    function: *const fn (args: []const ScriptValue) ScriptValue,
    closure: Closure,
    table: std.StringHashMap(ScriptValue),

    pub fn deinit(self: *ScriptValue, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .closure => |*c| c.deinit(allocator),
            .table => |*t| {
                var it = t.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.deinit(allocator);
                }
                t.deinit();
            },
            else => {},
        }
    }

    pub fn copy(self: ScriptValue, allocator: std.mem.Allocator) !ScriptValue {
        switch (self) {
            .string => |s| return .{ .string = try allocator.dupe(u8, s) },
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
            else => return self, // numbers, booleans, nil, functions don't need copying
        }
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
        const parsed = try parser.parse();
        return Script{
            .engine = self,
            .vm = VM.init(self.config.allocator, parsed.instructions, parsed.constants, parsed.functions, self),
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
};

pub const Opcode = enum(u8) {
    nop,
    load_const,
    load_global,
    store_global,
    load_local,
    store_local,
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
    for_init,
    for_loop,
    while_loop,
    file_read,
    file_write,
    file_exists,
    file_delete,
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
    globals: std.StringHashMap(ScriptValue),
    pc: usize,
    code: []const Instruction,
    constants: []const ScriptValue,
    functions: []const FunctionInfo,
    allocator: std.mem.Allocator,
    engine: *ScriptEngine,

    pub fn init(allocator: std.mem.Allocator, code: []const Instruction, constants: []const ScriptValue, functions: []const FunctionInfo, engine: *ScriptEngine) VM {
        var vm = VM{
            .registers = undefined,
            .locals = undefined,
            .globals = std.StringHashMap(ScriptValue).init(allocator),
            .pc = 0,
            .code = code,
            .constants = constants,
            .functions = functions,
            .allocator = allocator,
            .engine = engine,
        };

        // Initialize registers and locals to nil
        for (&vm.registers) |*reg| {
            reg.* = .{ .nil = {} };
        }
        for (&vm.locals) |*local| {
            local.* = .{ .nil = {} };
        }

        return vm;
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
    }

    pub fn run(self: *VM) !ScriptValue {
        while (self.pc < self.code.len) {
            const instr = self.code[self.pc];
            switch (instr.opcode) {
                .nop => {},
                .load_const => {
                    const reg = instr.operands[0];
                    const const_idx = instr.operands[1];
                    // Clean up the destination register before overwriting
                    self.registers[reg].deinit(self.allocator);
                    // Make a copy of the constant to avoid double-free issues
                    self.registers[reg] = try self.constants[const_idx].copy(self.allocator);
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
                        if (self.globals.get(name.string)) |value| {
                            self.registers[reg] = value;
                        } else if (self.engine.globals.get(name.string)) |value| {
                            self.registers[reg] = value;
                        } else {
                            return error.UndefinedVariable;
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
                    self.registers[reg] = self.locals[local_idx];
                },
                .store_local => {
                    const reg = instr.operands[0];
                    const local_idx = instr.operands[1];
                    self.locals[local_idx] = self.registers[reg];
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
                            .globals = std.StringHashMap(ScriptValue).init(self.allocator),
                            .pc = 0,
                            .code = func.instructions,
                            .constants = func.constants,
                            .functions = &[_]FunctionInfo{}, // empty functions to avoid double-free
                            .allocator = self.allocator,
                            .engine = self.engine,
                        };

                        // Initialize registers and locals
                        for (&func_vm.registers) |*reg| {
                            reg.* = .{ .nil = {} };
                        }
                        for (&func_vm.locals) |*local| {
                            local.* = .{ .nil = {} };
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
                            try module_table.put(content_key, .{ .string = content_value });

                            self.registers[dest_reg] = .{ .table = module_table };
                        } else |err| {
                            switch (err) {
                                error.FileNotFound => {
                                    // If file doesn't exist, create a basic module table
                                    var module_table = std.StringHashMap(ScriptValue).init(self.allocator);
                                    const version_key = try self.allocator.dupe(u8, "version");
                                    try module_table.put(version_key, .{ .string = try self.allocator.dupe(u8, "1.0.0") });
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

                    if (val_a == .string and val_b == .string) {
                        // Clean up the destination register before overwriting
                        self.registers[dest].deinit(self.allocator);
                        const result = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{val_a.string, val_b.string});
                        self.registers[dest] = .{ .string = result };
                    } else {
                        return error.TypeError;
                    }
                },
                .strlen => {
                    const dest = instr.operands[0];
                    const str_reg = instr.operands[1];
                    const str_val = self.registers[str_reg];

                    if (str_val == .string) {
                        self.registers[dest] = .{ .number = @floatFromInt(str_val.string.len) };
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

                    if (str_val == .string and start_val == .number) {
                        // Clean up the destination register before overwriting
                        self.registers[dest].deinit(self.allocator);
                        const start_idx = @max(0, @min(@as(usize, @intFromFloat(start_val.number)), str_val.string.len));
                        const substr = str_val.string[start_idx..];
                        const result = try self.allocator.dupe(u8, substr);
                        self.registers[dest] = .{ .string = result };
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

                    if (filename_val == .string) {
                        // Clean up the destination register before overwriting
                        self.registers[dest_reg].deinit(self.allocator);

                        // Read file contents
                        const file_content = std.fs.cwd().readFileAlloc(filename_val.string, self.allocator, .unlimited) catch |err| switch (err) {
                            error.FileNotFound => try self.allocator.dupe(u8, ""),
                            error.AccessDenied => try self.allocator.dupe(u8, ""),
                            else => try self.allocator.dupe(u8, ""),
                        };
                        self.registers[dest_reg] = .{ .string = file_content };
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

                    if (filename_val == .string and content_val == .string) {
                        // Clean up the result register before overwriting
                        self.registers[result_reg].deinit(self.allocator);

                        // Write file contents
                        const success = blk: {
                            std.fs.cwd().writeFile(.{ .sub_path = filename_val.string, .data = content_val.string }) catch {
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

                    if (filename_val == .string) {
                        // Clean up the destination register before overwriting
                        self.registers[dest_reg].deinit(self.allocator);

                        // Check if file exists
                        const exists = blk: {
                            std.fs.cwd().access(filename_val.string, .{}) catch {
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

                    if (filename_val == .string) {
                        // Clean up the result register before overwriting
                        self.registers[result_reg].deinit(self.allocator);

                        // Delete file
                        const success = blk: {
                            std.fs.cwd().deleteFile(filename_val.string) catch {
                                break :blk false;
                            };
                            break :blk true;
                        };
                        self.registers[result_reg] = .{ .boolean = success };
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

        // Clean up constants
        for (self.vm.constants) |*constant| {
            var mut_constant = constant.*;
            mut_constant.deinit(self.engine.config.allocator);
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

                // For now, treat locals as globals (simplified implementation)
                // TODO: Implement proper local scope management
                const name_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, var_name) });
                try instructions.append(self.allocator, .{ .opcode = .store_global, .operands = [_]u16{expr_reg, name_idx, 0} });
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
                const jump_to_else_idx = instructions.items.len;
                try instructions.append(self.allocator, .{ .opcode = .jump_if_false, .operands = [_]u16{cond_reg, 0, 0} }); // will patch later

                // Parse if body
                _ = try self.parseStatement(constants, instructions, functions);
                try self.expect('}');

                // Jump over else block
                const jump_over_else_idx = instructions.items.len;
                try instructions.append(self.allocator, .{ .opcode = .jump, .operands = [_]u16{0, 0, 0} }); // will patch later

                // Patch the jump_if_false target (start of else block)
                const else_start = @as(u16, @intCast(instructions.items.len));
                instructions.items[jump_to_else_idx].operands[1] = else_start;

                // Check for else clause
                self.skipWhitespace();
                if (self.peekKeyword("else")) {
                    try self.expectKeyword("else");
                    self.skipWhitespace();
                    try self.expect('{');
                    _ = try self.parseStatement(constants, instructions, functions);
                    try self.expect('}');
                }

                // Patch the jump over else
                const after_else = @as(u16, @intCast(instructions.items.len));
                instructions.items[jump_over_else_idx].operands[0] = after_else;

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
                    // Check if this is an assignment (var = expr)
                    self.skipWhitespace();
                    if (self.peek() == '=') {
                        // This is an assignment: var = expr
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
        const left_reg = try self.parseTerm(constants, instructions, reg_start);

        self.skipWhitespace(); // Skip whitespace after left operand

        while (self.peek()) |c| {
            if (c == '+') {
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                const result_reg = reg_start + 2;
                try instructions.append(self.allocator, .{ .opcode = .add, .operands = [_]u16{result_reg, left_reg, right_reg} });
                return result_reg;
            } else if (c == '-') {
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                const result_reg = reg_start + 2;
                try instructions.append(self.allocator, .{ .opcode = .sub, .operands = [_]u16{result_reg, left_reg, right_reg} });
                return result_reg;
            } else if (c == '=' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '=') {
                // == operator
                self.advance();
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                const result_reg = reg_start + 2;
                try instructions.append(self.allocator, .{ .opcode = .eq, .operands = [_]u16{result_reg, left_reg, right_reg} });
                return result_reg;
            } else if (c == '<') {
                self.advance();
                self.skipWhitespace();
                const right_reg = try self.parseTerm(constants, instructions, reg_start + 1);
                const result_reg = reg_start + 2;
                try instructions.append(self.allocator, .{ .opcode = .lt, .operands = [_]u16{result_reg, left_reg, right_reg} });
                return result_reg;
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
            } else {
                break;
            }
        }

        return left_reg;
    }

    fn parseTerm(self: *Parser, constants: *std.ArrayListUnmanaged(ScriptValue), instructions: *std.ArrayListUnmanaged(Instruction), reg: u16) anyerror!u16 {
        if (self.peekNumber()) {
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
                // variable
                const name_idx = @as(u16, @intCast(constants.items.len));
                try constants.append(self.allocator, .{ .string = try self.allocator.dupe(u8, ident) });
                try instructions.append(self.allocator, .{ .opcode = .load_global, .operands = [_]u16{reg, name_idx, 0} });
                return reg;
            }
        } else {
            return error.ParseError;
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
        while (self.pos < self.source.len and std.ascii.isWhitespace(self.source[self.pos])) {
            self.advance();
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
