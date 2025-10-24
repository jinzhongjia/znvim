const std = @import("std");
const builtin = @import("builtin");
const connection = @import("../connection.zig");
const transport_mod = @import("../transport/mod.zig");
const Transport = transport_mod.Transport;

// Ensures the thin wrapper properly dispatches into the backing implementation via the vtable.
test "transport wrapper dispatches to concrete implementation" {
    const DummyTransport = struct {
        connected: bool = false,
        read_calls: usize = 0,
        last_write_len: usize = 0,

        fn connect(tr: *Transport, _: []const u8) anyerror!void {
            tr.downcast(@This()).connected = true;
        }

        fn disconnect(tr: *Transport) void {
            tr.downcast(@This()).connected = false;
        }

        fn read(tr: *Transport, buffer: []u8) Transport.ReadError!usize {
            const self = tr.downcast(@This());
            self.read_calls += 1;
            if (buffer.len > 0) buffer[0] = 0xAA;
            return @min(buffer.len, 1);
        }

        fn write(tr: *Transport, data: []const u8) Transport.WriteError!void {
            tr.downcast(@This()).last_write_len = data.len;
        }

        fn isConnected(tr: *const Transport) bool {
            return tr.downcastConst(@This()).connected;
        }

        const vtable = Transport.VTable{
            .connect = connect,
            .disconnect = disconnect,
            .read = read,
            .write = write,
            .is_connected = isConnected,
        };
    };

    var impl = DummyTransport{};
    var wrapper = Transport.init(&impl, &DummyTransport.vtable);
    try std.testing.expect(!wrapper.isConnected());

    try wrapper.connect("ignored");
    try std.testing.expect(wrapper.isConnected());
    try std.testing.expect(impl.connected);

    var buf: [2]u8 = undefined;
    const read_len = try wrapper.read(buf[0..]);
    try std.testing.expectEqual(@as(usize, 1), read_len);
    try std.testing.expectEqual(@as(usize, 1), impl.read_calls);
    try std.testing.expectEqual(@as(u8, 0xAA), buf[0]);

    try wrapper.write("abc");
    try std.testing.expectEqual(@as(usize, 3), impl.last_write_len);

    wrapper.disconnect();
    try std.testing.expect(!wrapper.isConnected());
    try std.testing.expect(!impl.connected);
}

// Validates that the stdio transport reports it is always connected.
test "stdio transport reports connected" {
    var stdio = transport_mod.Stdio.init();
    defer stdio.deinit();

    var wrapper = stdio.asTransport();
    try std.testing.expect(wrapper.isConnected());
}

// Instantiating the TCP transport should duplicate the host string and start disconnected.
test "tcp socket init duplicates host" {
    const allocator = std.testing.allocator;

    var socket = try transport_mod.TcpSocket.init(allocator, "localhost", 6666);
    defer socket.deinit();

    try std.testing.expectEqualStrings("localhost", socket.host);
    try std.testing.expectEqual(@as(u16, 6666), socket.port);

    var wrapper = socket.asTransport();
    try std.testing.expect(!wrapper.isConnected());

    const literal_ptr = @intFromPtr("localhost".ptr);
    const stored_ptr = @intFromPtr(socket.host.ptr);
    try std.testing.expect(literal_ptr != stored_ptr);
}

// Unix sockets should start disconnected and tolerate repeated deinit calls.
test "unix socket starts disconnected" {
    const allocator = std.testing.allocator;

    var unix = transport_mod.UnixSocket.init(allocator);
    defer unix.deinit();

    var wrapper = unix.asTransport();
    try std.testing.expect(!wrapper.isConnected());

    unix.deinit();
    try std.testing.expect(!wrapper.isConnected());
}

// Child process transport wires argv and timeout without spawning Neovim during init.
test "child process init configures argv and timeout" {
    const allocator = std.testing.allocator;
    const options = connection.ConnectionOptions{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 25,
    };

    var child = try transport_mod.ChildProcess.init(allocator, options);
    defer child.deinit();

    try std.testing.expectEqual(@as(usize, 3), child.argv.len);
    try std.testing.expectEqualStrings("nvim", child.argv[0]);
    try std.testing.expectEqualStrings("--headless", child.argv[1]);
    try std.testing.expectEqualStrings("--embed", child.argv[2]);
    try std.testing.expect(child.child == null);
    try std.testing.expect(child.stdin_file == null);
    try std.testing.expect(child.stdout_file == null);

    const expected_timeout = if (options.timeout_ms == 0)
        @as(u64, 0)
    else
        @as(u64, options.timeout_ms) * std.time.ns_per_ms;
    try std.testing.expectEqual(expected_timeout, child.shutdown_timeout_ns);

    var wrapper = child.asTransport();
    try std.testing.expect(!wrapper.isConnected());
}

// Verifies that the transport module re-exports the implementations we expect.
test "transport module reexports concrete types" {
    comptime {
        _ = transport_mod.Transport;
        _ = transport_mod.UnixSocket;
        _ = transport_mod.TcpSocket;
        _ = transport_mod.Stdio;
        _ = transport_mod.ChildProcess;
    }

    if (builtin.os.tag == .windows) {
        comptime _ = transport_mod.WindowsPipe;
    } else {
        try std.testing.expectEqual(@as(usize, 0), @sizeOf(transport_mod.WindowsPipe));
    }
}
