const std = @import("std");
const windows = std.os.windows;
const unicode = std.unicode;
const Transport = @import("transport.zig").Transport;

const ns_per_ms = std.time.ns_per_ms;

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

            const handle = windows.CreateFileW(
                wide.ptr,
                windows.GENERIC_READ | windows.GENERIC_WRITE,
                0,
                null,
                windows.OPEN_EXISTING,
                windows.FILE_ATTRIBUTE_NORMAL,
                null,
            ) catch |err| switch (err) {
                error.PipeBusy, error.FileNotFound => {
                    if (infinite_wait) {
                        _ = windows.WaitNamedPipeW(wide.ptr, windows.NMPWAIT_WAIT_FOREVER) catch |wait_err| switch (wait_err) {
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
                    _ = windows.WaitNamedPipeW(wide.ptr, wait_arg) catch |wait_err| switch (wait_err) {
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
            error.BrokenPipe => Transport.ReadError.ConnectionClosed,
            error.HandleEOF => Transport.ReadError.ConnectionClosed,
            else => Transport.ReadError.UnexpectedError,
        };
    }

    /// Wraps `WriteFile`, reporting broken pipes as connection closures.
    fn write(tr: *Transport, data: []const u8) Transport.WriteError!void {
        const self = tr.downcast(WindowsPipe);
        const handle = self.handle orelse return Transport.WriteError.ConnectionClosed;

        _ = windows.WriteFile(handle, data, null) catch |err| switch (err) {
            error.BrokenPipe => return Transport.WriteError.BrokenPipe,
            error.HandleEOF => return Transport.WriteError.ConnectionClosed,
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
