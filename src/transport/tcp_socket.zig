const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const ws2 = windows.ws2_32;
const Transport = @import("transport.zig").Transport;

var winsock_ready = std.atomic.Value(bool).init(false);
var winsock_mutex = std.Thread.Mutex{};

/// Transport backed by a TCP socket connected to a remote Neovim instance.
pub const TcpSocket = struct {
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    stream: ?std.net.Stream = null,

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !TcpSocket {
        return .{
            .allocator = allocator,
            .host = try allocator.dupe(u8, host),
            .port = port,
            .stream = null,
        };
    }

    pub fn deinit(self: *TcpSocket) void {
        if (self.stream) |s| {
            s.close();
            self.stream = null;
        }
        self.allocator.free(self.host);
    }

    pub fn asTransport(self: *TcpSocket) Transport {
        return Transport.init(self, &vtable);
    }

    fn connect(tr: *Transport, _: []const u8) anyerror!void {
        const self = tr.downcast(TcpSocket);
        if (self.stream) |s| {
            s.close();
            self.stream = null;
        }
        try ensureWinsock();
        self.stream = try std.net.tcpConnectToHost(self.allocator, self.host, self.port);
    }

    fn disconnect(tr: *Transport) void {
        const self = tr.downcast(TcpSocket);
        if (self.stream) |s| s.close();
        self.stream = null;
    }

    /// Normalizes socket read errors into the shared transport error contract.
    fn read(tr: *Transport, buffer: []u8) Transport.ReadError!usize {
        const self = tr.downcast(TcpSocket);
        const stream = self.stream orelse return Transport.ReadError.ConnectionClosed;
        return stream.read(buffer) catch |err| switch (err) {
            error.WouldBlock => Transport.ReadError.Timeout,
            error.ConnectionResetByPeer,
            error.SocketNotConnected,
            => Transport.ReadError.ConnectionClosed,
            else => Transport.ReadError.UnexpectedError,
        };
    }

    /// Writes the entire buffer and maps OS errors to transport error codes.
    fn write(tr: *Transport, data: []const u8) Transport.WriteError!void {
        const self = tr.downcast(TcpSocket);
        const stream = self.stream orelse return Transport.WriteError.ConnectionClosed;
        stream.writeAll(data) catch |err| switch (err) {
            error.BrokenPipe => return Transport.WriteError.BrokenPipe,
            error.ConnectionResetByPeer,
            error.SocketNotConnected,
            => return Transport.WriteError.ConnectionClosed,
            else => return Transport.WriteError.UnexpectedError,
        };
    }

    fn isConnected(tr: *Transport) bool {
        const self = tr.downcastConst(TcpSocket);
        return self.stream != null;
    }

    fn ensureWinsock() !void {
        if (builtin.os.tag != .windows)
            return;

        if (winsock_ready.load(.acquire))
            return;

        winsock_mutex.lock();
        defer winsock_mutex.unlock();

        if (!winsock_ready.load(.monotonic)) {
            windows.callWSAStartup() catch |err| switch (err) {
                error.ProcessFdQuotaExceeded => return error.SystemResources,
                error.Unexpected => return error.Unexpected,
                error.SystemResources => return error.SystemResources,
            };
            winsock_ready.store(true, .release);
        }
    }

    pub const vtable = Transport.VTable{
        .connect = connect,
        .disconnect = disconnect,
        .read = read,
        .write = write,
        .is_connected = isConnected,
    };
};
