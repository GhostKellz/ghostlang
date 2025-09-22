const std = @import("std");

// By convention, root.zig is the root source file when making a library.

pub const ScriptValueType = enum {
    nil,
    boolean,
    number,
    string,
    function,
    table,
};

pub const ScriptValue = union(ScriptValueType) {
    nil: void,
    boolean: bool,
    number: f64,
    string: []const u8,
    function: *const fn (args: []const ScriptValue) ScriptValue,
    table: std.StringHashMap(ScriptValue),

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
        _ = source; // TODO: parse source
        // For now, hardcode a simple script: compute 3 + 4 and print it
        const constants = [_]ScriptValue{ .{ .number = 3 }, .{ .number = 4 }, .{ .string = "print" } };
        const code = [_]Instruction{
            .{ .opcode = .load_const, .operands = [_]u16{ 0, 0, 0 } }, // r0 = 3
            .{ .opcode = .load_const, .operands = [_]u16{ 1, 1, 0 } }, // r1 = 4
            .{ .opcode = .add, .operands = [_]u16{ 2, 0, 1 } }, // r2 = r0 + r1
            .{ .opcode = .call, .operands = [_]u16{ 2, 2, 1 } }, // call "print" with r2 (1 arg)
            .{ .opcode = .ret, .operands = [_]u16{ 2, 0, 0 } }, // return r2
        };
        const constants_copy = try self.config.allocator.dupe(ScriptValue, &constants);
        const code_copy = try self.config.allocator.dupe(Instruction, &code);
        return Script{
            .engine = self,
            .vm = VM.init(self.config.allocator, code_copy, constants_copy, self),
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
    add,
    sub,
    mul,
    div,
    call,
    ret,
};

pub const Instruction = struct {
    opcode: Opcode,
    operands: [3]u16, // for simplicity, up to 3 operands
};

pub const VM = struct {
    registers: [256]ScriptValue,
    pc: usize,
    code: []const Instruction,
    constants: []const ScriptValue,
    allocator: std.mem.Allocator,
    engine: *ScriptEngine,

    pub fn init(allocator: std.mem.Allocator, code: []const Instruction, constants: []const ScriptValue, engine: *ScriptEngine) VM {
        return VM{
            .registers = undefined,
            .pc = 0,
            .code = code,
            .constants = constants,
            .allocator = allocator,
            .engine = engine,
        };
    }

    pub fn run(self: *VM) !ScriptValue {
        while (self.pc < self.code.len) {
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
        self.engine.config.allocator.free(self.vm.constants);
        self.engine.config.allocator.free(self.vm.code);
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
