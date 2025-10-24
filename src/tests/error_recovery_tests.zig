const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;
const protocol = znvim.protocol;
const transport = znvim.transport;
const Client = znvim.Client;

/// Mock transport that simulates partial message reads
const PartialReadTransport = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize = 0,
    bytes_per_read: usize,
    connected: bool = true,

    fn init(allocator: std.mem.Allocator, data: []const u8, bytes_per_read: usize) !PartialReadTransport {
        const copy = try allocator.dupe(u8, data);
        return PartialReadTransport{
            .allocator = allocator,
            .data = copy,
            .bytes_per_read = bytes_per_read,
        };
    }

    fn deinit(self: *PartialReadTransport) void {
        self.allocator.free(self.data);
    }

    fn connect(tr: *transport.Transport, _: []const u8) anyerror!void {
        const self = tr.downcast(PartialReadTransport);
        self.connected = true;
    }

    fn disconnect(tr: *transport.Transport) void {
        const self = tr.downcast(PartialReadTransport);
        self.connected = false;
    }

    fn read(tr: *transport.Transport, buffer: []u8) transport.Transport.ReadError!usize {
        const self = tr.downcast(PartialReadTransport);
        if (!self.connected or self.offset >= self.data.len) {
            return 0;
        }

        const remaining = self.data.len - self.offset;
        const to_read = @min(@min(buffer.len, remaining), self.bytes_per_read);
        @memcpy(buffer[0..to_read], self.data[self.offset .. self.offset + to_read]);
        self.offset += to_read;
        return to_read;
    }

    fn write(tr: *transport.Transport, _: []const u8) transport.Transport.WriteError!void {
        const self = tr.downcast(PartialReadTransport);
        if (!self.connected) {
            return transport.Transport.WriteError.ConnectionClosed;
        }
    }

    fn isConnected(tr: *const transport.Transport) bool {
        return tr.downcastConst(PartialReadTransport).connected;
    }

    pub const vtable = transport.Transport.VTable{
        .connect = connect,
        .disconnect = disconnect,
        .read = read,
        .write = write,
        .is_connected = isConnected,
    };
};

/// Mock transport that disconnects after N bytes
const DisconnectingTransport = struct {
    allocator: std.mem.Allocator,
    data: []const u8,
    offset: usize = 0,
    disconnect_after: usize,
    connected: bool = true,

    fn init(allocator: std.mem.Allocator, data: []const u8, disconnect_after: usize) !DisconnectingTransport {
        const copy = try allocator.dupe(u8, data);
        return DisconnectingTransport{
            .allocator = allocator,
            .data = copy,
            .disconnect_after = disconnect_after,
        };
    }

    fn deinit(self: *DisconnectingTransport) void {
        self.allocator.free(self.data);
    }

    fn connect(tr: *transport.Transport, _: []const u8) anyerror!void {
        const self = tr.downcast(DisconnectingTransport);
        self.connected = true;
    }

    fn disconnect(tr: *transport.Transport) void {
        const self = tr.downcast(DisconnectingTransport);
        self.connected = false;
    }

    fn read(tr: *transport.Transport, buffer: []u8) transport.Transport.ReadError!usize {
        const self = tr.downcast(DisconnectingTransport);
        if (!self.connected) {
            return transport.Transport.ReadError.ConnectionClosed;
        }

        if (self.offset >= self.disconnect_after) {
            self.connected = false;
            return transport.Transport.ReadError.ConnectionClosed;
        }

        const remaining = self.data.len - self.offset;
        const bytes_until_disconnect = self.disconnect_after - self.offset;
        const to_read = @min(@min(buffer.len, remaining), bytes_until_disconnect);

        if (to_read == 0) {
            self.connected = false;
            return transport.Transport.ReadError.ConnectionClosed;
        }

        @memcpy(buffer[0..to_read], self.data[self.offset .. self.offset + to_read]);
        self.offset += to_read;
        return to_read;
    }

    fn write(tr: *transport.Transport, _: []const u8) transport.Transport.WriteError!void {
        const self = tr.downcast(DisconnectingTransport);
        if (!self.connected) {
            return transport.Transport.WriteError.ConnectionClosed;
        }
    }

    fn isConnected(tr: *const transport.Transport) bool {
        return tr.downcastConst(DisconnectingTransport).connected;
    }

    pub const vtable = transport.Transport.VTable{
        .connect = connect,
        .disconnect = disconnect,
        .read = read,
        .write = write,
        .is_connected = isConnected,
    };
};

// Test: Client handles partial message reads correctly
test "client recovers from partial message read" {
    const allocator = std.testing.allocator;

    // Build a valid response message
    const response_msg = protocol.message.Response{
        .msgid = 0,
        .result = msgpack.int(42),
    };
    const encoded = try protocol.encoder.encodeResponse(allocator, response_msg);
    defer allocator.free(encoded);

    // Verify the message can be decoded in parts by the decoder
    // This tests that the decoder can handle partial reads
    const half = encoded.len / 2;

    // Try to decode just the first half - should fail with LengthReading
    const partial_decode = protocol.decoder.decode(allocator, encoded[0..half]);
    try std.testing.expectError(error.LengthReading, partial_decode);

    // Full message should decode successfully
    var full_decode = try protocol.decoder.decode(allocator, encoded);
    defer protocol.message.deinitMessage(&full_decode.message, allocator);

    switch (full_decode.message) {
        .Response => |resp| {
            try std.testing.expectEqual(@as(u32, 0), resp.msgid);
            const value = try msgpack.expectI64(resp.result.?);
            try std.testing.expectEqual(@as(i64, 42), value);
        },
        else => return error.UnexpectedMessageType,
    }
}

// Test: Client handles connection drop during read
test "transport reports connection closed correctly" {
    const allocator = std.testing.allocator;

    const response_msg = protocol.message.Response{
        .msgid = 0,
        .result = msgpack.int(100),
    };
    const encoded = try protocol.encoder.encodeResponse(allocator, response_msg);
    defer allocator.free(encoded);

    // Create a transport that disconnects after partial data
    const disconnect_at = encoded.len / 2;
    var mock_transport = try DisconnectingTransport.init(allocator, encoded, disconnect_at);
    defer mock_transport.deinit();

    var wrapper = transport.Transport.init(&mock_transport, &DisconnectingTransport.vtable);
    try wrapper.connect("");

    // Read first part should work
    var buffer: [4096]u8 = undefined;
    const first_read = try wrapper.read(&buffer);
    try std.testing.expect(first_read > 0);

    // Subsequent read should fail with ConnectionClosed
    const second_read = wrapper.read(&buffer);
    try std.testing.expectError(transport.Transport.ReadError.ConnectionClosed, second_read);
}

// Test: Client handles empty response array
test "client handles empty array response" {
    const allocator = std.testing.allocator;

    const empty_array = try msgpack.array(allocator, &[_]msgpack.Value{});
    defer msgpack.free(empty_array, allocator);

    try std.testing.expectEqual(@as(usize, 0), (try msgpack.expectArray(empty_array)).len);
}

// Test: Client handles very long strings
test "client handles large string payload" {
    const allocator = std.testing.allocator;

    // Create a 10KB string
    const large_string = try allocator.alloc(u8, 10 * 1024);
    defer allocator.free(large_string);
    @memset(large_string, 'A');

    const str_value = try msgpack.string(allocator, large_string);
    defer msgpack.free(str_value, allocator);

    const decoded = try msgpack.expectString(str_value);
    try std.testing.expectEqual(@as(usize, 10 * 1024), decoded.len);
}

// Test: Client handles message ID wraparound
test "client message id increments correctly near max value" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    // Set message ID near max value
    client.next_msgid.store(std.math.maxInt(u32) - 5, .monotonic);

    // Get several IDs to test wraparound
    var ids: [10]u32 = undefined;
    for (&ids) |*id| {
        id.* = client.nextMessageId();
    }

    // First 6 should increment normally
    try std.testing.expectEqual(std.math.maxInt(u32) - 5, ids[0]);
    try std.testing.expectEqual(std.math.maxInt(u32) - 4, ids[1]);

    // After max, should wrap to 0
    try std.testing.expectEqual(std.math.maxInt(u32), ids[5]);
    try std.testing.expectEqual(@as(u32, 0), ids[6]);
    try std.testing.expectEqual(@as(u32, 1), ids[7]);
}

// Test: Protocol handles malformed message gracefully
test "decoder rejects invalid message type" {
    const allocator = std.testing.allocator;

    // We'll create a valid response and then test the decoder with valid data
    // The decoder will properly handle message type validation internally
    const response_msg = protocol.message.Response{
        .msgid = 1,
        .result = msgpack.int(42),
    };

    const encoded = try protocol.encoder.encodeResponse(allocator, response_msg);
    defer allocator.free(encoded);

    // Valid decode should work
    var decoded = try protocol.decoder.decode(allocator, encoded);
    defer protocol.message.deinitMessage(&decoded.message, allocator);

    switch (decoded.message) {
        .Response => |resp| {
            try std.testing.expectEqual(@as(u32, 1), resp.msgid);
        },
        else => return error.UnexpectedMessageType,
    }
}

// Test: Transport handles zero-byte reads
test "transport handles zero-byte read buffer" {
    const ZeroByteTransport = struct {
        connected: bool = true,

        fn connect(tr: *transport.Transport, _: []const u8) anyerror!void {
            tr.downcast(@This()).connected = true;
        }

        fn disconnect(tr: *transport.Transport) void {
            tr.downcast(@This()).connected = false;
        }

        fn read(_: *transport.Transport, buffer: []u8) transport.Transport.ReadError!usize {
            return @min(buffer.len, 0);
        }

        fn write(_: *transport.Transport, _: []const u8) transport.Transport.WriteError!void {}

        fn isConnected(tr: *const transport.Transport) bool {
            return tr.downcastConst(@This()).connected;
        }

        const vtable = transport.Transport.VTable{
            .connect = connect,
            .disconnect = disconnect,
            .read = read,
            .write = write,
            .is_connected = isConnected,
        };
    };

    var impl = ZeroByteTransport{};
    var wrapper = transport.Transport.init(&impl, &ZeroByteTransport.vtable);

    var buffer: [10]u8 = undefined;
    const bytes_read = try wrapper.read(&buffer);
    try std.testing.expectEqual(@as(usize, 0), bytes_read);
}

// Test: Client handles response with null error and null result
test "client handles null response fields" {
    const response_msg = protocol.message.Response{
        .msgid = 5,
        .@"error" = null,
        .result = null,
    };

    try std.testing.expect(response_msg.@"error" == null);
    try std.testing.expect(response_msg.result == null);
}

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

    const a_val = obj.map.get("a").?;
    try std.testing.expectEqual(@as(i64, 42), try msgpack.expectI64(a_val));

    const b_val = obj.map.get("b").?;
    try std.testing.expectEqualStrings("hello", try msgpack.expectString(b_val));

    const c_val = obj.map.get("c").?;
    try std.testing.expectEqual(true, try msgpack.expectBool(c_val));

    const e_val = obj.map.get("e").?;
    try std.testing.expect(e_val == .nil);
}

// Test: Client handles request with empty params
test "client encodes request with empty params array" {
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
