const std = @import("std");
const web3 = @import("src/web3.zig");
const blockchain = @import("src/blockchain.zig");

pub fn main() !void {
    std.debug.print("Web3 and blockchain modules compiled successfully!\n", .{});

    // Test web3 address utilities
    const addr = web3.AddressUtil.ZERO;
    std.debug.print("Zero address: {}\n", .{web3.AddressUtil.isZero(addr)});

    // Test gas calculation
    const gas = web3.Gas.calculateCalldata("hello world");
    std.debug.print("Calldata gas: {d}\n", .{gas});

    std.debug.print("All modules loaded successfully!\n", .{});
}
