const std = @import("std");
const builtin = @import("builtin");
const znvim = @import("../root.zig");
const Stdio = @import("../transport/stdio.zig").Stdio;
const Transport = @import("../transport/transport.zig").Transport;

// ============================================================================
// Windows 专用的 Stdio Transport 测试
//
// 由于 Windows 不支持 POSIX pipe()，这里使用临时文件和实际的
// 子进程来测试 Stdio transport 的读写功能。
// ============================================================================

// ============================================================================
// Helper: 使用临时文件模拟 stdio 管道
// ============================================================================

const TempFilePair = struct {
    read_file: std.fs.File,
    write_file: std.fs.File,
    read_path: []const u8,
    write_path: []const u8,
    allocator: std.mem.Allocator,

    fn create(allocator: std.mem.Allocator) !TempFilePair {
        const temp_dir = std.fs.cwd();

        // 创建唯一的临时文件名
        const timestamp = std.time.milliTimestamp();
        const read_path = try std.fmt.allocPrint(allocator, "test_stdio_read_{d}.tmp", .{timestamp});
        errdefer allocator.free(read_path);

        const write_path = try std.fmt.allocPrint(allocator, "test_stdio_write_{d}.tmp", .{timestamp});
        errdefer allocator.free(write_path);

        // 创建临时文件
        const read_file = try temp_dir.createFile(read_path, .{ .read = true, .truncate = true });
        errdefer {
            read_file.close();
            temp_dir.deleteFile(read_path) catch {};
        }

        const write_file = try temp_dir.createFile(write_path, .{ .read = true, .truncate = true });
        errdefer {
            write_file.close();
            temp_dir.deleteFile(write_path) catch {};
        }

        return TempFilePair{
            .read_file = read_file,
            .write_file = write_file,
            .read_path = read_path,
            .write_path = write_path,
            .allocator = allocator,
        };
    }

    fn close(self: *TempFilePair) void {
        self.read_file.close();
        self.write_file.close();

        // 删除临时文件
        const temp_dir = std.fs.cwd();
        temp_dir.deleteFile(self.read_path) catch {};
        temp_dir.deleteFile(self.write_path) catch {};

        self.allocator.free(self.read_path);
        self.allocator.free(self.write_path);
    }

    // 重新打开文件用于读取（在写入后）
    fn reopenForRead(self: *TempFilePair, path: []const u8) !std.fs.File {
        const temp_dir = std.fs.cwd();
        return try temp_dir.openFile(path, .{ .mode = .read_only });
    }
};

// ============================================================================
// Test: Windows 上使用临时文件的基本读写操作
// ============================================================================

test "stdio transport Windows: write and read data through temp files" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    // 使用临时文件创建 Stdio
    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // 写入数据
    const write_data = "Hello, Windows Stdio!";
    try transport.write(write_data);

    // 需要关闭写入文件并重新打开以读取
    temp_pair.write_file.close();
    const read_back_file = try temp_pair.reopenForRead(temp_pair.write_path);
    defer read_back_file.close();

    // 读取数据验证
    var read_buffer: [100]u8 = undefined;
    const bytes_read = try read_back_file.read(&read_buffer);
    try std.testing.expectEqual(write_data.len, bytes_read);
    try std.testing.expectEqualStrings(write_data, read_buffer[0..bytes_read]);
}

test "stdio transport Windows: multiple sequential writes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // 写入多个数据块
    try transport.write("First ");
    try transport.write("Second ");
    try transport.write("Third");

    // 关闭并重新打开以读取
    temp_pair.write_file.close();
    const read_back_file = try temp_pair.reopenForRead(temp_pair.write_path);
    defer read_back_file.close();

    // 读取所有数据
    var read_buffer: [100]u8 = undefined;
    const bytes_read = try read_back_file.read(&read_buffer);
    try std.testing.expectEqualStrings("First Second Third", read_buffer[0..bytes_read]);
}

test "stdio transport Windows: write empty data" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // 写入空数据应该成功
    try transport.write("");
}

test "stdio transport Windows: write large data chunk" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // 创建大数据 (1KB)
    var large_data: [1024]u8 = undefined;
    for (&large_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    // 写入和验证
    try transport.write(&large_data);

    temp_pair.write_file.close();
    const read_back_file = try temp_pair.reopenForRead(temp_pair.write_path);
    defer read_back_file.close();

    var read_buffer: [1024]u8 = undefined;
    const bytes_read = try read_back_file.read(&read_buffer);
    try std.testing.expectEqual(@as(usize, 1024), bytes_read);
    try std.testing.expectEqualSlices(u8, &large_data, &read_buffer);
}

test "stdio transport Windows: handle binary data with null bytes" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // 二进制数据包含空字节
    const binary_data = [_]u8{ 0x01, 0x00, 0x02, 0x00, 0x03, 0xFF };
    try transport.write(&binary_data);

    temp_pair.write_file.close();
    const read_back_file = try temp_pair.reopenForRead(temp_pair.write_path);
    defer read_back_file.close();

    var read_buffer: [6]u8 = undefined;
    const bytes_read = try read_back_file.read(&read_buffer);
    try std.testing.expectEqual(@as(usize, 6), bytes_read);
    try std.testing.expectEqualSlices(u8, &binary_data, &read_buffer);
}

test "stdio transport Windows: handle all byte values (0-255)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // 创建包含所有可能字节值的数据
    var all_bytes: [256]u8 = undefined;
    for (&all_bytes, 0..) |*byte, i| {
        byte.* = @intCast(i);
    }

    try transport.write(&all_bytes);

    temp_pair.write_file.close();
    const read_back_file = try temp_pair.reopenForRead(temp_pair.write_path);
    defer read_back_file.close();

    var read_buffer: [256]u8 = undefined;
    const bytes_read = try read_back_file.read(&read_buffer);
    try std.testing.expectEqual(@as(usize, 256), bytes_read);
    try std.testing.expectEqualSlices(u8, &all_bytes, &read_buffer);
}

test "stdio transport Windows: read data from pre-written file" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    // 预先写入数据到读取文件
    const test_data = "Test data for reading";
    _ = try temp_pair.read_file.write(test_data);

    // 将文件指针移回开头
    try temp_pair.read_file.seekTo(0);

    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // 通过 transport 读取
    var read_buffer: [100]u8 = undefined;
    const bytes_read = try transport.read(&read_buffer);
    try std.testing.expectEqual(test_data.len, bytes_read);
    try std.testing.expectEqualStrings(test_data, read_buffer[0..bytes_read]);
}

test "stdio transport Windows: read partial data from small buffer" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    // 写入更多数据
    _ = try temp_pair.read_file.write("1234567890");
    try temp_pair.read_file.seekTo(0);

    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // 用小缓冲区读取
    var small_buffer: [5]u8 = undefined;
    const bytes_read = try transport.read(&small_buffer);
    try std.testing.expectEqual(@as(usize, 5), bytes_read);
    try std.testing.expectEqualStrings("12345", &small_buffer);

    // 读取剩余数据
    var remaining_buffer: [5]u8 = undefined;
    const remaining_read = try transport.read(&remaining_buffer);
    try std.testing.expectEqual(@as(usize, 5), remaining_read);
    try std.testing.expectEqualStrings("67890", &remaining_buffer);
}

test "stdio transport Windows: read into empty buffer" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    // 写入一些数据
    _ = try temp_pair.read_file.write("test");
    try temp_pair.read_file.seekTo(0);

    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // 尝试用空缓冲区读取
    var empty_buffer: [0]u8 = undefined;
    const bytes_read = try transport.read(&empty_buffer);
    try std.testing.expectEqual(@as(usize, 0), bytes_read);
}

test "stdio transport Windows: simulated msgpack-rpc message exchange" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    defer stdio.deinit();

    var transport = stdio.asTransport();

    // 模拟 MessagePack-RPC 请求: [0, 1, "nvim_get_mode", []]
    const request_data = [_]u8{ 0x94, 0x00, 0x01, 0xAD, 'n', 'v', 'i', 'm', '_', 'g', 'e', 't', '_', 'm', 'o', 'd', 'e', 0x90 };
    try transport.write(&request_data);

    // 读取验证
    temp_pair.write_file.close();
    const read_back_file = try temp_pair.reopenForRead(temp_pair.write_path);
    defer read_back_file.close();

    var read_buffer: [100]u8 = undefined;
    const bytes_read = try read_back_file.read(&read_buffer);
    try std.testing.expectEqual(request_data.len, bytes_read);
    try std.testing.expectEqualSlices(u8, &request_data, read_buffer[0..bytes_read]);
}

// ============================================================================
// Test: Ownership handling
// ============================================================================

test "stdio transport Windows: deinit with owns_handles=false does not close files" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var temp_pair = try TempFilePair.create(allocator);
    defer temp_pair.close();

    var stdio = Stdio.initWithFiles(temp_pair.read_file, temp_pair.write_file, false);
    stdio.deinit();

    // 文件应该仍然可用
    const test_data = "Still works";
    const bytes_written = try temp_pair.write_file.write(test_data);
    try std.testing.expectEqual(test_data.len, bytes_written);
}

test "stdio transport Windows: deinit with owns_handles=true closes files" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 创建临时文件
    const temp_dir = std.fs.cwd();
    const timestamp = std.time.milliTimestamp();
    const path1 = try std.fmt.allocPrint(allocator, "test_owns_read_{d}.tmp", .{timestamp});
    defer allocator.free(path1);
    const path2 = try std.fmt.allocPrint(allocator, "test_owns_write_{d}.tmp", .{timestamp});
    defer allocator.free(path2);

    const read_file = try temp_dir.createFile(path1, .{});
    const write_file = try temp_dir.createFile(path2, .{});

    // stdio 拥有文件句柄的所有权
    var stdio = Stdio.initWithFiles(read_file, write_file, true);
    stdio.deinit();

    // 清理临时文件
    temp_dir.deleteFile(path1) catch {};
    temp_dir.deleteFile(path2) catch {};

    // 验证 deinit 没有崩溃就是成功
}

// ============================================================================
// Test: 使用实际的 child process 进行端到端测试
// ============================================================================

test "stdio transport Windows: real communication with child process" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;

    // 使用 spawn_process 创建真实的 nvim 实例
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .skip_api_info = true,
    });
    defer {
        client.disconnect();
        client.deinit();
    }

    try client.connect();

    // 执行一个简单的请求验证 stdio 通信工作正常
    const msgpack = @import("../msgpack.zig");
    const params = [_]msgpack.Value{};
    const result = try client.request("nvim_get_mode", &params);
    defer msgpack.free(result, allocator);

    // 验证返回了结果
    try std.testing.expect(result == .map);
}
