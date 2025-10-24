const std = @import("std");
const message = @import("../protocol/message.zig");
const encoder = @import("../protocol/encoder.zig");
const decoder = @import("../protocol/decoder.zig");
const msgpack = @import("../msgpack.zig");

// ============================================================================
// Protocol Message 和 Encoder 单元测试
//
// 测试 Request, Response, Notification 消息结构和编解码
// ============================================================================

// ============================================================================
// Test: Request 消息
// ============================================================================

test "Request creation with basic fields" {
    const allocator = std.testing.allocator;

    const params = [_]msgpack.Value{};
    const request = message.Request{
        .msgid = 1,
        .method = "test_method",
        .params = msgpack.Value{ .arr = &params },
    };

    try std.testing.expectEqual(@as(u32, 1), request.msgid);
    try std.testing.expectEqual(message.MessageType.Request, request.type);
    try std.testing.expectEqualStrings("test_method", request.method);
    try std.testing.expect(!request.method_owned);
    try std.testing.expect(request.params == .arr);

    _ = allocator;
}

test "Request with owned method string" {
    const allocator = std.testing.allocator;

    const method = try allocator.dupe(u8, "owned_method");
    defer allocator.free(method);

    var request = message.Request{
        .msgid = 5,
        .method = method,
        .method_owned = true,
        .params = msgpack.nil(),
    };

    try std.testing.expect(request.method_owned);
    try std.testing.expectEqualStrings("owned_method", request.method);

    // deinit 应该释放 method
    request.deinit(allocator);
}

test "Request with various msgid values" {
    const test_ids = [_]u32{ 0, 1, 100, 65535, std.math.maxInt(u32) };

    for (test_ids) |test_id| {
        const request = message.Request{
            .msgid = test_id,
            .method = "test",
            .params = msgpack.nil(),
        };

        try std.testing.expectEqual(test_id, request.msgid);
    }
}

test "Request with different param types" {
    const allocator = std.testing.allocator;

    // nil params
    var req1 = message.Request{
        .msgid = 1,
        .method = "method1",
        .params = msgpack.nil(),
    };
    try std.testing.expect(req1.params == .nil);

    // array params
    const params = [_]msgpack.Value{msgpack.int(42)};
    var req2 = message.Request{
        .msgid = 2,
        .method = "method2",
        .params = msgpack.Value{ .arr = &params },
    };
    try std.testing.expect(req2.params == .arr);
    try std.testing.expectEqual(@as(usize, 1), req2.params.arr.len);

    // object params
    var map_params = msgpack.Value.mapPayload(allocator);
    defer map_params.free(allocator);

    var req3 = message.Request{
        .msgid = 3,
        .method = "method3",
        .params = map_params,
    };
    try std.testing.expect(req3.params == .map);
}

// ============================================================================
// Test: Response 消息
// ============================================================================

test "Response creation with result" {
    const allocator = std.testing.allocator;

    const result_value = msgpack.int(42);
    const response = message.Response{
        .msgid = 1,
        .result = result_value,
        .@"error" = null,
    };

    try std.testing.expectEqual(@as(u32, 1), response.msgid);
    try std.testing.expectEqual(message.MessageType.Response, response.type);
    try std.testing.expect(response.result != null);
    try std.testing.expect(response.@"error" == null);
    try std.testing.expectEqual(@as(i64, 42), response.result.?.int);

    _ = allocator;
}

test "Response creation with error" {
    const allocator = std.testing.allocator;

    const error_value = try msgpack.string(allocator, "Error message");
    defer msgpack.free(error_value, allocator);

    const response = message.Response{
        .msgid = 2,
        .result = null,
        .@"error" = error_value,
    };

    try std.testing.expectEqual(@as(u32, 2), response.msgid);
    try std.testing.expect(response.result == null);
    try std.testing.expect(response.@"error" != null);
}

test "Response with both error and result" {
    const allocator = std.testing.allocator;

    // 虽然不推荐，但协议允许同时有 error 和 result
    const response = message.Response{
        .msgid = 3,
        .result = msgpack.int(1),
        .@"error" = msgpack.int(0),
    };

    try std.testing.expect(response.result != null);
    try std.testing.expect(response.@"error" != null);

    _ = allocator;
}

test "Response deinit cleans up owned values" {
    const allocator = std.testing.allocator;

    const result_str = try msgpack.string(allocator, "result");
    const error_str = try msgpack.string(allocator, "error");

    var response = message.Response{
        .msgid = 4,
        .result = result_str,
        .@"error" = error_str,
    };

    // deinit 应该释放两个值
    response.deinit(allocator);
}

// ============================================================================
// Test: Notification 消息
// ============================================================================

test "Notification creation with basic fields" {
    const allocator = std.testing.allocator;

    const params = [_]msgpack.Value{};
    const notification = message.Notification{
        .method = "notify_method",
        .params = msgpack.Value{ .arr = &params },
    };

    try std.testing.expectEqual(message.MessageType.Notification, notification.type);
    try std.testing.expectEqualStrings("notify_method", notification.method);
    try std.testing.expect(!notification.method_owned);

    _ = allocator;
}

test "Notification with owned method" {
    const allocator = std.testing.allocator;

    const method = try allocator.dupe(u8, "owned_notification");
    defer allocator.free(method);

    var notification = message.Notification{
        .method = method,
        .method_owned = true,
        .params = msgpack.nil(),
    };

    try std.testing.expect(notification.method_owned);

    notification.deinit(allocator);
}

test "Notification with various param types" {
    const allocator = std.testing.allocator;

    // nil params
    var notif1 = message.Notification{
        .method = "notify1",
        .params = msgpack.nil(),
    };
    try std.testing.expect(notif1.params == .nil);

    // array params
    const params = [_]msgpack.Value{
        msgpack.int(1),
        msgpack.int(2),
    };
    var notif2 = message.Notification{
        .method = "notify2",
        .params = msgpack.Value{ .arr = &params },
    };
    try std.testing.expect(notif2.params == .arr);
    try std.testing.expectEqual(@as(usize, 2), notif2.params.arr.len);

    _ = allocator;
}

// ============================================================================
// Test: AnyMessage union
// ============================================================================

test "AnyMessage with Request" {
    const request = message.Request{
        .msgid = 1,
        .method = "test",
        .params = msgpack.nil(),
    };

    const any_msg = message.AnyMessage{ .Request = request };

    try std.testing.expect(any_msg == .Request);
    try std.testing.expectEqual(@as(u32, 1), any_msg.Request.msgid);
}

test "AnyMessage with Response" {
    const response = message.Response{
        .msgid = 2,
        .result = msgpack.int(42),
        .@"error" = null,
    };

    const any_msg = message.AnyMessage{ .Response = response };

    try std.testing.expect(any_msg == .Response);
    try std.testing.expectEqual(@as(u32, 2), any_msg.Response.msgid);
}

test "AnyMessage with Notification" {
    const notification = message.Notification{
        .method = "notify",
        .params = msgpack.nil(),
    };

    const any_msg = message.AnyMessage{ .Notification = notification };

    try std.testing.expect(any_msg == .Notification);
    try std.testing.expectEqualStrings("notify", any_msg.Notification.method);
}

// ============================================================================
// Test: Encoder - Request 编码
// ============================================================================

test "Encoder encodes request with empty method" {
    const allocator = std.testing.allocator;

    const params = [_]msgpack.Value{};
    const request = message.Request{
        .msgid = 1,
        .method = "",
        .params = msgpack.Value{ .arr = &params },
    };

    const encoded = try encoder.encodeRequest(allocator, request);
    defer allocator.free(encoded);

    // 应该成功编码
    try std.testing.expect(encoded.len > 0);
}

test "Encoder encodes request with long method name" {
    const allocator = std.testing.allocator;

    // 创建一个很长的方法名
    var long_method: [256]u8 = undefined;
    @memset(&long_method, 'a');

    const params = [_]msgpack.Value{};
    const request = message.Request{
        .msgid = 1,
        .method = &long_method,
        .params = msgpack.Value{ .arr = &params },
    };

    const encoded = try encoder.encodeRequest(allocator, request);
    defer allocator.free(encoded);

    try std.testing.expect(encoded.len > 256);
}

test "Encoder encodes request with complex params" {
    const allocator = std.testing.allocator;

    const str1 = try msgpack.string(allocator, "param1");
    defer msgpack.free(str1, allocator);

    const params = [_]msgpack.Value{
        msgpack.int(42),
        str1,
        msgpack.boolean(true),
    };

    const request = message.Request{
        .msgid = 100,
        .method = "complex_method",
        .params = msgpack.Value{ .arr = &params },
    };

    const encoded = try encoder.encodeRequest(allocator, request);
    defer allocator.free(encoded);

    // 应该包含所有参数
    try std.testing.expect(encoded.len > 10);
}

// ============================================================================
// Test: Encoder - Response 编码
// ============================================================================

test "Encoder encodes response with null result" {
    const allocator = std.testing.allocator;

    const response = message.Response{
        .msgid = 1,
        .result = msgpack.nil(),
        .@"error" = null,
    };

    const encoded = try encoder.encodeResponse(allocator, response);
    defer allocator.free(encoded);

    try std.testing.expect(encoded.len > 0);
}

test "Encoder encodes response with complex result" {
    const allocator = std.testing.allocator;

    var map_result = msgpack.Value.mapPayload(allocator);
    defer map_result.free(allocator);

    const key_str = try msgpack.string(allocator, "status");
    try map_result.map.put("status", key_str);

    const response = message.Response{
        .msgid = 2,
        .result = map_result,
        .@"error" = null,
    };

    const encoded = try encoder.encodeResponse(allocator, response);
    defer allocator.free(encoded);

    try std.testing.expect(encoded.len > 5);
}

test "Encoder encodes response with error array" {
    const allocator = std.testing.allocator;

    const err_code = msgpack.int(1);
    const err_msg = try msgpack.string(allocator, "Error message");
    defer msgpack.free(err_msg, allocator);

    const error_arr = [_]msgpack.Value{ err_code, err_msg };
    const error_value = msgpack.Value{ .arr = &error_arr };

    const response = message.Response{
        .msgid = 3,
        .result = null,
        .@"error" = error_value,
    };

    const encoded = try encoder.encodeResponse(allocator, response);
    defer allocator.free(encoded);

    try std.testing.expect(encoded.len > 10);
}

// ============================================================================
// Test: Encoder - Notification 编码
// ============================================================================

test "Encoder encodes notification with empty params" {
    const allocator = std.testing.allocator;

    const params = [_]msgpack.Value{};
    const notification = message.Notification{
        .method = "notify",
        .params = msgpack.Value{ .arr = &params },
    };

    const encoded = try encoder.encodeNotification(allocator, notification);
    defer allocator.free(encoded);

    try std.testing.expect(encoded.len > 0);
}

test "Encoder encodes notification with params" {
    const allocator = std.testing.allocator;

    const event_str = try msgpack.string(allocator, "BufEnter");
    defer msgpack.free(event_str, allocator);

    const params = [_]msgpack.Value{event_str};
    const notification = message.Notification{
        .method = "nvim_buf_event",
        .params = msgpack.Value{ .arr = &params },
    };

    const encoded = try encoder.encodeNotification(allocator, notification);
    defer allocator.free(encoded);

    try std.testing.expect(encoded.len > 10);
}

// ============================================================================
// Test: Roundtrip - 编码后解码
// ============================================================================

test "Roundtrip request encode and decode" {
    const allocator = std.testing.allocator;

    const params = [_]msgpack.Value{msgpack.int(123)};
    const original = message.Request{
        .msgid = 42,
        .method = "test_roundtrip",
        .params = msgpack.Value{ .arr = &params },
    };

    const encoded = try encoder.encodeRequest(allocator, original);
    defer allocator.free(encoded);

    const decode_result = try decoder.decode(allocator, encoded);
    defer {
        if (decode_result.message) |msg| {
            switch (msg) {
                .Request => |req| {
                    var mut_req = req;
                    mut_req.deinit(allocator);
                },
                .Response => |res| {
                    var mut_res = res;
                    mut_res.deinit(allocator);
                },
                .Notification => |notif| {
                    var mut_notif = notif;
                    mut_notif.deinit(allocator);
                },
            }
        }
    }

    try std.testing.expect(decode_result.message != null);
    const decoded_msg = decode_result.message.?;

    try std.testing.expect(decoded_msg == .Request);
    try std.testing.expectEqual(@as(u32, 42), decoded_msg.Request.msgid);
    try std.testing.expectEqualStrings("test_roundtrip", decoded_msg.Request.method);
}

test "Roundtrip response encode and decode" {
    const allocator = std.testing.allocator;

    const original = message.Response{
        .msgid = 99,
        .result = msgpack.int(456),
        .@"error" = null,
    };

    const encoded = try encoder.encodeResponse(allocator, original);
    defer allocator.free(encoded);

    const decode_result = try decoder.decode(allocator, encoded);
    defer {
        if (decode_result.message) |msg| {
            switch (msg) {
                .Response => |res| {
                    var mut_res = res;
                    mut_res.deinit(allocator);
                },
                else => {},
            }
        }
    }

    try std.testing.expect(decode_result.message != null);
    const decoded_msg = decode_result.message.?;

    try std.testing.expect(decoded_msg == .Response);
    try std.testing.expectEqual(@as(u32, 99), decoded_msg.Response.msgid);
    try std.testing.expect(decoded_msg.Response.result != null);
}

test "Roundtrip notification encode and decode" {
    const allocator = std.testing.allocator;

    const params = [_]msgpack.Value{};
    const original = message.Notification{
        .method = "test_notification",
        .params = msgpack.Value{ .arr = &params },
    };

    const encoded = try encoder.encodeNotification(allocator, original);
    defer allocator.free(encoded);

    const decode_result = try decoder.decode(allocator, encoded);
    defer {
        if (decode_result.message) |msg| {
            switch (msg) {
                .Notification => |notif| {
                    var mut_notif = notif;
                    mut_notif.deinit(allocator);
                },
                else => {},
            }
        }
    }

    try std.testing.expect(decode_result.message != null);
    const decoded_msg = decode_result.message.?;

    try std.testing.expect(decoded_msg == .Notification);
    try std.testing.expectEqualStrings("test_notification", decoded_msg.Notification.method);
}

// ============================================================================
// Test: MessageType enum
// ============================================================================

test "MessageType enum values" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(message.MessageType.Request));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(message.MessageType.Response));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(message.MessageType.Notification));
}

test "MessageType from int" {
    const req_type: message.MessageType = @enumFromInt(0);
    const res_type: message.MessageType = @enumFromInt(1);
    const notif_type: message.MessageType = @enumFromInt(2);

    try std.testing.expectEqual(message.MessageType.Request, req_type);
    try std.testing.expectEqual(message.MessageType.Response, res_type);
    try std.testing.expectEqual(message.MessageType.Notification, notif_type);
}
