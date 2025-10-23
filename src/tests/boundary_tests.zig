const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;
const protocol = znvim.protocol;
const transport = znvim.transport;
const Client = znvim.Client;

// Test: Client handles extremely large arrays
test "client handles large array payloads" {
    const allocator = std.testing.allocator;

    // Create array with 1000 elements
    const size = 1000;
    const elements = try allocator.alloc(msgpack.Value, size);
    defer allocator.free(elements);

    for (elements, 0..) |*elem, i| {
        elem.* = msgpack.int(@intCast(i));
    }

    const large_array = try msgpack.array(allocator, elements);
    defer msgpack.free(large_array, allocator);

    const arr = try msgpack.expectArray(large_array);
    try std.testing.expectEqual(@as(usize, size), arr.len);

    // Verify first and last elements
    const first = try msgpack.expectI64(arr[0]);
    try std.testing.expectEqual(@as(i64, 0), first);

    const last = try msgpack.expectI64(arr[size - 1]);
    try std.testing.expectEqual(@as(i64, size - 1), last);
}

// Test: Client handles very large strings (1MB+)
test "client handles megabyte string payloads" {
    const allocator = std.testing.allocator;

    const mb_size = 1024 * 1024; // 1MB
    const large_string = try allocator.alloc(u8, mb_size);
    defer allocator.free(large_string);

    // Fill with pattern
    for (large_string, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    const str_value = try msgpack.string(allocator, large_string);
    defer msgpack.free(str_value, allocator);

    const decoded = try msgpack.expectString(str_value);
    try std.testing.expectEqual(mb_size, decoded.len);

    // Verify pattern
    for (decoded, 0..) |byte, i| {
        try std.testing.expectEqual(@as(u8, @intCast(i % 256)), byte);
    }
}

// Test: MessageID generation stress test
test "client generates unique message ids under load" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    const count = 10000;
    var ids = try std.ArrayList(u32).initCapacity(allocator, count);
    defer ids.deinit(allocator);

    // Generate many IDs
    var i: usize = 0;
    while (i < count) : (i += 1) {
        try ids.append(allocator, client.nextMessageId());
    }

    // Verify all are unique and sequential
    for (ids.items, 0..) |id, idx| {
        try std.testing.expectEqual(@as(u32, @intCast(idx)), id);
    }
}

// Test: Empty string handling
test "msgpack handles empty strings correctly" {
    const allocator = std.testing.allocator;

    const empty_str = try msgpack.string(allocator, "");
    defer msgpack.free(empty_str, allocator);

    const decoded = try msgpack.expectString(empty_str);
    try std.testing.expectEqual(@as(usize, 0), decoded.len);
}

// Test: Single character strings
test "msgpack handles single character strings" {
    const allocator = std.testing.allocator;

    const single_char = try msgpack.string(allocator, "A");
    defer msgpack.free(single_char, allocator);

    const decoded = try msgpack.expectString(single_char);
    try std.testing.expectEqualStrings("A", decoded);
}

// Test: Unicode string handling
test "msgpack handles unicode strings" {
    const allocator = std.testing.allocator;

    const unicode = try msgpack.string(allocator, "Hello 世界 🌍");
    defer msgpack.free(unicode, allocator);

    const decoded = try msgpack.expectString(unicode);
    try std.testing.expectEqualStrings("Hello 世界 🌍", decoded);
}

// Test: Zero values
test "msgpack handles zero values for all numeric types" {
    const zero_int = msgpack.int(0);
    try std.testing.expectEqual(@as(i64, 0), try msgpack.expectI64(zero_int));

    const zero_uint = msgpack.uint(0);
    try std.testing.expectEqual(@as(u64, 0), try msgpack.expectU64(zero_uint));

    const zero_float = msgpack.float(0.0);
    try std.testing.expect(zero_float == .float);
}

// Test: Maximum integer values
test "msgpack handles maximum integer values" {
    const max_i64 = msgpack.int(std.math.maxInt(i64));
    const value_i64 = try msgpack.expectI64(max_i64);
    try std.testing.expectEqual(std.math.maxInt(i64), value_i64);

    const max_u64 = msgpack.uint(std.math.maxInt(u64));
    const value_u64 = try msgpack.expectU64(max_u64);
    try std.testing.expectEqual(std.math.maxInt(u64), value_u64);
}

// Test: Minimum integer values
test "msgpack handles minimum integer values" {
    const min_i64 = msgpack.int(std.math.minInt(i64));
    const value = try msgpack.expectI64(min_i64);
    try std.testing.expectEqual(std.math.minInt(i64), value);
}

// Test: Float edge cases
test "msgpack handles float edge cases" {
    const inf = msgpack.float(std.math.inf(f64));
    try std.testing.expect(inf == .float);

    const neg_inf = msgpack.float(-std.math.inf(f64));
    try std.testing.expect(neg_inf == .float);

    const nan = msgpack.float(std.math.nan(f64));
    try std.testing.expect(nan == .float);
}

// Test: Empty maps
test "msgpack handles empty maps" {
    const allocator = std.testing.allocator;

    var empty_map = msgpack.Value.mapPayload(allocator);
    defer empty_map.free(allocator);

    try std.testing.expect(empty_map == .map);
    try std.testing.expectEqual(@as(usize, 0), empty_map.map.count());
}

// Test: Single element arrays
test "msgpack handles single element arrays" {
    const allocator = std.testing.allocator;

    const single = try msgpack.array(allocator, &[_]msgpack.Value{msgpack.int(42)});
    defer msgpack.free(single, allocator);

    const arr = try msgpack.expectArray(single);
    try std.testing.expectEqual(@as(usize, 1), arr.len);
    try std.testing.expectEqual(@as(i64, 42), try msgpack.expectI64(arr[0]));
}

// Test: Request with very long method name
test "protocol handles long method names" {
    const allocator = std.testing.allocator;

    const long_method = try allocator.alloc(u8, 1000);
    defer allocator.free(long_method);
    @memset(long_method, 'a');

    var params = try msgpack.Value.arrPayload(0, allocator);
    defer params.free(allocator);

    const request = protocol.message.Request{
        .msgid = 1,
        .method = long_method,
        .params = params,
    };

    const encoded = try protocol.encoder.encodeRequest(allocator, request);
    defer allocator.free(encoded);

    var decoded = try protocol.decoder.decode(allocator, encoded);
    defer protocol.message.deinitMessage(&decoded.message, allocator);

    switch (decoded.message) {
        .Request => |req| {
            try std.testing.expectEqual(@as(usize, 1000), req.method.len);
        },
        else => return error.UnexpectedMessageType,
    }
}

// Test: Notification with maximum parameters
test "protocol handles notifications with many parameters" {
    const allocator = std.testing.allocator;

    const param_count = 100;
    var params = try msgpack.Value.arrPayload(param_count, allocator);
    defer params.free(allocator);

    var i: usize = 0;
    while (i < param_count) : (i += 1) {
        params.arr[i] = msgpack.int(@intCast(i));
    }

    const notification = protocol.message.Notification{
        .method = "test_method",
        .params = params,
    };

    const encoded = try protocol.encoder.encodeNotification(allocator, notification);
    defer allocator.free(encoded);

    var decoded = try protocol.decoder.decode(allocator, encoded);
    defer protocol.message.deinitMessage(&decoded.message, allocator);

    switch (decoded.message) {
        .Notification => |notif| {
            const arr_len = try notif.params.getArrLen();
            try std.testing.expectEqual(@as(usize, param_count), arr_len);
        },
        else => return error.UnexpectedMessageType,
    }
}

// Test: Binary data edge cases
test "msgpack handles empty binary data" {
    const allocator = std.testing.allocator;

    const empty_binary = try msgpack.binary(allocator, &[_]u8{});
    defer msgpack.free(empty_binary, allocator);

    try std.testing.expect(empty_binary == .bin);
}

// Test: Binary data with nulls
test "msgpack handles binary data containing nulls" {
    const allocator = std.testing.allocator;

    const data_with_nulls = [_]u8{ 0x00, 0x01, 0x00, 0x02, 0x00 };
    const binary = try msgpack.binary(allocator, &data_with_nulls);
    defer msgpack.free(binary, allocator);

    try std.testing.expect(binary == .bin);
}

// Test: Consecutive nil values
test "msgpack handles multiple consecutive nil values" {
    const allocator = std.testing.allocator;

    const nils = try msgpack.array(allocator, &[_]msgpack.Value{
        msgpack.nil(),
        msgpack.nil(),
        msgpack.nil(),
    });
    defer msgpack.free(nils, allocator);

    const arr = try msgpack.expectArray(nils);
    try std.testing.expectEqual(@as(usize, 3), arr.len);
    try std.testing.expect(arr[0] == .nil);
    try std.testing.expect(arr[1] == .nil);
    try std.testing.expect(arr[2] == .nil);
}

// Test: Mixed type arrays
test "msgpack handles arrays with mixed types" {
    const allocator = std.testing.allocator;

    const str = try msgpack.string(allocator, "test");

    const mixed = try msgpack.array(allocator, &[_]msgpack.Value{
        msgpack.int(42),
        msgpack.boolean(true),
        str,
        msgpack.nil(),
        msgpack.float(3.14),
    });
    // Only free the mixed array, which will free all contained values including str
    defer msgpack.free(mixed, allocator);

    const arr = try msgpack.expectArray(mixed);
    try std.testing.expectEqual(@as(usize, 5), arr.len);

    try std.testing.expectEqual(@as(i64, 42), try msgpack.expectI64(arr[0]));
    try std.testing.expectEqual(true, try msgpack.expectBool(arr[1]));
    try std.testing.expectEqualStrings("test", try msgpack.expectString(arr[2]));
    try std.testing.expect(arr[3] == .nil);
    try std.testing.expect(arr[4] == .float);
}

// Test: Response with error but no result
test "protocol handles response with only error field" {
    const allocator = std.testing.allocator;

    const error_msg = try msgpack.string(allocator, "Something went wrong");
    defer msgpack.free(error_msg, allocator);

    const response = protocol.message.Response{
        .msgid = 5,
        .@"error" = error_msg,
        .result = null,
    };

    try std.testing.expect(response.@"error" != null);
    try std.testing.expect(response.result == null);
}

// Test: Response with result but no error
test "protocol handles response with only result field" {
    const response = protocol.message.Response{
        .msgid = 6,
        .@"error" = null,
        .result = msgpack.int(123),
    };

    try std.testing.expect(response.@"error" == null);
    try std.testing.expect(response.result != null);
}

// Test: Struct with optional fields all null
test "msgpack handles struct with all optional fields null" {
    const allocator = std.testing.allocator;

    const TestStruct = struct {
        a: ?i32,
        b: ?[]const u8,
        c: ?bool,
    };

    const obj = try msgpack.object(allocator, TestStruct{
        .a = null,
        .b = null,
        .c = null,
    });
    defer msgpack.free(obj, allocator);

    try std.testing.expect(obj == .map);
    try std.testing.expectEqual(@as(usize, 3), obj.map.count());

    const a_val = obj.map.get("a").?;
    try std.testing.expect(a_val == .nil);

    const b_val = obj.map.get("b").?;
    try std.testing.expect(b_val == .nil);

    const c_val = obj.map.get("c").?;
    try std.testing.expect(c_val == .nil);
}

// Test: Very small timeout values
test "client init accepts zero timeout" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .timeout_ms = 0,
    });
    defer client.deinit();

    try std.testing.expectEqual(@as(u32, 0), client.options.timeout_ms);
}

// Test: Very large timeout values
test "client init accepts large timeout values" {
    const allocator = std.testing.allocator;

    const large_timeout = std.math.maxInt(u32);
    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .timeout_ms = large_timeout,
    });
    defer client.deinit();

    try std.testing.expectEqual(large_timeout, client.options.timeout_ms);
}

// Test: Client with skip_api_info flag
test "client respects skip_api_info flag" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .skip_api_info = true,
    });
    defer client.deinit();

    try std.testing.expectEqual(true, client.options.skip_api_info);
    try std.testing.expect(client.api_info == null);
}

// Test: Multiple rapid init/deinit cycles
test "client handles rapid init deinit cycles" {
    const allocator = std.testing.allocator;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var client = try Client.init(allocator, .{
            .socket_path = "/tmp/test.sock",
        });
        client.deinit();
    }
}
