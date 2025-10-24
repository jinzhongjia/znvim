const std = @import("std");
const builtin = @import("builtin");
const UnixSocket = @import("../transport/unix_socket.zig").UnixSocket;
const Transport = @import("../transport/transport.zig").Transport;

// ============================================================================
// UnixSocket Transport 单元测试
//
// 创建测试用的 Unix domain socket 服务端来测试实际的读写功能
// 不依赖 Neovim
// ============================================================================

// ============================================================================
// Helper: Unix Socket 测试服务端
// ============================================================================

const SocketServer = struct {
    server: std.net.Server,
    socket_path: []const u8,
    allocator: std.mem.Allocator,
    server_thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool),
    client_stream: ?std.net.Stream = null,

    const Self = @This();

    fn init(allocator: std.mem.Allocator) !Self {
        if (builtin.os.tag == .windows) {
            return error.PlatformNotSupported;
        }

        const timestamp = std.time.milliTimestamp();
        const socket_path = try std.fmt.allocPrint(
            allocator,
            "/tmp/test-socket-{d}",
            .{timestamp},
        );
        errdefer allocator.free(socket_path);

        // 删除可能存在的旧socket文件
        std.fs.cwd().deleteFile(socket_path) catch {};

        const addr = try std.net.Address.initUnix(socket_path);
        const server = try addr.listen(.{
            .reuse_address = true,
        });

        return Self{
            .server = server,
            .socket_path = socket_path,
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

        // 清理 socket 文件
        std.fs.cwd().deleteFile(self.socket_path) catch {};
        self.allocator.free(self.socket_path);
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
// Test: 基本初始化和状态
// ============================================================================

test "UnixSocket init creates disconnected instance" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    try std.testing.expect(socket.stream == null);

    var transport = socket.asTransport();
    try std.testing.expect(!transport.isConnected());
}

test "UnixSocket deinit without connection is safe" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var socket = UnixSocket.init(allocator);

    // 多次调用 deinit 应该是安全的
    socket.deinit();
    socket.deinit();
    socket.deinit();

    try std.testing.expect(socket.stream == null);
}

test "UnixSocket asTransport returns valid transport" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();

    // 验证 vtable 指针正确
    try std.testing.expectEqual(&UnixSocket.vtable, transport.vtable);

    // 验证初始状态
    try std.testing.expect(!transport.isConnected());
}

// ============================================================================
// Test: 连接和断开
// ============================================================================

test "UnixSocket connect to server" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 创建服务端
    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();

    // 等待服务端启动
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // 创建客户端
    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();

    // 连接
    try transport.connect(server.socket_path);
    try std.testing.expect(transport.isConnected());
    try std.testing.expect(socket.stream != null);
}

test "UnixSocket disconnect closes stream" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server.socket_path);

    // 断开连接
    transport.disconnect();

    try std.testing.expect(!transport.isConnected());
    try std.testing.expect(socket.stream == null);
}

test "UnixSocket reconnect after disconnect" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 第一次连接
    var server1 = try SocketServer.init(allocator);
    defer server1.deinit();
    try server1.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server1.socket_path);
    try std.testing.expect(transport.isConnected());

    // 断开
    transport.disconnect();
    try std.testing.expect(!transport.isConnected());

    // 重新连接到新服务端
    var server2 = try SocketServer.init(allocator);
    defer server2.deinit();
    try server2.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    try transport.connect(server2.socket_path);
    try std.testing.expect(transport.isConnected());
}

// ============================================================================
// Test: 读写操作
// ============================================================================

test "UnixSocket basic write and read" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server.socket_path);

    // 写入数据
    const write_data = "Hello, Unix Socket!";
    try transport.write(write_data);

    // 读取回显数据
    var read_buffer: [100]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(write_data.len, bytes_read);
    try std.testing.expectEqualStrings(write_data, read_buffer[0..bytes_read]);
}

test "UnixSocket multiple sequential writes" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server.socket_path);

    // 写入多个数据块
    const data1 = "First ";
    const data2 = "Second ";
    const data3 = "Third";

    try transport.write(data1);
    try transport.write(data2);
    try transport.write(data3);

    // 读取所有回显数据
    var buffer1: [10]u8 = undefined;
    var buffer2: [10]u8 = undefined;
    var buffer3: [10]u8 = undefined;

    const len1 = try transport.read(&buffer1);
    const len2 = try transport.read(&buffer2);
    const len3 = try transport.read(&buffer3);

    try std.testing.expectEqualStrings(data1, buffer1[0..len1]);
    try std.testing.expectEqualStrings(data2, buffer2[0..len2]);
    try std.testing.expectEqualStrings(data3, buffer3[0..len3]);
}

test "UnixSocket binary data with null bytes" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server.socket_path);

    // 二进制数据包含空字节
    const binary_data = [_]u8{ 0x01, 0x00, 0x02, 0x00, 0x03, 0xFF };
    try transport.write(&binary_data);

    var read_buffer: [10]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(@as(usize, 6), bytes_read);
    try std.testing.expectEqualSlices(u8, &binary_data, read_buffer[0..bytes_read]);
}

test "UnixSocket all byte values (0-255)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server.socket_path);

    // 创建包含所有可能字节值的数据
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

test "UnixSocket large data transfer (1KB)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server.socket_path);

    // 创建 1KB 数据
    var large_data: [1024]u8 = undefined;
    for (&large_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    try transport.write(&large_data);

    var read_buffer: [1024]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(@as(usize, 1024), bytes_read);
    try std.testing.expectEqualSlices(u8, &large_data, &read_buffer);
}

test "UnixSocket very large data transfer (4KB)" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server.socket_path);

    // 创建 4KB 数据
    var large_data: [4096]u8 = undefined;
    for (&large_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    try transport.write(&large_data);

    var read_buffer: [4096]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(@as(usize, 4096), bytes_read);
    try std.testing.expectEqualSlices(u8, &large_data, &read_buffer);
}

test "UnixSocket empty data write" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server.socket_path);

    // 写入空数据应该成功
    try transport.write("");
}

test "UnixSocket read with small buffer" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server.socket_path);

    // 写入数据
    const data = "1234567890";
    try transport.write(data);

    // 用小缓冲区读取
    var small_buffer: [5]u8 = undefined;
    const bytes_read = try transport.read(&small_buffer);

    // 应该只读取缓冲区大小的数据
    try std.testing.expectEqual(@as(usize, 5), bytes_read);
    try std.testing.expectEqualStrings("12345", &small_buffer);

    // 读取剩余数据
    var remaining_buffer: [5]u8 = undefined;
    const remaining_read = try transport.read(&remaining_buffer);
    try std.testing.expectEqual(@as(usize, 5), remaining_read);
    try std.testing.expectEqualStrings("67890", &remaining_buffer);
}

// ============================================================================
// Test: 错误处理
// ============================================================================

test "UnixSocket read on disconnected returns ConnectionClosed" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    var buffer: [10]u8 = undefined;

    const result = transport.read(&buffer);
    try std.testing.expectError(Transport.ReadError.ConnectionClosed, result);
}

test "UnixSocket write on disconnected returns ConnectionClosed" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    const data = "test data";

    const result = transport.write(data);
    try std.testing.expectError(Transport.WriteError.ConnectionClosed, result);
}

test "UnixSocket connect to nonexistent socket fails" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();

    const nonexistent_path = "/tmp/nonexistent-socket-12345";
    const result = transport.connect(nonexistent_path);

    try std.testing.expect(std.meta.isError(result));
}

test "UnixSocket multiple disconnect calls are safe" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();

    // 多次断开连接应该是安全的
    transport.disconnect();
    transport.disconnect();
    transport.disconnect();

    try std.testing.expect(!transport.isConnected());
}

// ============================================================================
// Test: VTable 机制
// ============================================================================

test "UnixSocket vtable function pointers are valid" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const vtable_addr = @intFromPtr(&UnixSocket.vtable);
    try std.testing.expect(vtable_addr != 0);

    try std.testing.expect(@intFromPtr(UnixSocket.vtable.connect) != 0);
    try std.testing.expect(@intFromPtr(UnixSocket.vtable.disconnect) != 0);
    try std.testing.expect(@intFromPtr(UnixSocket.vtable.read) != 0);
    try std.testing.expect(@intFromPtr(UnixSocket.vtable.write) != 0);
    try std.testing.expect(@intFromPtr(UnixSocket.vtable.is_connected) != 0);
}

test "UnixSocket downcast works correctly" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();

    // downcast 应该返回原始指针
    const downcasted = transport.downcast(UnixSocket);
    try std.testing.expectEqual(&socket, downcasted);

    // downcastConst 也应该工作
    const downcasted_const = transport.downcastConst(UnixSocket);
    try std.testing.expectEqual(&socket, downcasted_const);
}

// ============================================================================
// Test: MessagePack-RPC 风格数据
// ============================================================================

test "UnixSocket MessagePack-RPC style data" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try SocketServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var socket = UnixSocket.init(allocator);
    defer socket.deinit();

    var transport = socket.asTransport();
    try transport.connect(server.socket_path);

    // 模拟 MessagePack-RPC 请求: [0, 1, "nvim_get_mode", []]
    const msgpack_request = [_]u8{ 0x94, 0x00, 0x01, 0xAD, 'n', 'v', 'i', 'm', '_', 'g', 'e', 't', '_', 'm', 'o', 'd', 'e', 0x90 };

    try transport.write(&msgpack_request);

    var read_buffer: [50]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(msgpack_request.len, bytes_read);
    try std.testing.expectEqualSlices(u8, &msgpack_request, read_buffer[0..bytes_read]);
}
