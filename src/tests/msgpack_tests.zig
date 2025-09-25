const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;

test "msgpack encode primitives" {
    const allocator = std.testing.allocator;

    const bool_value = try msgpack.encode(allocator, true);
    defer msgpack.free(bool_value, allocator);
    try std.testing.expect(bool_value == .bool);
    try std.testing.expectEqual(true, try msgpack.expectBool(bool_value));
    try std.testing.expectEqual(true, msgpack.asBool(bool_value).?);

    const int_value = try msgpack.encode(allocator, @as(i32, -42));
    defer msgpack.free(int_value, allocator);
    try std.testing.expect(int_value == .int);
    try std.testing.expectEqual(@as(i64, -42), try msgpack.expectI64(int_value));
    try std.testing.expectEqual(@as(i64, -42), msgpack.asI64(int_value).?);

    const optional_null = try msgpack.encode(allocator, @as(?u8, null));
    defer msgpack.free(optional_null, allocator);
    try std.testing.expect(optional_null == .nil);

    const optional_value = try msgpack.encode(allocator, @as(?u8, 7));
    defer msgpack.free(optional_value, allocator);
    try std.testing.expectEqual(@as(u64, 7), try msgpack.expectU64(optional_value));
    try std.testing.expectEqual(@as(u64, 7), msgpack.asU64(optional_value).?);
}

test "msgpack string helper" {
    const allocator = std.testing.allocator;

    const str_value = try msgpack.string(allocator, "hello");
    defer msgpack.free(str_value, allocator);

    const text = try msgpack.expectString(str_value);
    try std.testing.expectEqualStrings("hello", text);
    try std.testing.expectEqualStrings("hello", msgpack.asString(str_value).?);
}

test "msgpack array helper encodes tuple" {
    const allocator = std.testing.allocator;

    const str_slice: []const u8 = "hi";
    const array_value = try msgpack.array(allocator, .{ true, @as(i8, -1), str_slice });
    defer msgpack.free(array_value, allocator);

    try std.testing.expect(array_value == .arr);

    const arr = try msgpack.expectArray(array_value);
    try std.testing.expectEqual(@as(usize, 3), arr.len);
    try std.testing.expectEqual(true, try msgpack.expectBool(arr[0]));
    try std.testing.expectEqual(@as(i64, -1), try msgpack.expectI64(arr[1]));
    const text = try msgpack.expectString(arr[2]);
    try std.testing.expectEqualStrings("hi", text);
}

test "msgpack object helper encodes struct" {
    const allocator = std.testing.allocator;

    const PayloadStruct = struct {
        foo: u32,
        bar: []const u8,
    };

    const obj_value = try msgpack.object(allocator, PayloadStruct{
        .foo = 9,
        .bar = "bar",
    });
    defer msgpack.free(obj_value, allocator);

    try std.testing.expect(obj_value == .map);

    const foo_payload_opt = obj_value.map.get("foo");
    try std.testing.expect(foo_payload_opt != null);
    const foo_payload = foo_payload_opt.?;
    try std.testing.expectEqual(@as(u64, 9), try msgpack.expectU64(foo_payload));

    const bar_payload_opt = obj_value.map.get("bar");
    try std.testing.expect(bar_payload_opt != null);
    const bar_payload = bar_payload_opt.?;
    const text = try msgpack.expectString(bar_payload);
    try std.testing.expectEqualStrings("bar", text);
}

test "msgpack expect error paths" {
    const bool_value = msgpack.boolean(true);
    try std.testing.expectError(msgpack.DecodeError.ExpectedArray, msgpack.expectArray(bool_value));

    const big_uint = msgpack.uint(std.math.maxInt(u64));
    try std.testing.expectError(msgpack.DecodeError.Overflow, msgpack.expectI64(big_uint));

    const negative_int = msgpack.int(-1);
    try std.testing.expectError(msgpack.DecodeError.Overflow, msgpack.expectU64(negative_int));
}
