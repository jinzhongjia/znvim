const std = @import("std");
const windows = std.os.windows;
const unicode = std.unicode;
const Transport = @import("transport.zig").Transport;

/// Transport that connects to a Windows named pipe created by Neovim.
pub const WindowsPipe = struct {
    allocator: std.mem.Allocator,
    handle: ?windows.HANDLE = null,

    pub fn init(allocator: std.mem.Allocator) WindowsPipe {
        return .{ .allocator = allocator, .handle = null };
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

        while (true) {
            const handle = windows.CreateFileW(
                wide.ptr,
                windows.GENERIC_READ | windows.GENERIC_WRITE,
                0,
                null,
                windows.OPEN_EXISTING,
                windows.FILE_ATTRIBUTE_NORMAL,
                null,
            ) catch |err| switch (err) {
                error.PipeBusy => {
                    _ = windows.WaitNamedPipeW(wide.ptr, windows.NMPWAIT_WAIT_FOREVER) catch |wait_err| switch (wait_err) {
                        error.FileNotFound => continue,
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
            error.BrokenPipe => return Transport.WriteError.ConnectionClosed,
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
