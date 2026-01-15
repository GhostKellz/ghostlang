const std = @import("std");
const ghostlang = @import("ghostlang");

const max_script_size: usize = 4 * 1024 * 1024; // 4 MiB safety cap

pub fn main(init: std.process.Init) !void {
    var exit_code: u8 = 0;
    defer if (exit_code != 0) std.process.exit(exit_code);

    const allocator = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        try printUsage(if (args.len > 0) args[0] else "ghostlang");
        exit_code = 1;
        return;
    }

    const script_path = args[1];

    const source = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        script_path,
        allocator,
        std.Io.Limit.limited(max_script_size),
    ) catch |err| {
        reportIoError(script_path, err) catch {};
        exit_code = 1;
        return;
    };
    defer allocator.free(source);

    const config = ghostlang.EngineConfig{ .allocator = allocator };
    var engine = ghostlang.ScriptEngine.create(config) catch |err| {
        reportEngineError("Failed to initialize engine", err) catch {};
        exit_code = 1;
        return;
    };
    defer engine.deinit();

    if (engine.registerFunction("print", printFunction)) |_| {} else |err| {
        reportEngineError("Failed to register print function", err) catch {};
        exit_code = 1;
        return;
    }

    var script = engine.loadScript(source) catch |err| {
        reportLoadError(&engine, script_path, err) catch {};
        exit_code = 1;
        return;
    };
    defer script.deinit();

    var result = script.run() catch |err| {
        reportRuntimeError(&engine, &script, script_path, err) catch {};
        exit_code = 1;
        return;
    };
    defer result.deinit(engine.tracked_allocator);

    var buf: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buf);
    stdout.interface.writeAll("Result: ") catch {};
    writeValueDebug(result);
    stdout.interface.writeAll("\n") catch {};
    stdout.interface.flush() catch {};
}

fn printUsage(exe_name: []const u8) !void {
    std.debug.print("Usage: {s} <script.gza>\n", .{exe_name});
}

fn reportIoError(path: []const u8, err: anyerror) !void {
    std.debug.print("error: failed to read '{s}': {s}\n", .{ path, @errorName(err) });
}

fn reportEngineError(msg: []const u8, err: anyerror) !void {
    std.debug.print("error: {s}: {s}\n", .{ msg, @errorName(err) });
}

fn reportLoadError(engine: *ghostlang.ScriptEngine, path: []const u8, err: anyerror) !void {
    std.debug.print("error: failed to load '{s}': {s}\n", .{ path, @errorName(err) });
    const diagnostics = engine.getDiagnostics();
    for (diagnostics) |diag| {
        std.debug.print("  {s}:{d}:{d}: {s}: {s}\n", .{
            path,
            diag.line,
            diag.column,
            severityLabel(diag.severity),
            diag.message,
        });
    }
}

fn reportRuntimeError(engine: *ghostlang.ScriptEngine, script: ?*ghostlang.Script, path: []const u8, err: anyerror) !void {
    std.debug.print("error: script '{s}' failed: {s}\n", .{ path, @errorName(err) });

    const memory_related = err == ghostlang.ExecutionError.MemoryLimitExceeded or err == ghostlang.ExecutionError.OutOfMemory;
    if (!memory_related or script == null) return;

    var buffer = std.array_list.Managed(u8).init(engine.config.allocator);
    defer buffer.deinit();

    const Writer = struct {
        list: *std.array_list.Managed(u8),

        pub const Error = std.mem.Allocator.Error;

        pub fn writeAll(self: @This(), bytes: []const u8) Error!void {
            try self.list.appendSlice(bytes);
        }

        pub fn print(self: @This(), comptime fmt: []const u8, args: anytype) Error!void {
            const ArgsType = @TypeOf(args);
            const args_type_info = @typeInfo(ArgsType);
            if (args_type_info != .@"struct") {
                @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
            }

            // Use bufPrint with a temporary buffer, then append
            var buf: [4096]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, fmt, args) catch |e| switch (e) {
                error.NoSpaceLeft => {
                    // If the buffer is too small, use allocPrint instead
                    const allocator = self.list.allocator;
                    const dynamic = try std.fmt.allocPrint(allocator, fmt, args);
                    defer allocator.free(dynamic);
                    try self.writeAll(dynamic);
                    return;
                },
            };
            try self.writeAll(formatted);
        }
    };
    const writer = Writer{ .list = &buffer };

    const wrote = try script.?.writeMemorySummary(writer);
    if (!wrote or buffer.items.len == 0) return;

    std.debug.print("  memory context:\n{s}", .{buffer.items});
    std.debug.print("  hint: Investigate the references above; release or reuse these values to prevent leaks.\n", .{});
}

fn severityLabel(severity: ghostlang.ParseSeverity) []const u8 {
    return switch (severity) {
        .info => "info",
        .warning => "warning",
        .fatal => "error",
    };
}

fn writeValueDebug(value: ghostlang.ScriptValue) void {
    switch (value) {
        .nil => std.debug.print("nil", .{}),
        .boolean => |b| std.debug.print("{s}", .{if (b) "true" else "false"}),
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
}

fn printFunction(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (index > 0) std.debug.print(" ", .{});
        writeValueDebug(args[index]);
    }
    std.debug.print("\n", .{});
    return if (args.len > 0) args[0] else .{ .nil = {} };
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
