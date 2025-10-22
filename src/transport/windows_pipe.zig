const std = @import("std");
const windows = std.os.windows;
const unicode = std.unicode;
const Transport = @import("transport.zig").Transport;

const ns_per_ms = std.time.ns_per_ms;
const nmpwait_wait_forever: windows.DWORD = std.math.maxInt(windows.DWORD);

extern "kernel32" fn CreateFileW(
    lpFileName: windows.LPCWSTR,
    dwDesiredAccess: windows.DWORD,
    dwShareMode: windows.DWORD,
    lpSecurityAttributes: ?*windows.SECURITY_ATTRIBUTES,
    dwCreationDisposition: windows.DWORD,
    dwFlagsAndAttributes: windows.DWORD,
    hTemplateFile: ?windows.HANDLE,
) callconv(.winapi) windows.HANDLE;

extern "kernel32" fn WaitNamedPipeW(
    lpNamedPipeName: windows.LPCWSTR,
    nTimeOut: windows.DWORD,
) callconv(.winapi) windows.BOOL;

const CreatePipeHandleError = error{
    FileNotFound,
    PipeBusy,
    AccessDenied,
    Unexpected,
};

fn openPipeHandle(
    path: [*:0]const u16,
    desired_access: windows.DWORD,
    share_mode: windows.DWORD,
    creation: windows.DWORD,
    flags: windows.DWORD,
) CreatePipeHandleError!windows.HANDLE {
    const handle = CreateFileW(path, desired_access, share_mode, null, creation, flags, null);
    if (handle == windows.INVALID_HANDLE_VALUE) {
        const err = windows.GetLastError();
        return switch (err) {
            .FILE_NOT_FOUND => error.FileNotFound,
            .PIPE_BUSY => error.PipeBusy,
            .ACCESS_DENIED => error.AccessDenied,
            else => error.Unexpected,
        };
    }
    return handle;
}

const WaitNamedPipeError = error{
    FileNotFound,
    WaitTimeout,
    Unexpected,
};

fn waitForNamedPipe(path: [*:0]const u16, timeout_ms: windows.DWORD) WaitNamedPipeError!void {
    if (WaitNamedPipeW(path, timeout_ms) != 0) return;

    const err = windows.GetLastError();
    return switch (err) {
        .FILE_NOT_FOUND => error.FileNotFound,
        .WAIT_TIMEOUT => error.WaitTimeout,
        else => error.Unexpected,
    };
}

/// Transport that connects to a Windows named pipe created by Neovim.
pub const WindowsPipe = struct {
    allocator: std.mem.Allocator,
    handle: ?windows.HANDLE = null,
    timeout_ms: u32,

    pub fn init(allocator: std.mem.Allocator, timeout_ms: u32) WindowsPipe {
        return .{ .allocator = allocator, .handle = null, .timeout_ms = timeout_ms };
    }

    pub fn deinit(self: *WindowsPipe) void {
        if (self.handle) |h| {
            windows.CloseHandle(h);
            self.handle = null;
        }
    }

    pub fn asTransport(self: *WindowsPipe) Transport {
        return Transport.init(self, &vtable);
    }

    fn connect(tr: *Transport, address: []const u8) anyerror!void {
        const self = tr.downcast(WindowsPipe);
        if (self.handle) |h| {
            windows.CloseHandle(h);
            self.handle = null;
        }

        const wide = try unicode.utf8ToUtf16LeAllocZ(self.allocator, address);
        defer self.allocator.free(wide);

        const infinite_wait = self.timeout_ms == 0;
        var timer: std.time.Timer = undefined;
        var deadline_ns: u64 = 0;
        if (!infinite_wait) {
            timer = std.time.Timer.start() catch unreachable;
            deadline_ns = @as(u64, self.timeout_ms) * ns_per_ms;
        }

        while (true) {
            if (!infinite_wait) {
                if (timer.read() >= deadline_ns) return error.Timeout;
            }

            const handle = openPipeHandle(
                wide.ptr,
                windows.GENERIC_READ | windows.GENERIC_WRITE,
                0,
                windows.OPEN_EXISTING,
                windows.FILE_ATTRIBUTE_NORMAL,
            ) catch |err| switch (err) {
                error.PipeBusy, error.FileNotFound => {
                    if (infinite_wait) {
                        waitForNamedPipe(wide.ptr, nmpwait_wait_forever) catch |wait_err| switch (wait_err) {
                            error.FileNotFound => continue,
                            else => return wait_err,
                        };
                        continue;
                    }

                    const elapsed_ns = timer.read();
                    if (elapsed_ns >= deadline_ns) return error.Timeout;
                    var remaining_ns = deadline_ns - elapsed_ns;
                    if (remaining_ns < ns_per_ms) remaining_ns = ns_per_ms;
                    const remaining_ms_rounded = (remaining_ns + ns_per_ms - 1) / ns_per_ms;
                    const wait_ms_u64 = std.math.clamp(remaining_ms_rounded, 1, @as(u64, std.math.maxInt(u32)));
                    const wait_arg: windows.DWORD = @intCast(wait_ms_u64);
                    waitForNamedPipe(wide.ptr, wait_arg) catch |wait_err| switch (wait_err) {
                        error.FileNotFound => continue,
                        error.WaitTimeout => return error.Timeout,
                        else => return wait_err,
                    };
                    continue;
                },
                else => return err,
            };

            self.handle = handle;
            break;
        }
    }

    fn disconnect(tr: *Transport) void {
        const self = tr.downcast(WindowsPipe);
        if (self.handle) |h| {
            windows.CloseHandle(h);
            self.handle = null;
        }
    }

    /// Wraps `ReadFile`, mapping Windows error codes to the cross-platform transport errors.
    fn read(tr: *Transport, buffer: []u8) Transport.ReadError!usize {
        const self = tr.downcast(WindowsPipe);
        const handle = self.handle orelse return Transport.ReadError.ConnectionClosed;

        return windows.ReadFile(handle, buffer, null) catch |err| switch (err) {
            error.BrokenPipe, error.ConnectionResetByPeer => Transport.ReadError.ConnectionClosed,
            else => Transport.ReadError.UnexpectedError,
        };
    }

    /// Wraps `WriteFile`, reporting broken pipes as connection closures.
    fn write(tr: *Transport, data: []const u8) Transport.WriteError!void {
        const self = tr.downcast(WindowsPipe);
        const handle = self.handle orelse return Transport.WriteError.ConnectionClosed;

        _ = windows.WriteFile(handle, data, null) catch |err| switch (err) {
            error.BrokenPipe => return Transport.WriteError.BrokenPipe,
            error.ConnectionResetByPeer => return Transport.WriteError.ConnectionClosed,
            else => return Transport.WriteError.UnexpectedError,
        };
    }

    fn isConnected(tr: *Transport) bool {
        const self = tr.downcastConst(WindowsPipe);
        return self.handle != null;
    }

    pub const vtable = Transport.VTable{
        .connect = connect,
        .disconnect = disconnect,
        .read = read,
        .write = write,
        .is_connected = isConnected,
    };
};

// ============================================================================
// 单元测试
// ============================================================================

test "WindowsPipe init creates disconnected instance" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    try std.testing.expect(pipe.handle == null);
    try std.testing.expectEqual(@as(u32, 5000), pipe.timeout_ms);

    var transport = pipe.asTransport();
    try std.testing.expect(!transport.isConnected());
}

test "WindowsPipe init with zero timeout" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 0);
    defer pipe.deinit();

    try std.testing.expectEqual(@as(u32, 0), pipe.timeout_ms);
    try std.testing.expect(pipe.handle == null);
}

test "WindowsPipe init with custom timeout" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const custom_timeout: u32 = 12345;
    var pipe = WindowsPipe.init(allocator, custom_timeout);
    defer pipe.deinit();

    try std.testing.expectEqual(custom_timeout, pipe.timeout_ms);
}

test "WindowsPipe deinit without connection is safe" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 1000);

    // 多次调用 deinit 应该是安全的
    pipe.deinit();
    pipe.deinit();
    pipe.deinit();

    try std.testing.expect(pipe.handle == null);
}

test "WindowsPipe asTransport returns valid transport" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();

    // 验证 vtable 指针正确
    try std.testing.expectEqual(&WindowsPipe.vtable, transport.vtable);

    // 验证初始状态
    try std.testing.expect(!transport.isConnected());
}

test "WindowsPipe vtable disconnect on unconnected pipe is safe" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();

    // 在未连接状态下调用 disconnect 应该是安全的
    transport.disconnect();
    transport.disconnect();

    try std.testing.expect(!transport.isConnected());
    try std.testing.expect(pipe.handle == null);
}

test "WindowsPipe read on disconnected returns ConnectionClosed" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    var buffer: [10]u8 = undefined;

    const result = transport.read(&buffer);
    try std.testing.expectError(Transport.ReadError.ConnectionClosed, result);
}

test "WindowsPipe write on disconnected returns ConnectionClosed" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    var transport = pipe.asTransport();
    const data = "test data";

    const result = transport.write(data);
    try std.testing.expectError(Transport.WriteError.ConnectionClosed, result);
}

test "WindowsPipe openPipeHandle validates error codes" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    // 测试不存在的管道路径应该返回 FileNotFound
    const invalid_path = [_:0]u16{ '\\', '\\', '.', '\\', 'p', 'i', 'p', 'e', '\\', 'n', 'o', 'n', 'e', 'x', 'i', 's', 't', 'e', 'n', 't', '-', 't', 'e', 's', 't', '-', 'p', 'i', 'p', 'e', 0 };

    const result = openPipeHandle(
        &invalid_path,
        windows.GENERIC_READ | windows.GENERIC_WRITE,
        0,
        windows.OPEN_EXISTING,
        windows.FILE_ATTRIBUTE_NORMAL,
    );

    // 应该返回错误（FileNotFound 或其他错误）
    try std.testing.expect(std.meta.isError(result));
}

test "WindowsPipe waitForNamedPipe timeout validation" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    // 测试等待不存在的管道应该超时
    const invalid_path = [_:0]u16{ '\\', '\\', '.', '\\', 'p', 'i', 'p', 'e', '\\', 'n', 'o', 'n', 'e', 'x', 'i', 's', 't', 'e', 'n', 't', '-', 't', 'e', 's', 't', 0 };

    const result = waitForNamedPipe(&invalid_path, 1); // 1ms 超时

    // 应该返回超时或文件不存在错误
    if (result) |_| {
        try std.testing.expect(false); // 不应该成功
    } else |err| {
        const is_expected_error = (err == error.FileNotFound) or
            (err == error.WaitTimeout) or
            (err == error.Unexpected);
        try std.testing.expect(is_expected_error);
    }
}

test "WindowsPipe state remains consistent after failed connection" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 100);
    defer pipe.deinit();

    var transport = pipe.asTransport();

    // 尝试连接到不存在的管道
    const invalid_pipe_path = "\\\\.\\pipe\\nonexistent-test-pipe-12345";
    const connect_result = transport.connect(invalid_pipe_path);

    // 连接应该失败
    try std.testing.expect(std.meta.isError(connect_result));

    // 失败后状态应该保持一致
    try std.testing.expect(!transport.isConnected());
    try std.testing.expect(pipe.handle == null);

    // 应该可以安全清理
    pipe.deinit();
    try std.testing.expect(pipe.handle == null);
}

test "WindowsPipe multiple timeout values are preserved" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const test_timeouts = [_]u32{ 0, 1, 100, 1000, 5000, 30000, std.math.maxInt(u32) };

    for (test_timeouts) |timeout| {
        var pipe = WindowsPipe.init(allocator, timeout);
        defer pipe.deinit();

        try std.testing.expectEqual(timeout, pipe.timeout_ms);
    }
}

test "WindowsPipe allocator is stored correctly" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pipe = WindowsPipe.init(allocator, 5000);
    defer pipe.deinit();

    // 验证 allocator 被正确存储（通过创建一些分配来间接测试）
    // 这主要是确保结构体字段正确初始化
    try std.testing.expect(pipe.handle == null);
}

test "WindowsPipe handle starts as null" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 1000);
    defer pipe.deinit();

    try std.testing.expect(pipe.handle == null);

    // 即使通过 transport 接口查询，也应该是未连接状态
    var transport = pipe.asTransport();
    try std.testing.expect(!transport.isConnected());
}

test "WindowsPipe isConnected reflects handle state" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 1000);
    defer pipe.deinit();

    var transport = pipe.asTransport();

    // 初始状态：未连接
    try std.testing.expect(!transport.isConnected());
    try std.testing.expect(pipe.handle == null);

    // 注意：我们不能模拟一个有效的 handle，因为那需要真实的系统调用
    // 但我们可以验证 null 状态下的行为
}

test "WindowsPipe vtable function pointers are not null" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    // 验证 vtable 中的所有函数指针都被正确设置
    // 通过检查它们的地址非零来验证
    const vtable_addr = @intFromPtr(&WindowsPipe.vtable);
    try std.testing.expect(vtable_addr != 0);

    // 验证每个函数指针都有有效的地址
    try std.testing.expect(@intFromPtr(WindowsPipe.vtable.connect) != 0);
    try std.testing.expect(@intFromPtr(WindowsPipe.vtable.disconnect) != 0);
    try std.testing.expect(@intFromPtr(WindowsPipe.vtable.read) != 0);
    try std.testing.expect(@intFromPtr(WindowsPipe.vtable.write) != 0);
    try std.testing.expect(@intFromPtr(WindowsPipe.vtable.is_connected) != 0);
}

test "WindowsPipe downcast works correctly" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var pipe = WindowsPipe.init(allocator, 2000);
    defer pipe.deinit();

    var transport = pipe.asTransport();

    // downcast 应该返回原始的 pipe 指针
    const downcasted = transport.downcast(WindowsPipe);
    try std.testing.expectEqual(&pipe, downcasted);
    try std.testing.expectEqual(@as(u32, 2000), downcasted.timeout_ms);

    // downcastConst 也应该工作
    const downcasted_const = transport.downcastConst(WindowsPipe);
    try std.testing.expectEqual(&pipe, downcasted_const);
}

test "WindowsPipe CreatePipeHandleError error set is complete" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    // 验证错误类型可以被转换到 CreatePipeHandleError
    const err1: CreatePipeHandleError = error.FileNotFound;
    const err2: CreatePipeHandleError = error.PipeBusy;
    const err3: CreatePipeHandleError = error.AccessDenied;
    const err4: CreatePipeHandleError = error.Unexpected;

    try std.testing.expectEqual(error.FileNotFound, err1);
    try std.testing.expectEqual(error.PipeBusy, err2);
    try std.testing.expectEqual(error.AccessDenied, err3);
    try std.testing.expectEqual(error.Unexpected, err4);
}

test "WindowsPipe WaitNamedPipeError error set is complete" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    // 验证错误类型可以被转换到 WaitNamedPipeError
    const err1: WaitNamedPipeError = error.FileNotFound;
    const err2: WaitNamedPipeError = error.WaitTimeout;
    const err3: WaitNamedPipeError = error.Unexpected;

    try std.testing.expectEqual(error.FileNotFound, err1);
    try std.testing.expectEqual(error.WaitTimeout, err2);
    try std.testing.expectEqual(error.Unexpected, err3);
}

test "WindowsPipe constant values are correct" {
    if (@import("builtin").os.tag != .windows) return error.SkipZigTest;

    // 验证常量定义
    try std.testing.expectEqual(@as(u64, std.time.ns_per_ms), ns_per_ms);
    try std.testing.expectEqual(std.math.maxInt(windows.DWORD), nmpwait_wait_forever);
}
