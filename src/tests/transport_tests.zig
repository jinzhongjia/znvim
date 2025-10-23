const std = @import("std");
const builtin = @import("builtin");
const znvim = @import("../root.zig");
const msgpack = @import("msgpack");
const posix = std.posix;
const windows = std.os.windows;

// 编译时选项控制是否输出调试信息
const debug_output = false;

/// 测试上下文，管理测试所需的资源
const TestContext = struct {
    allocator: std.mem.Allocator,
    client: ?*znvim.Client = null,
    nvim_process: ?std.process.Child = null,

    const Self = @This();

    /// 初始化测试上下文
    fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    /// 清理资源
    fn deinit(self: *Self) void {
        if (self.client) |client| {
            client.disconnect();
            client.deinit();
        }
        if (self.nvim_process) |*child| {
            NvimProcess.terminate(child);
        }
    }

    /// 执行简单的求值测试
    fn testEval(self: *Self) !void {
        if (debug_output) std.debug.print("Testing eval...\n", .{});

        const client = self.client orelse return error.NoClient;
        var expr = try msgpack.Payload.strToPayload("1+1", self.allocator);
        defer expr.free(self.allocator);

        const params = [_]msgpack.Payload{expr};
        var result = try client.request("vim_eval", &params);
        defer result.free(self.allocator);

        switch (result) {
            .int => |value| try std.testing.expectEqual(@as(i64, 2), value),
            .uint => |value| try std.testing.expectEqual(@as(u64, 2), value),
            else => return error.UnexpectedResultType,
        }
    }

    /// 发送退出命令
    fn sendQuitCommand(self: *Self) !void {
        if (debug_output) std.debug.print("Sending quit command...\n", .{});

        const client = self.client orelse return error.NoClient;
        var cmd = try msgpack.Payload.strToPayload("qa!", self.allocator);
        defer cmd.free(self.allocator);

        const params = [_]msgpack.Payload{cmd};
        try client.notify("nvim_command", &params);
    }
};

/// Nvim 进程管理
const NvimProcess = struct {
    const SpawnError = error{
        NvimNotFound,
        SpawnFailed,
    };

    /// 启动监听模式的 Nvim 进程
    fn spawnListen(allocator: std.mem.Allocator, address: []const u8) !std.process.Child {
        var child = std.process.Child.init(&.{ "nvim", "--headless", "--clean", "--listen", address }, allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Inherit;

        child.spawn() catch |err| switch (err) {
            error.FileNotFound => return error.SkipZigTest,
            else => return err,
        };

        return child;
    }

    /// 终止 Nvim 进程
    fn terminate(child: *std.process.Child) void {
        _ = waitForExit(child, 10 * std.time.ns_per_s);
    }

    /// 等待进程退出（带超时）
    fn waitForExit(child: *std.process.Child, timeout_ns: u64) bool {
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
                    if (builtin.os.tag == .windows) {
                        _ = windows.TerminateProcess(child.id, 1) catch {};
                    } else {
                        _ = posix.kill(child.id, posix.SIG.TERM) catch {};
                    }
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

/// 连接等待器
const ConnectionWaiter = struct {
    const max_attempts: usize = 200;
    const retry_delay_ms: u64 = 10;

    /// 等待 Unix 套接字可用
    fn waitForUnixSocket(path: []const u8) !void {
        var attempt: usize = 0;
        while (attempt < max_attempts) : (attempt += 1) {
            if (std.fs.cwd().access(path, .{})) {
                return;
            } else |_| {}
            std.Thread.sleep(retry_delay_ms * std.time.ns_per_ms);
        }
        return error.Timeout;
    }

    /// 等待 TCP 端口可用
    fn waitForTcp(host: []const u8, port: u16, allocator: std.mem.Allocator) !void {
        var attempt: usize = 0;
        while (attempt < max_attempts) : (attempt += 1) {
            if (std.net.tcpConnectToHost(allocator, host, port)) |stream| {
                stream.close();
                return;
            } else |_| {}
            std.Thread.sleep(retry_delay_ms * std.time.ns_per_ms);
        }
        return error.Timeout;
    }

    /// 等待 Windows 命名管道可用
    fn waitForWindowsPipe(allocator: std.mem.Allocator, pipe_path: []const u8) !void {
        if (builtin.os.tag != .windows) return error.SkipZigTest;

        const unicode = std.unicode;
        var attempt: usize = 0;

        while (attempt < max_attempts) : (attempt += 1) {
            // 尝试转换路径为 UTF16
            const wide_path = unicode.utf8ToUtf16LeAllocZ(allocator, pipe_path) catch {
                std.Thread.sleep(retry_delay_ms * std.time.ns_per_ms);
                attempt += 1;
                continue;
            };
            defer allocator.free(wide_path);

            // 尝试打开管道（只是测试是否存在）
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
};

/// Unix 套接字传输测试
const UnixSocketTransport = struct {
    fn runTest() !void {
        if (builtin.os.tag == .windows) return error.SkipZigTest;

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var ctx = TestContext.init(allocator);
        defer ctx.deinit();

        // 生成唯一的套接字路径
        const socket_path = try std.fmt.allocPrint(allocator, "/tmp/znvim-test-{d}.sock", .{std.time.timestamp()});
        defer allocator.free(socket_path);

        // 启动 Nvim 进程
        ctx.nvim_process = try NvimProcess.spawnListen(allocator, socket_path);

        // 等待套接字就绪
        ConnectionWaiter.waitForUnixSocket(socket_path) catch |err| switch (err) {
            error.Timeout => return error.SkipZigTest,
            else => return err,
        };

        // 创建并连接客户端
        var client = try znvim.Client.init(allocator, .{
            .socket_path = socket_path,
            .skip_api_info = true,
        });
        ctx.client = &client;

        try client.connect();

        // 执行测试
        try ctx.testEval();
        try ctx.sendQuitCommand();
    }
};

/// TCP 套接字传输测试
const TcpSocketTransport = struct {
    fn runTest() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var ctx = TestContext.init(allocator);
        defer ctx.deinit();

        // Windows 需要初始化 Winsock
        if (builtin.os.tag == .windows) {
            windows.callWSAStartup() catch |err| switch (err) {
                error.ProcessFdQuotaExceeded => return error.SkipZigTest,
                error.Unexpected => return err,
                error.SystemResources => return error.SkipZigTest,
            };
        }

        // 生成随机端口
        const host = "127.0.0.1";
        const port: u16 = 22000 + (std.crypto.random.int(u16) % 1000);

        const address_buf = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ host, port });
        defer allocator.free(address_buf);

        if (debug_output) std.debug.print("Spawning nvim with address: {s}\n", .{address_buf});
        ctx.nvim_process = try NvimProcess.spawnListen(allocator, address_buf);

        if (builtin.os.tag == .windows and debug_output) std.debug.print("Waiting for TCP port {s}:{d}\n", .{ host, port });
        ConnectionWaiter.waitForTcp(host, port, allocator) catch |err| switch (err) {
            error.Timeout => return error.SkipZigTest,
            else => return err,
        };

        if (debug_output) std.debug.print("Connecting RPC client to {s}:{d}\n", .{ host, port });
        var client = try znvim.Client.init(allocator, .{
            .tcp_address = host,
            .tcp_port = port,
            .skip_api_info = true,
        });
        ctx.client = &client;

        try client.connect();

        if (debug_output) std.debug.print("testEval via TCP transport\n", .{});
        try ctx.testEval();
        if (debug_output) std.debug.print("Sending quit via TCP transport\n", .{});
        try ctx.sendQuitCommand();
    }
};

/// 子进程传输测试
const ChildProcessTransport = struct {
    fn runTest() !void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var ctx = TestContext.init(allocator);
        defer ctx.deinit();

        // 创建并连接客户端（自动生成子进程）
        var client = try znvim.Client.init(allocator, .{
            .spawn_process = true,
            .skip_api_info = true,
        });
        ctx.client = &client;

        try client.connect();

        // 执行测试
        try ctx.testEval();
        try ctx.sendQuitCommand();
    }
};

/// Windows 命名管道传输测试
const WindowsPipeTransport = struct {
    fn runTest() !void {
        if (builtin.os.tag != .windows) return error.SkipZigTest;

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        defer _ = gpa.deinit();
        const allocator = gpa.allocator();

        var ctx = TestContext.init(allocator);
        defer ctx.deinit();

        // 生成唯一的管道名称
        const timestamp = std.time.timestamp();
        const pipe_name = try std.fmt.allocPrint(
            allocator,
            "\\\\.\\pipe\\nvim-test-{d}",
            .{timestamp},
        );
        defer allocator.free(pipe_name);

        if (debug_output) std.debug.print("Spawning nvim with pipe: {s}\n", .{pipe_name});

        // 启动 Nvim 进程监听命名管道
        ctx.nvim_process = try NvimProcess.spawnListen(allocator, pipe_name);

        // 等待命名管道就绪
        if (debug_output) std.debug.print("Waiting for pipe {s}\n", .{pipe_name});
        ConnectionWaiter.waitForWindowsPipe(allocator, pipe_name) catch |err| switch (err) {
            error.Timeout => {
                if (debug_output) std.debug.print("Pipe wait timeout, skipping test\n", .{});
                return error.SkipZigTest;
            },
            else => return err,
        };

        // 创建并连接客户端
        if (debug_output) std.debug.print("Connecting RPC client to {s}\n", .{pipe_name});
        var client = try znvim.Client.init(allocator, .{
            .socket_path = pipe_name,
            .skip_api_info = true,
        });
        ctx.client = &client;

        try client.connect();

        // 执行测试
        if (debug_output) std.debug.print("testEval via WindowsPipe transport\n", .{});
        try ctx.testEval();

        if (debug_output) std.debug.print("Sending quit via WindowsPipe transport\n", .{});
        try ctx.sendQuitCommand();
    }
};

test "Unix socket transport" {
    try UnixSocketTransport.runTest();
}

test "TCP socket transport" {
    try TcpSocketTransport.runTest();
}

test "Windows named pipe transport" {
    try WindowsPipeTransport.runTest();
}

test "Child process transport" {
    try ChildProcessTransport.runTest();
}
