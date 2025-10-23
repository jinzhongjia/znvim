const std = @import("std");
const builtin = @import("builtin");
const znvim = @import("../root.zig");
const Client = znvim.Client;

// Tests for Client initialization and transport setup logic

test "Client setupTransport chooses UnixSocket for socket_path on non-Windows" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try std.testing.expectEqual(.unix_socket, client.transport_kind);
    try std.testing.expect(client.transport_unix != null);
}

test "Client setupTransport chooses TcpSocket for tcp_address" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .tcp_address = "localhost",
        .tcp_port = 6666,
    });
    defer client.deinit();

    try std.testing.expectEqual(.tcp_socket, client.transport_kind);
    try std.testing.expect(client.transport_tcp != null);
}

test "Client setupTransport chooses ChildProcess for spawn_process" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    defer client.deinit();

    try std.testing.expectEqual(.child_process, client.transport_kind);
    try std.testing.expect(client.transport_child != null);
}

test "Client setupTransport chooses Stdio for use_stdio" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .use_stdio = true,
    });
    defer client.deinit();

    try std.testing.expectEqual(.stdio, client.transport_kind);
    try std.testing.expect(client.transport_stdio != null);
}

test "Client setupTransport priority: spawn_process highest" {
    const allocator = std.testing.allocator;

    // Even with socket_path, spawn_process takes priority
    var client = try Client.init(allocator, .{
        .spawn_process = true,
        .socket_path = "/tmp/test.sock",
        .use_stdio = true,
        .nvim_path = "nvim",
    });
    defer client.deinit();

    try std.testing.expectEqual(.child_process, client.transport_kind);
}

test "Client setupTransport priority: use_stdio over socket" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .use_stdio = true,
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try std.testing.expectEqual(.stdio, client.transport_kind);
}

test "Client setupTransport priority: tcp over socket on non-Windows" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .tcp_address = "localhost",
        .tcp_port = 6666,
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try std.testing.expectEqual(.tcp_socket, client.transport_kind);
}

test "Client setupTransport fails without tcp_port for tcp_address" {
    const allocator = std.testing.allocator;

    // tcp_address without tcp_port should fail
    const result = Client.init(allocator, .{
        .tcp_address = "localhost",
        // Missing tcp_port
    });

    try std.testing.expectError(error.UnsupportedTransport, result);
}

test "Client init with skip_api_info skips metadata fetch" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .skip_api_info = true,
    });
    defer client.deinit();

    try std.testing.expectEqual(true, client.options.skip_api_info);
    try std.testing.expect(client.api_info == null);
}

test "Client init with custom nvim_path" {
    const allocator = std.testing.allocator;

    const custom_path = "/usr/local/bin/nvim";
    var client = try Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = custom_path,
    });
    defer client.deinit();

    try std.testing.expectEqualStrings(custom_path, client.options.nvim_path);
}

test "Client init with custom timeout" {
    const allocator = std.testing.allocator;

    const timeout: u32 = 10000; // 10 seconds
    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .timeout_ms = timeout,
    });
    defer client.deinit();

    try std.testing.expectEqual(timeout, client.options.timeout_ms);
}

test "Client deinit cleans up transport resources" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });

    // Verify transport was created
    try std.testing.expectEqual(.unix_socket, client.transport_kind);

    client.deinit();

    // After deinit, transport_kind should be reset
    try std.testing.expectEqual(.none, client.transport_kind);
    try std.testing.expect(client.transport_unix == null);
}

test "Client deinit clears transport pointers" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });

    // Verify transport was initialized
    try std.testing.expect(client.transport_unix != null);

    client.deinit();

    // After deinit, pointers should be null
    try std.testing.expect(client.transport_unix == null);
    try std.testing.expectEqual(.none, client.transport_kind);
}
