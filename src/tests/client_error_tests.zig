const std = @import("std");
const znvim = @import("../root.zig");
const Client = znvim.Client;
const msgpack = znvim.msgpack;

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
