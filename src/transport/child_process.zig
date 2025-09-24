const std = @import("std");
const process = std.process;
const AtomicBool = std.atomic.Value(bool);
const Transport = @import("transport.zig").Transport;
const connection = @import("../connection.zig");

/// Transport that launches an embedded Neovim instance and communicates over pipes.
pub const ChildProcess = struct {
    allocator: std.mem.Allocator,
    nvim_path: []const u8,
    argv: [][]const u8,
    child: ?*process.Child = null,
    stdin_file: ?std.fs.File = null,
    stdout_file: ?std.fs.File = null,
    shutdown_timeout_ns: u64,

    pub fn init(allocator: std.mem.Allocator, options: connection.ConnectionOptions) !ChildProcess {
        const path_copy = try allocator.dupe(u8, options.nvim_path);
        var argv = try allocator.alloc([]const u8, 3);
        argv[0] = path_copy;
        argv[1] = "--headless";
        argv[2] = "--embed";
        const timeout_ns = if (options.timeout_ms == 0)
            0
        else
            @as(u64, options.timeout_ms) * std.time.ns_per_ms;
        return .{
            .allocator = allocator,
            .nvim_path = path_copy,
            .argv = argv,
            .child = null,
            .stdin_file = null,
            .stdout_file = null,
            .shutdown_timeout_ns = timeout_ns,
        };
    }

    pub fn deinit(self: *ChildProcess) void {
        self.disconnectInternal();
        self.allocator.free(self.argv);
        self.allocator.free(self.nvim_path);
    }

    pub fn asTransport(self: *ChildProcess) Transport {
        return Transport.init(self, &vtable);
    }

    fn connect(tr: *Transport, _: []const u8) anyerror!void {
        const self = tr.downcast(ChildProcess);
        try self.reconnect();
    }

    /// Tears down any existing process and respawns a fresh embedded Neovim.
    fn reconnect(self: *ChildProcess) !void {
        self.disconnectInternal();

        const child_ptr = try self.allocator.create(process.Child);
        errdefer self.allocator.destroy(child_ptr);

        child_ptr.* = process.Child.init(self.argv, self.allocator);
        child_ptr.stdin_behavior = .Pipe;
        child_ptr.stdout_behavior = .Pipe;
        child_ptr.stderr_behavior = .Inherit;

        try child_ptr.spawn();
        try child_ptr.waitForSpawn();

        if (child_ptr.stdin) |file| {
            self.stdin_file = file;
            child_ptr.stdin = null;
        } else {
            self.stdin_file = null;
        }
        if (child_ptr.stdout) |file| {
            self.stdout_file = file;
            child_ptr.stdout = null;
        } else {
            self.stdout_file = null;
        }

        self.child = child_ptr;
    }

    fn disconnect(tr: *Transport) void {
        const self = tr.downcast(ChildProcess);
        self.disconnectInternal();
    }

    /// Shared cleanup that ensures pipes and child process handles are released.
    fn disconnectInternal(self: *ChildProcess) void {
        if (self.child) |child_ptr| {
            if (self.stdin_file) |file| file.close();
            if (self.stdout_file) |file| file.close();
            self.stdin_file = null;
            self.stdout_file = null;

            const timeout_ns = self.shutdown_timeout_ns;
            _ = waitForChildExit(child_ptr, timeout_ns);
            self.allocator.destroy(child_ptr);
            self.child = null;
        }
    }

    fn read(tr: *Transport, buffer: []u8) Transport.ReadError!usize {
        const self = tr.downcast(ChildProcess);
        const file = self.stdout_file orelse return Transport.ReadError.ConnectionClosed;
        return file.read(buffer) catch |err| switch (err) {
            error.WouldBlock, error.ConnectionTimedOut => Transport.ReadError.Timeout,
            error.BrokenPipe,
            error.ConnectionResetByPeer,
            error.SocketNotConnected,
            error.NotOpenForReading,
            error.OperationAborted,
            error.Canceled,
            error.ProcessNotFound => Transport.ReadError.ConnectionClosed,
            else => Transport.ReadError.UnexpectedError,
        };
    }

    fn write(tr: *Transport, data: []const u8) Transport.WriteError!void {
        const self = tr.downcast(ChildProcess);
        const file = self.stdin_file orelse return Transport.WriteError.ConnectionClosed;
        file.writeAll(data) catch |err| switch (err) {
            error.BrokenPipe => return Transport.WriteError.BrokenPipe,
            error.ConnectionResetByPeer,
            error.NotOpenForWriting,
            error.OperationAborted,
            error.ProcessNotFound => return Transport.WriteError.ConnectionClosed,
            else => return Transport.WriteError.UnexpectedError,
        };
    }

    fn isConnected(tr: *Transport) bool {
        const self = tr.downcastConst(ChildProcess);
        return self.child != null;
    }

    pub const vtable = Transport.VTable{
        .connect = connect,
        .disconnect = disconnect,
        .read = read,
        .write = write,
        .is_connected = isConnected,
    };
};

/// Waits for the child to exit, killing it if the provided timeout elapses.
fn waitForChildExit(child: *process.Child, timeout_ns: u64) bool {
    const Waiter = struct {
        fn run(proc_child: *process.Child, term_ptr: *?process.Child.Term, done: *AtomicBool) void {
            term_ptr.* = proc_child.wait() catch null;
            done.store(true, .seq_cst);
        }
    };

    var done = AtomicBool.init(false);
    var term: ?process.Child.Term = null;
    const thread = std.Thread.spawn(.{}, Waiter.run, .{ child, &term, &done }) catch {
        _ = child.wait() catch {};
        return true;
    };

    var timer = std.time.Timer.start() catch unreachable;
    const enforce_timeout = timeout_ns != 0;
    var timed_out = false;
    while (!done.load(.seq_cst)) {
        if (enforce_timeout and timer.read() >= timeout_ns) {
            timed_out = true;
            if (!done.load(.seq_cst)) {
                _ = child.kill() catch {};
            }
            break;
        }
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }

    thread.join();

    if (term == null) {
        _ = child.wait() catch {};
    }

    return !timed_out;
}
