//! GhostLang Bytecode
//!
//! This module defines the bytecode instructions used by the GhostLang VM.
//! The VM is a register-based virtual machine with up to 256 registers.

const std = @import("std");

/// Bytecode opcodes for the GhostLang VM.
/// Each opcode represents a single VM instruction.
pub const Opcode = enum(u8) {
    /// No operation
    nop,
    /// Move value between registers: MOVE dest, src
    move,
    /// Load constant into register: LOAD_CONST dest, const_idx
    load_const,
    /// Load global variable: LOAD_GLOBAL dest, name_idx
    load_global,
    /// Store to global variable: STORE_GLOBAL name_idx, src
    store_global,
    /// Create new table: NEW_TABLE dest
    new_table,
    /// Create new array: NEW_ARRAY dest
    new_array,
    /// Set table field: TABLE_SET_FIELD table, key, value
    table_set_field,
    /// Get table field: TABLE_GET_FIELD dest, table, key
    table_get_field,
    /// Resolve method on table: RESOLVE_METHOD dest, table, method_name
    resolve_method,
    /// Set table index: TABLE_SET_INDEX table, index, value
    table_set_index,
    /// Get table index: TABLE_GET_INDEX dest, table, index
    table_get_index,
    /// Append to array: ARRAY_APPEND array, value
    array_append,
    /// Initialize iterator: ITERATOR_INIT dest, iterable
    iterator_init,
    /// Advance iterator: ITERATOR_NEXT dest, iterator
    iterator_next,
    /// Unpack iterator values: ITERATOR_UNPACK dest, iterator, count
    iterator_unpack,
    /// Collect varargs: VARARG_COLLECT dest, start, count
    vararg_collect,
    /// Add: ADD dest, a, b
    add,
    /// Subtract: SUB dest, a, b
    sub,
    /// Multiply: MUL dest, a, b
    mul,
    /// Divide: DIV dest, a, b
    div,
    /// Modulo: MOD dest, a, b
    mod,
    /// Concatenate strings: CONCAT dest, a, b
    concat,
    /// Equal: EQ dest, a, b
    eq,
    /// Not equal: NEQ dest, a, b
    neq,
    /// Less than: LT dest, a, b
    lt,
    /// Greater than: GT dest, a, b
    gt,
    /// Less than or equal: LTE dest, a, b
    lte,
    /// Greater than or equal: GTE dest, a, b
    gte,
    /// Logical AND: AND dest, a, b
    and_op,
    /// Logical OR: OR dest, a, b
    or_op,
    /// Logical NOT: NOT dest, src
    not_op,
    /// Begin new scope
    begin_scope,
    /// End current scope
    end_scope,
    /// Call function: CALL dest, func, arg_start, arg_count
    call,
    /// Call value as function: CALL_VALUE dest, value, arg_start, arg_count
    call_value,
    /// Unconditional jump: JUMP offset
    jump,
    /// Jump if condition is false: JUMP_IF_FALSE cond, offset
    jump_if_false,
    /// Return with value: RETURN_VALUE src
    return_value,
    /// Return without value
    ret,
};

/// A single bytecode instruction.
/// Contains an opcode and up to 3 operands.
pub const Instruction = struct {
    opcode: Opcode,
    operands: [3]u16, // for simplicity, up to 3 operands
    extra: u16 = 0,

    /// Create a no-operation instruction.
    pub fn nop() Instruction {
        return .{ .opcode = .nop, .operands = .{ 0, 0, 0 } };
    }

    /// Create a move instruction.
    pub fn move(dest: u16, src: u16) Instruction {
        return .{ .opcode = .move, .operands = .{ dest, src, 0 } };
    }

    /// Create a load constant instruction.
    pub fn loadConst(dest: u16, const_idx: u16) Instruction {
        return .{ .opcode = .load_const, .operands = .{ dest, const_idx, 0 } };
    }

    /// Create a load global instruction.
    pub fn loadGlobal(dest: u16, name_idx: u16) Instruction {
        return .{ .opcode = .load_global, .operands = .{ dest, name_idx, 0 } };
    }

    /// Create a store global instruction.
    pub fn storeGlobal(name_idx: u16, src: u16) Instruction {
        return .{ .opcode = .store_global, .operands = .{ name_idx, src, 0 } };
    }

    /// Create an add instruction.
    pub fn add(dest: u16, a: u16, b: u16) Instruction {
        return .{ .opcode = .add, .operands = .{ dest, a, b } };
    }

    /// Create a call instruction.
    pub fn call(dest: u16, func: u16, arg_start: u16, arg_count: u16) Instruction {
        return .{ .opcode = .call, .operands = .{ dest, func, arg_start }, .extra = arg_count };
    }

    /// Create a jump instruction.
    pub fn jump(offset: u16) Instruction {
        return .{ .opcode = .jump, .operands = .{ offset, 0, 0 } };
    }

    /// Create a conditional jump instruction.
    pub fn jumpIfFalse(cond: u16, offset: u16) Instruction {
        return .{ .opcode = .jump_if_false, .operands = .{ cond, offset, 0 } };
    }

    /// Create a return value instruction.
    pub fn returnValue(src: u16) Instruction {
        return .{ .opcode = .return_value, .operands = .{ src, 0, 0 } };
    }

    /// Create a return (void) instruction.
    pub fn ret() Instruction {
        return .{ .opcode = .ret, .operands = .{ 0, 0, 0 } };
    }
};

/// Syntax tree node kind for AST representation.
pub const SyntaxNodeKind = enum {
    root,
    instruction,
    constant,
};

/// A node in the syntax tree.
pub const SyntaxNode = struct {
    kind: SyntaxNodeKind,
    opcode: ?Opcode,
    instruction_index: ?usize,
    constant_index: ?usize,
};

/// Syntax tree built from bytecode instructions.
/// Used for analysis and transformation passes.
pub const SyntaxTree = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(SyntaxNode),
    instruction_count: usize,
    constant_count: usize,

    /// Initialize a syntax tree from compiled instructions.
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

    /// Free the syntax tree resources.
    pub fn deinit(self: *SyntaxTree) void {
        self.nodes.deinit(self.allocator);
        self.nodes = .{};
        self.instruction_count = 0;
        self.constant_count = 0;
    }

    /// Get the root node of the tree.
    pub fn root(self: *const SyntaxTree) ?*const SyntaxNode {
        if (self.nodes.items.len == 0) return null;
        return &self.nodes.items[0];
    }

    /// Get the number of nodes in the tree.
    pub fn nodeCount(self: *const SyntaxTree) usize {
        return self.nodes.items.len;
    }
};

test "Instruction creation" {
    const instr = Instruction.add(0, 1, 2);
    try std.testing.expectEqual(Opcode.add, instr.opcode);
    try std.testing.expectEqual(@as(u16, 0), instr.operands[0]);
    try std.testing.expectEqual(@as(u16, 1), instr.operands[1]);
    try std.testing.expectEqual(@as(u16, 2), instr.operands[2]);
}

test "SyntaxTree initialization" {
    const allocator = std.testing.allocator;
    const instructions = [_]Instruction{
        Instruction.loadConst(0, 0),
        Instruction.loadConst(1, 1),
        Instruction.add(2, 0, 1),
        Instruction.ret(),
    };

    var tree = try SyntaxTree.initFromInstructions(allocator, &instructions, 2);
    defer tree.deinit();

    // 1 root + 4 instructions + 2 constants = 7 nodes
    try std.testing.expectEqual(@as(usize, 7), tree.nodeCount());
    try std.testing.expectEqual(@as(usize, 4), tree.instruction_count);
    try std.testing.expectEqual(@as(usize, 2), tree.constant_count);
}
