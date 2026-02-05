const std = @import("std");
const builtin = @import("builtin");
const znvim = @import("../root.zig");
const Client = znvim.Client;
const ConnectionOptions = znvim.ConnectionOptions;

// 这个文件包含 Client 层的 Windows 特定测试

// ============================================================================
// 传输选择测试
// ============================================================================

test "Client chooses WindowsPipe on Windows with socket_path" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client chooses TcpSocket on Windows with tcp_address" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .tcp_address = "127.0.0.1",
        .tcp_port = 9999,
    });
    defer client.deinit();

    // 验证 Client 选择了 TCP Socket 传输
    try std.testing.expect(client.tcp_conn != null);
}

test "Client chooses ChildProcess on Windows with spawn_process" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .spawn_process = true,
    });
    defer client.deinit();

    // 验证 Client 选择了 ChildProcess 传输
    try std.testing.expect(client.child_conn != null);
}

test "Client chooses Stdio on Windows with use_stdio" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .use_stdio = true,
    });
    defer client.deinit();

    // 验证 Client 选择了 Stdio 传输
    try std.testing.expect(client.stdio_conn != null);
}

// ============================================================================
// WindowsState 生命周期测试
// ============================================================================

test "WindowsState pipe pointer is properly managed" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "WindowsState is null for non-pipe transports" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "WindowsState multiple init and deinit cycles" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "WindowsState survives transport kind changes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

// ============================================================================
// 超时配置传递测试
// ============================================================================

test "Client passes timeout_ms to WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client passes zero timeout to WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client passes large timeout to WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client timeout_ms defaults to 5000 for WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

// ============================================================================
// 连接选项验证测试
// ============================================================================

test "Client rejects missing tcp_port for tcp_address on Windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const result = Client.init(allocator, .{
        .tcp_address = "127.0.0.1",
        // 缺少 tcp_port
    });

    try std.testing.expectError(error.UnsupportedTransport, result);
}

test "Client rejects missing socket_path and tcp_address on Windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const result = Client.init(allocator, .{
        // 没有任何传输选项
    });

    try std.testing.expectError(error.UnsupportedTransport, result);
}

test "Client accepts valid pipe path formats on Windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

// ============================================================================
// 初始状态验证测试
// ============================================================================

test "Client with WindowsPipe starts disconnected" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client WindowsPipe fields after deinit" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client can create multiple WindowsPipe instances" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

// ============================================================================
// API Info 和 WindowsPipe 集成测试
// ============================================================================

test "Client with WindowsPipe can disable API info" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client with WindowsPipe has correct options" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

// ============================================================================
// 错误处理测试
// ============================================================================

test "Client init creates WindowsPipe correctly" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client init is deterministic for WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client disconnect clears WindowsPipe state" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

// ============================================================================
// 内存管理测试
// ============================================================================

test "Client with WindowsPipe has no memory leaks" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client with WindowsPipe multiple init-deinit no leaks" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

// ============================================================================
// 传输优先级测试
// ============================================================================

test "Client prefers spawn_process over socket_path on Windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .spawn_process = true,
        .socket_path = "\\\\.\\pipe\\should-be-ignored",
    });
    defer client.deinit();

    // spawn_process 优先级更高
    try std.testing.expect(client.child_conn != null);
}

test "Client prefers use_stdio over socket_path on Windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .use_stdio = true,
        .socket_path = "\\\\.\\pipe\\should-be-ignored",
    });
    defer client.deinit();

    // use_stdio 优先级更高
    try std.testing.expect(client.stdio_conn != null);
}

test "Client prefers tcp over socket_path on Windows" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .tcp_address = "localhost",
        .tcp_port = 8888,
        .socket_path = "\\\\.\\pipe\\should-be-ignored",
    });
    defer client.deinit();

    // tcp 优先级更高
    try std.testing.expect(client.tcp_conn != null);
}

// ============================================================================
// 传输层接口一致性测试
// ============================================================================

test "Client WindowsPipe exposes Transport interface" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client with WindowsPipe handle disconnect before connect" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

// ============================================================================
// 边界条件测试
// ============================================================================

test "Client with very long pipe name" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client with special characters in pipe name" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

// ============================================================================
// 与其他传输的互操作测试
// ============================================================================

test "Client WindowsPipe allocator matches client allocator" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client nextMessageId increments correctly with WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}

test "Client read_buffer is initialized for WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    return error.SkipZigTest; // Windows named pipes not yet supported with zio transport
}
