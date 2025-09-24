const std = @import("std");
const Transport = @import("transport.zig").Transport;

/// Transport backed by a blocking Unix domain socket stream.
pub const UnixSocket = struct {
    allocator: std.mem.Allocator,
    stream: ?std.net.Stream = null,

    pub fn init(allocator: std.mem.Allocator) UnixSocket {
        return .{ .allocator = allocator, .stream = null };
    }

    pub fn deinit(self: *UnixSocket) void {
        if (self.stream) |stream| {
            stream.close();
        }
        self.stream = null;
    }

    pub fn asTransport(self: *UnixSocket) Transport {
        return Transport.init(self, &vtable);
    }

    fn connect(tr: *Transport, address: []const u8) anyerror!void {
        const self = tr.downcast(UnixSocket);
        if (self.stream) |stream| {
            stream.close();
        }
        self.stream = try std.net.connectUnixSocket(address);
    }

    fn disconnect(tr: *Transport) void {
        const self = tr.downcast(UnixSocket);
        if (self.stream) |stream| {
            stream.close();
        }
        self.stream = null;
    }

    /// Maps system-level read failures to the higher-level transport error set.
    fn read(tr: *Transport, buffer: []u8) Transport.ReadError!usize {
        const self = tr.downcast(UnixSocket);
        const stream = self.stream orelse return Transport.ReadError.ConnectionClosed;

        return stream.read(buffer) catch |err| switch (err) {
            error.WouldBlock => Transport.ReadError.Timeout,
            error.ConnectionResetByPeer, error.SocketNotConnected => Transport.ReadError.ConnectionClosed,
            else => Transport.ReadError.UnexpectedError,
        };
    }

    /// Writes a full message, normalizing OS errors to the transport error set.
    fn write(tr: *Transport, data: []const u8) Transport.WriteError!void {
        const self = tr.downcast(UnixSocket);
        const stream = self.stream orelse return Transport.WriteError.ConnectionClosed;

        stream.writeAll(data) catch |err| switch (err) {
            error.BrokenPipe => return Transport.WriteError.BrokenPipe,
            error.ConnectionResetByPeer, error.SocketNotConnected => return Transport.WriteError.ConnectionClosed,
            else => return Transport.WriteError.UnexpectedError,
        };
    }

    fn isConnected(tr: *Transport) bool {
        const self = tr.downcastConst(UnixSocket);
        return self.stream != null;
    }

    pub const vtable = Transport.VTable{
        .connect = connect,
        .disconnect = disconnect,
        .read = read,
        .write = write,
        .is_connected = isConnected,
    };
};
