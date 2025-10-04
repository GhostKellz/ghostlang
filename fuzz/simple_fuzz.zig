const std = @import("std");
const ghostlang = @import("ghostlang");

const MaxIterations = 10_000;
const MaxScriptLength = 256;
const Alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 +-*/%=(){}[]:,.;\n\t\r<>!";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.rand.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
    const random = prng.random();

    var iteration: usize = 0;
    while (iteration < MaxIterations) : (iteration += 1) {
        try fuzzOnce(random, allocator, iteration);
    }
}

fn fuzzOnce(random: std.rand.Random, allocator: std.mem.Allocator, iteration: usize) !void {
    const script_source = try makeCandidate(random, allocator, iteration);
    defer allocator.free(script_source);

    const config = ghostlang.EngineConfig{
        .allocator = allocator,
        .memory_limit = 256 * 1024,
        .execution_timeout_ms = 10,
        .allow_io = false,
        .allow_syscalls = false,
        .deterministic = true,
    };

    var engine = ghostlang.ScriptEngine.create(config) catch |err| {
        std.log.err("fuzz iteration {d}: engine create failed: {s}", .{ iteration, @errorName(err) });
        return err;
    };
    defer engine.deinit();

    var script = engine.loadScript(script_source) catch |err| {
        switch (err) {
            error.ParseError => return,
            error.MemoryLimitExceeded => return,
            else => {
                std.log.err("fuzz iteration {d}: loadScript unexpected {s} for script: {s}", .{ iteration, @errorName(err), script_source });
                return err;
            },
        }
    };
    defer script.deinit();

    _ = script.run() catch |err| {
        switch (err) {
            error.ParseError,
            error.TypeError,
            error.UndefinedVariable,
            error.FunctionNotFound,
            error.NotAFunction,
            error.ExecutionTimeout,
            error.MemoryLimitExceeded,
            => return,
            else => {
                std.log.err("fuzz iteration {d}: run unexpected {s} for script: {s}", .{ iteration, @errorName(err), script_source });
                return err;
            },
        }
    };
}

fn makeCandidate(random: std.rand.Random, allocator: std.mem.Allocator, iteration: usize) ![]u8 {
    // Periodically replay structured seeds for coverage
    const seeds = [_][]const u8{
        "var x = 10",
        "for i in 0..3 { i }",
        "function add(a,b) { return a + b } add(1,2)",
        "if true then 1 else 0 end",
        "{ flag = true, values = [1,2,3] }",
        "while false do break end",
        "queue:push(1)",
        "\"ghost\"",
    };
    if (iteration < seeds.len) {
        return allocator.dupe(u8, seeds[iteration]) catch unreachable;
    }

    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    const length = random.intRangeLessThan(usize, 0, MaxScriptLength);
    var idx: usize = 0;
    while (idx < length) : (idx += 1) {
        const ch = Alphabet[random.int(u8) % Alphabet.len];
        try buffer.append(ch);
    }

    if (buffer.items.len == 0) {
        try buffer.appendSlice("var noop = 0");
    }

    return try buffer.toOwnedSlice();
}
