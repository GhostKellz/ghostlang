const std = @import("std");
const ghostlang = @import("ghostlang");

const max_script_size: usize = 4 * 1024 * 1024; // 4 MiB safety cap

pub fn main() !void {
    var exit_code: u8 = 0;
    defer if (exit_code != 0) std.process.exit(exit_code);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage(args[0]);
        exit_code = 1;
        return;
    }

    const script_path = args[1];

    const source = std.fs.cwd().readFileAlloc(
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

    var stdout_file = std.fs.File.stdout();
    try stdout_file.writeAll("Result: ");
    try writeValue(stdout_file, result);
    try stdout_file.writeAll("\n");
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

    const stderr = std.fs.File.stderr();
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = stderr.writer(&stderr_buffer);
    try stderr_writer.interface.writeAll("  memory context:\n");
    try stderr_writer.interface.writeAll(buffer.items);
    try stderr_writer.interface.writeAll("  hint: Investigate the references above; release or reuse these values to prevent leaks.\n");
    try stderr_writer.interface.flush();
}

fn severityLabel(severity: ghostlang.ParseSeverity) []const u8 {
    return switch (severity) {
        .info => "info",
        .warning => "warning",
        .fatal => "error",
    };
}

fn writeValue(file: std.fs.File, value: ghostlang.ScriptValue) !void {
    switch (value) {
        .nil => try file.writeAll("nil"),
        .boolean => |b| try file.writeAll(if (b) "true" else "false"),
        .number => |n| {
            var buf: [64]u8 = undefined;
            const text = try std.fmt.bufPrint(&buf, "{}", .{n});
            try file.writeAll(text);
        },
        .string => |s| try file.writeAll(s),
        .function => try file.writeAll("<function>"),
        .native_function => try file.writeAll("<function>"),
        .script_function => try file.writeAll("<function>"),
        .table => try file.writeAll("<table>"),
        .array => try file.writeAll("<array>"),
        .iterator => try file.writeAll("<iterator>"),
        .upvalue => try file.writeAll("<upvalue>"),
    }
}

fn printFunction(args: []const ghostlang.ScriptValue) ghostlang.ScriptValue {
    var stdout_file = std.fs.File.stdout();
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        if (index > 0) stdout_file.writeAll(" ") catch {};
        writeValue(stdout_file, args[index]) catch {};
    }
    stdout_file.writeAll("\n") catch {};
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
