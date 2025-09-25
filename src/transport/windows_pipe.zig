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
