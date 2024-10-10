const std = @import("std");
const testing = std.testing;

const MergeStructs = @import("../../meta/utils.zig").MergeStructs;
const MergeTupleStructs = @import("../../meta/utils.zig").MergeTupleStructs;
const Omit = @import("../../meta/utils.zig").Omit;
const StructToTupleType = @import("../../meta/utils.zig").StructToTupleType;

test "Meta" {
    try expectEqualStructs(struct { foo: u32, jazz: bool }, MergeStructs(struct { foo: u32 }, struct { jazz: bool }));
    try expectEqualStructs(struct { u32, bool }, MergeTupleStructs(struct { u32 }, struct { bool }));
    try expectEqualStructs(struct { foo: u32, jazz: bool }, Omit(struct { foo: u32, bar: u256, baz: i64, jazz: bool }, &.{ "bar", "baz" }));
    try expectEqualStructs(std.meta.Tuple(&[_]type{ u64, std.meta.Tuple(&[_]type{ u64, u256 }) }), StructToTupleType(struct { foo: u64, bar: struct { baz: u64, jazz: u256 } }));
}

fn expectEqualStructs(comptime expected: type, comptime actual: type) !void {
    const expectInfo = @typeInfo(expected).Struct;
    const actualInfo = @typeInfo(actual).Struct;

    try testing.expectEqual(expectInfo.layout, actualInfo.layout);
    try testing.expectEqual(expectInfo.decls.len, actualInfo.decls.len);
    try testing.expectEqual(expectInfo.fields.len, actualInfo.fields.len);
    try testing.expectEqual(expectInfo.is_tuple, actualInfo.is_tuple);

    inline for (expectInfo.fields, actualInfo.fields) |e, a| {
        try testing.expectEqualStrings(e.name, a.name);
        if (@typeInfo(e.type) == .Struct) return try expectEqualStructs(e.type, a.type);
        if (@typeInfo(e.type) == .Struct) return try expectEqualUnions(e.type, a.type);
        try testing.expectEqual(e.type, a.type);
        try testing.expectEqual(e.alignment, a.alignment);
    }
}

fn expectEqualUnions(comptime expected: type, comptime actual: type) !void {
    const expectInfo = @typeInfo(expected).Union;
    const actualInfo = @typeInfo(actual).Union;

    try testing.expectEqual(expectInfo.layout, actualInfo.layout);
    try testing.expectEqual(expectInfo.decls.len, actualInfo.decls.len);
    try testing.expectEqual(expectInfo.fields.len, actualInfo.fields.len);

    inline for (expectInfo.fields, actualInfo.fields) |e, a| {
        try testing.expectEqualStrings(e.name, a.name);
        if (@typeInfo(e.type) == .Struct) return try expectEqualStructs(e.type, a.type);
        if (@typeInfo(e.type) == .Union) return try expectEqualUnions(e.type, a.type);
        try testing.expectEqual(e.type, a.type);
        try testing.expectEqual(e.alignment, a.alignment);
    }
}
