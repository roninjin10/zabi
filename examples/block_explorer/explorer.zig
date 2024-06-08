const args_parser = zabi.args;
const std = @import("std");
const zabi = @import("zabi");

const BlockExplorer = zabi.clients.BlockExplorer;

pub const CliOptions = struct {
    apikey: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var iter = try std.process.argsWithAllocator(gpa.allocator());
    defer iter.deinit();

    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    var explorer = BlockExplorer.init(.{
        .allocator = gpa.allocator(),
        .apikey = parsed.apikey,
    });
    defer explorer.deinit();

    const result = try explorer.getEtherPrice();
    defer result.deinit();

    std.debug.print("Explorer result: {any}", .{result.response});
}
