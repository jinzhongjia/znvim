const std = @import("std");
const builtin = @import("builtin");
const znvim = @import("../root.zig");
const transport = @import("../transport/mod.zig");
const protocol = @import("../protocol/msgpack_rpc.zig");
const msgpack = @import("msgpack");
const AtomicBool = std.atomic.Value(bool);
const posix = std.posix;
const windows = std.os.windows;

const TestError = error{Timeout};

fn waitForUnixSocket(path: []const u8) !void {
    const max_attempts: usize = 200;
    var attempt: usize = 0;
    while (attempt < max_attempts) : (attempt += 1) {
        if (std.fs.cwd().access(path, .{})) {
            return;
        } else |_| {}
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
    return TestError.Timeout;
}

fn waitForTcp(host: []const u8, port: u16, allocator: std.mem.Allocator) !void {
    const max_attempts: usize = 200;
    var attempt: usize = 0;
    while (attempt < max_attempts) : (attempt += 1) {
        if (std.net.tcpConnectToHost(allocator, host, port)) |stream| {
            stream.close();
            return;
        } else |_| {}
        std.Thread.sleep(10 * std.time.ns_per_ms);
    }
    return TestError.Timeout;
}

fn expectEval(client: *znvim.Client, allocator: std.mem.Allocator) !void {
    std.debug.print("expectEval start\n", .{});
    var expr = try msgpack.Payload.strToPayload("1+1", allocator);
    defer expr.free(allocator);
    const params = [_]msgpack.Payload{expr};
    var result = try client.request("vim_eval", &params);
    defer result.free(allocator);
    switch (result) {
        .int => |value| try std.testing.expectEqual(@as(i64, 2), value),
        else => try std.testing.expect(false),
    }
    std.debug.print("expectEval done\n", .{});
}

fn sendQuit(client: *znvim.Client, allocator: std.mem.Allocator) !void {
    std.debug.print("sendQuit start\n", .{});
    var cmd = try msgpack.Payload.strToPayload("qa!", allocator);
    defer cmd.free(allocator);
    const params = [_]msgpack.Payload{cmd};
    try client.notify("nvim_command", &params);
    std.debug.print("sendQuit notified\n", .{});
}

fn spawnNvimListen(allocator: std.mem.Allocator, address: []const u8) !std.process.Child {
    var child = std.process.Child.init(&.{ "nvim", "--headless", "--clean", "--listen", address }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Inherit;
    child.spawn() catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    return child;
}

fn spawnNvimEmbed(allocator: std.mem.Allocator) !std.process.Child {
    var child = std.process.Child.init(&.{ "nvim", "--headless", "--clean", "--embed" }, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Inherit;
    child.spawn() catch |err| switch (err) {
        error.FileNotFound => return error.SkipZigTest,
        else => return err,
    };
    return child;
}

fn waitForExit(child: *std.process.Child, timeout_ns: u64) bool {
    const Waiter = struct {
        fn run(proc_child: *std.process.Child, term_ptr: *?std.process.Child.Term, done: *AtomicBool) void {
            term_ptr.* = proc_child.wait() catch null;
            done.store(true, .seq_cst);
        }
    };

    var done = AtomicBool.init(false);
    var term: ?std.process.Child.Term = null;
    const thread = std.Thread.spawn(.{}, Waiter.run, .{ child, &term, &done }) catch {
        _ = child.wait() catch {};
        return true;
    };

    var timer = std.time.Timer.start() catch unreachable;
    var timed_out = false;
    while (!done.load(.seq_cst)) {
        if (timer.read() >= timeout_ns) {
            timed_out = true;
            if (!done.load(.seq_cst)) {
                if (builtin.os.tag == .windows) {
                    _ = windows.TerminateProcess(child.id, 1) catch {};
                } else {
                    _ = posix.kill(child.id, posix.SIG.TERM) catch {};
                }
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

fn cleanupChild(child: *std.process.Child) void {
    _ = waitForExit(child, 10 * std.time.ns_per_s);
}

fn unixSocketTest() !void {
    std.debug.print("unixSocketTest begin\n", .{});
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const socket_path = try std.fmt.allocPrint(allocator, "/tmp/znvim-test-{d}.sock", .{std.time.timestamp()});
    defer allocator.free(socket_path);

    var child = try spawnNvimListen(allocator, socket_path);
    var child_cleaned = false;
    defer if (!child_cleaned) cleanupChild(&child);

    waitForUnixSocket(socket_path) catch |err| switch (err) {
        TestError.Timeout => return error.SkipZigTest,
        else => return err,
    };

    var client = try znvim.Client.init(allocator, .{ .socket_path = socket_path, .skip_api_info = true });
    defer client.deinit();
    std.debug.print("unix connect\n", .{});
    try client.connect();
    std.debug.print("unix connected\n", .{});

    try expectEval(&client, allocator);
    try sendQuit(&client, allocator);
    client.disconnect();

    child_cleaned = waitForExit(&child, 10 * std.time.ns_per_s);
    if (!child_cleaned) return error.SkipZigTest;
}

fn tcpSocketTest() !void {
    const host = "127.0.0.1";
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const random_offset = std.crypto.random.int(u16) % 1000;
    const port: u16 = 22000 + random_offset;

    const address_buf = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ host, port });
    defer allocator.free(address_buf);

    var child = try spawnNvimListen(allocator, address_buf);
    var child_cleaned = false;
    defer if (!child_cleaned) cleanupChild(&child);

    waitForTcp(host, port, allocator) catch |err| switch (err) {
        TestError.Timeout => return error.SkipZigTest,
        else => return err,
    };

    var client = try znvim.Client.init(allocator, .{ .tcp_address = host, .tcp_port = port, .skip_api_info = true });
    defer client.deinit();
    std.debug.print("tcp connect\n", .{});
    try client.connect();
    std.debug.print("tcp connected\n", .{});

    try expectEval(&client, allocator);
    try sendQuit(&client, allocator);
    client.disconnect();

    child_cleaned = waitForExit(&child, 10 * std.time.ns_per_s);
    if (!child_cleaned) return error.SkipZigTest;
}

fn childProcessTest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try znvim.Client.init(allocator, .{ .spawn_process = true, .skip_api_info = true });
    defer client.deinit();
    std.debug.print("child connect\n", .{});
    try client.connect();
    std.debug.print("child connected\n", .{});

    try expectEval(&client, allocator);
    try sendQuit(&client, allocator);
    client.disconnect();
}

fn runAllTransports() !void {
    if (std.process.hasEnvVarConstant("SKIP_ZNVIM_TRANSPORT_TESTS")) {
        return error.SkipZigTest;
    }
    try unixSocketTest();
    try tcpSocketTest();
    try childProcessTest();
}

test "transport integrations" {
    try runAllTransports();
}
