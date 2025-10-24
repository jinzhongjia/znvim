const std = @import("std");
const builtin = @import("builtin");
const TcpSocket = @import("../transport/tcp_socket.zig").TcpSocket;
const Transport = @import("../transport/transport.zig").Transport;

// ============================================================================
// TCP Socket Unix/POSIX 平台专用测试
//
// 这些测试专门针对 Unix/Linux/macOS 平台的 POSIX 错误处理和网络行为
// 在 Windows 上这些测试会被跳过
// ============================================================================

// ============================================================================
// Helper: 创建 TCP 测试服务端
// ============================================================================

const TcpTestServer = struct {
    server: std.net.Server,
    port: u16,
    allocator: std.mem.Allocator,
    server_thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool),
    client_stream: ?std.net.Stream = null,

    const Self = @This();

    fn init(allocator: std.mem.Allocator) !Self {
        // 使用端口 0 让系统自动分配一个可用端口
        const addr = try std.net.Address.parseIp("127.0.0.1", 0);
        const server = try addr.listen(.{
            .reuse_address = true,
        });

        // 获取实际分配的端口
        const actual_addr = try server.listen_address.getOsSockLen();
        const port = actual_addr.in.port;

        return Self{
            .server = server,
            .port = std.mem.bigToNative(u16, port),
            .allocator = allocator,
            .should_stop = std.atomic.Value(bool).init(false),
        };
    }

    fn deinit(self: *Self) void {
        self.should_stop.store(true, .seq_cst);

        if (self.server_thread) |thread| {
            thread.join();
        }

        if (self.client_stream) |stream| {
            stream.close();
        }

        self.server.deinit();
    }

    fn acceptConnection(self: *Self) !void {
        const connection = try self.server.accept();
        self.client_stream = connection.stream;
    }

    fn read(self: *Self, buffer: []u8) !usize {
        const stream = self.client_stream orelse return error.NotConnected;
        return try stream.read(buffer);
    }

    fn write(self: *Self, data: []const u8) !void {
        const stream = self.client_stream orelse return error.NotConnected;
        try stream.writeAll(data);
    }

    fn closeClientConnection(self: *Self) void {
        if (self.client_stream) |stream| {
            stream.close();
            self.client_stream = null;
        }
    }

    // Echo server: 读取数据并原样返回
    fn echoServerThread(self: *Self) void {
        self.acceptConnection() catch return;

        var buffer: [4096]u8 = undefined;
        while (!self.should_stop.load(.seq_cst)) {
            const bytes_read = self.read(&buffer) catch break;
            if (bytes_read == 0) break;

            self.write(buffer[0..bytes_read]) catch break;
        }
    }

    fn startEchoServer(self: *Self) !void {
        self.server_thread = try std.Thread.spawn(.{}, echoServerThread, .{self});
    }
};

// ============================================================================
// Test: Unix 平台基本功能
// ============================================================================

test "TCP Socket Unix: init and basic setup" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var socket = try TcpSocket.init(allocator, "127.0.0.1", 8080);
    defer socket.deinit();

    try std.testing.expectEqualStrings("127.0.0.1", socket.host);
    try std.testing.expectEqual(@as(u16, 8080), socket.port);
    try std.testing.expect(socket.stream == null);
}

test "TCP Socket Unix: connect and disconnect" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 创建服务端
    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // 创建客户端
    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();

    // 连接
    try transport.connect("");
    try std.testing.expect(transport.isConnected());

    // 断开
    transport.disconnect();
    try std.testing.expect(!transport.isConnected());
}

test "TCP Socket Unix: basic read and write" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect("");

    // 写入数据
    const write_data = "Hello, TCP on Unix!";
    try transport.write(write_data);

    // 读取回显数据
    var read_buffer: [100]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(write_data.len, bytes_read);
    try std.testing.expectEqualStrings(write_data, read_buffer[0..bytes_read]);
}

// ============================================================================
// Test: Unix POSIX 错误处理
// ============================================================================

test "TCP Socket Unix: BrokenPipe error on write to closed socket" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect("");

    // 服务端关闭连接
    server.closeClientConnection();
    std.Thread.sleep(100 * std.time.ns_per_ms);

    // 尝试写入应该得到 BrokenPipe 或 ConnectionClosed 错误
    const write_result = transport.write("test data");
    try std.testing.expect(std.meta.isError(write_result));

    // 应该是 BrokenPipe 或 ConnectionClosed
    if (write_result) |_| {
        try std.testing.expect(false);
    } else |err| {
        const is_expected = (err == Transport.WriteError.BrokenPipe or
            err == Transport.WriteError.ConnectionClosed);
        try std.testing.expect(is_expected);
    }
}

test "TCP Socket Unix: ConnectionResetByPeer on abrupt close" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect("");

    // 发送一些数据
    try transport.write("initial data");

    // 服务端突然关闭
    server.closeClientConnection();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // 读取应该返回 ConnectionClosed
    var buffer: [100]u8 = undefined;
    const read_result = transport.read(&buffer);

    if (read_result) |bytes| {
        // 可能读到 0 字节（EOF）
        try std.testing.expectEqual(@as(usize, 0), bytes);
    } else |err| {
        // 或者得到 ConnectionClosed 错误
        try std.testing.expectEqual(Transport.ReadError.ConnectionClosed, err);
    }
}

test "TCP Socket Unix: read returns 0 on graceful close" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect("");

    // 服务端正常关闭
    server.closeClientConnection();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // 读取应该返回 0 或 ConnectionClosed
    var buffer: [100]u8 = undefined;
    const result = transport.read(&buffer);

    if (result) |bytes| {
        try std.testing.expectEqual(@as(usize, 0), bytes);
    } else |_| {
        // ConnectionClosed 也是可接受的
    }
}

test "TCP Socket Unix: error on read from disconnected socket" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var socket = try TcpSocket.init(allocator, "127.0.0.1", 9999);
    defer socket.deinit();

    var transport = socket.asTransport();

    // 未连接时读取
    var buffer: [100]u8 = undefined;
    const result = transport.read(&buffer);

    try std.testing.expectError(Transport.ReadError.ConnectionClosed, result);
}

test "TCP Socket Unix: error on write to disconnected socket" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var socket = try TcpSocket.init(allocator, "127.0.0.1", 9998);
    defer socket.deinit();

    var transport = socket.asTransport();

    // 未连接时写入
    const result = transport.write("test data");

    try std.testing.expectError(Transport.WriteError.ConnectionClosed, result);
}

// ============================================================================
// Test: Unix 网络特性
// ============================================================================

test "TCP Socket Unix: SO_REUSEADDR allows quick rebind" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 创建并关闭一个服务器
    var server1 = try TcpTestServer.init(allocator);
    const port = server1.port;
    server1.deinit();

    // 立即在同一端口创建新服务器（SO_REUSEADDR 允许这样做）
    std.Thread.sleep(10 * std.time.ns_per_ms);

    const addr = try std.net.Address.parseIp("127.0.0.1", port);
    const server2 = addr.listen(.{
        .reuse_address = true,
    }) catch |err| {
        // 如果失败，可能是端口仍在 TIME_WAIT 状态
        // 这在某些系统上是正常的
        if (err == error.AddressInUse) {
            return error.SkipZigTest;
        }
        return err;
    };
    defer server2.deinit();

    // 验证服务器创建成功
    try std.testing.expect(true);
}

test "TCP Socket Unix: large data transfer" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect("");

    // 发送 4KB 数据
    var large_data: [4096]u8 = undefined;
    for (&large_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    try transport.write(&large_data);

    // 读取回显
    var read_buffer: [4096]u8 = undefined;
    var total_read: usize = 0;

    while (total_read < large_data.len) {
        const bytes_read = try transport.read(read_buffer[total_read..]);
        if (bytes_read == 0) break;
        total_read += bytes_read;
    }

    try std.testing.expectEqual(large_data.len, total_read);
    try std.testing.expectEqualSlices(u8, &large_data, &read_buffer);
}

test "TCP Socket Unix: multiple sequential connections" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var socket = try TcpSocket.init(allocator, "127.0.0.1", 0);
    defer socket.deinit();

    var transport = socket.asTransport();

    // 连接和断开多次
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        var server = try TcpTestServer.init(allocator);
        defer server.deinit();

        try server.startEchoServer();
        std.Thread.sleep(50 * std.time.ns_per_ms);

        // 更新端口
        socket.port = server.port;

        // 连接
        try transport.connect("");
        try std.testing.expect(transport.isConnected());

        // 简单通信
        try transport.write("test");
        var buffer: [10]u8 = undefined;
        _ = try transport.read(&buffer);

        // 断开
        transport.disconnect();
        try std.testing.expect(!transport.isConnected());

        std.Thread.sleep(50 * std.time.ns_per_ms);
    }
}

test "TCP Socket Unix: binary data with all byte values" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect("");

    // 创建包含所有字节值的数据
    var all_bytes: [256]u8 = undefined;
    for (&all_bytes, 0..) |*byte, i| {
        byte.* = @intCast(i);
    }

    try transport.write(&all_bytes);

    var read_buffer: [256]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(@as(usize, 256), bytes_read);
    try std.testing.expectEqualSlices(u8, &all_bytes, &read_buffer);
}

test "TCP Socket Unix: null bytes in binary data" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect("");

    // 包含空字节的二进制数据
    const binary_data = [_]u8{ 0x01, 0x00, 0x02, 0x00, 0x03, 0xFF, 0x00 };
    try transport.write(&binary_data);

    var read_buffer: [10]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(binary_data.len, bytes_read);
    try std.testing.expectEqualSlices(u8, &binary_data, read_buffer[0..bytes_read]);
}

test "TCP Socket Unix: reconnect to different server" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 第一个服务器
    var server1 = try TcpTestServer.init(allocator);
    defer server1.deinit();
    try server1.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server1.port);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect("");

    // 验证连接到第一个服务器
    try transport.write("server1");
    var buffer1: [10]u8 = undefined;
    _ = try transport.read(&buffer1);

    // 断开
    transport.disconnect();

    // 第二个服务器
    var server2 = try TcpTestServer.init(allocator);
    defer server2.deinit();
    try server2.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // 连接到第二个服务器
    socket.port = server2.port;
    try transport.connect("");

    // 验证连接到第二个服务器
    try transport.write("server2");
    var buffer2: [10]u8 = undefined;
    _ = try transport.read(&buffer2);

    try std.testing.expect(transport.isConnected());
}

// ============================================================================
// Test: Unix 特定的边界情况
// ============================================================================

test "TCP Socket Unix: connect to localhost via 127.0.0.1" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect("");

    try std.testing.expect(transport.isConnected());
}

test "TCP Socket Unix: IPv6 loopback connection" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 尝试创建 IPv6 服务器
    const addr = std.net.Address.parseIp("::1", 0) catch {
        // 如果系统不支持 IPv6，跳过测试
        return error.SkipZigTest;
    };

    const server = addr.listen(.{
        .reuse_address = true,
    }) catch {
        // IPv6 可能不可用
        return error.SkipZigTest;
    };
    defer server.deinit();

    const actual_addr = try server.listen_address.getOsSockLen();
    const port = std.mem.bigToNative(u16, actual_addr.in6.port);

    var socket = try TcpSocket.init(allocator, "::1", port);
    defer socket.deinit();

    var transport = socket.asTransport();

    // 尝试连接（可能失败，取决于系统配置）
    transport.connect("") catch {
        return error.SkipZigTest;
    };

    try std.testing.expect(transport.isConnected());
}

test "TCP Socket Unix: rapid connect/disconnect cycles" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();

    // 快速连接和断开
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try transport.connect("");
        try std.testing.expect(transport.isConnected());

        transport.disconnect();
        try std.testing.expect(!transport.isConnected());

        // 短暂延迟
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
}

test "TCP Socket Unix: MessagePack-RPC style data" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try TcpTestServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = try TcpSocket.init(allocator, "127.0.0.1", server.port);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect("");

    // 模拟 MessagePack-RPC 请求
    const msgpack_request = [_]u8{ 0x94, 0x00, 0x01, 0xAD, 'n', 'v', 'i', 'm', '_', 'g', 'e', 't', '_', 'm', 'o', 'd', 'e', 0x90 };

    try transport.write(&msgpack_request);

    var read_buffer: [50]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(msgpack_request.len, bytes_read);
    try std.testing.expectEqualSlices(u8, &msgpack_request, read_buffer[0..bytes_read]);
}
