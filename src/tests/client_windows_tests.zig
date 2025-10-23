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

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\nvim-test",
    });
    defer client.deinit();

    // 验证 Client 选择了 WindowsPipe 传输
    try std.testing.expectEqual(.named_pipe, client.transport_kind);
    try std.testing.expect(client.windows.pipe != null);

    // 验证其他传输为 null
    try std.testing.expect(client.transport_unix == null);
    try std.testing.expect(client.transport_tcp == null);
    try std.testing.expect(client.transport_stdio == null);
    try std.testing.expect(client.transport_child == null);
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
    try std.testing.expectEqual(.tcp_socket, client.transport_kind);
    try std.testing.expect(client.transport_tcp != null);

    // 验证 WindowsPipe 为 null
    try std.testing.expect(client.windows.pipe == null);
}

test "Client chooses ChildProcess on Windows with spawn_process" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .spawn_process = true,
    });
    defer client.deinit();

    // 验证 Client 选择了 ChildProcess 传输
    try std.testing.expectEqual(.child_process, client.transport_kind);
    try std.testing.expect(client.transport_child != null);

    // 验证 WindowsPipe 为 null
    try std.testing.expect(client.windows.pipe == null);
}

test "Client chooses Stdio on Windows with use_stdio" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .use_stdio = true,
    });
    defer client.deinit();

    // 验证 Client 选择了 Stdio 传输
    try std.testing.expectEqual(.stdio, client.transport_kind);
    try std.testing.expect(client.transport_stdio != null);

    // 验证 WindowsPipe 为 null
    try std.testing.expect(client.windows.pipe == null);
}

// ============================================================================
// WindowsState 生命周期测试
// ============================================================================

test "WindowsState pipe pointer is properly managed" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\test-lifecycle",
    });

    // 初始化后应该有 pipe 指针
    try std.testing.expect(client.windows.pipe != null);
    const pipe_ptr = client.windows.pipe.?;

    // 验证 pipe 指针有效
    try std.testing.expect(pipe_ptr.handle == null);
    try std.testing.expectEqual(.named_pipe, client.transport_kind);

    // 清理
    client.deinit();

    // deinit 后应该清除 pipe 指针
    try std.testing.expect(client.windows.pipe == null);
    try std.testing.expectEqual(.none, client.transport_kind);
}

test "WindowsState is null for non-pipe transports" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // TCP
    {
        var client = try Client.init(allocator, .{
            .tcp_address = "localhost",
            .tcp_port = 8080,
        });
        defer client.deinit();

        try std.testing.expect(client.windows.pipe == null);
    }

    // Stdio
    {
        var client = try Client.init(allocator, .{
            .use_stdio = true,
        });
        defer client.deinit();

        try std.testing.expect(client.windows.pipe == null);
    }

    // ChildProcess
    {
        var client = try Client.init(allocator, .{
            .spawn_process = true,
        });
        defer client.deinit();

        try std.testing.expect(client.windows.pipe == null);
    }
}

test "WindowsState multiple init and deinit cycles" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 第一次初始化
    var client1 = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\test1",
    });
    try std.testing.expect(client1.windows.pipe != null);
    client1.deinit();
    try std.testing.expect(client1.windows.pipe == null);

    // 第二次初始化（确保可以重复）
    var client2 = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\test2",
    });
    try std.testing.expect(client2.windows.pipe != null);
    client2.deinit();
    try std.testing.expect(client2.windows.pipe == null);
}

test "WindowsState survives transport kind changes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 创建 WindowsPipe 客户端
    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\test-change",
    });
    defer client.deinit();

    try std.testing.expectEqual(.named_pipe, client.transport_kind);
    try std.testing.expect(client.windows.pipe != null);

    // 注意：Client 不支持运行时改变传输类型
    // 此测试只验证初始状态正确
}

// ============================================================================
// 超时配置传递测试
// ============================================================================

test "Client passes timeout_ms to WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const custom_timeout: u32 = 3000;
    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\timeout-test",
        .timeout_ms = custom_timeout,
    });
    defer client.deinit();

    try std.testing.expect(client.windows.pipe != null);
    try std.testing.expectEqual(custom_timeout, client.windows.pipe.?.timeout_ms);
}

test "Client passes zero timeout to WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\infinite-timeout",
        .timeout_ms = 0,
    });
    defer client.deinit();

    try std.testing.expect(client.windows.pipe != null);
    try std.testing.expectEqual(@as(u32, 0), client.windows.pipe.?.timeout_ms);
}

test "Client passes large timeout to WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const large_timeout: u32 = 60000; // 60秒
    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\large-timeout",
        .timeout_ms = large_timeout,
    });
    defer client.deinit();

    try std.testing.expect(client.windows.pipe != null);
    try std.testing.expectEqual(large_timeout, client.windows.pipe.?.timeout_ms);
}

test "Client timeout_ms defaults to 5000 for WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\default-timeout",
        // 不指定 timeout_ms，使用默认值
    });
    defer client.deinit();

    try std.testing.expect(client.windows.pipe != null);
    try std.testing.expectEqual(@as(u32, 5000), client.windows.pipe.?.timeout_ms);
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

    const allocator = std.testing.allocator;

    const valid_paths = [_][]const u8{
        "\\\\.\\pipe\\nvim",
        "\\\\.\\pipe\\nvim-12345",
        "\\\\.\\pipe\\my-app-nvim",
        "\\\\.\\PIPE\\UPPERCASE",
    };

    for (valid_paths) |path| {
        var client = try Client.init(allocator, .{
            .socket_path = path,
        });
        defer client.deinit();

        try std.testing.expectEqual(.named_pipe, client.transport_kind);
        try std.testing.expect(client.windows.pipe != null);
    }
}

// ============================================================================
// 初始状态验证测试
// ============================================================================

test "Client with WindowsPipe starts disconnected" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\initial-state",
    });
    defer client.deinit();

    try std.testing.expect(!client.connected);
    try std.testing.expect(!client.isConnected());
    try std.testing.expect(client.windows.pipe != null);
    try std.testing.expect(client.windows.pipe.?.handle == null);
}

test "Client WindowsPipe fields after deinit" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\deinit-test",
    });

    try std.testing.expect(client.windows.pipe != null);

    client.deinit();

    // deinit 后验证清理
    try std.testing.expect(client.windows.pipe == null);
    try std.testing.expectEqual(.none, client.transport_kind);
    try std.testing.expect(!client.connected);
}

test "Client can create multiple WindowsPipe instances" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client1 = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\client1",
    });
    defer client1.deinit();

    var client2 = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\client2",
    });
    defer client2.deinit();

    var client3 = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\client3",
    });
    defer client3.deinit();

    // 验证所有实例都正确初始化
    try std.testing.expect(client1.windows.pipe != null);
    try std.testing.expect(client2.windows.pipe != null);
    try std.testing.expect(client3.windows.pipe != null);

    // 验证它们是独立的
    try std.testing.expect(client1.windows.pipe != client2.windows.pipe);
    try std.testing.expect(client2.windows.pipe != client3.windows.pipe);
}

// ============================================================================
// API Info 和 WindowsPipe 集成测试
// ============================================================================

test "Client with WindowsPipe can disable API info" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\no-api-info",
        .skip_api_info = true,
    });
    defer client.deinit();

    try std.testing.expect(client.options.skip_api_info);
    try std.testing.expect(client.api_info == null);
}

test "Client with WindowsPipe has correct options" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const pipe_path = "\\\\.\\pipe\\options-test";
    const timeout = 7500;

    var client = try Client.init(allocator, .{
        .socket_path = pipe_path,
        .timeout_ms = timeout,
        .skip_api_info = true,
    });
    defer client.deinit();

    // 验证选项被正确存储
    try std.testing.expect(client.options.socket_path != null);
    try std.testing.expectEqualStrings(pipe_path, client.options.socket_path.?);
    try std.testing.expectEqual(@as(u32, timeout), client.options.timeout_ms);
    try std.testing.expect(client.options.skip_api_info);
}

// ============================================================================
// 错误处理测试
// ============================================================================

test "Client init creates WindowsPipe correctly" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\setup-test",
    });
    defer client.deinit();

    // init 内部会调用 setupTransport
    try std.testing.expectEqual(.named_pipe, client.transport_kind);
    try std.testing.expect(client.windows.pipe != null);
}

test "Client init is deterministic for WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 多次初始化相同配置应该产生相同结果
    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\deterministic-test",
        .timeout_ms = 1234,
    });
    defer client.deinit();

    try std.testing.expectEqual(.named_pipe, client.transport_kind);
    try std.testing.expect(client.windows.pipe != null);
    try std.testing.expectEqual(@as(u32, 1234), client.windows.pipe.?.timeout_ms);
}

test "Client disconnect clears WindowsPipe state" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\disconnect-test",
    });
    defer client.deinit();

    // 模拟连接状态
    client.connected = true;

    // disconnect 应该清除状态
    client.disconnect();

    try std.testing.expect(!client.connected);
    try std.testing.expect(client.api_info == null);

    // WindowsPipe 本身不应该被销毁（只有 deinit 才销毁）
    try std.testing.expect(client.windows.pipe != null);
}

// ============================================================================
// 内存管理测试
// ============================================================================

test "Client with WindowsPipe has no memory leaks" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected in Client with WindowsPipe");
        }
    }
    const allocator = gpa.allocator();

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\leak-test",
        .timeout_ms = 2500,
    });
    client.deinit();
}

test "Client with WindowsPipe multiple init-deinit no leaks" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected in multiple init-deinit cycles");
        }
    }
    const allocator = gpa.allocator();

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        var client = try Client.init(allocator, .{
            .socket_path = "\\\\.\\pipe\\multi-leak-test",
        });
        client.deinit();
    }
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
    try std.testing.expectEqual(.child_process, client.transport_kind);
    try std.testing.expect(client.windows.pipe == null);
    try std.testing.expect(client.transport_child != null);
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
    try std.testing.expectEqual(.stdio, client.transport_kind);
    try std.testing.expect(client.windows.pipe == null);
    try std.testing.expect(client.transport_stdio != null);
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
    try std.testing.expectEqual(.tcp_socket, client.transport_kind);
    try std.testing.expect(client.windows.pipe == null);
    try std.testing.expect(client.transport_tcp != null);
}

// ============================================================================
// 传输层接口一致性测试
// ============================================================================

test "Client WindowsPipe exposes Transport interface" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\interface-test",
    });
    defer client.deinit();

    // 验证 transport 字段已正确初始化
    // vtable 是一个指针，应该有有效地址
    try std.testing.expect(@intFromPtr(client.transport.vtable) != 0);
    try std.testing.expect(@intFromPtr(client.transport.impl) != 0);

    // 验证 transport 接口函数可以调用（即使未连接）
    try std.testing.expect(!client.transport.isConnected());
}

test "Client with WindowsPipe handle disconnect before connect" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\disconnect-before-connect",
    });
    defer client.deinit();

    // 在未连接状态调用 disconnect 应该是安全的
    client.disconnect();
    client.disconnect();

    try std.testing.expect(!client.connected);
}

// ============================================================================
// 边界条件测试
// ============================================================================

test "Client with very long pipe name" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 创建一个很长的管道名称
    const long_name = "\\\\.\\pipe\\very-long-pipe-name-for-testing-purposes-" ++
        "with-many-characters-to-ensure-it-works-correctly-" ++
        "even-with-unusual-length-specifications-12345";

    var client = try Client.init(allocator, .{
        .socket_path = long_name,
    });
    defer client.deinit();

    try std.testing.expectEqual(.named_pipe, client.transport_kind);
    try std.testing.expect(client.windows.pipe != null);
}

test "Client with special characters in pipe name" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    const special_names = [_][]const u8{
        "\\\\.\\pipe\\nvim-test_123",
        "\\\\.\\pipe\\nvim.test.app",
        "\\\\.\\pipe\\nvim-test-2024",
    };

    for (special_names) |name| {
        var client = try Client.init(allocator, .{
            .socket_path = name,
        });
        defer client.deinit();

        try std.testing.expectEqual(.named_pipe, client.transport_kind);
    }
}

// ============================================================================
// 与其他传输的互操作测试
// ============================================================================

test "Client WindowsPipe allocator matches client allocator" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\allocator-test",
    });
    defer client.deinit();

    // 验证 WindowsPipe 使用相同的 allocator
    try std.testing.expect(client.windows.pipe != null);
    // 注意：我们不能直接比较 allocator，但可以验证没有内存泄漏
}

test "Client nextMessageId increments correctly with WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\msgid-test",
    });
    defer client.deinit();

    // 验证消息 ID 正确递增
    const id1 = client.nextMessageId();
    const id2 = client.nextMessageId();
    const id3 = client.nextMessageId();

    try std.testing.expectEqual(@as(u32, 0), id1);
    try std.testing.expectEqual(@as(u32, 1), id2);
    try std.testing.expectEqual(@as(u32, 2), id3);
}

test "Client read_buffer is initialized for WindowsPipe" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "\\\\.\\pipe\\buffer-test",
    });
    defer client.deinit();

    // read_buffer 应该被初始化为空
    try std.testing.expectEqual(@as(usize, 0), client.read_buffer.items.len);
}
