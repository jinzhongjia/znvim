const std = @import("std");
const protocol = @import("../protocol/mod.zig");
const message = protocol.message;
const encoder = protocol.encoder;
const decoder = protocol.decoder;
const payload_utils = protocol.payload_utils;
const msgpack = @import("msgpack");

// ============================================================================
// Encoder: 边界条件测试
// ============================================================================

test "encoder: encode request with empty method name" {
    const allocator = std.testing.allocator;

    const params = try msgpack.Payload.arrPayload(0, allocator);
    var req = message.Request{
        .msgid = 1,
        .method = "",
        .params = params,
    };
    defer req.deinit(allocator);

    const bytes = try encoder.encodeRequest(allocator, req);
    defer allocator.free(bytes);

    try std.testing.expect(bytes.len > 0);
}

test "encoder: encode request with empty params array" {
    const allocator = std.testing.allocator;

    const params = try msgpack.Payload.arrPayload(0, allocator);
    var req = message.Request{
        .msgid = 1,
        .method = "test_method",
        .params = params,
    };
    defer req.deinit(allocator);

    const bytes = try encoder.encodeRequest(allocator, req);
    defer allocator.free(bytes);

    var decoded = try decoder.decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    try std.testing.expect(decoded.message == .Request);
    try std.testing.expectEqual(@as(usize, 0), try decoded.message.Request.params.getArrLen());
}

test "encoder: encode request with msgid=0" {
    const allocator = std.testing.allocator;

    const params = try msgpack.Payload.arrPayload(0, allocator);
    var req = message.Request{
        .msgid = 0,
        .method = "test",
        .params = params,
    };
    defer req.deinit(allocator);

    const bytes = try encoder.encodeRequest(allocator, req);
    defer allocator.free(bytes);

    var decoded = try decoder.decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    try std.testing.expectEqual(@as(u32, 0), decoded.message.Request.msgid);
}

test "encoder: encode request with max msgid" {
    const allocator = std.testing.allocator;

    const params = try msgpack.Payload.arrPayload(0, allocator);
    var req = message.Request{
        .msgid = std.math.maxInt(u32),
        .method = "test",
        .params = params,
    };
    defer req.deinit(allocator);

    const bytes = try encoder.encodeRequest(allocator, req);
    defer allocator.free(bytes);

    var decoded = try decoder.decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    try std.testing.expectEqual(std.math.maxInt(u32), decoded.message.Request.msgid);
}

test "encoder: encode response with both error and result" {
    const allocator = std.testing.allocator;

    const err_payload = try msgpack.Payload.strToPayload("error message", allocator);
    const result_payload = msgpack.Payload.intToPayload(42);

    var resp = message.Response{
        .msgid = 1,
        .@"error" = err_payload,
        .result = result_payload,
    };
    defer resp.deinit(allocator);

    const bytes = try encoder.encodeResponse(allocator, resp);
    defer allocator.free(bytes);

    var decoded = try decoder.decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    try std.testing.expect(decoded.message.Response.@"error" != null);
    try std.testing.expect(decoded.message.Response.result != null);
}

test "encoder: encode notification with empty method" {
    const allocator = std.testing.allocator;

    const params = try msgpack.Payload.arrPayload(0, allocator);
    var notif = message.Notification{
        .method = "",
        .params = params,
    };
    defer notif.deinit(allocator);

    const bytes = try encoder.encodeNotification(allocator, notif);
    defer allocator.free(bytes);

    var decoded = try decoder.decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    try std.testing.expectEqualStrings("", decoded.message.Notification.method);
}

test "encoder: encode notification with empty params" {
    const allocator = std.testing.allocator;

    const params = try msgpack.Payload.arrPayload(0, allocator);
    var notif = message.Notification{
        .method = "test_notif",
        .params = params,
    };
    defer notif.deinit(allocator);

    const bytes = try encoder.encodeNotification(allocator, notif);
    defer allocator.free(bytes);

    var decoded = try decoder.decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    try std.testing.expectEqual(@as(usize, 0), try decoded.message.Notification.params.getArrLen());
}

// ============================================================================
// Decoder: 错误路径测试
// ============================================================================

test "decoder: reject empty input" {
    const allocator = std.testing.allocator;

    const empty_bytes: []const u8 = &.{};
    const result = decoder.decode(allocator, empty_bytes);

    try std.testing.expectError(error.LengthReading, result);
}

test "decoder: reject incomplete message" {
    const allocator = std.testing.allocator;

    const incomplete_bytes: []const u8 = &[_]u8{0x94}; // just array marker
    const result = decoder.decode(allocator, incomplete_bytes);

    try std.testing.expectError(error.LengthReading, result);
}

// ============================================================================
// payload_utils: 深拷贝测试（特别是 map）
// ============================================================================

test "payload_utils: clone empty map" {
    const allocator = std.testing.allocator;

    var original = msgpack.Payload.mapPayload(allocator);
    defer original.free(allocator);

    const cloned = try payload_utils.clonePayload(allocator, original);
    defer cloned.free(allocator);

    try std.testing.expect(cloned == .map);
    try std.testing.expectEqual(@as(usize, 0), cloned.map.count());
}

test "payload_utils: clone map with single entry" {
    const allocator = std.testing.allocator;

    var original = msgpack.Payload.mapPayload(allocator);
    defer original.free(allocator);

    const key = try allocator.dupe(u8, "key1");
    const value = msgpack.Payload.intToPayload(42);
    try original.map.put(key, value);

    const cloned = try payload_utils.clonePayload(allocator, original);
    defer cloned.free(allocator);

    try std.testing.expect(cloned == .map);
    try std.testing.expectEqual(@as(usize, 1), cloned.map.count());

    const cloned_value = cloned.map.get("key1");
    try std.testing.expect(cloned_value != null);
    try std.testing.expectEqual(@as(i64, 42), cloned_value.?.int);
}

test "payload_utils: clone map with multiple entries" {
    const allocator = std.testing.allocator;

    var original = msgpack.Payload.mapPayload(allocator);
    defer original.free(allocator);

    const key1 = try allocator.dupe(u8, "key1");
    const key2 = try allocator.dupe(u8, "key2");
    const key3 = try allocator.dupe(u8, "key3");

    try original.map.put(key1, msgpack.Payload.intToPayload(1));
    try original.map.put(key2, msgpack.Payload.boolToPayload(true));
    try original.map.put(key3, try msgpack.Payload.strToPayload("value3", allocator));

    const cloned = try payload_utils.clonePayload(allocator, original);
    defer cloned.free(allocator);

    try std.testing.expectEqual(@as(usize, 3), cloned.map.count());

    try std.testing.expectEqual(@as(i64, 1), cloned.map.get("key1").?.int);
    try std.testing.expectEqual(true, cloned.map.get("key2").?.bool);
    try std.testing.expectEqualStrings("value3", cloned.map.get("key3").?.str.value());
}

test "payload_utils: clone nested map" {
    const allocator = std.testing.allocator;

    var inner_map = msgpack.Payload.mapPayload(allocator);
    const inner_key = try allocator.dupe(u8, "inner_key");
    try inner_map.map.put(inner_key, msgpack.Payload.intToPayload(99));

    var outer_map = msgpack.Payload.mapPayload(allocator);
    defer outer_map.free(allocator);
    const outer_key = try allocator.dupe(u8, "outer_key");
    try outer_map.map.put(outer_key, inner_map);

    const cloned = try payload_utils.clonePayload(allocator, outer_map);
    defer cloned.free(allocator);

    try std.testing.expectEqual(@as(usize, 1), cloned.map.count());

    const cloned_inner = cloned.map.get("outer_key");
    try std.testing.expect(cloned_inner != null);
    try std.testing.expect(cloned_inner.? == .map);
    try std.testing.expectEqual(@as(usize, 1), cloned_inner.?.map.count());
    try std.testing.expectEqual(@as(i64, 99), cloned_inner.?.map.get("inner_key").?.int);
}

test "payload_utils: clone map with array values" {
    const allocator = std.testing.allocator;

    var arr = try msgpack.Payload.arrPayload(2, allocator);
    arr.arr[0] = msgpack.Payload.intToPayload(1);
    arr.arr[1] = msgpack.Payload.intToPayload(2);

    var original = msgpack.Payload.mapPayload(allocator);
    defer original.free(allocator);
    const key = try allocator.dupe(u8, "array_key");
    try original.map.put(key, arr);

    const cloned = try payload_utils.clonePayload(allocator, original);
    defer cloned.free(allocator);

    const cloned_arr = cloned.map.get("array_key");
    try std.testing.expect(cloned_arr != null);
    try std.testing.expect(cloned_arr.? == .arr);
    try std.testing.expectEqual(@as(usize, 2), cloned_arr.?.arr.len);
    try std.testing.expectEqual(@as(i64, 1), cloned_arr.?.arr[0].int);
    try std.testing.expectEqual(@as(i64, 2), cloned_arr.?.arr[1].int);
}

test "payload_utils: clone map is independent of original" {
    const allocator = std.testing.allocator;

    var original = msgpack.Payload.mapPayload(allocator);
    defer original.free(allocator);

    const key1 = try allocator.dupe(u8, "key1");
    try original.map.put(key1, msgpack.Payload.intToPayload(100));

    const cloned = try payload_utils.clonePayload(allocator, original);
    defer cloned.free(allocator);

    // Modify original after cloning
    const key2 = try allocator.dupe(u8, "key2");
    try original.map.put(key2, msgpack.Payload.intToPayload(200));

    // Cloned should not be affected
    try std.testing.expectEqual(@as(usize, 1), cloned.map.count());
    try std.testing.expect(cloned.map.get("key2") == null);
}

test "payload_utils: clone binary data" {
    const allocator = std.testing.allocator;

    const binary_data = [_]u8{ 0x00, 0x01, 0xFF, 0x7F, 0x80 };
    const original = try msgpack.Payload.binToPayload(&binary_data, allocator);
    defer original.free(allocator);

    const cloned = try payload_utils.clonePayload(allocator, original);
    defer cloned.free(allocator);

    try std.testing.expect(cloned == .bin);
    try std.testing.expectEqualSlices(u8, &binary_data, cloned.bin.value());
}

test "payload_utils: clone ext type" {
    const allocator = std.testing.allocator;

    const ext_data = [_]u8{ 0xAA, 0xBB, 0xCC };
    const original = try msgpack.Payload.extToPayload(42, &ext_data, allocator);
    defer original.free(allocator);

    const cloned = try payload_utils.clonePayload(allocator, original);
    defer cloned.free(allocator);

    try std.testing.expect(cloned == .ext);
    try std.testing.expectEqual(@as(i8, 42), cloned.ext.type);
    try std.testing.expectEqualSlices(u8, &ext_data, cloned.ext.data);
}

test "payload_utils: clone timestamp" {
    const allocator = std.testing.allocator;

    const original = msgpack.Payload.timestampToPayload(1234567890, 999999999);

    const cloned = try payload_utils.clonePayload(allocator, original);
    defer cloned.free(allocator);

    try std.testing.expect(cloned == .timestamp);
    try std.testing.expectEqual(@as(i64, 1234567890), cloned.timestamp.seconds);
    try std.testing.expectEqual(@as(u32, 999999999), cloned.timestamp.nanoseconds);
}

// ============================================================================
// 综合测试：复杂消息的编码和解码
// ============================================================================

test "roundtrip: request with complex params" {
    const allocator = std.testing.allocator;

    // Create complex params: [42, "text", true, null, [1, 2, 3]]
    var params = try msgpack.Payload.arrPayload(5, allocator);
    params.arr[0] = msgpack.Payload.intToPayload(42);
    params.arr[1] = try msgpack.Payload.strToPayload("text", allocator);
    params.arr[2] = msgpack.Payload.boolToPayload(true);
    params.arr[3] = msgpack.Payload.nilToPayload();

    var nested_arr = try msgpack.Payload.arrPayload(3, allocator);
    nested_arr.arr[0] = msgpack.Payload.intToPayload(1);
    nested_arr.arr[1] = msgpack.Payload.intToPayload(2);
    nested_arr.arr[2] = msgpack.Payload.intToPayload(3);
    params.arr[4] = nested_arr;

    var req = message.Request{
        .msgid = 123,
        .method = "complex_method",
        .params = params,
    };
    defer req.deinit(allocator);

    const bytes = try encoder.encodeRequest(allocator, req);
    defer allocator.free(bytes);

    var decoded = try decoder.decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    try std.testing.expect(decoded.message == .Request);
    try std.testing.expectEqual(@as(u32, 123), decoded.message.Request.msgid);
    try std.testing.expectEqualStrings("complex_method", decoded.message.Request.method);
    try std.testing.expectEqual(@as(usize, 5), try decoded.message.Request.params.getArrLen());
}

test "roundtrip: response with error array" {
    const allocator = std.testing.allocator;

    // Error as array: [1, "Error message"]
    var err_arr = try msgpack.Payload.arrPayload(2, allocator);
    err_arr.arr[0] = msgpack.Payload.intToPayload(1);
    err_arr.arr[1] = try msgpack.Payload.strToPayload("Error message", allocator);

    var resp = message.Response{
        .msgid = 456,
        .@"error" = err_arr,
        .result = null,
    };
    defer resp.deinit(allocator);

    const bytes = try encoder.encodeResponse(allocator, resp);
    defer allocator.free(bytes);

    var decoded = try decoder.decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    try std.testing.expect(decoded.message == .Response);
    try std.testing.expectEqual(@as(u32, 456), decoded.message.Response.msgid);
    try std.testing.expect(decoded.message.Response.@"error" != null);
    try std.testing.expect(decoded.message.Response.result == null);
}
