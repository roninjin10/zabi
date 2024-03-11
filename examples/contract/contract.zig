const abi = zabi.abi;
const human = zabi.human_readable.parsing;
const std = @import("std");
const utils = zabi.utils;
const zabi = @import("zabi");

const Abi = abi.abitypes.Abi;
const Contract = zabi.clients.contract.Contract(.http);
const Wallet = zabi.clients.wallet.Wallet(.http);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var iter = try std.process.ArgIterator.initWithAllocator(gpa.allocator());
    defer iter.deinit();

    _ = iter.skip();

    const private_key = iter.next().?;
    const host_url = iter.next().?;

    const uri = try std.Uri.parse(host_url);

    const slice =
        \\  function transfer(address to, uint256 amount)
        \\  function approve(address operator, uint256 size) external returns (bool)
        \\  function balanceOf(address owner) public view returns (uint256)
    ;
    var abi_parsed = try human.parseHumanReadable(Abi, gpa.allocator(), slice);
    defer abi_parsed.deinit();

    var contract: Contract = undefined;
    try contract.init(.{ .private_key = private_key, .abi = abi_parsed.value, .wallet_opts = .{ .allocator = gpa.allocator(), .uri = uri } });
    defer contract.deinit();

    const approve = try contract.writeContractFunction("transfer", .{ try utils.addressToBytes("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"), 69421 }, .{ .type = .london, .to = try utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") });
    var receipt = try contract.wallet.waitForTransactionReceipt(approve, 1);

    if (receipt) |tx_receipt| {
        std.debug.print("Transaction receipt: {}", .{tx_receipt});
    } else std.process.exit(1);

    const balance = try contract.readContractFunction(struct { u256 }, "balanceOf", .{try contract.wallet.getWalletAddress()}, .{ .london = .{ .to = try utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") } });
    defer balance.deinit();
    std.debug.print("BALANCE: {d}\n", .{balance.values[0]});

    if (balance.values[0] > 0) {
        const transfer = try contract.writeContractFunction("transfer", .{ try utils.addressToBytes("0x70997970C51812dc3A010C7d01b50e0d17dc79C8"), balance.values[0] - 1 }, .{ .type = .london, .to = try utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") });
        receipt = try contract.wallet.waitForTransactionReceipt(transfer, 1);

        if (receipt) |tx_receipt| {
            std.debug.print("Transaction receipt: {}", .{tx_receipt});
        } else std.process.exit(1);
    }
}
