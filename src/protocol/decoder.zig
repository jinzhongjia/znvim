const std = @import("std");
const msgpack = @import("msgpack");
const message = @import("message.zig");
const payload_utils = @import("payload_utils.zig");
const encoder = @import("encoder.zig");

/// Minimal writer used to satisfy the msgpack reader/writer interface.
const DummyWriterContext = struct {
    pub const Error = error{};

    pub fn write(_: *DummyWriterContext, _: []const u8) Error!usize {
        return 0;
    }
};

/// Stateful reader that lets msgpack consume from the provided byte slice.
const ReaderContext = struct {
    data: []const u8,
    position: usize = 0,

    pub const Error = error{};

    pub fn read(self: *ReaderContext, dest: []u8) Error!usize {
        if (self.position >= self.data.len) {
            return 0;
        }
        const remaining = self.data.len - self.position;
        const amount = @min(dest.len, remaining);
        @memcpy(dest[0..amount], self.data[self.position..][0..amount]);
        self.position += amount;
        return amount;
    }
};

const Packer = msgpack.Pack(
    *DummyWriterContext,
    *ReaderContext,
    DummyWriterContext.Error,
    ReaderContext.Error,
    DummyWriterContext.write,
    ReaderContext.read,
);

pub const DecodeError = msgpack.MsGPackError || std.mem.Allocator.Error || error{
    InvalidMessageFormat,
    InvalidMessageType,
    InvalidFieldType,
};

pub const DecodeResult = struct {
    message: message.AnyMessage,
    bytes_read: usize,
};

/// Parses a MessagePack-RPC frame from the given bytes and reports how many were consumed.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!DecodeResult {
    var writer_ctx = DummyWriterContext{};
    var reader_ctx = ReaderContext{ .data = bytes };
    var packer = Packer.init(&writer_ctx, &reader_ctx);

    var payload = try packer.read(allocator);
    defer payload.free(allocator);

    const root = switch (payload) {
        .arr => |arr| arr,
        else => return error.InvalidMessageFormat,
    };

    if (root.len == 0) return error.InvalidMessageFormat;

    const msg_type = try extractMessageType(root[0]);

    const result_message = switch (msg_type) {
        .Request => message.AnyMessage{ .Request = try decodeRequest(allocator, root) },
        .Response => message.AnyMessage{ .Response = try decodeResponse(allocator, root) },
        .Notification => message.AnyMessage{ .Notification = try decodeNotification(allocator, root) },
    };

    return DecodeResult{
        .message = result_message,
        .bytes_read = reader_ctx.position,
    };
}

/// Builds a request object from the message array, copying owned data.
fn decodeRequest(allocator: std.mem.Allocator, root: []msgpack.Payload) DecodeError!message.Request {
    if (root.len < 4) return error.InvalidMessageFormat;

    const msgid = try payloadToU32(root[1]);
    const method_slice = try payloadToString(root[2]);
    const method_copy = try payload_utils.copyString(allocator, method_slice);
    const params_copy = try payload_utils.clonePayload(allocator, root[3]);

    return message.Request{
        .msgid = msgid,
        .method = method_copy,
        .method_owned = true,
        .params = params_copy,
    };
}

/// Builds a response object, cloning optional error/result payloads when present.
fn decodeResponse(allocator: std.mem.Allocator, root: []msgpack.Payload) DecodeError!message.Response {
    if (root.len < 4) return error.InvalidMessageFormat;

    const msgid = try payloadToU32(root[1]);

    var error_payload: ?msgpack.Payload = null;
    if (!isNil(root[2])) {
        error_payload = try payload_utils.clonePayload(allocator, root[2]);
    }

    var result_payload: ?msgpack.Payload = null;
    if (!isNil(root[3])) {
        result_payload = try payload_utils.clonePayload(allocator, root[3]);
    }

    return message.Response{
        .msgid = msgid,
        .@"error" = error_payload,
        .result = result_payload,
    };
}

/// Builds a notification object from the message array, copying owned data.
fn decodeNotification(allocator: std.mem.Allocator, root: []msgpack.Payload) DecodeError!message.Notification {
    if (root.len < 3) return error.InvalidMessageFormat;

    const method_slice = try payloadToString(root[1]);
    const method_copy = try payload_utils.copyString(allocator, method_slice);
    const params_copy = try payload_utils.clonePayload(allocator, root[2]);

    return message.Notification{
        .method = method_copy,
        .method_owned = true,
        .params = params_copy,
    };
}

fn payloadToString(value: msgpack.Payload) DecodeError![]const u8 {
    return switch (value) {
        .str => value.str.value(),
        else => error.InvalidFieldType,
    };
}

fn payloadToU32(value: msgpack.Payload) DecodeError!u32 {
    switch (value) {
        .uint => |u| return std.math.cast(u32, u) orelse error.InvalidFieldType,
        .int => |i| return std.math.cast(u32, i) orelse error.InvalidFieldType,
        else => return error.InvalidFieldType,
    }
}

/// Converts the first tuple element into a strongly-typed message kind.
fn extractMessageType(value: msgpack.Payload) DecodeError!message.MessageType {
    const number: u8 = switch (value) {
        .uint => |u| std.math.cast(u8, u) orelse return error.InvalidMessageType,
        .int => |i| std.math.cast(u8, i) orelse return error.InvalidMessageType,
        else => return error.InvalidMessageType,
    };

    return switch (number) {
        0 => message.MessageType.Request,
        1 => message.MessageType.Response,
        2 => message.MessageType.Notification,
        else => error.InvalidMessageType,
    };
}

fn isNil(value: msgpack.Payload) bool {
    return switch (value) {
        .nil => true,
        else => false,
    };
}

test "decode response preserves error and result" {
    const allocator = std.testing.allocator;

    var response = message.Response{
        .msgid = 9,
        .@"error" = try msgpack.Payload.strToPayload("oops", allocator),
        .result = msgpack.Payload.intToPayload(17),
    };
    const bytes = try encoder.encodeResponse(allocator, response);
    defer allocator.free(bytes);
    if (response.@"error") |*err_payload| err_payload.*.free(allocator);
    if (response.result) |*res_payload| res_payload.*.free(allocator);

    var decoded = try decode(allocator, bytes);
    defer message.deinitMessage(&decoded.message, allocator);

    try std.testing.expectEqual(decoded.bytes_read, bytes.len);
    switch (decoded.message) {
        .Response => |resp| {
            try std.testing.expectEqual(@as(u32, 9), resp.msgid);
            const err_payload = resp.@"error" orelse return error.TestExpectedEqual;
            try std.testing.expect(err_payload == .str);
            try std.testing.expectEqualStrings("oops", err_payload.str.value());
            const result_payload = resp.result orelse return error.TestExpectedEqual;
            const numeric = switch (result_payload) {
                .int => |val| val,
                .uint => |val| std.math.cast(i64, val) orelse return error.TestExpectedEqual,
                else => return error.TestExpectedEqual,
            };
            try std.testing.expectEqual(@as(i64, 17), numeric);
        },
        else => return error.TestExpectedEqual,
    }
}

test "decode rejects unknown message type" {
    const allocator = std.testing.allocator;

    var request = message.Request{
        .msgid = 1,
        .method = "nvim_command",
        .params = try msgpack.Payload.arrPayload(0, allocator),
    };
    defer request.deinit(allocator);

    const valid = try encoder.encodeRequest(allocator, request);
    defer allocator.free(valid);

    var mutated = try allocator.dupe(u8, valid);
    defer allocator.free(mutated);
    mutated[1] = 0x10;

    try std.testing.expectError(error.InvalidMessageType, decode(allocator, mutated));
}
