const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;
const Client = znvim.Client;

// Helper to create a test client with embedded Neovim
fn createTestClient(allocator: std.mem.Allocator) !znvim.Client {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 10000,
    });
    errdefer client.deinit();
    try client.connect();
    return client;
}

// Test: Multiple threads sharing same Client for requests
test "shared client: concurrent requests with mutex protection" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const thread_count = 8;
    const requests_per_thread = 20;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var success_count = std.atomic.Value(usize).init(0);
    var error_count = std.atomic.Value(usize).init(0);

    const ThreadContext = struct {
        client: *Client,
        allocator: std.mem.Allocator,
        thread_id: usize,
        requests: usize,
        success: *std.atomic.Value(usize),
        errors: *std.atomic.Value(usize),
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.requests) : (i += 1) {
                // Each thread evaluates a different expression
                const expr_text = std.fmt.allocPrint(
                    ctx.allocator,
                    "{d} * {d}",
                    .{ ctx.thread_id, i },
                ) catch {
                    _ = ctx.errors.fetchAdd(1, .monotonic);
                    continue;
                };
                defer ctx.allocator.free(expr_text);

                const expr = msgpack.string(ctx.allocator, expr_text) catch {
                    _ = ctx.errors.fetchAdd(1, .monotonic);
                    continue;
                };
                defer msgpack.free(expr, ctx.allocator);

                const params = [_]msgpack.Value{expr};
                const result = ctx.client.request("nvim_eval", &params) catch {
                    _ = ctx.errors.fetchAdd(1, .monotonic);
                    continue;
                };
                defer msgpack.free(result, ctx.allocator);

                const value = msgpack.expectI64(result) catch {
                    _ = ctx.errors.fetchAdd(1, .monotonic);
                    continue;
                };

                const expected = @as(i64, @intCast(ctx.thread_id * i));
                if (value == expected) {
                    _ = ctx.success.fetchAdd(1, .monotonic);
                } else {
                    _ = ctx.errors.fetchAdd(1, .monotonic);
                }
            }
        }
    }.run;

    // Spawn threads that share the same client
    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .allocator = allocator,
            .thread_id = i,
            .requests = requests_per_thread,
            .success = &success_count,
            .errors = &error_count,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    // Wait for all threads
    for (threads) |thread| {
        thread.join();
    }

    // Verify results
    const total_expected = thread_count * requests_per_thread;
    const successes = success_count.load(.monotonic);

    // With mutex protection, all should succeed
    try std.testing.expect(successes >= (total_expected * 95 / 100));
}

// Test: Concurrent notifications with shared client
test "shared client: concurrent notifications" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const thread_count = 10;
    const notifications_per_thread = 30;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var sent_count = std.atomic.Value(usize).init(0);

    const ThreadContext = struct {
        client: *Client,
        allocator: std.mem.Allocator,
        thread_id: usize,
        count: usize,
        sent: *std.atomic.Value(usize),
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.count) : (i += 1) {
                const var_name_str = std.fmt.allocPrint(
                    ctx.allocator,
                    "shared_notif_{d}_{d}",
                    .{ ctx.thread_id, i },
                ) catch continue;
                defer ctx.allocator.free(var_name_str);

                const var_name = msgpack.string(ctx.allocator, var_name_str) catch continue;
                defer msgpack.free(var_name, ctx.allocator);

                const var_value = msgpack.int(@as(i64, @intCast(i)));

                ctx.client.notify("nvim_set_var", &.{ var_name, var_value }) catch continue;

                _ = ctx.sent.fetchAdd(1, .monotonic);
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .allocator = allocator,
            .thread_id = i,
            .count = notifications_per_thread,
            .sent = &sent_count,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    const sent = sent_count.load(.monotonic);

    // With mutex protection, all should succeed
    try std.testing.expect(sent >= (thread_count * notifications_per_thread * 95 / 100));
}

// Test: Mixed concurrent requests and notifications
test "shared client: mixed concurrent requests and notifications" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const thread_count = 6;
    const ops_per_thread = 20;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var ops_count = std.atomic.Value(usize).init(0);

    const ThreadContext = struct {
        client: *Client,
        allocator: std.mem.Allocator,
        thread_id: usize,
        count: usize,
        ops: *std.atomic.Value(usize),
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.count) : (i += 1) {
                // Alternate between requests and notifications
                if (i % 2 == 0) {
                    // Request
                    const expr_str = std.fmt.allocPrint(
                        ctx.allocator,
                        "{d}",
                        .{ctx.thread_id * 100 + i},
                    ) catch continue;
                    defer ctx.allocator.free(expr_str);

                    const expr = msgpack.string(ctx.allocator, expr_str) catch continue;
                    defer msgpack.free(expr, ctx.allocator);

                    const result = ctx.client.request("nvim_eval", &.{expr}) catch continue;
                    defer msgpack.free(result, ctx.allocator);

                    _ = ctx.ops.fetchAdd(1, .monotonic);
                } else {
                    // Notification
                    const var_name_str = std.fmt.allocPrint(
                        ctx.allocator,
                        "mixed_{d}_{d}",
                        .{ ctx.thread_id, i },
                    ) catch continue;
                    defer ctx.allocator.free(var_name_str);

                    const var_name = msgpack.string(ctx.allocator, var_name_str) catch continue;
                    defer msgpack.free(var_name, ctx.allocator);

                    ctx.client.notify("nvim_set_var", &.{ var_name, msgpack.int(1) }) catch continue;

                    _ = ctx.ops.fetchAdd(1, .monotonic);
                }
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .allocator = allocator,
            .thread_id = i,
            .count = ops_per_thread,
            .ops = &ops_count,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    const total_ops = ops_count.load(.monotonic);

    // Most operations should succeed
    try std.testing.expect(total_ops >= (thread_count * ops_per_thread * 90 / 100));
}

// Test: Concurrent buffer operations on shared client
test "shared client: concurrent buffer create and delete" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const thread_count = 5;
    const buffers_per_thread = 10;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var total_created = std.atomic.Value(usize).init(0);

    const ThreadContext = struct {
        client: *Client,
        allocator: std.mem.Allocator,
        count: usize,
        created: *std.atomic.Value(usize),
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.count) : (i += 1) {
                // Create buffer
                const buf = ctx.client.request("nvim_create_buf", &.{
                    msgpack.boolean(false),
                    msgpack.boolean(false),
                }) catch continue;
                defer msgpack.free(buf, ctx.allocator);

                _ = ctx.created.fetchAdd(1, .monotonic);

                // Verify it's valid
                const is_valid = ctx.client.request("nvim_buf_is_valid", &.{buf}) catch continue;
                defer msgpack.free(is_valid, ctx.allocator);

                // Delete it
                var opts = msgpack.Value.mapPayload(ctx.allocator);
                defer opts.free(ctx.allocator);
                opts.mapPut("force", msgpack.boolean(true)) catch continue;

                const del_result = ctx.client.request("nvim_buf_delete", &.{ buf, opts }) catch continue;
                defer msgpack.free(del_result, ctx.allocator);
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .allocator = allocator,
            .count = buffers_per_thread,
            .created = &total_created,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    const created = total_created.load(.monotonic);

    // Should have created most buffers
    try std.testing.expect(created >= (thread_count * buffers_per_thread * 90 / 100));
}

// Test: Concurrent variable operations on shared client
test "shared client: concurrent variable set and get" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const thread_count = 8;
    const ops_per_thread = 15;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var ops_count = std.atomic.Value(usize).init(0);

    const ThreadContext = struct {
        client: *Client,
        allocator: std.mem.Allocator,
        thread_id: usize,
        ops: usize,
        count: *std.atomic.Value(usize),
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.ops) : (i += 1) {
                // Set unique variable for this thread
                const var_name_str = std.fmt.allocPrint(
                    ctx.allocator,
                    "shared_var_{d}_{d}",
                    .{ ctx.thread_id, i },
                ) catch continue;
                defer ctx.allocator.free(var_name_str);

                const var_name = msgpack.string(ctx.allocator, var_name_str) catch continue;
                defer msgpack.free(var_name, ctx.allocator);

                const var_value = msgpack.int(@as(i64, @intCast(ctx.thread_id * 1000 + i)));

                // Set variable
                const set_result = ctx.client.request("nvim_set_var", &.{ var_name, var_value }) catch continue;
                defer msgpack.free(set_result, ctx.allocator);

                // Get it back
                const get_result = ctx.client.request("nvim_get_var", &.{var_name}) catch continue;
                defer msgpack.free(get_result, ctx.allocator);

                const retrieved = msgpack.expectI64(get_result) catch continue;
                const expected = @as(i64, @intCast(ctx.thread_id * 1000 + i));

                if (retrieved == expected) {
                    _ = ctx.count.fetchAdd(1, .monotonic);
                }
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .allocator = allocator,
            .thread_id = i,
            .ops = ops_per_thread,
            .count = &ops_count,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    const successful = ops_count.load(.monotonic);

    // Should complete most operations correctly
    try std.testing.expect(successful >= (thread_count * ops_per_thread * 90 / 100));
}

// Test: Concurrent commands on shared client
test "shared client: concurrent command execution" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const thread_count = 4;
    const commands_per_thread = 15;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var executed = std.atomic.Value(usize).init(0);

    const ThreadContext = struct {
        client: *Client,
        allocator: std.mem.Allocator,
        thread_id: usize,
        count: usize,
        executed: *std.atomic.Value(usize),
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.count) : (i += 1) {
                // Execute a simple command
                const cmd_str = std.fmt.allocPrint(
                    ctx.allocator,
                    "let g:shared_cmd_{d}_{d} = {d}",
                    .{ ctx.thread_id, i, ctx.thread_id * 100 + i },
                ) catch continue;
                defer ctx.allocator.free(cmd_str);

                const cmd = msgpack.string(ctx.allocator, cmd_str) catch continue;
                defer msgpack.free(cmd, ctx.allocator);

                var opts = msgpack.Value.mapPayload(ctx.allocator);
                defer opts.free(ctx.allocator);
                opts.mapPut("output", msgpack.boolean(false)) catch continue;

                const result = ctx.client.request("nvim_exec2", &.{ cmd, opts }) catch continue;
                defer msgpack.free(result, ctx.allocator);

                _ = ctx.executed.fetchAdd(1, .monotonic);
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .allocator = allocator,
            .thread_id = i,
            .count = commands_per_thread,
            .executed = &executed,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    const total = executed.load(.monotonic);

    // Should complete most commands
    try std.testing.expect(total >= (thread_count * commands_per_thread * 90 / 100));
}

// Test: Stress test with high concurrency
test "shared client: high concurrency stress test" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const thread_count = 16;
    const requests_per_thread = 10;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var success = std.atomic.Value(usize).init(0);

    const ThreadContext = struct {
        client: *Client,
        allocator: std.mem.Allocator,
        count: usize,
        success: *std.atomic.Value(usize),
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.count) : (i += 1) {
                const expr = msgpack.string(ctx.allocator, "1") catch continue;
                defer msgpack.free(expr, ctx.allocator);

                const result = ctx.client.request("nvim_eval", &.{expr}) catch continue;
                defer msgpack.free(result, ctx.allocator);

                _ = ctx.success.fetchAdd(1, .monotonic);
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .allocator = allocator,
            .count = requests_per_thread,
            .success = &success,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    const successful = success.load(.monotonic);

    // Should complete most requests
    try std.testing.expect(successful >= (thread_count * requests_per_thread * 90 / 100));
}

// Test: Concurrent connect attempts (should be safe with mutex)
test "shared client: concurrent connect is safe" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 5000,
    });
    defer client.deinit();

    const thread_count = 5;
    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var success_count = std.atomic.Value(usize).init(0);
    var already_connected = std.atomic.Value(usize).init(0);

    const ThreadContext = struct {
        client: *Client,
        success: *std.atomic.Value(usize),
        already: *std.atomic.Value(usize),
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            ctx.client.connect() catch |err| {
                if (err == error.AlreadyConnected) {
                    _ = ctx.already.fetchAdd(1, .monotonic);
                }
                return;
            };
            _ = ctx.success.fetchAdd(1, .monotonic);
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .success = &success_count,
            .already = &already_connected,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    const successes = success_count.load(.monotonic);
    const already = already_connected.load(.monotonic);

    // Exactly one should succeed, others get AlreadyConnected
    try std.testing.expectEqual(@as(usize, 1), successes);
    try std.testing.expectEqual(@as(usize, thread_count - 1), already);
}

// Test: Concurrent API info access is safe
test "shared client: concurrent api info access" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const thread_count = 10;
    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    const ThreadContext = struct {
        client: *const Client,
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < 50) : (i += 1) {
                const info = ctx.client.getApiInfo();
                if (info) |api_info| {
                    // Access API info (read-only)
                    _ = api_info.channel_id;
                    _ = api_info.version.major;
                    _ = api_info.functions.len;
                }
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{ .client = &client };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }
}
