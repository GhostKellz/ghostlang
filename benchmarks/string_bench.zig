// Ghostlang String & Pattern Matching Performance Benchmarks
// Comprehensive benchmarking suite testing through the ScriptEngine

const std = @import("std");
const ghostlang = @import("ghostlang");

const BenchResult = struct {
    name: []const u8,
    iterations: usize,
    total_ns: u64,
    avg_ns: u64,
    ops_per_sec: f64,
};

fn printResult(result: BenchResult) void {
    std.debug.print(
        "  {s:<40} | {d:>8} iter | {d:>8} ns/op | {d:>10.0} ops/sec\n",
        .{ result.name, result.iterations, result.avg_ns, result.ops_per_sec },
    );
}

fn benchmarkScript(
    allocator: std.mem.Allocator,
    comptime name: []const u8,
    comptime iterations: usize,
    source: []const u8,
) !BenchResult {
    const config = ghostlang.EngineConfig{
        .allocator = allocator,
    };
    var engine = try ghostlang.ScriptEngine.create(config);
    defer engine.deinit();

    // Register string functions (stringMatch, stringGsub, etc.)
    try engine.registerEditorHelpers();

    var timer = try std.time.Timer.start();
    const start = timer.read();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        var script = try engine.loadScript(source);
        defer script.deinit();
        _ = try script.run();
    }

    const end = timer.read();
    const total_ns = end - start;
    const avg_ns = total_ns / iterations;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0);

    return BenchResult{
        .name = name,
        .iterations = iterations,
        .total_ns = total_ns,
        .avg_ns = avg_ns,
        .ops_per_sec = ops_per_sec,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n=== Ghostlang String & Pattern Matching Benchmarks ===\n\n", .{});

    // Benchmark 1: Character class patterns
    {
        std.debug.print("Character Class Patterns:\n", .{});

        const result1 = try benchmarkScript(allocator, "Match letters (%a+)", 10_000,
            \\local text = "Hello World 123!"
            \\local match = stringMatch(text, "%a+")
            \\match
        );
        printResult(result1);

        const result2 = try benchmarkScript(allocator, "Match digits (%d+)", 10_000,
            \\local text = "Hello World 123!"
            \\local match = stringMatch(text, "%d+")
            \\match
        );
        printResult(result2);

        const result3 = try benchmarkScript(allocator, "Match alphanumeric (%w+)", 10_000,
            \\local text = "Hello World 123!"
            \\local match = stringMatch(text, "%w+")
            \\match
        );
        printResult(result3);
    }

    // Benchmark 2: Character sets
    {
        std.debug.print("\nCharacter Set Patterns:\n", .{});

        const result1 = try benchmarkScript(allocator, "Number range [0-9]+", 10_000,
            \\local text = "test123abc"
            \\local match = stringMatch(text, "[0-9]+")
            \\match
        );
        printResult(result1);

        const result2 = try benchmarkScript(allocator, "Vowel set [aeiou]+", 10_000,
            \\local text = "test123abc"
            \\local match = stringMatch(text, "[aeiou]")
            \\match
        );
        printResult(result2);

        const result3 = try benchmarkScript(allocator, "Negated set [^0-9]+", 10_000,
            \\local text = "test123abc"
            \\local match = stringMatch(text, "[^0-9]+")
            \\match
        );
        printResult(result3);
    }

    // Benchmark 3: Captures (GSH critical!)
    {
        std.debug.print("\nCapture Patterns (GSH Critical):\n", .{});

        const result1 = try benchmarkScript(allocator, "Git branch capture", 10_000,
            \\local head = "ref: refs/heads/main"
            \\local branch = stringMatch(head, "refs/heads/(%w+)")
            \\branch
        );
        printResult(result1);

        const result2 = try benchmarkScript(allocator, "Email capture (2 groups)", 10_000,
            \\local email = "user@example.com"
            \\local match = stringMatch(email, "(%w+)@(%w+)")
            \\match
        );
        printResult(result2);

        const result3 = try benchmarkScript(allocator, "Path parsing (3 groups)", 5_000,
            \\local path = "/home/user/file.txt"
            \\local match = stringMatch(path, "(.*/)(.*)(%.%w+)$")
            \\match
        );
        printResult(result3);
    }

    // Benchmark 4: Global substitution
    {
        std.debug.print("\nGlobal Substitution (gsub):\n", .{});

        const result1 = try benchmarkScript(allocator, "Simple replace (l->L)", 10_000,
            \\local text = "hello world"
            \\local result = stringGsub(text, "l", "L")
            \\result
        );
        printResult(result1);

        const result2 = try benchmarkScript(allocator, "Word replace (test->best)", 10_000,
            \\local text = "test test test"
            \\local result = stringGsub(text, "test", "best")
            \\result
        );
        printResult(result2);

        const result3 = try benchmarkScript(allocator, "Capture swap (%1 %2)", 5_000,
            \\local text = "hello world"
            \\local result = stringGsub(text, "(%w+) (%w+)", "%2 %1")
            \\result
        );
        printResult(result3);
    }

    // Benchmark 5: Quantifiers
    {
        std.debug.print("\nQuantifier Patterns:\n", .{});

        const result1 = try benchmarkScript(allocator, "Greedy + quantifier", 10_000,
            \\local text = "aaaaaaaaaa"
            \\local match = stringMatch(text, "a+")
            \\match
        );
        printResult(result1);

        const result2 = try benchmarkScript(allocator, "Greedy * quantifier", 10_000,
            \\local text = "aaaaaaaaaa"
            \\local match = stringMatch(text, "a*")
            \\match
        );
        printResult(result2);

        const result3 = try benchmarkScript(allocator, "Optional ? quantifier", 10_000,
            \\local text = "test"
            \\local match = stringMatch(text, "te?st")
            \\match
        );
        printResult(result3);
    }

    // Benchmark 6: Anchors
    {
        std.debug.print("\nAnchor Patterns:\n", .{});

        const result1 = try benchmarkScript(allocator, "Start anchor (^)", 10_000,
            \\local text = "hello world"
            \\local match = stringMatch(text, "^hello")
            \\match
        );
        printResult(result1);

        const result2 = try benchmarkScript(allocator, "End anchor ($)", 10_000,
            \\local text = "hello world"
            \\local match = stringMatch(text, "world$")
            \\match
        );
        printResult(result2);

        const result3 = try benchmarkScript(allocator, "Both anchors (exact)", 10_000,
            \\local text = "test"
            \\local match = stringMatch(text, "^test$")
            \\match
        );
        printResult(result3);
    }

    // Benchmark 7: Complex real-world patterns
    {
        std.debug.print("\nComplex Real-World Patterns:\n", .{});

        const result1 = try benchmarkScript(allocator, "Config parsing (key: value)", 5_000,
            \\local text = "Port: 8080, Timeout: 30s"
            \\local match = stringMatch(text, "(%a+):%s*(%d+)")
            \\match
        );
        printResult(result1);

        const result2 = try benchmarkScript(allocator, "URL parsing (protocol://domain)", 5_000,
            \\local url = "https://github.com/user/repo"
            \\local match = stringMatch(url, "(%w+)://([%w%.]+)")
            \\match
        );
        printResult(result2);

        const result3 = try benchmarkScript(allocator, "Filename extraction", 5_000,
            \\local path = "/home/user/file.txt"
            \\local match = stringMatch(path, "([^/]+)$")
            \\match
        );
        printResult(result3);
    }

    // Benchmark 8: String operations
    {
        std.debug.print("\nBasic String Operations:\n", .{});

        const result1 = try benchmarkScript(allocator, "stringUpper", 10_000,
            \\local text = "hello world"
            \\local result = stringUpper(text)
            \\result
        );
        printResult(result1);

        const result2 = try benchmarkScript(allocator, "stringLower", 10_000,
            \\local text = "HELLO WORLD"
            \\local result = stringLower(text)
            \\result
        );
        printResult(result2);

        const result3 = try benchmarkScript(allocator, "stringFormat", 10_000,
            \\local result = stringFormat("User: %s, Score: %d", "test", 100)
            \\result
        );
        printResult(result3);
    }

    std.debug.print("\n=== Benchmarks Complete ===\n\n", .{});
    std.debug.print("Performance Summary:\n", .{});
    std.debug.print("  All operations running through full VM\n", .{});
    std.debug.print("  Build mode: ReleaseFast\n", .{});
    std.debug.print("  Pattern engine: Lua 5.4 compatible\n", .{});
    std.debug.print("\nTargets (through VM):\n", .{});
    std.debug.print("  Simple patterns:     <1µs/op\n", .{});
    std.debug.print("  Character classes:   <2µs/op\n", .{});
    std.debug.print("  Complex captures:    <5µs/op\n", .{});
    std.debug.print("  Gsub operations:     <10µs/op\n", .{});
}
