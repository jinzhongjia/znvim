const std = @import("std");
const connection = @import("../connection.zig");

// Default options should match the documented behaviour.
test "connection options defaults" {
    const opts = connection.ConnectionOptions{};

    try std.testing.expect(opts.socket_path == null);
    try std.testing.expect(opts.tcp_address == null);
    try std.testing.expect(opts.tcp_port == null);
    try std.testing.expect(!opts.use_stdio);
    try std.testing.expect(!opts.spawn_process);
    try std.testing.expectEqualStrings("nvim", opts.nvim_path);
    try std.testing.expectEqual(@as(u32, 5000), opts.timeout_ms);
    try std.testing.expect(!opts.skip_api_info);
}

// Mixing TCP options should leave unrelated flags untouched.
test "tcp connection options" {
    const opts = connection.ConnectionOptions{
        .tcp_address = "127.0.0.1",
        .tcp_port = 7777,
        .timeout_ms = 0,
    };

    try std.testing.expect(opts.socket_path == null);
    try std.testing.expectEqualStrings("127.0.0.1", opts.tcp_address.?);
    try std.testing.expectEqual(@as(u16, 7777), opts.tcp_port.?);
    try std.testing.expectEqual(@as(u32, 0), opts.timeout_ms);
    try std.testing.expect(!opts.use_stdio);
    try std.testing.expect(!opts.spawn_process);
}

// Enabling the embedded process path should preserve the configured timeout and path.
test "spawn process connection options" {
    const opts = connection.ConnectionOptions{
        .spawn_process = true,
        .nvim_path = "/usr/bin/nvim",
        .timeout_ms = 1500,
    };

    try std.testing.expect(opts.spawn_process);
    try std.testing.expectEqualStrings("/usr/bin/nvim", opts.nvim_path);
    try std.testing.expectEqual(@as(u32, 1500), opts.timeout_ms);
    try std.testing.expect(opts.socket_path == null);
    try std.testing.expect(opts.tcp_address == null);
    try std.testing.expect(opts.tcp_port == null);
}
