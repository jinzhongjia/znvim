const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const Transport = @import("../transport/transport.zig").Transport;
const WindowsPipe = if (builtin.os.tag == .windows)
    @import("../transport/windows_pipe.zig").WindowsPipe
else
    struct {};

// ============================================================================
// Windows 命名管道单元测试 - 独立读写测试
//
// 这些测试创建一个简单的命名管道服务端来测试 WindowsPipe 的实际
// 读写功能，不依赖 Neovim。
// ============================================================================

// Windows API 声明
extern "kernel32" fn CreateNamedPipeW(
    lpName: windows.LPCWSTR,
    dwOpenMode: windows.DWORD,
    dwPipeMode: windows.DWORD,
    nMaxInstances: windows.DWORD,
    nOutBufferSize: windows.DWORD,
    nInBufferSize: windows.DWORD,
    nDefaultTimeOut: windows.DWORD,
    lpSecurityAttributes: ?*windows.SECURITY_ATTRIBUTES,
) callconv(.winapi) windows.HANDLE;

extern "kernel32" fn ConnectNamedPipe(
    hNamedPipe: windows.HANDLE,
    lpOverlapped: ?*windows.OVERLAPPED,
) callconv(.winapi) windows.BOOL;

extern "kernel32" fn DisconnectNamedPipe(
    hNamedPipe: windows.HANDLE,
) callconv(.winapi) windows.BOOL;

// 常量定义
const PIPE_ACCESS_DUPLEX: windows.DWORD = 0x00000003;
const PIPE_TYPE_BYTE: windows.DWORD = 0x00000000;
const PIPE_READMODE_BYTE: windows.DWORD = 0x00000000;
const PIPE_WAIT: windows.DWORD = 0x00000000;
const PIPE_UNLIMITED_INSTANCES: windows.DWORD = 255;

// ============================================================================
// Helper: 命名管道测试服务端
// ============================================================================

const PipeServer = struct {
    pipe_handle: windows.HANDLE,
    pipe_path: []const u8,
    allocator: std.mem.Allocator,
    server_thread: ?std.Thread = null,
    should_stop: std.atomic.Value(bool),

    const Self = @This();

    fn init(allocator: std.mem.Allocator) !Self {
        const timestamp = std.time.milliTimestamp();
        const pipe_path = try std.fmt.allocPrint(
            allocator,
            "\\\\.\\pipe\\test-pipe-{d}",
            .{timestamp},
        );
        errdefer allocator.free(pipe_path);

        const wide_path = try std.unicode.utf8ToUtf16LeAllocZ(allocator, pipe_path);
        defer allocator.free(wide_path);

        const handle = CreateNamedPipeW(
            wide_path.ptr,
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
            PIPE_UNLIMITED_INSTANCES,
            4096, // out buffer size
            4096, // in buffer size
            0, // default timeout
            null,
        );

        if (handle == windows.INVALID_HANDLE_VALUE) {
            allocator.free(pipe_path);
            return error.CreatePipeFailed;
        }

        return Self{
            .pipe_handle = handle,
            .pipe_path = pipe_path,
            .allocator = allocator,
            .should_stop = std.atomic.Value(bool).init(false),
        };
    }

    fn deinit(self: *Self) void {
        self.should_stop.store(true, .seq_cst);

        if (self.server_thread) |thread| {
            thread.join();
        }

        if (self.pipe_handle != windows.INVALID_HANDLE_VALUE) {
            _ = DisconnectNamedPipe(self.pipe_handle);
            windows.CloseHandle(self.pipe_handle);
        }

        self.allocator.free(self.pipe_path);
    }

    fn waitForConnection(self: *Self) !void {
        const result = ConnectNamedPipe(self.pipe_handle, null);
        if (result == 0) {
            const err = windows.GetLastError();
            if (err != .PIPE_CONNECTED) {
                return error.ConnectFailed;
            }
        }
    }

    fn read(self: *Self, buffer: []u8) !usize {
        var bytes_read: windows.DWORD = 0;
        const result = windows.kernel32.ReadFile(
            self.pipe_handle,
            buffer.ptr,
            @intCast(buffer.len),
            &bytes_read,
            null,
        );

        if (result == 0) {
            return error.ReadFailed;
        }

        return bytes_read;
    }

    fn write(self: *Self, data: []const u8) !void {
        var bytes_written: windows.DWORD = 0;
        const result = windows.kernel32.WriteFile(
            self.pipe_handle,
            data.ptr,
            @intCast(data.len),
            &bytes_written,
            null,
        );

        if (result == 0 or bytes_written != data.len) {
            return error.WriteFailed;
        }
    }

    // Echo server: 读取数据并原样返回
    fn echoServerThread(self: *Self) void {
        self.waitForConnection() catch return;

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
// Test: 基本读写操作
// ============================================================================

test "WindowsPipe unit: basic write and read" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 创建服务端
    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();

    // 等待服务端启动
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // 创建客户端
    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();

    // 连接
    try transport.connect(server.pipe_path);
    try std.testing.expect(transport.isConnected());

    // 写入数据
    const write_data = "Hello, Named Pipe!";
    try transport.write(write_data);

    // 读取回显数据
    var read_buffer: [100]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(write_data.len, bytes_read);
    try std.testing.expectEqualStrings(write_data, read_buffer[0..bytes_read]);
}

test "WindowsPipe unit: multiple sequential writes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    try transport.connect(server.pipe_path);

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

test "WindowsPipe unit: binary data with null bytes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    try transport.connect(server.pipe_path);

    // 二进制数据包含空字节
    const binary_data = [_]u8{ 0x01, 0x00, 0x02, 0x00, 0x03, 0xFF };
    try transport.write(&binary_data);

    var read_buffer: [10]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(@as(usize, 6), bytes_read);
    try std.testing.expectEqualSlices(u8, &binary_data, read_buffer[0..bytes_read]);
}

test "WindowsPipe unit: all byte values (0-255)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    try transport.connect(server.pipe_path);

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

test "WindowsPipe unit: large data transfer (1KB)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    try transport.connect(server.pipe_path);

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

test "WindowsPipe unit: very large data transfer (4KB)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    try transport.connect(server.pipe_path);

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

test "WindowsPipe unit: empty data write" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    try transport.connect(server.pipe_path);

    // 写入空数据应该成功
    try transport.write("");
}

test "WindowsPipe unit: read with small buffer" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    try transport.connect(server.pipe_path);

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

test "WindowsPipe unit: disconnect and reconnect" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();

    // 第一次连接
    try transport.connect(server.pipe_path);
    try std.testing.expect(transport.isConnected());

    // 断开连接
    transport.disconnect();
    try std.testing.expect(!transport.isConnected());

    // 重新创建服务端（因为服务端只接受一次连接）
    server.deinit();
    server = try PipeServer.init(allocator);
    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // 重新连接
    try transport.connect(server.pipe_path);
    try std.testing.expect(transport.isConnected());

    // 验证仍然可以通信
    const data = "reconnect test";
    try transport.write(data);

    var buffer: [20]u8 = undefined;
    const bytes_read = try transport.read(&buffer);
    try std.testing.expectEqualStrings(data, buffer[0..bytes_read]);
}

test "WindowsPipe unit: multiple rapid writes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    try transport.connect(server.pipe_path);

    // 快速连续写入多个数据
    const iterations = 10;
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const data = "X";
        try transport.write(data);

        var buffer: [1]u8 = undefined;
        const bytes_read = try transport.read(&buffer);
        try std.testing.expectEqual(@as(usize, 1), bytes_read);
        try std.testing.expectEqual(@as(u8, 'X'), buffer[0]);
    }
}

test "WindowsPipe unit: alternating small and large writes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    try transport.connect(server.pipe_path);

    // 小数据
    const small_data = "Hi";
    try transport.write(small_data);
    var small_buffer: [10]u8 = undefined;
    const small_read = try transport.read(&small_buffer);
    try std.testing.expectEqualStrings(small_data, small_buffer[0..small_read]);

    // 大数据
    var large_data: [512]u8 = undefined;
    @memset(&large_data, 'A');
    try transport.write(&large_data);
    var large_buffer: [512]u8 = undefined;
    const large_read = try transport.read(&large_buffer);
    try std.testing.expectEqual(@as(usize, 512), large_read);
    try std.testing.expectEqualSlices(u8, &large_data, &large_buffer);

    // 再次小数据
    const small_data2 = "Bye";
    try transport.write(small_data2);
    var small_buffer2: [10]u8 = undefined;
    const small_read2 = try transport.read(&small_buffer2);
    try std.testing.expectEqualStrings(small_data2, small_buffer2[0..small_read2]);
}

test "WindowsPipe unit: MessagePack-RPC style data" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    var server = try PipeServer.init(allocator);
    defer server.deinit();

    try server.startEchoServer();
    std.Thread.sleep(50 * std.time.ns_per_ms);

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    try transport.connect(server.pipe_path);

    // 模拟 MessagePack-RPC 请求: [0, 1, "nvim_get_mode", []]
    const msgpack_request = [_]u8{ 0x94, 0x00, 0x01, 0xAD, 'n', 'v', 'i', 'm', '_', 'g', 'e', 't', '_', 'm', 'o', 'd', 'e', 0x90 };

    try transport.write(&msgpack_request);

    var read_buffer: [50]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);

    try std.testing.expectEqual(msgpack_request.len, bytes_read);
    try std.testing.expectEqualSlices(u8, &msgpack_request, read_buffer[0..bytes_read]);
}
