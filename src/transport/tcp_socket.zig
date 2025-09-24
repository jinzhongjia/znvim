const std = @import("std");
const Transport = @import("transport.zig").Transport;

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
        self.stream = try std.net.tcpConnectToHost(self.allocator, self.host, self.port);
    }

    fn disconnect(tr: *Transport) void {
        const self = tr.downcast(TcpSocket);
        if (self.stream) |s| s.close();
        self.stream = null;
    }

    fn read(tr: *Transport, buffer: []u8) Transport.ReadError!usize {
        const self = tr.downcast(TcpSocket);
        const stream = self.stream orelse return Transport.ReadError.ConnectionClosed;
        return stream.read(buffer) catch |err| switch (err) {
            error.WouldBlock => Transport.ReadError.Timeout,
            error.ConnectionResetByPeer, error.SocketNotConnected => Transport.ReadError.ConnectionClosed,
            else => Transport.ReadError.UnexpectedError,
        };
    }

    fn write(tr: *Transport, data: []const u8) Transport.WriteError!void {
        const self = tr.downcast(TcpSocket);
        const stream = self.stream orelse return Transport.WriteError.ConnectionClosed;
        stream.writeAll(data) catch |err| switch (err) {
            error.BrokenPipe => return Transport.WriteError.BrokenPipe,
            error.ConnectionResetByPeer, error.SocketNotConnected => return Transport.WriteError.ConnectionClosed,
            else => return Transport.WriteError.UnexpectedError,
        };
    }

    fn isConnected(tr: *Transport) bool {
        const self = tr.downcastConst(TcpSocket);
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
