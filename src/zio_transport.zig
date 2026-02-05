const std = @import("std");
const zio = @import("zio");
const builtin = @import("builtin");

/// ZIO-based transport layer for znvim.
/// Provides async I/O connections via zio's event-driven runtime.
///
/// All operations require a zio.Runtime, which must be managed by the caller (Client).

pub const Runtime = zio.Runtime;
pub const Stream = zio.net.Stream;
pub const Timeout = zio.Timeout;

/// Connection result containing the stream and optional child process.
pub const Connection = struct {
    stream: Stream,
    child_process: ?std.process.Child = null,

    pub fn close(self: *Connection, rt: *Runtime) void {
        self.stream.close(rt);
        if (self.child_process) |*child| {
            _ = child.kill() catch {};
            _ = child.wait() catch {};
        }
    }
};

/// Error types for zio transport operations.
pub const ConnectError = error{
    ConnectionFailed,
    InvalidAddress,
    Timeout,
    ProcessSpawnFailed,
    PipeCreationFailed,
    OutOfMemory,
    UnsupportedPlatform,
    NameTooLong,
    InvalidHostName,
};

/// Connect to a Unix domain socket.
/// Only available on Unix-like systems.
pub fn connectUnixSocket(rt: *Runtime, path: []const u8) ConnectError!Connection {
    if (comptime !zio.net.has_unix_sockets) {
        return ConnectError.UnsupportedPlatform;
    }

    const addr = zio.net.UnixAddress.init(path) catch |err| switch (err) {
        error.NameTooLong => return ConnectError.NameTooLong,
    };

    const stream = addr.connect(rt, .{}) catch |err| {
        std.log.err("Failed to connect to Unix socket: {s}, error: {}", .{ path, err });
        return ConnectError.ConnectionFailed;
    };

    return Connection{ .stream = stream };
}

/// Connect to a TCP socket using IP address.
pub fn connectTcp(rt: *Runtime, host: []const u8, port: u16) ConnectError!Connection {
    // Try to parse as IPv4 first
    if (zio.net.IpAddress.parseIp4(host, port)) |addr| {
        const stream = addr.connect(rt, .{}) catch |err| {
            std.log.err("Failed to connect to TCP IPv4: {s}:{}, error: {}", .{ host, port, err });
            return ConnectError.ConnectionFailed;
        };
        return Connection{ .stream = stream };
    } else |_| {}

    // Try to parse as IPv6
    if (zio.net.IpAddress.parseIp6(host, port)) |addr| {
        const stream = addr.connect(rt, .{}) catch |err| {
            std.log.err("Failed to connect to TCP IPv6: {s}:{}, error: {}", .{ host, port, err });
            return ConnectError.ConnectionFailed;
        };
        return Connection{ .stream = stream };
    } else |_| {}

    // Try hostname resolution
    const hostname = zio.net.HostName.init(host) catch |err| switch (err) {
        error.NameTooLong => return ConnectError.NameTooLong,
        error.InvalidHostName => return ConnectError.InvalidHostName,
    };

    const stream = hostname.connect(rt, port, .{}) catch |err| {
        std.log.err("Failed to connect to TCP host: {s}:{}, error: {}", .{ host, port, err });
        return ConnectError.ConnectionFailed;
    };

    return Connection{ .stream = stream };
}

/// Spawn a child process (e.g., nvim --embed) and connect via stdio.
/// Uses std.process for spawning, then uses zio for async pipe I/O.
///
/// Note: This function spawns the child process but the pipe I/O handling
/// requires special consideration as zio's Stream is designed for sockets.
/// For child process communication, we need to use zio's file I/O or
/// a different approach.
pub fn spawnChildProcess(allocator: std.mem.Allocator, nvim_path: []const u8) ConnectError!ChildProcessConnection {
    // Build argv for nvim --embed --clean (clean mode skips user config)
    const argv = [_][]const u8{ nvim_path, "--embed", "--clean" };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Inherit; // Let stderr go to parent's stderr (avoid pipe buffer issues)

    child.spawn() catch |err| {
        std.log.err("Failed to spawn child process: {s}, error: {}", .{ nvim_path, err });
        return ConnectError.ProcessSpawnFailed;
    };

    return ChildProcessConnection{
        .child = child,
        .stdin_pipe = child.stdin.?,
        .stdout_pipe = child.stdout.?,
    };
}

/// Connection via child process pipes (not zio.net.Stream).
/// Child process I/O uses std file handles, not zio sockets.
pub const ChildProcessConnection = struct {
    child: std.process.Child,
    stdin_pipe: std.fs.File,
    stdout_pipe: std.fs.File,

    /// Read from child's stdout (blocking or async depending on context)
    pub fn read(self: *ChildProcessConnection, buffer: []u8) !usize {
        return self.stdout_pipe.read(buffer);
    }

    /// Write to child's stdin
    pub fn write(self: *ChildProcessConnection, data: []const u8) !usize {
        return self.stdin_pipe.write(data);
    }

    /// Write all data to child's stdin
    pub fn writeAll(self: *ChildProcessConnection, data: []const u8) !void {
        return self.stdin_pipe.writeAll(data);
    }

    pub fn close(self: *ChildProcessConnection) void {
        // Kill the child process to ensure it exits
        // Note: kill() on POSIX sends SIGKILL and waits for termination
        // wait() automatically cleans up stdin/stdout/stderr streams
        _ = self.child.kill() catch {};
    }
};

/// Connect via stdio (stdin/stdout).
/// Used when znvim is launched as a subprocess of nvim.
/// Note: Stdio uses std file handles, not zio sockets.
pub const StdioConnection = struct {
    stdin_file: std.fs.File,
    stdout_file: std.fs.File,

    pub fn init() StdioConnection {
        return .{
            .stdin_file = std.fs.File.stdin(),
            .stdout_file = std.fs.File.stdout(),
        };
    }

    pub fn read(self: *StdioConnection, buffer: []u8) !usize {
        return self.stdin_file.read(buffer);
    }

    pub fn write(self: *StdioConnection, data: []const u8) !usize {
        return self.stdout_file.write(data);
    }

    pub fn writeAll(self: *StdioConnection, data: []const u8) !void {
        return self.stdout_file.writeAll(data);
    }

    pub fn close(self: *StdioConnection) void {
        // Don't close stdin/stdout
        _ = self;
    }
};

/// Transport type enumeration
pub const TransportType = enum {
    unix_socket,
    tcp,
    child_process,
    stdio,
    named_pipe, // Windows only, TODO
};

// ============================================================================
// Tests
// ============================================================================

test "zio_transport module compiles" {
    // Basic compilation test
    _ = ConnectError;
    _ = Connection;
    _ = ChildProcessConnection;
    _ = StdioConnection;
    _ = TransportType;
}

test "StdioConnection init" {
    const conn = StdioConnection.init();
    _ = conn;
}
