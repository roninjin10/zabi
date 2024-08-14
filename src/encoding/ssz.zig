//! The code bellow is essentially a port of https://github.com/gballet/ssz.zig/tree/master
//! to the most recent version of zig with a couple of stylistic changes and support for
//! other zig types.

const std = @import("std");
const testing = std.testing;
const utils = @import("../utils/utils.zig");

// Types
const Allocator = std.mem.Allocator;

/// Performs ssz encoding according to the [specification](https://ethereum.org/developers/docs/data-structures-and-encoding/ssz).
/// Almost all zig types are supported.
///
/// Caller owns the memory
pub fn encodeSSZ(allocator: Allocator, value: anytype) ![]u8 {
    var list = std.ArrayList(u8).init(allocator);
    errdefer list.deinit();

    try encodeItem(value, &list);

    return try list.toOwnedSlice();
}

fn encodeItem(value: anytype, list: *std.ArrayList(u8)) !void {
    const info = @typeInfo(@TypeOf(value));
    var writer = list.writer();

    switch (info) {
        .Bool => try writer.writeInt(u8, @intFromBool(value), .little),
        .Int => |int_info| {
            switch (int_info.bits) {
                8, 16, 32, 64, 128, 256 => try writer.writeInt(@TypeOf(value), value, .little),
                else => @compileError(std.fmt.comptimePrint("Unsupported {d} bits for ssz encoding", .{int_info.bits})),
            }
        },
        .ComptimeInt => {
            const size = comptime utils.computeSize(@intCast(value)) * 8;
            switch (size) {
                8, 16, 32, 64, 128, 256 => try writer.writeInt(@Type(.{ .Int = .{ .signedness = .unsigned, .bits = size } }), value, .little),
                else => @compileError(std.fmt.comptimePrint("Unsupported {d} bits for ssz encoding", .{size})),
            }
        },
        .Null => return,
        .Optional => {
            if (value) |val| {
                try writer.writeInt(u8, 1, .little);
                return try encodeItem(val, list);
            } else try writer.writeInt(u8, 0, .little);
        },
        .Union => |union_info| {
            if (union_info.tag_type == null)
                @compileError("Untagged unions are not supported");

            inline for (union_info.fields, 0..) |field, i| {
                if (@intFromEnum(value) == i) {
                    try writer.writeInt(u8, i, .little);
                    return try encodeItem(@field(value, field.name), list);
                }
            }
        },
        .Pointer => |ptr_info| {
            switch (ptr_info.size) {
                .One => return try encodeItem(value.*, list),
                .Slice => {
                    if (ptr_info.child == u8) {
                        try writer.writeAll(value);
                        return;
                    }

                    for (value) |val| {
                        try encodeItem(val, list);
                    }
                },
                else => @compileError("Unsupported pointer type " ++ @typeName(@TypeOf(value))),
            }
        },
        .Vector => |vec_info| {
            if (vec_info.child == bool) {
                var as_byte: u8 = 0;
                for (value, 0..) |val, i| {
                    if (val) {
                        as_byte |= @as(u8, 1) << @as(u3, @truncate(i));
                    }

                    if (i % 8 == 7) {
                        try writer.writeByte(as_byte);
                        as_byte = 0;
                    }
                }

                if (as_byte % 8 != 0)
                    try writer.writeByte(as_byte);

                return;
            }

            for (0..vec_info.len) |i| {
                try encodeItem(value[i], list);
            }
        },
        .Enum, .EnumLiteral => try writer.writeAll(@tagName(value)),
        .ErrorSet => try writer.writeAll(@errorName(value)),
        .Array => |arr_info| {
            if (arr_info.child == u8) {
                try writer.writeAll(&value);
                return;
            }

            if (arr_info.child == bool) {
                var as_byte: u8 = 0;
                for (value, 0..) |val, i| {
                    if (val) {
                        as_byte |= @as(u8, 1) << @as(u3, @truncate(i));
                    }

                    if (i % 8 == 7) {
                        try writer.writeByte(as_byte);
                        as_byte = 0;
                    }
                }

                if (as_byte % 8 != 0)
                    try writer.writeByte(as_byte);

                return;
            }

            if (utils.isStaticType(arr_info.child)) {
                for (value) |val| {
                    try encodeItem(val, list);
                }
                return;
            }

            var offset_start = list.items.len;

            for (value) |_| {
                try writer.writeInt(u32, 0, .little);
            }

            for (value) |val| {
                std.mem.writeInt(u32, list.items[offset_start .. offset_start + 4][0..4], @as(u32, @truncate(list.items.len)), .little);
                try encodeItem(val, list);
                offset_start += 4;
            }
        },
        .Struct => |struct_info| {
            comptime var start: usize = 0;
            inline for (struct_info.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .Int, .Bool => start += @sizeOf(field.type),
                    else => start += 4,
                }
            }

            var accumulate: usize = start;
            inline for (struct_info.fields) |field| {
                switch (@typeInfo(field.type)) {
                    .Int, .Bool => try encodeItem(@field(value, field.name), list),
                    else => {
                        try encodeItem(@as(u32, @truncate(accumulate)), list);
                        accumulate += sizeOfValue(@field(value, field.name));
                    },
                }
            }

            if (accumulate > start) {
                inline for (struct_info.fields) |field| {
                    switch (@typeInfo(field.type)) {
                        .Bool, .Int => continue,
                        else => try encodeItem(@field(value, field.name), list),
                    }
                }
            }
        },
        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(value))),
    }
}

// Helpers
fn sizeOfValue(value: anytype) usize {
    const info = @typeInfo(@TypeOf(value));

    switch (info) {
        .Array => return value.len,
        .Pointer => switch (info.Pointer.size) {
            .Slice => return value.len,
            else => return sizeOfValue(value.*),
        },
        .Optional => return if (value == null)
            @intCast(1)
        else
            1 + sizeOfValue(value.?),
        .Null => return @intCast(0),
        else => @compileError("Unsupported type " ++ @typeName(@TypeOf(value))),
    }
    // It should never reach this
    unreachable;
}
