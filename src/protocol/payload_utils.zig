const std = @import("std");
const msgpack = @import("msgpack");

/// Deeply duplicates a msgpack payload so the caller receives its own owned copy.
pub fn clonePayload(allocator: std.mem.Allocator, value: msgpack.Payload) !msgpack.Payload {
    return switch (value) {
        .nil => msgpack.Payload.nilToPayload(),
        .bool => msgpack.Payload.boolToPayload(value.bool),
        .int => msgpack.Payload.intToPayload(value.int),
        .uint => msgpack.Payload.uintToPayload(value.uint),
        .float => msgpack.Payload.floatToPayload(value.float),
        .str => try msgpack.Payload.strToPayload(value.str.value(), allocator),
        .bin => try msgpack.Payload.binToPayload(value.bin.value(), allocator),
        .arr => blk: {
            const original = value.arr;
            var cloned = try msgpack.Payload.arrPayload(original.len, allocator);
            errdefer cloned.free(allocator);
            for (original, 0..) |item, index| {
                cloned.arr[index] = try clonePayload(allocator, item);
            }
            break :blk cloned;
        },
        .map => blk: {
            var map_payload = msgpack.Payload.mapPayload(allocator);
            errdefer map_payload.free(allocator);

            var it = value.map.iterator();
            while (it.next()) |entry| {
                const key_slice = entry.key_ptr.*;
                const key_copy = try allocator.dupe(u8, key_slice);
                const val_copy = clonePayload(allocator, entry.value_ptr.*) catch |err| {
                    allocator.free(key_copy);
                    return err;
                };
                map_payload.map.put(key_copy, val_copy) catch |err| {
                    allocator.free(key_copy);
                    val_copy.free(allocator);
                    return err;
                };
            }

            break :blk map_payload;
        },
        .ext => try msgpack.Payload.extToPayload(value.ext.type, value.ext.data, allocator),
        .timestamp => msgpack.Payload.timestampToPayload(value.timestamp.seconds, value.timestamp.nanoseconds),
    };
}

/// Allocates and copies a string slice so it can outlive the original buffer.
pub fn copyString(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const copy = try allocator.alloc(u8, source.len);
    @memcpy(copy, source);
    return copy;
}

test "clonePayload deep copies nested structures" {
    const allocator = std.testing.allocator;

    var original = try msgpack.Payload.arrPayload(2, allocator);
    defer original.free(allocator);

    original.arr[0] = try msgpack.Payload.strToPayload("alpha", allocator);
    var nested = try msgpack.Payload.arrPayload(1, allocator);
    nested.arr[0] = msgpack.Payload.intToPayload(42);
    original.arr[1] = nested;

    const cloned = try clonePayload(allocator, original);
    defer cloned.free(allocator);

    original.arr[0].free(allocator);
    original.arr[0] = try msgpack.Payload.strToPayload("beta", allocator);
    original.arr[1].arr[0] = msgpack.Payload.intToPayload(7);

    try std.testing.expect(cloned == .arr);
    try std.testing.expectEqual(@as(usize, 2), cloned.arr.len);
    try std.testing.expectEqualStrings("alpha", cloned.arr[0].str.value());
    try std.testing.expect(cloned.arr[1] == .arr);
    try std.testing.expectEqual(@as(usize, 1), cloned.arr[1].arr.len);
    try std.testing.expectEqual(@as(i64, 42), cloned.arr[1].arr[0].int);
}

test "copyString allocates new buffer" {
    const allocator = std.testing.allocator;
    const source = "payload";
    const copy = try copyString(allocator, source);
    defer allocator.free(copy);

    try std.testing.expectEqualStrings(source, copy);
    try std.testing.expect(copy.ptr != source.ptr);
}
