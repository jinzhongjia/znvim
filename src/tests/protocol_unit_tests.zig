const std = @import("std");
const protocol = @import("../protocol/mod.zig");
const message = protocol.message;
const encoder = protocol.encoder;
const decoder = protocol.decoder;
const msgpack = @import("msgpack");

// Request deinit should release owned method strings and parameter payloads.
test "message request deinit releases owned data" {
    const allocator = std.testing.allocator;
    const method_copy = try allocator.dupe(u8, "nvim_call");
    var params = try msgpack.Payload.arrPayload(1, allocator);
    params.arr[0] = msgpack.Payload.intToPayload(7);

    var req = message.Request{
        .msgid = 3,
        .method = method_copy,
        .method_owned = true,
        .params = params,
    };

    req.deinit(allocator);
}

// Notification deinit should free any owned payloads.
test "message notification deinit releases payload" {
    const allocator = std.testing.allocator;
    var params = try msgpack.Payload.arrPayload(2, allocator);
    params.arr[0] = msgpack.Payload.boolToPayload(true);
    params.arr[1] = msgpack.Payload.nilToPayload();

    var notif = message.Notification{
        .method = "nvim_echo",
        .params = params,
    };

    notif.deinit(allocator);
}

// Response deinit should clean optional payloads without leaks.
test "message response deinit releases optional payloads" {
    const allocator = std.testing.allocator;
    const err_payload = try msgpack.Payload.strToPayload("boom", allocator);
    var resp = message.Response{
        .msgid = 9,
        .@"error" = err_payload,
        .result = msgpack.Payload.uintToPayload(5),
    };

    resp.deinit(allocator);
}

// Encoding a response with null fields should produce nil placeholders.
test "encode response emits nil placeholders" {
    const allocator = std.testing.allocator;
    const response = message.Response{
        .msgid = 11,
    };

    const bytes = try encoder.encodeResponse(allocator, response);
    defer allocator.free(bytes);

    var decoded = try decoder.decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    switch (decoded.message) {
        .Response => |resp| {
            try std.testing.expectEqual(@as(u32, 11), resp.msgid);
            try std.testing.expect(resp.@"error" == null);
            try std.testing.expect(resp.result == null);
        },
        else => return error.UnexpectedMessageType,
    }
}

// Encoding a notification should preserve the parameter payload content.
test "encode notification preserves payload" {
    const allocator = std.testing.allocator;
    var params = try msgpack.Payload.arrPayload(1, allocator);
    params.arr[0] = msgpack.Payload.intToPayload(123);

    var notif = message.Notification{
        .method = "nvim_set_var",
        .params = params,
    };
    defer notif.deinit(allocator);

    const bytes = try encoder.encodeNotification(allocator, notif);
    defer allocator.free(bytes);

    var decoded = try decoder.decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    switch (decoded.message) {
        .Notification => |decoded_notif| {
            try std.testing.expectEqualStrings("nvim_set_var", decoded_notif.method);
            try std.testing.expectEqual(@as(usize, 1), try decoded_notif.params.getArrLen());
            const element = try decoded_notif.params.getArrElement(0);
            const numeric = switch (element) {
                .int => |value| value,
                .uint => |value| std.math.cast(i64, value) orelse return error.TestExpectedEqual,
                else => return error.TestExpectedEqual,
            };
            try std.testing.expectEqual(@as(i64, 123), numeric);
        },
        else => return error.UnexpectedMessageType,
    }
}
