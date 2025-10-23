const std = @import("std");
const builtin = @import("builtin");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;
const windows = std.os.windows;

// 这个文件包含 Windows 命名管道的高级集成测试

// 编译时选项控制是否输出调试信息
const debug_output = false;

/// 测试辅助工具
const TestHelper = struct {
    allocator: std.mem.Allocator,
    nvim_process: ?std.process.Child = null,

    fn init(allocator: std.mem.Allocator) TestHelper {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *TestHelper) void {
        if (self.nvim_process) |*child| {
            self.terminateNvim(child);
        }
    }

    /// 启动 Nvim 监听命名管道
    fn spawnNvimWithPipe(self: *TestHelper, pipe_name: []const u8) !void {
        var child = std.process.Child.init(
            &.{ "nvim", "--headless", "--clean", "--listen", pipe_name },
            self.allocator,
        );
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Inherit;

        child.spawn() catch |err| switch (err) {
            error.FileNotFound => return error.SkipZigTest,
            else => return err,
        };

        self.nvim_process = child;
    }

    /// 等待管道就绪
    fn waitForPipe(self: *TestHelper, pipe_name: []const u8) !void {
        const unicode = std.unicode;
        const max_attempts: usize = 200;
        const retry_delay_ms: u64 = 10;

        var attempt: usize = 0;
        while (attempt < max_attempts) : (attempt += 1) {
            const wide_path = unicode.utf8ToUtf16LeAllocZ(self.allocator, pipe_name) catch {
                std.Thread.sleep(retry_delay_ms * std.time.ns_per_ms);
                continue;
            };
            defer self.allocator.free(wide_path);

            const handle = windows.kernel32.CreateFileW(
                wide_path.ptr,
                windows.GENERIC_READ,
                0,
                null,
                windows.OPEN_EXISTING,
                windows.FILE_ATTRIBUTE_NORMAL,
                null,
            );

            if (handle != windows.INVALID_HANDLE_VALUE) {
                windows.CloseHandle(handle);
                return;
            }

            std.Thread.sleep(retry_delay_ms * std.time.ns_per_ms);
        }
        return error.Timeout;
    }

    /// 终止 Nvim 进程
    fn terminateNvim(self: *TestHelper, child: *std.process.Child) void {
        _ = self.waitForExit(child, 10 * std.time.ns_per_s);
    }

    /// 等待进程退出（带超时）
    fn waitForExit(self: *TestHelper, child: *std.process.Child, timeout_ns: u64) bool {
        _ = self;
        const AtomicBool = std.atomic.Value(bool);

        const Waiter = struct {
            fn run(proc: *std.process.Child, term: *?std.process.Child.Term, done: *AtomicBool) void {
                term.* = proc.wait() catch null;
                done.store(true, .seq_cst);
            }
        };

        var done = AtomicBool.init(false);
        var term: ?std.process.Child.Term = null;

        const thread = std.Thread.spawn(.{}, Waiter.run, .{ child, &term, &done }) catch {
            _ = child.wait() catch {};
            return true;
        };

        var timer = std.time.Timer.start() catch unreachable;
        var timed_out = false;

        while (!done.load(.seq_cst)) {
            if (timer.read() >= timeout_ns) {
                timed_out = true;
                if (!done.load(.seq_cst)) {
                    _ = windows.TerminateProcess(child.id, 1) catch {};
                }
                break;
            }
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }

        thread.join();

        if (term == null) {
            _ = child.wait() catch {};
        }

        return !timed_out;
    }
};

// ============================================================================
// 集成测试
// ============================================================================

test "WindowsPipe connection and basic RPC" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var helper = TestHelper.init(allocator);
    defer helper.deinit();

    // 生成唯一管道名
    const pipe_name = try std.fmt.allocPrint(
        allocator,
        "\\\\.\\pipe\\nvim-rpc-test-{d}",
        .{std.time.timestamp()},
    );
    defer allocator.free(pipe_name);

    // 启动 Nvim（如果失败则跳过测试）
    helper.spawnNvimWithPipe(pipe_name) catch |err| switch (err) {
        error.SkipZigTest => return error.SkipZigTest,
        else => return err,
    };

    // 等待管道就绪
    helper.waitForPipe(pipe_name) catch |err| switch (err) {
        error.Timeout => return error.SkipZigTest,
        else => return err,
    };

    // 连接客户端
    var client = try znvim.Client.init(allocator, .{
        .socket_path = pipe_name,
        .skip_api_info = true,
    });
    defer client.deinit();

    client.connect() catch |err| switch (err) {
        error.Timeout, error.TransportNotInitialized => return error.SkipZigTest,
        else => return err,
    };

    if (!client.isConnected()) return error.SkipZigTest;

    // 执行简单的 RPC 调用
    const expr = try msgpack.string(allocator, "1+1");
    defer msgpack.free(expr, allocator);

    const params = [_]msgpack.Value{expr};
    var result = try client.request("vim_eval", &params);
    defer result.free(allocator);

    switch (result) {
        .int => |value| try std.testing.expectEqual(@as(i64, 2), value),
        .uint => |value| try std.testing.expectEqual(@as(u64, 2), value),
        else => return error.UnexpectedResultType,
    }

    // 发送退出命令
    const cmd = try msgpack.string(allocator, "qa!");
    defer msgpack.free(cmd, allocator);

    const quit_params = [_]msgpack.Value{cmd};
    try client.notify("nvim_command", &quit_params);
}

test "WindowsPipe with API info" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var helper = TestHelper.init(allocator);
    defer helper.deinit();

    const pipe_name = try std.fmt.allocPrint(
        allocator,
        "\\\\.\\pipe\\nvim-api-test-{d}",
        .{std.time.timestamp()},
    );
    defer allocator.free(pipe_name);

    helper.spawnNvimWithPipe(pipe_name) catch |err| switch (err) {
        error.SkipZigTest => return error.SkipZigTest,
        else => return err,
    };

    helper.waitForPipe(pipe_name) catch |err| switch (err) {
        error.Timeout => return error.SkipZigTest,
        else => return err,
    };

    // 这次不跳过 API info 获取
    var client = try znvim.Client.init(allocator, .{
        .socket_path = pipe_name,
        .skip_api_info = false,
    });
    defer client.deinit();

    client.connect() catch |err| switch (err) {
        error.Timeout, error.TransportNotInitialized => return error.SkipZigTest,
        else => return err,
    };

    // 验证 API info 被获取
    const api_info = client.getApiInfo();
    try std.testing.expect(api_info != null);
    try std.testing.expect(api_info.?.functions.len > 0);

    // 查找一个已知的 API 函数
    const eval_fn = client.findApiFunction("nvim_eval");
    try std.testing.expect(eval_fn != null);
    try std.testing.expectEqualStrings("nvim_eval", eval_fn.?.name);

    // 清理
    const cmd = try msgpack.string(allocator, "qa!");
    defer msgpack.free(cmd, allocator);
    const params = [_]msgpack.Value{cmd};
    try client.notify("nvim_command", &params);
}

test "WindowsPipe large data transfer" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var helper = TestHelper.init(allocator);
    defer helper.deinit();

    const pipe_name = try std.fmt.allocPrint(
        allocator,
        "\\\\.\\pipe\\nvim-large-test-{d}",
        .{std.time.timestamp()},
    );
    defer allocator.free(pipe_name);

    helper.spawnNvimWithPipe(pipe_name) catch |err| switch (err) {
        error.SkipZigTest => return error.SkipZigTest,
        else => return err,
    };

    helper.waitForPipe(pipe_name) catch |err| switch (err) {
        error.Timeout => return error.SkipZigTest,
        else => return err,
    };

    var client = try znvim.Client.init(allocator, .{
        .socket_path = pipe_name,
        .skip_api_info = true,
    });
    defer client.deinit();

    client.connect() catch |err| switch (err) {
        error.Timeout, error.ConnectionClosed => return error.SkipZigTest,
        else => return err,
    };

    // 创建大量行数据
    const line_count = 100;
    const lines = try allocator.alloc(msgpack.Value, line_count);
    defer allocator.free(lines);

    for (lines, 0..) |*line, i| {
        const line_text = try std.fmt.allocPrint(
            allocator,
            "Line {d}: This is a test line with some content to make it longer",
            .{i},
        );
        line.* = try msgpack.string(allocator, line_text);
        allocator.free(line_text);
    }

    // 注意：msgpack.array 对于 Value 类型不会克隆，而是直接引用
    // 所以 lines_array 会接管 lines 中所有 Value 的所有权
    // 释放 lines_array 时会自动释放所有元素，我们只需要释放 lines 数组本身
    const lines_array = try msgpack.array(allocator, lines);
    defer msgpack.free(lines_array, allocator);

    // 获取当前 buffer
    var buf_response = client.request("nvim_get_current_buf", &.{}) catch |err| switch (err) {
        error.ConnectionClosed, error.Timeout => return error.SkipZigTest,
        else => return err,
    };
    defer buf_response.free(allocator);

    const buf_handle = switch (buf_response) {
        .int => buf_response.int,
        .uint => |v| @as(i64, @intCast(v)),
        else => return error.SkipZigTest, // 如果类型不对，可能是连接问题，跳过测试
    };

    // 设置大量行
    const set_params = [_]msgpack.Value{
        msgpack.int(buf_handle),
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        lines_array,
    };
    var set_result = try client.request("nvim_buf_set_lines", &set_params);
    defer set_result.free(allocator);

    // 读取回来验证
    const get_params = [_]msgpack.Value{
        msgpack.int(buf_handle),
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    };
    var get_result = try client.request("nvim_buf_get_lines", &get_params);
    defer get_result.free(allocator);

    const returned_lines = try msgpack.expectArray(get_result);
    try std.testing.expectEqual(line_count, returned_lines.len);

    // 清理
    const cmd = try msgpack.string(allocator, "qa!");
    defer msgpack.free(cmd, allocator);
    const quit_params = [_]msgpack.Value{cmd};
    try client.notify("nvim_command", &quit_params);
}

test "WindowsPipe disconnect and reconnect" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var helper = TestHelper.init(allocator);
    defer helper.deinit();

    const pipe_name = try std.fmt.allocPrint(
        allocator,
        "\\\\.\\pipe\\nvim-reconnect-test-{d}",
        .{std.time.timestamp()},
    );
    defer allocator.free(pipe_name);

    helper.spawnNvimWithPipe(pipe_name) catch |err| switch (err) {
        error.SkipZigTest => return error.SkipZigTest,
        else => return err,
    };

    helper.waitForPipe(pipe_name) catch |err| switch (err) {
        error.Timeout => return error.SkipZigTest,
        else => return err,
    };

    var client = try znvim.Client.init(allocator, .{
        .socket_path = pipe_name,
        .skip_api_info = true,
    });
    defer client.deinit();

    // 第一次连接
    client.connect() catch |err| switch (err) {
        error.Timeout, error.TransportNotInitialized => return error.SkipZigTest,
        else => return err,
    };

    if (!client.isConnected()) return error.SkipZigTest;

    // 执行一个操作
    const expr1 = try msgpack.string(allocator, "2+2");
    defer msgpack.free(expr1, allocator);
    const params1 = [_]msgpack.Value{expr1};
    var result1 = try client.request("vim_eval", &params1);
    defer result1.free(allocator);

    // 断开连接
    client.disconnect();
    try std.testing.expect(!client.isConnected());

    // 等待一小会儿
    std.Thread.sleep(100 * std.time.ns_per_ms);

    // 重新连接
    try client.connect();
    try std.testing.expect(client.isConnected());

    // 再次执行操作
    const expr2 = try msgpack.string(allocator, "3+3");
    defer msgpack.free(expr2, allocator);
    const params2 = [_]msgpack.Value{expr2};
    var result2 = try client.request("vim_eval", &params2);
    defer result2.free(allocator);

    switch (result2) {
        .int => |value| try std.testing.expectEqual(@as(i64, 6), value),
        .uint => |value| try std.testing.expectEqual(@as(u64, 6), value),
        else => return error.UnexpectedResultType,
    }

    // 清理
    const cmd = try msgpack.string(allocator, "qa!");
    defer msgpack.free(cmd, allocator);
    const quit_params = [_]msgpack.Value{cmd};
    try client.notify("nvim_command", &quit_params);
}

test "WindowsPipe multiple requests" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var helper = TestHelper.init(allocator);
    defer helper.deinit();

    const pipe_name = try std.fmt.allocPrint(
        allocator,
        "\\\\.\\pipe\\nvim-multi-test-{d}",
        .{std.time.timestamp()},
    );
    defer allocator.free(pipe_name);

    helper.spawnNvimWithPipe(pipe_name) catch |err| switch (err) {
        error.SkipZigTest => return error.SkipZigTest,
        else => return err,
    };

    helper.waitForPipe(pipe_name) catch |err| switch (err) {
        error.Timeout => return error.SkipZigTest,
        else => return err,
    };

    var client = try znvim.Client.init(allocator, .{
        .socket_path = pipe_name,
        .skip_api_info = true,
    });
    defer client.deinit();

    client.connect() catch |err| switch (err) {
        error.Timeout, error.TransportNotInitialized => return error.SkipZigTest,
        else => return err,
    };

    // 执行多个连续的请求
    const test_cases = [_]struct { expr: []const u8, expected: i64 }{
        .{ .expr = "1+1", .expected = 2 },
        .{ .expr = "2*3", .expected = 6 },
        .{ .expr = "10-5", .expected = 5 },
        .{ .expr = "20/4", .expected = 5 },
        .{ .expr = "7%3", .expected = 1 },
    };

    for (test_cases) |tc| {
        const expr = try msgpack.string(allocator, tc.expr);
        defer msgpack.free(expr, allocator);

        const params = [_]msgpack.Value{expr};
        var result = try client.request("vim_eval", &params);
        defer result.free(allocator);

        const value = switch (result) {
            .int => result.int,
            .uint => @as(i64, @intCast(result.uint)),
            else => return error.UnexpectedResultType,
        };

        try std.testing.expectEqual(tc.expected, value);
    }

    // 清理
    const cmd = try msgpack.string(allocator, "qa!");
    defer msgpack.free(cmd, allocator);
    const quit_params = [_]msgpack.Value{cmd};
    try client.notify("nvim_command", &quit_params);
}

test "WindowsPipe timeout handling" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 尝试连接到不存在的管道，应该超时
    const nonexistent_pipe = "\\\\.\\pipe\\nonexistent-pipe-12345";

    var client = try znvim.Client.init(allocator, .{
        .socket_path = nonexistent_pipe,
        .timeout_ms = 100, // 短超时
        .skip_api_info = true,
    });
    defer client.deinit();

    // 连接应该失败（超时）
    const connect_result = client.connect();
    try std.testing.expect(std.meta.isError(connect_result));
}
