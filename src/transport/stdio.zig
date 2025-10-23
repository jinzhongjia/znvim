const std = @import("std");
const Transport = @import("transport.zig").Transport;

/// Transport that uses the current process stdin/stdout handles for communication.
pub const Stdio = struct {
    stdin_file: std.fs.File,
    stdout_file: std.fs.File,
    owns_handles: bool = false,

    pub fn init() Stdio {
        return .{
            .stdin_file = std.fs.File.stdin(),
            .stdout_file = std.fs.File.stdout(),
            .owns_handles = false,
        };
    }

    /// Allows tests to inject alternative file handles and control ownership.
    pub fn initWithFiles(reader: std.fs.File, writer: std.fs.File, owns: bool) Stdio {
        return .{ .stdin_file = reader, .stdout_file = writer, .owns_handles = owns };
    }

    pub fn deinit(self: *Stdio) void {
        if (self.owns_handles) {
            self.stdin_file.close();
            self.stdout_file.close();
        }
    }

    pub fn asTransport(self: *Stdio) Transport {
        return Transport.init(self, &vtable);
    }

    fn connect(tr: *Transport, _: []const u8) anyerror!void {
        _ = tr;
    }

    fn disconnect(tr: *Transport) void {
        _ = tr;
    }

    fn read(tr: *Transport, buffer: []u8) Transport.ReadError!usize {
        const self = tr.downcast(Stdio);
        return self.stdin_file.read(buffer) catch |err| switch (err) {
            error.WouldBlock, error.ConnectionTimedOut => Transport.ReadError.Timeout,
            error.BrokenPipe, error.ConnectionResetByPeer, error.SocketNotConnected, error.NotOpenForReading, error.OperationAborted, error.Canceled, error.ProcessNotFound => Transport.ReadError.ConnectionClosed,
            else => Transport.ReadError.UnexpectedError,
        };
    }

    fn write(tr: *Transport, data: []const u8) Transport.WriteError!void {
        const self = tr.downcast(Stdio);
        self.stdout_file.writeAll(data) catch |err| switch (err) {
            error.BrokenPipe => return Transport.WriteError.BrokenPipe,
            error.ConnectionResetByPeer, error.NotOpenForWriting, error.OperationAborted, error.ProcessNotFound => return Transport.WriteError.ConnectionClosed,
            else => return Transport.WriteError.UnexpectedError,
        };
    }

    fn isConnected(tr: *Transport) bool {
        _ = tr;
        return true;
    }

    pub const vtable = Transport.VTable{
        .connect = connect,
        .disconnect = disconnect,
        .read = read,
        .write = write,
        .is_connected = isConnected,
    };
};
