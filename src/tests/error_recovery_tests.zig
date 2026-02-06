const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;
const protocol = znvim.protocol;

// Tests for msgpack and protocol error handling edge cases

// Test: msgpack handles nested arrays
test "msgpack handles deeply nested arrays" {
    const allocator = std.testing.allocator;

    const inner = try msgpack.array(allocator, &[_]msgpack.Value{msgpack.int(1)});
    const middle = try msgpack.array(allocator, &[_]msgpack.Value{inner});
    const outer = try msgpack.array(allocator, &[_]msgpack.Value{middle});
    // Only free the outer array, which will recursively free inner arrays
    defer msgpack.free(outer, allocator);

    const arr1 = try msgpack.expectArray(outer);
    try std.testing.expectEqual(@as(usize, 1), arr1.len);

    const arr2 = try msgpack.expectArray(arr1[0]);
    try std.testing.expectEqual(@as(usize, 1), arr2.len);

    const arr3 = try msgpack.expectArray(arr2[0]);
    try std.testing.expectEqual(@as(usize, 1), arr3.len);

    const value = try msgpack.expectI64(arr3[0]);
    try std.testing.expectEqual(@as(i64, 1), value);
}

// Test: msgpack handles maps with many keys
test "msgpack handles map with multiple keys" {
    const allocator = std.testing.allocator;

    const TestStruct = struct {
        a: i32,
        b: []const u8,
        c: bool,
        d: f64,
        e: ?i32,
    };

    const obj = try msgpack.object(allocator, TestStruct{
        .a = 42,
        .b = "hello",
        .c = true,
        .d = 3.14,
        .e = null,
    });
    defer msgpack.free(obj, allocator);

    try std.testing.expect(obj == .map);
    try std.testing.expectEqual(@as(usize, 5), obj.map.count());

    const a_val = obj.map.getByString("a").?;
    try std.testing.expectEqual(@as(i64, 42), try msgpack.expectI64(a_val));

    const b_val = obj.map.getByString("b").?;
    try std.testing.expectEqualStrings("hello", try msgpack.expectString(b_val));

    const c_val = obj.map.getByString("c").?;
    try std.testing.expectEqual(true, try msgpack.expectBool(c_val));

    const e_val = obj.map.getByString("e").?;
    try std.testing.expect(e_val == .nil);
}

// Test: Protocol handles request with empty params
test "protocol encodes request with empty params array" {
    const allocator = std.testing.allocator;

    const params = [_]msgpack.Value{};
    var params_payload = try msgpack.Value.arrPayload(params.len, allocator);
    defer params_payload.free(allocator);

    const request_msg = protocol.message.Request{
        .msgid = 10,
        .method = "nvim_get_mode",
        .params = params_payload,
    };

    const encoded = try protocol.encoder.encodeRequest(allocator, request_msg);
    defer allocator.free(encoded);

    var decoded = try protocol.decoder.decode(allocator, encoded);
    defer protocol.message.deinitMessage(&decoded.message, allocator);

    switch (decoded.message) {
        .Request => |req| {
            try std.testing.expectEqual(@as(u32, 10), req.msgid);
            try std.testing.expectEqualStrings("nvim_get_mode", req.method);
            const arr_len = try req.params.getArrLen();
            try std.testing.expectEqual(@as(usize, 0), arr_len);
        },
        else => return error.UnexpectedMessageType,
    }
}

// Test: msgpack type conversion edge cases
test "msgpack handles type overflow gracefully" {
    const big_uint = msgpack.uint(std.math.maxInt(u64));

    // Should fail to convert to i64
    const result = msgpack.expectI64(big_uint);
    try std.testing.expectError(msgpack.DecodeError.Overflow, result);

    // Should succeed for u64
    const value = try msgpack.expectU64(big_uint);
    try std.testing.expectEqual(std.math.maxInt(u64), value);
}

// Test: msgpack handles negative integers
test "msgpack handles negative integer edge cases" {
    const min_int = msgpack.int(std.math.minInt(i64));

    const value = try msgpack.expectI64(min_int);
    try std.testing.expectEqual(std.math.minInt(i64), value);

    // Should fail to convert to u64
    const result = msgpack.expectU64(min_int);
    try std.testing.expectError(msgpack.DecodeError.Overflow, result);
}
