const std = @import("std");
const znvim = @import("../root.zig");

// ============================================================================
// 连接配置选项边界测试
//
// 注意：这些测试主要验证配置验证逻辑，不进行实际的网络连接
// 以避免测试超时和挂起
// ============================================================================

// ============================================================================
// 1. 无效配置组合测试
// ============================================================================

test "connection options: no transport specified returns error" {
    const allocator = std.testing.allocator;

    // 所有 transport 选项都为 null/false，应该返回 UnsupportedTransport
    const client = znvim.Client.init(allocator, .{});
    try std.testing.expectError(error.UnsupportedTransport, client);
}

test "connection options: tcp address without port returns error" {
    const allocator = std.testing.allocator;

    // 只有 tcp_address 没有 tcp_port
    const client = znvim.Client.init(allocator, .{
        .tcp_address = "127.0.0.1",
    });
    try std.testing.expectError(error.UnsupportedTransport, client);
}

test "connection options: tcp port without address returns error" {
    const allocator = std.testing.allocator;

    // 只有 tcp_port 没有 tcp_address
    const client = znvim.Client.init(allocator, .{
        .tcp_port = 6666,
    });
    try std.testing.expectError(error.UnsupportedTransport, client);
}

// ============================================================================
// 2. 路径配置验证测试（只测试 init，不连接）
// ============================================================================

test "connection options: empty socket path can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .socket_path = "",
    });
    defer client.deinit();

    // init 应该成功，不测试 connect
    try std.testing.expect(!client.connected);
}

test "connection options: nonexistent socket path can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .socket_path = "/this/path/does/not/exist/nvim.sock",
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

test "connection options: socket path with special characters can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .socket_path = "/tmp/nvim_test_$#@!.sock",
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

test "connection options: extremely long socket path can init" {
    const allocator = std.testing.allocator;

    // Unix socket 路径有长度限制（通常 108 字节）
    const long_path = "/tmp/" ++ "a" ** 200 ++ ".sock";

    var client = try znvim.Client.init(allocator, .{
        .socket_path = long_path,
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

test "connection options: unicode socket path can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .socket_path = "/tmp/nvim_测试_🚀.sock",
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

// ============================================================================
// 3. TCP 配置验证测试（只测试 init）
// ============================================================================

test "connection options: tcp with empty address can init" {
    const allocator = std.testing.allocator;

    var result = znvim.Client.init(allocator, .{
        .tcp_address = "",
        .tcp_port = 6666,
    });

    if (result) |*client| {
        defer client.deinit();
        try std.testing.expect(!client.connected);
    } else |_| {
        // init 失败也是可以接受的
    }
}

test "connection options: tcp with port 0 can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .tcp_address = "127.0.0.1",
        .tcp_port = 0,
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

test "connection options: tcp with max port 65535 can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .tcp_address = "127.0.0.1",
        .tcp_port = 65535,
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

test "connection options: tcp with invalid hostname can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .tcp_address = "this.host.does.not.exist.example.invalid",
        .tcp_port = 6666,
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

test "connection options: tcp with ipv6 loopback can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .tcp_address = "::1",
        .tcp_port = 6666,
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

test "connection options: tcp with whitespace address can init" {
    const allocator = std.testing.allocator;

    var result = znvim.Client.init(allocator, .{
        .tcp_address = " 127.0.0.1 ",
        .tcp_port = 6666,
    });

    if (result) |*client| {
        defer client.deinit();
        try std.testing.expect(!client.connected);
    } else |_| {
        // init 失败也可以接受
    }
}

// ============================================================================
// 4. Spawn Process 配置验证测试
// ============================================================================

test "connection options: spawn with empty nvim path can init" {
    const allocator = std.testing.allocator;

    var result = znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "",
    });

    if (result) |*client| {
        defer client.deinit();
        try std.testing.expect(!client.connected);
    } else |_| {
        // init 失败也是可以接受的
    }
}

test "connection options: spawn with nonexistent binary can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "/this/binary/does/not/exist",
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

test "connection options: spawn with relative path can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "./nvim",
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

test "connection options: spawn with path containing spaces can init" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "/usr/local/bin/my nvim",
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
}

// ============================================================================
// 5. 超时配置测试
// ============================================================================

test "connection options: timeout 0 disables timeout" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .timeout_ms = 0,
    });
    defer client.deinit();

    try std.testing.expect(client.options.timeout_ms == 0);
}

test "connection options: very small timeout 1ms" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .timeout_ms = 1,
    });
    defer client.deinit();

    try std.testing.expect(client.options.timeout_ms == 1);
}

test "connection options: very large timeout max" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .timeout_ms = std.math.maxInt(u32),
    });
    defer client.deinit();

    try std.testing.expect(client.options.timeout_ms == std.math.maxInt(u32));
}

test "connection options: normal timeout 5000ms" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .timeout_ms = 5000,
    });
    defer client.deinit();

    try std.testing.expect(client.options.timeout_ms == 5000);
}

test "connection options: timeout boundary values can init" {
    const allocator = std.testing.allocator;

    const timeout_values = [_]u32{ 0, 1, 100, 1000, 5000, 60000, std.math.maxInt(u32) };

    for (timeout_values) |timeout| {
        var client = try znvim.Client.init(allocator, .{
            .spawn_process = true,
            .timeout_ms = timeout,
            .skip_api_info = true,
        });
        defer client.deinit();

        try std.testing.expect(client.options.timeout_ms == timeout);
    }
}

// ============================================================================
// 6. Transport 优先级测试
// ============================================================================

test "connection options: spawn_process takes priority" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .socket_path = "/tmp/nvim.sock",
        .tcp_address = "127.0.0.1",
        .tcp_port = 6666,
        .use_stdio = true,
    });
    defer client.deinit();

    // spawn_process 应该被选择
    try std.testing.expect(client.transport_kind == .child_process);
}

test "connection options: use_stdio takes priority over socket and tcp" {
    const allocator = std.testing.allocator;

    var result = znvim.Client.init(allocator, .{
        .use_stdio = true,
        .socket_path = "/tmp/nvim.sock",
        .tcp_address = "127.0.0.1",
        .tcp_port = 6666,
    });

    if (result) |*client| {
        defer client.deinit();
        try std.testing.expect(client.transport_kind == .stdio);
    } else |_| {
        // init 失败也可以接受
    }
}

test "connection options: tcp takes priority over socket" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .tcp_address = "127.0.0.1",
        .tcp_port = 6666,
        .socket_path = "/tmp/nvim.sock",
    });
    defer client.deinit();

    try std.testing.expect(client.transport_kind == .tcp_socket);
}

// ============================================================================
// 7. skip_api_info 标志测试
// ============================================================================

test "connection options: skip_api_info true" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .skip_api_info = true,
    });
    defer client.deinit();

    try std.testing.expect(client.options.skip_api_info == true);
    try client.connect();
    try std.testing.expect(client.api_info == null);
}

test "connection options: skip_api_info false fetches api info" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .skip_api_info = false,
    });
    defer client.deinit();

    try std.testing.expect(client.options.skip_api_info == false);
    try client.connect();
    try std.testing.expect(client.api_info != null);
}

// ============================================================================
// 8. 组合配置测试
// ============================================================================

test "connection options: all default values returns error" {
    const allocator = std.testing.allocator;

    const result = znvim.Client.init(allocator, .{});
    try std.testing.expectError(error.UnsupportedTransport, result);
}

test "connection options: spawn with all options customized" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 10000,
        .skip_api_info = false,
    });
    defer client.deinit();

    try std.testing.expect(client.options.timeout_ms == 10000);
    try std.testing.expect(client.options.skip_api_info == false);
    try client.connect();
    try std.testing.expect(client.api_info != null);
}
