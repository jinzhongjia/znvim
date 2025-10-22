const std = @import("std");
const msgpack = @import("msgpack");
const message = @import("message.zig");
const payload_utils = @import("payload_utils.zig");

/// Collects encoded bytes in-memory while the msgpack packer writes into it.
const WriterContext = struct {
    buffer: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    pub const Error = std.mem.Allocator.Error;

    pub fn write(self: *WriterContext, bytes: []const u8) Error!usize {
        try self.buffer.appendSlice(self.allocator, bytes);
        return bytes.len;
    }
};

const ReaderContext = struct {
    /// Reader is unused for encoding but required by the msgpack packer type.
    pub const Error = error{};

    pub fn read(_: *ReaderContext, _: []u8) Error!usize {
        return 0;
    }
};

/// Msgpack packer configured with our writer/reader shims.
const Packer = msgpack.Pack(
    *WriterContext,
    *ReaderContext,
    WriterContext.Error,
    ReaderContext.Error,
    WriterContext.write,
    ReaderContext.read,
);

pub const EncodeError = WriterContext.Error || msgpack.MsgPackError;

/// Serializes a MessagePack-RPC request into a heap-owned byte slice.
pub fn encodeRequest(allocator: std.mem.Allocator, req: message.Request) EncodeError![]u8 {
    var buffer = std.ArrayListUnmanaged(u8){};
    errdefer buffer.deinit(allocator);

    var writer_ctx = WriterContext{ .buffer = &buffer, .allocator = allocator };
    var reader_ctx = ReaderContext{};
    var packer = Packer.init(&writer_ctx, &reader_ctx);

    var payload = try msgpack.Payload.arrPayload(4, allocator);
    defer payload.free(allocator);

    payload.arr[0] = msgpack.Payload.uintToPayload(@intFromEnum(req.type));
    payload.arr[1] = msgpack.Payload.uintToPayload(req.msgid);
    payload.arr[2] = try msgpack.Payload.strToPayload(req.method, allocator);
    payload.arr[3] = try payload_utils.clonePayload(allocator, req.params);

    try packer.write(payload);

    return try buffer.toOwnedSlice(allocator);
}

/// Serializes a MessagePack-RPC notification into a heap-owned byte slice.
pub fn encodeNotification(allocator: std.mem.Allocator, notif: message.Notification) EncodeError![]u8 {
    var buffer = std.ArrayListUnmanaged(u8){};
    errdefer buffer.deinit(allocator);

    var writer_ctx = WriterContext{ .buffer = &buffer, .allocator = allocator };
    var reader_ctx = ReaderContext{};
    var packer = Packer.init(&writer_ctx, &reader_ctx);

    var payload = try msgpack.Payload.arrPayload(3, allocator);
    defer payload.free(allocator);

    payload.arr[0] = msgpack.Payload.uintToPayload(@intFromEnum(notif.type));
    payload.arr[1] = try msgpack.Payload.strToPayload(notif.method, allocator);
    payload.arr[2] = try payload_utils.clonePayload(allocator, notif.params);

    try packer.write(payload);

    return try buffer.toOwnedSlice(allocator);
}

/// Serializes a MessagePack-RPC response, cloning optional error/result payloads as needed.
pub fn encodeResponse(allocator: std.mem.Allocator, resp: message.Response) EncodeError![]u8 {
    var buffer = std.ArrayListUnmanaged(u8){};
    errdefer buffer.deinit(allocator);

    var writer_ctx = WriterContext{ .buffer = &buffer, .allocator = allocator };
    var reader_ctx = ReaderContext{};
    var packer = Packer.init(&writer_ctx, &reader_ctx);

    var payload = try msgpack.Payload.arrPayload(4, allocator);
    defer payload.free(allocator);

    payload.arr[0] = msgpack.Payload.uintToPayload(@intFromEnum(resp.type));
    payload.arr[1] = msgpack.Payload.uintToPayload(resp.msgid);

    const err_opt = resp.@"error";
    payload.arr[2] = blk: {
        if (err_opt) |err_payload| {
            break :blk try payload_utils.clonePayload(allocator, err_payload);
        } else {
            break :blk msgpack.Payload.nilToPayload();
        }
    };

    const result_opt = resp.result;
    payload.arr[3] = blk: {
        if (result_opt) |res_payload| {
            break :blk try payload_utils.clonePayload(allocator, res_payload);
        } else {
            break :blk msgpack.Payload.nilToPayload();
        }
    };

    try packer.write(payload);

    return try buffer.toOwnedSlice(allocator);
}
