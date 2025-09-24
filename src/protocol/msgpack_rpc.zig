const std = @import("std");
const msgpack = @import("msgpack");

pub const message = @import("message.zig");
pub const encoder = @import("encoder.zig");
pub const decoder = @import("decoder.zig");

pub const EncodeError = encoder.EncodeError;
pub const DecodeError = decoder.DecodeError;

pub const encodeRequest = encoder.encodeRequest;
pub const encodeNotification = encoder.encodeNotification;
pub const encodeResponse = encoder.encodeResponse;

pub const decode = decoder.decode;
test "request encode/decode roundtrip" {
    const allocator = std.testing.allocator;

    var request = message.Request{
        .msgid = 42,
        .method = "nvim_get_current_line",
        .params = try msgpack.Payload.arrPayload(0, allocator),
    };
    defer request.deinit(allocator);

    const bytes = try encoder.encodeRequest(allocator, request);
    defer allocator.free(bytes);

    var decoded_result = try decode(allocator, bytes);
    defer message.deinitMessage(&decoded_result.message, allocator);
    try std.testing.expectEqual(@as(usize, bytes.len), decoded_result.bytes_read);

    switch (decoded_result.message) {
        .Request => |decoded_req| {
            try std.testing.expectEqual(@as(u32, 42), decoded_req.msgid);
            try std.testing.expectEqualStrings(request.method, decoded_req.method);
            try std.testing.expectEqual(@as(usize, 0), try decoded_req.params.getArrLen());
        },
        else => return error.UnexpectedMessageType,
    }
}
