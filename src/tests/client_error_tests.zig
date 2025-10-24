const std = @import("std");
const znvim = @import("../root.zig");
const Client = znvim.Client;
const msgpack = znvim.msgpack;
const protocol = znvim.protocol;
const transport = znvim.transport;

// Tests for Client error paths and edge cases

test "Client init fails with UnsupportedTransport when no transport specified" {
    const allocator = std.testing.allocator;

    // No socket_path, no tcp, no stdio, no spawn_process
    const result = Client.init(allocator, .{});

    try std.testing.expectError(error.UnsupportedTransport, result);
}

test "Client connect fails if already connected" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    defer client.deinit();

    try client.connect();

    // Second connect should fail
    const result = client.connect();
    try std.testing.expectError(error.AlreadyConnected, result);
}

test "Client request fails if not connected" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/nonexistent.sock",
    });
    defer client.deinit();

    // Don't call connect()
    const result = client.request("nvim_get_mode", &.{});
    try std.testing.expectError(error.NotConnected, result);
}

test "Client notify fails if not connected" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/nonexistent.sock",
    });
    defer client.deinit();

    // Don't call connect()
    const cmd = try msgpack.string(allocator, "echo 'test'");
    defer msgpack.free(cmd, allocator);

    const result = client.notify("nvim_command", &[_]msgpack.Value{cmd});
    try std.testing.expectError(error.NotConnected, result);
}

test "Client handles NvimError in response" {
    const allocator = std.testing.allocator;

    // Create a response with error field
    const error_msg = try msgpack.string(allocator, "Invalid arguments");
    var response = protocol.message.Response{
        .msgid = 0,
        .@"error" = error_msg,
        .result = null,
    };
    const encoded = try protocol.encoder.encodeResponse(allocator, response);
    defer allocator.free(encoded);
    if (response.@"error") |*e| e.*.free(allocator);

    // Create mock transport that returns this error response
    const MockTransport = struct {
        allocator: std.mem.Allocator,
        data: []const u8,
        offset: usize = 0,
        connected: bool = true,

        fn init(alloc: std.mem.Allocator, response_data: []const u8) !@This() {
            const copy = try alloc.dupe(u8, response_data);
            return @This(){
                .allocator = alloc,
                .data = copy,
            };
        }

        fn deinit(self: *@This()) void {
            self.allocator.free(self.data);
        }

        fn connect(tr: *transport.Transport, _: []const u8) anyerror!void {
            const self = tr.downcast(@This());
            self.connected = true;
        }

        fn disconnect(tr: *transport.Transport) void {
            const self = tr.downcast(@This());
            self.connected = false;
        }

        fn read(tr: *transport.Transport, buffer: []u8) transport.Transport.ReadError!usize {
            const self = tr.downcast(@This());
            if (self.offset >= self.data.len) return 0;
            const remaining = self.data.len - self.offset;
            const amount = @min(buffer.len, remaining);
            @memcpy(buffer[0..amount], self.data[self.offset .. self.offset + amount]);
            self.offset += amount;
            return amount;
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

    var mock = try MockTransport.init(allocator, encoded);
    defer mock.deinit();

    var client = Client{
        .allocator = allocator,
        .options = .{},
        .transport_kind = .unix_socket,
        .transport = transport.Transport.init(&mock, &MockTransport.vtable),
        .connected = true,
        .next_msgid = std.atomic.Value(u32).init(0),
        .api_arena = std.heap.ArenaAllocator.init(allocator),
    };
    defer client.deinit();

    const result = client.request("test_method", &.{});
    try std.testing.expectError(error.NvimError, result);
}

test "Client handles ConnectionClosed during request" {
    const allocator = std.testing.allocator;

    // Mock transport that closes immediately on read
    const ClosingTransport = struct {
        connected: bool = true,

        fn connect(tr: *transport.Transport, _: []const u8) anyerror!void {
            tr.downcast(@This()).connected = true;
        }

        fn disconnect(tr: *transport.Transport) void {
            tr.downcast(@This()).connected = false;
        }

        fn read(_: *transport.Transport, _: []u8) transport.Transport.ReadError!usize {
            return transport.Transport.ReadError.ConnectionClosed;
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

    var mock = ClosingTransport{};

    var client = Client{
        .allocator = allocator,
        .options = .{},
        .transport_kind = .unix_socket,
        .transport = transport.Transport.init(&mock, &ClosingTransport.vtable),
        .connected = true,
        .next_msgid = std.atomic.Value(u32).init(0),
        .api_arena = std.heap.ArenaAllocator.init(allocator),
    };
    defer client.deinit();

    const result = client.request("test_method", &.{});
    try std.testing.expectError(error.ConnectionClosed, result);

    // Client should update connected state
    try std.testing.expect(!client.connected);
}

test "Client detects ConnectionClosed and updates state" {
    const allocator = std.testing.allocator;

    const ClosingTransport = struct {
        connected: bool = true,

        fn connect(tr: *transport.Transport, _: []const u8) anyerror!void {
            tr.downcast(@This()).connected = true;
        }

        fn disconnect(tr: *transport.Transport) void {
            tr.downcast(@This()).connected = false;
        }

        fn read(_: *transport.Transport, _: []u8) transport.Transport.ReadError!usize {
            return 0; // Zero bytes = connection closed
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

    var mock = ClosingTransport{};

    var client = Client{
        .allocator = allocator,
        .options = .{},
        .transport_kind = .unix_socket,
        .transport = transport.Transport.init(&mock, &ClosingTransport.vtable),
        .connected = true,
        .next_msgid = std.atomic.Value(u32).init(0),
        .api_arena = std.heap.ArenaAllocator.init(allocator),
    };
    defer client.deinit();

    // Should detect closed connection
    const result = client.request("test", &.{});
    try std.testing.expectError(error.ConnectionClosed, result);

    // Verify client updated its state
    try std.testing.expect(!client.connected);
}

test "Client disconnect handles not connected state gracefully" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    // Disconnect without connecting
    client.disconnect(); // Should not crash

    try std.testing.expect(!client.connected);
}

test "Client multiple disconnect calls are safe" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    // Multiple disconnects should be safe
    client.disconnect();
    client.disconnect();
    client.disconnect();

    try std.testing.expect(!client.connected);
}

test "Client isConnected reflects actual state" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    // Initially not connected
    try std.testing.expect(!client.isConnected());

    // Still not connected (we didn't actually connect)
    try std.testing.expect(!client.isConnected());
}

test "Client handles UnexpectedMessage error" {
    const allocator = std.testing.allocator;

    // Create response with wrong message ID
    const response = protocol.message.Response{
        .msgid = 999, // Wrong ID (we'll request with ID 0)
        .result = msgpack.int(42),
    };
    const encoded = try protocol.encoder.encodeResponse(allocator, response);
    defer allocator.free(encoded);

    const MockTransport = struct {
        allocator: std.mem.Allocator,
        data: []const u8,
        offset: usize = 0,
        connected: bool = true,

        fn init(alloc: std.mem.Allocator, response_data: []const u8) !@This() {
            const copy = try alloc.dupe(u8, response_data);
            return @This(){
                .allocator = alloc,
                .data = copy,
            };
        }

        fn deinit(self: *@This()) void {
            self.allocator.free(self.data);
        }

        fn connect(tr: *transport.Transport, _: []const u8) anyerror!void {
            tr.downcast(@This()).connected = true;
        }

        fn disconnect(tr: *transport.Transport) void {
            tr.downcast(@This()).connected = false;
        }

        fn read(tr: *transport.Transport, buffer: []u8) transport.Transport.ReadError!usize {
            const self = tr.downcast(@This());
            if (self.offset >= self.data.len) return 0;
            const remaining = self.data.len - self.offset;
            const amount = @min(buffer.len, remaining);
            @memcpy(buffer[0..amount], self.data[self.offset .. self.offset + amount]);
            self.offset += amount;
            return amount;
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

    var mock = try MockTransport.init(allocator, encoded);
    defer mock.deinit();

    var client = Client{
        .allocator = allocator,
        .options = .{},
        .transport_kind = .unix_socket,
        .transport = transport.Transport.init(&mock, &MockTransport.vtable),
        .connected = true,
        .next_msgid = std.atomic.Value(u32).init(0),
        .api_arena = std.heap.ArenaAllocator.init(allocator),
    };
    defer client.deinit();

    // Request with ID 0, but response has ID 999
    const result = client.request("test", &.{});
    try std.testing.expectError(error.UnexpectedMessage, result);
}

test "Client handles empty response buffer" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    // Verify read_buffer starts empty
    try std.testing.expectEqual(@as(usize, 0), client.read_buffer.items.len);
}

test "Client nextMessageId starts at zero" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try std.testing.expectEqual(@as(u32, 0), client.nextMessageId());
    try std.testing.expectEqual(@as(u32, 1), client.nextMessageId());
    try std.testing.expectEqual(@as(u32, 2), client.nextMessageId());
}
