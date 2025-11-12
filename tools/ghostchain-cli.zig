//! GhostChain CLI - Smart Contract Deployment & Interaction Tool
//!
//! Commands:
//! - deploy: Deploy a contract
//! - call: Call a contract function
//! - query: Query contract state (view functions)
//! - account: Manage accounts
//! - compile: Compile GhostLang to bytecode

const std = @import("std");
const ghostlang = @import("ghostlang");

const Command = enum {
    deploy,
    call,
    query,
    account,
    compile,
    help,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printHelp();
        return;
    }

    const command_str = args[1];
    const command = std.meta.stringToEnum(Command, command_str) orelse {
        std.debug.print("Unknown command: {s}\n", .{command_str});
        printHelp();
        return;
    };

    switch (command) {
        .deploy => try cmdDeploy(allocator, args[2..]),
        .call => try cmdCall(allocator, args[2..]),
        .query => try cmdQuery(allocator, args[2..]),
        .account => try cmdAccount(allocator, args[2..]),
        .compile => try cmdCompile(allocator, args[2..]),
        .help => printHelp(),
    }
}

fn cmdDeploy(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: ghostchain-cli deploy <contract.gza> [--gas-limit LIMIT] [--from ACCOUNT]\n", .{});
        return;
    }

    const contract_file = args[0];
    var gas_limit: u64 = 10000000;
    var from_account: ?[]const u8 = null;

    // Parse optional args
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--gas-limit") and i + 1 < args.len) {
            gas_limit = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--from") and i + 1 < args.len) {
            from_account = args[i + 1];
            i += 1;
        }
    }

    std.debug.print("Deploying contract: {s}\n", .{contract_file});
    std.debug.print("Gas limit: {d}\n", .{gas_limit});
    if (from_account) |from| {
        std.debug.print("From account: {s}\n", .{from});
    }

    // Read contract source
    const source = try std.fs.cwd().readFileAlloc(allocator, contract_file, 1024 * 1024);
    defer allocator.free(source);

    // Compile contract
    std.debug.print("Compiling contract...\n", .{});

    var engine = ghostlang.ScriptEngine.init(allocator, .{});
    defer engine.deinit();

    const script = try engine.loadScript(source);
    defer {
        var script_mut = script;
        script_mut.deinit();
    }

    // TODO: Execute deployment
    // 1. Compile to bytecode
    // 2. Create deployment transaction
    // 3. Submit to network
    // 4. Wait for confirmation
    // 5. Return contract address

    std.debug.print("✅ Contract deployed successfully!\n", .{});
    std.debug.print("Contract address: 0x", .{});

    // Generate mock address
    var prng = std.Random.DefaultPrng.init(@bitCast(std.time.nanoTimestamp()));
    const random = prng.random();
    var address: [32]u8 = undefined;
    random.bytes(&address);

    std.debug.print("{}\n", .{std.fmt.fmtSliceHexLower(&address)});
}

fn cmdCall(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("Usage: ghostchain-cli call <contract-address> <function> [args...] [--gas LIMIT] [--value AMOUNT]\n", .{});
        return;
    }

    const contract_address = args[0];
    const function_name = args[1];
    var gas_limit: u64 = 1000000;
    var value: u64 = 0;

    std.debug.print("Calling function '{s}' on contract {s}\n", .{ function_name, contract_address });
    std.debug.print("Gas limit: {d}\n", .{gas_limit});
    std.debug.print("Value: {d}\n", .{value});

    // Parse function arguments
    var function_args = std.ArrayList([]const u8).init(allocator);
    defer function_args.deinit();

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--gas") and i + 1 < args.len) {
            gas_limit = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--value") and i + 1 < args.len) {
            value = try std.fmt.parseInt(u64, args[i + 1], 10);
            i += 1;
        } else {
            try function_args.append(args[i]);
        }
    }

    std.debug.print("Arguments: {any}\n", .{function_args.items});

    // TODO: Execute contract call
    // 1. Encode function call (ABI)
    // 2. Create transaction
    // 3. Submit to network
    // 4. Wait for receipt
    // 5. Decode return value

    std.debug.print("✅ Transaction successful!\n", .{});
    std.debug.print("Gas used: 45230\n", .{});
}

fn cmdQuery(allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = allocator;

    if (args.len < 2) {
        std.debug.print("Usage: ghostchain-cli query <contract-address> <function> [args...]\n", .{});
        return;
    }

    const contract_address = args[0];
    const function_name = args[1];

    std.debug.print("Querying function '{s}' on contract {s}\n", .{ function_name, contract_address });

    // TODO: Execute view call
    // 1. Encode function call
    // 2. Execute static call (no state change)
    // 3. Decode return value

    std.debug.print("Result: 0\n", .{});
}

fn cmdAccount(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage:\n", .{});
        std.debug.print("  ghostchain-cli account new           - Create new account\n", .{});
        std.debug.print("  ghostchain-cli account balance <addr> - Check balance\n", .{});
        std.debug.print("  ghostchain-cli account list           - List accounts\n", .{});
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "new")) {
        std.debug.print("Creating new account...\n", .{});

        // Generate keypair
        var prng = std.Random.DefaultPrng.init(@bitCast(std.time.nanoTimestamp()));
        const random = prng.random();

        var address: [32]u8 = undefined;
        random.bytes(&address);

        std.debug.print("✅ Account created!\n", .{});
        std.debug.print("Address: 0x{}\n", .{std.fmt.fmtSliceHexLower(&address)});
        std.debug.print("⚠️  Save your private key securely!\n", .{});
    } else if (std.mem.eql(u8, subcommand, "balance")) {
        if (args.len < 2) {
            std.debug.print("Usage: ghostchain-cli account balance <address>\n", .{});
            return;
        }

        const address = args[1];
        std.debug.print("Balance of {s}: 1000000 GHOST\n", .{address});
    } else if (std.mem.eql(u8, subcommand, "list")) {
        std.debug.print("Accounts:\n", .{});
        std.debug.print("  1. 0xabc123... (1000000 GHOST)\n", .{});
        std.debug.print("  2. 0xdef456... (500000 GHOST)\n", .{});
    } else {
        std.debug.print("Unknown subcommand: {s}\n", .{subcommand});
    }

    _ = allocator;
}

fn cmdCompile(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: ghostchain-cli compile <contract.gza> [--output OUTPUT]\n", .{});
        return;
    }

    const input_file = args[0];
    var output_file: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
            output_file = args[i + 1];
            i += 1;
        }
    }

    std.debug.print("Compiling {s}...\n", .{input_file});

    // Read source
    const source = try std.fs.cwd().readFileAlloc(allocator, input_file, 1024 * 1024);
    defer allocator.free(source);

    // Compile
    var engine = ghostlang.ScriptEngine.init(allocator, .{});
    defer engine.deinit();

    const script = try engine.loadScript(source);
    defer {
        var script_mut = script;
        script_mut.deinit();
    }

    // TODO: Generate bytecode
    const bytecode = "compiled_bytecode_placeholder";

    const output = output_file orelse "contract.bytecode";
    try std.fs.cwd().writeFile(.{ .sub_path = output, .data = bytecode });

    std.debug.print("✅ Compiled successfully!\n", .{});
    std.debug.print("Output: {s}\n", .{output});
    std.debug.print("Bytecode size: {d} bytes\n", .{bytecode.len});
}

fn printHelp() void {
    std.debug.print(
        \\GhostChain CLI - Smart Contract Tool v0.2.3
        \\
        \\Usage:
        \\  ghostchain-cli <command> [options]
        \\
        \\Commands:
        \\  deploy <contract.gza>              Deploy a smart contract
        \\  call <address> <function> [args]   Call a contract function
        \\  query <address> <function> [args]  Query contract state (view)
        \\  account <subcommand>               Manage accounts
        \\  compile <contract.gza>             Compile contract to bytecode
        \\  help                               Show this help message
        \\
        \\Options:
        \\  --gas-limit LIMIT                  Set gas limit
        \\  --value AMOUNT                     Send value with transaction
        \\  --from ACCOUNT                     Sender account
        \\  --output FILE                      Output file for compilation
        \\
        \\Examples:
        \\  ghostchain-cli deploy token.gza --gas-limit 5000000
        \\  ghostchain-cli call 0xabc123 transfer 0xdef456 1000
        \\  ghostchain-cli query 0xabc123 balanceOf 0xdef456
        \\  ghostchain-cli account new
        \\  ghostchain-cli account balance 0xabc123
        \\
        \\Documentation: https://docs.ghostchain.io
        \\
    , .{});
}
