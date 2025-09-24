const std = @import("std");
const msgpack = @import("msgpack");

/// Enumerates the three message kinds defined by the MessagePack-RPC protocol.
pub const MessageType = enum(u8) {
    Request = 0,
    Response = 1,
    Notification = 2,
};

/// MessagePack-RPC request envelope with method name and parameters.
pub const Request = struct {
    type: MessageType = .Request,
    msgid: u32,
    method: []const u8,
    method_owned: bool = false,
    params: msgpack.Payload,

    pub fn deinit(self: *Request, allocator: std.mem.Allocator) void {
        if (self.method_owned) {
            allocator.free(self.method);
        }
        self.params.free(allocator);
    }
};

/// MessagePack-RPC response envelope with optional error or result payload.
pub const Response = struct {
    type: MessageType = .Response,
    msgid: u32,
    @"error": ?msgpack.Payload = null,
    result: ?msgpack.Payload = null,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        if (self.@"error") |*err_payload| {
            err_payload.*.free(allocator);
            self.@"error" = null;
        }
        if (self.result) |*res_payload| {
            res_payload.*.free(allocator);
            self.result = null;
        }
    }
};

/// MessagePack-RPC notification carrying a method and payload without expecting a reply.
pub const Notification = struct {
    type: MessageType = .Notification,
    method: []const u8,
    method_owned: bool = false,
    params: msgpack.Payload,

    pub fn deinit(self: *Notification, allocator: std.mem.Allocator) void {
        if (self.method_owned) {
            allocator.free(self.method);
        }
        self.params.free(allocator);
    }
};

/// Tagged union that stores any of the supported message envelopes.
pub const AnyMessage = union(MessageType) {
    Request: Request,
    Response: Response,
    Notification: Notification,
};

/// Disposes whatever payload is currently stored in a message union.
pub fn deinitMessage(message: *AnyMessage, allocator: std.mem.Allocator) void {
    switch (message.*) {
        .Request => |*req| req.deinit(allocator),
        .Response => |*resp| resp.deinit(allocator),
        .Notification => |*notif| notif.deinit(allocator),
    }
}
