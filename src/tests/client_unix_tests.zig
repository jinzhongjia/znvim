const std = @import("std");
const builtin = @import("builtin");
const znvim = @import("../root.zig");
const Client = znvim.Client;
const connection = @import("../connection.zig");

// Tests for Client behavior on Unix-like platforms (Linux, macOS, BSD)
// This mirrors client_windows_tests.zig to ensure platform parity

test "Client chooses UnixSocket on Unix with socket_path" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try std.testing.expectEqual(.unix_socket, client.transport_kind);
    try std.testing.expect(client.transport_unix != null);
    try std.testing.expect(client.transport_tcp == null);
    try std.testing.expect(client.transport_stdio == null);
    try std.testing.expect(client.transport_child == null);
}

test "Client chooses TcpSocket on Unix with tcp_address" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .tcp_address = "127.0.0.1",
        .tcp_port = 7777,
    });
    defer client.deinit();

    try std.testing.expectEqual(.tcp_socket, client.transport_kind);
    try std.testing.expect(client.transport_tcp != null);
    try std.testing.expect(client.transport_unix == null);
}

test "Client chooses ChildProcess on Unix with spawn_process" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    defer client.deinit();

    try std.testing.expectEqual(.child_process, client.transport_kind);
    try std.testing.expect(client.transport_child != null);
    try std.testing.expect(client.transport_unix == null);
}

test "Client chooses Stdio on Unix with use_stdio" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .use_stdio = true,
    });
    defer client.deinit();

    try std.testing.expectEqual(.stdio, client.transport_kind);
    try std.testing.expect(client.transport_stdio != null);
    try std.testing.expect(client.transport_unix == null);
}

test "Client Unix prefers spawn_process over socket_path" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .spawn_process = true,
        .socket_path = "/tmp/test.sock",
        .nvim_path = "nvim",
    });
    defer client.deinit();

    try std.testing.expectEqual(.child_process, client.transport_kind);
}

test "Client Unix prefers use_stdio over socket_path" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .use_stdio = true,
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try std.testing.expectEqual(.stdio, client.transport_kind);
}

test "Client Unix prefers tcp over socket_path" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .tcp_address = "localhost",
        .tcp_port = 8888,
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try std.testing.expectEqual(.tcp_socket, client.transport_kind);
}

test "Client Unix transport fields after init" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try std.testing.expect(client.transport_unix != null);
    try std.testing.expect(client.transport_tcp == null);
    try std.testing.expect(client.transport_stdio == null);
    try std.testing.expect(client.transport_child == null);
    try std.testing.expectEqual(.unix_socket, client.transport_kind);
}

test "Client Unix passes timeout_ms to transport" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const timeout: u32 = 3000;
    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .timeout_ms = timeout,
    });
    defer client.deinit();

    try std.testing.expectEqual(timeout, client.options.timeout_ms);
}

test "Client Unix accepts zero timeout" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .timeout_ms = 0,
    });
    defer client.deinit();

    try std.testing.expectEqual(@as(u32, 0), client.options.timeout_ms);
}

test "Client Unix accepts large timeout" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const large_timeout = std.math.maxInt(u32);
    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .timeout_ms = large_timeout,
    });
    defer client.deinit();

    try std.testing.expectEqual(large_timeout, client.options.timeout_ms);
}

test "Client Unix with default timeout" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    // Default timeout is 5000ms
    try std.testing.expectEqual(@as(u32, 5000), client.options.timeout_ms);
}

test "Client Unix starts disconnected" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
    try std.testing.expect(!client.isConnected());
}

test "Client Unix fields after deinit" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });

    try std.testing.expect(client.transport_unix != null);

    client.deinit();

    try std.testing.expect(client.transport_unix == null);
    try std.testing.expectEqual(.none, client.transport_kind);
}

test "Client Unix can create multiple instances" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client1 = try Client.init(allocator, .{
        .socket_path = "/tmp/test1.sock",
    });
    defer client1.deinit();

    var client2 = try Client.init(allocator, .{
        .socket_path = "/tmp/test2.sock",
    });
    defer client2.deinit();

    try std.testing.expect(client1.transport_unix != null);
    try std.testing.expect(client2.transport_unix != null);
    try std.testing.expect(client1.transport_unix != client2.transport_unix);
}

test "Client Unix with skip_api_info flag" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .skip_api_info = true,
    });
    defer client.deinit();

    try std.testing.expectEqual(true, client.options.skip_api_info);
}

test "Client Unix init is deterministic" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const options = connection.ConnectionOptions{
        .socket_path = "/tmp/test.sock",
        .timeout_ms = 3000,
    };

    var client1 = try Client.init(allocator, options);
    defer client1.deinit();

    var client2 = try Client.init(allocator, options);
    defer client2.deinit();

    try std.testing.expectEqual(client1.transport_kind, client2.transport_kind);
    try std.testing.expectEqual(client1.options.timeout_ms, client2.options.timeout_ms);
}

test "Client Unix disconnect clears state" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    client.disconnect();

    try std.testing.expect(!client.connected);
    try std.testing.expectEqual(@as(usize, 0), client.read_buffer.items.len);
    try std.testing.expect(client.api_info == null);
}

test "Client Unix exposes Transport interface" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    // Verify transport is properly initialized
    try std.testing.expect(!client.transport.isConnected());
}

test "Client Unix handles multiple init-deinit cycles" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var client = try Client.init(allocator, .{
            .socket_path = "/tmp/test.sock",
        });
        try std.testing.expectEqual(.unix_socket, client.transport_kind);
        client.deinit();
    }
}

test "Client Unix with all transport options creates child process" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // spawn_process has highest priority
    var client = try Client.init(allocator, .{
        .spawn_process = true,
        .use_stdio = true,
        .tcp_address = "localhost",
        .tcp_port = 9999,
        .socket_path = "/tmp/test.sock",
        .nvim_path = "nvim",
    });
    defer client.deinit();

    try std.testing.expectEqual(.child_process, client.transport_kind);
}

test "Client Unix options are preserved" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const socket_path = "/tmp/nvim.sock";
    const nvim_path = "/usr/local/bin/nvim";
    const timeout: u32 = 7500;

    var client = try Client.init(allocator, .{
        .socket_path = socket_path,
        .nvim_path = nvim_path,
        .timeout_ms = timeout,
    });
    defer client.deinit();

    try std.testing.expectEqualStrings(socket_path, client.options.socket_path.?);
    try std.testing.expectEqualStrings(nvim_path, client.options.nvim_path);
    try std.testing.expectEqual(timeout, client.options.timeout_ms);
}

test "Client Unix rejects tcp_address without tcp_port" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const result = Client.init(allocator, .{
        .tcp_address = "localhost",
        // Missing tcp_port
    });

    try std.testing.expectError(error.UnsupportedTransport, result);
}

test "Client Unix accepts valid socket paths" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const test_paths = [_][]const u8{
        "/tmp/nvim.sock",
        "/var/run/nvim.sock",
        "/tmp/test-socket",
        "/tmp/nvim_12345.sock",
    };

    for (test_paths) |path| {
        var client = try Client.init(allocator, .{
            .socket_path = path,
        });
        defer client.deinit();

        try std.testing.expectEqualStrings(path, client.options.socket_path.?);
    }
}

test "Client Unix transport_unix pointer is properly managed" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });

    const ptr_before = client.transport_unix;
    try std.testing.expect(ptr_before != null);

    client.deinit();

    try std.testing.expect(client.transport_unix == null);
}

test "Client Unix multiple init and deinit cycles" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        var client = try Client.init(allocator, .{
            .socket_path = "/tmp/test.sock",
        });
        defer client.deinit();

        try std.testing.expectEqual(.unix_socket, client.transport_kind);
        try std.testing.expect(client.transport_unix != null);
    }
}

test "Client Unix survives transport kind changes" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // Create with UnixSocket
    var client1 = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client1.deinit();
    try std.testing.expectEqual(.unix_socket, client1.transport_kind);

    // Create with TCP
    var client2 = try Client.init(allocator, .{
        .tcp_address = "localhost",
        .tcp_port = 6666,
    });
    defer client2.deinit();
    try std.testing.expectEqual(.tcp_socket, client2.transport_kind);

    // Create with ChildProcess
    var client3 = try Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    defer client3.deinit();
    try std.testing.expectEqual(.child_process, client3.transport_kind);
}

test "Client Unix no WindowsState overhead" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    // On Unix, WindowsState should be an empty struct with zero size
    const windows_state_size = @sizeOf(@TypeOf(client.windows));
    try std.testing.expectEqual(@as(usize, 0), windows_state_size);
}

test "Client Unix API info starts null" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .skip_api_info = true,
    });
    defer client.deinit();

    try std.testing.expect(client.api_info == null);
}

test "Client Unix read_buffer starts empty" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try std.testing.expectEqual(@as(usize, 0), client.read_buffer.items.len);
}

test "Client Unix message ID starts at zero" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    const first_id = client.nextMessageId();
    try std.testing.expectEqual(@as(u32, 0), first_id);
}

test "Client Unix correctly stores connection options" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const opts = connection.ConnectionOptions{
        .socket_path = "/tmp/custom.sock",
        .timeout_ms = 2500,
        .skip_api_info = true,
        .nvim_path = "/custom/nvim",
    };

    var client = try Client.init(allocator, opts);
    defer client.deinit();

    try std.testing.expectEqualStrings("/tmp/custom.sock", client.options.socket_path.?);
    try std.testing.expectEqual(@as(u32, 2500), client.options.timeout_ms);
    try std.testing.expectEqual(true, client.options.skip_api_info);
    try std.testing.expectEqualStrings("/custom/nvim", client.options.nvim_path);
}

test "Client Unix handle disconnect before connect" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    // Disconnect without connecting should be safe
    client.disconnect();

    try std.testing.expect(!client.connected);
}
