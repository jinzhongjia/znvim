const std = @import("std");
const builtin = @import("builtin");
const znvim = @import("../root.zig");
const ChildProcess = @import("../transport/child_process.zig").ChildProcess;
const Transport = @import("../transport/transport.zig").Transport;
const connection = @import("../connection.zig");

// ============================================================================
// ChildProcess Transport 单元测试
//
// 测试启动嵌入式 Neovim 进程并通过管道通信的功能
// ============================================================================

// ============================================================================
// Test: 初始化和清理
// ============================================================================

test "ChildProcess init creates disconnected instance" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 5000,
    });
    defer child_proc.deinit();

    // 初始状态应该是未连接
    try std.testing.expect(child_proc.child == null);
    try std.testing.expect(child_proc.stdin_file == null);
    try std.testing.expect(child_proc.stdout_file == null);

    var transport = child_proc.asTransport();
    try std.testing.expect(!transport.isConnected());
}

test "ChildProcess init stores nvim path" {
    const allocator = std.testing.allocator;

    const custom_path = "/usr/local/bin/nvim";
    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = custom_path,
    });
    defer child_proc.deinit();

    try std.testing.expectEqualStrings(custom_path, child_proc.nvim_path);
}

test "ChildProcess init creates argv array" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    defer child_proc.deinit();

    // 应该有 3 个参数: nvim, --headless, --embed
    try std.testing.expectEqual(@as(usize, 3), child_proc.argv.len);
    try std.testing.expectEqualStrings("nvim", child_proc.argv[0]);
    try std.testing.expectEqualStrings("--headless", child_proc.argv[1]);
    try std.testing.expectEqualStrings("--embed", child_proc.argv[2]);
}

test "ChildProcess init with zero timeout" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 0,
    });
    defer child_proc.deinit();

    try std.testing.expectEqual(@as(u64, 0), child_proc.shutdown_timeout_ns);
}

test "ChildProcess init with custom timeout" {
    const allocator = std.testing.allocator;

    const timeout_ms: u32 = 3000;
    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = timeout_ms,
    });
    defer child_proc.deinit();

    const expected_ns = @as(u64, timeout_ms) * std.time.ns_per_ms;
    try std.testing.expectEqual(expected_ns, child_proc.shutdown_timeout_ns);
}

test "ChildProcess deinit without connection is safe" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });

    // 多次调用 deinit 应该是安全的
    child_proc.deinit();

    // 验证资源被清理
    try std.testing.expect(child_proc.child == null);
}

test "ChildProcess asTransport returns valid transport" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    // 验证 vtable 指针正确
    try std.testing.expectEqual(&ChildProcess.vtable, transport.vtable);

    // 验证初始状态
    try std.testing.expect(!transport.isConnected());
}

// ============================================================================
// Test: 连接和断开（需要 nvim 可用）
// ============================================================================

test "ChildProcess connect spawns nvim process" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 5000,
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    // 尝试连接（启动 nvim）
    transport.connect("") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest, // nvim 不可用
        else => return err,
    };

    // 连接后应该有子进程和文件句柄
    try std.testing.expect(transport.isConnected());
    try std.testing.expect(child_proc.child != null);
    try std.testing.expect(child_proc.stdin_file != null);
    try std.testing.expect(child_proc.stdout_file != null);
}

test "ChildProcess disconnect closes process" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 5000,
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    transport.connect("") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };

    // 断开连接
    transport.disconnect();

    // 应该清理所有资源
    try std.testing.expect(!transport.isConnected());
    try std.testing.expect(child_proc.child == null);
    try std.testing.expect(child_proc.stdin_file == null);
    try std.testing.expect(child_proc.stdout_file == null);
}

test "ChildProcess reconnect works after disconnect" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 5000,
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    // 第一次连接
    transport.connect("") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    try std.testing.expect(transport.isConnected());

    // 断开
    transport.disconnect();
    try std.testing.expect(!transport.isConnected());

    // 重新连接
    try transport.connect("");
    try std.testing.expect(transport.isConnected());
}

// ============================================================================
// Test: 读写操作
// ============================================================================

test "ChildProcess read/write basic communication" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 5000,
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    transport.connect("") catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };

    // 使用 Client 进行实际的 RPC 通信测试
    const msgpack = @import("../msgpack.zig");

    // 创建一个简单的请求并手动编码
    const encoder = @import("../protocol/encoder.zig");
    const message = @import("../protocol/message.zig");

    const params = [_]msgpack.Value{};
    const request = message.Request{
        .msgid = 1,
        .method = "nvim_get_mode",
        .params = msgpack.Value{ .arr = &params },
    };

    const encoded = try encoder.encodeRequest(allocator, request);
    defer allocator.free(encoded);

    // 写入请求
    try transport.write(encoded);

    // 读取响应（应该能读到一些数据）
    var buffer: [1024]u8 = undefined;
    const bytes_read = try transport.read(&buffer);

    // 应该读到至少一些字节
    try std.testing.expect(bytes_read > 0);
}

test "ChildProcess read on disconnected returns error" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    var buffer: [10]u8 = undefined;
    const result = transport.read(&buffer);

    try std.testing.expectError(Transport.ReadError.ConnectionClosed, result);
}

test "ChildProcess write on disconnected returns error" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    const data = "test data";
    const result = transport.write(data);

    try std.testing.expectError(Transport.WriteError.ConnectionClosed, result);
}

// ============================================================================
// Test: VTable 机制
// ============================================================================

test "ChildProcess vtable function pointers are valid" {
    // 验证 vtable 中的所有函数指针都被正确设置
    const vtable_addr = @intFromPtr(&ChildProcess.vtable);
    try std.testing.expect(vtable_addr != 0);

    try std.testing.expect(@intFromPtr(ChildProcess.vtable.connect) != 0);
    try std.testing.expect(@intFromPtr(ChildProcess.vtable.disconnect) != 0);
    try std.testing.expect(@intFromPtr(ChildProcess.vtable.read) != 0);
    try std.testing.expect(@intFromPtr(ChildProcess.vtable.write) != 0);
    try std.testing.expect(@intFromPtr(ChildProcess.vtable.is_connected) != 0);
}

test "ChildProcess downcast works correctly" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 2000,
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    // downcast 应该返回原始指针
    const downcasted = transport.downcast(ChildProcess);
    try std.testing.expectEqual(&child_proc, downcasted);

    const expected_timeout = @as(u64, 2000) * std.time.ns_per_ms;
    try std.testing.expectEqual(expected_timeout, downcasted.shutdown_timeout_ns);

    // downcastConst 也应该工作
    const downcasted_const = transport.downcastConst(ChildProcess);
    try std.testing.expectEqual(&child_proc, downcasted_const);
}

// ============================================================================
// Test: 错误处理和边界情况
// ============================================================================

test "ChildProcess handles invalid nvim path" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "/nonexistent/path/to/nvim",
        .timeout_ms = 1000,
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    // 连接应该失败
    const result = transport.connect("");
    try std.testing.expect(std.meta.isError(result));
}

test "ChildProcess multiple disconnect calls are safe" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    // 多次断开连接应该是安全的
    transport.disconnect();
    transport.disconnect();
    transport.disconnect();

    try std.testing.expect(!transport.isConnected());
}

test "ChildProcess state after failed connection" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "/invalid/nvim",
        .timeout_ms = 100,
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    // 尝试连接（应该失败）
    const connect_result = transport.connect("");
    try std.testing.expect(std.meta.isError(connect_result));

    // 失败后状态应该保持一致
    try std.testing.expect(!transport.isConnected());
    try std.testing.expect(child_proc.child == null);
    try std.testing.expect(child_proc.stdin_file == null);
    try std.testing.expect(child_proc.stdout_file == null);
}

// ============================================================================
// Test: 集成场景
// ============================================================================

test "ChildProcess end-to-end nvim communication" {
    const allocator = std.testing.allocator;

    // 使用 Client 进行完整的端到端测试
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .skip_api_info = true,
        .timeout_ms = 5000,
    });
    defer {
        client.disconnect();
        client.deinit();
    }

    client.connect() catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };

    // 执行一个简单的请求
    const msgpack = @import("../msgpack.zig");
    const params = [_]msgpack.Value{};
    const result = try client.request("nvim_get_mode", &params);
    defer msgpack.free(result, allocator);

    // 验证返回了 map 类型的结果
    try std.testing.expect(result == .map);
}

test "ChildProcess handles rapid connect/disconnect cycles" {
    const allocator = std.testing.allocator;

    var child_proc = try ChildProcess.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 5000,
    });
    defer child_proc.deinit();

    var transport = child_proc.asTransport();

    // 快速连接和断开多次
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        transport.connect("") catch |err| switch (err) {
            error.FileNotFound => return error.SkipZigTest,
            else => return err,
        };
        try std.testing.expect(transport.isConnected());

        transport.disconnect();
        try std.testing.expect(!transport.isConnected());

        // 短暂延迟以确保进程完全清理
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
}
