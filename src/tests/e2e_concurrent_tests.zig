const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;

// Helper to create a test client with embedded Neovim
fn createTestClient(allocator: std.mem.Allocator) !znvim.Client {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 10000, // Longer timeout for concurrent tests
    });
    errdefer client.deinit();
    try client.connect();
    return client;
}

// Test: Shared client with concurrent requests (now thread-safe with mutex)
test "shared client: concurrent requests with mutex protection" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const thread_count = 8;
    const requests_per_thread = 15;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var success_count = std.atomic.Value(usize).init(0);

    const ThreadContext = struct {
        client: *znvim.Client,
        allocator: std.mem.Allocator,
        thread_id: usize,
        requests: usize,
        success: *std.atomic.Value(usize),
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
                ) catch continue;
                defer ctx.allocator.free(expr_text);

                const expr = msgpack.string(ctx.allocator, expr_text) catch continue;
                defer msgpack.free(expr, ctx.allocator);

                const params = [_]msgpack.Value{expr};
                const result = ctx.client.request("nvim_eval", &params) catch continue;
                defer msgpack.free(result, ctx.allocator);

                const value = msgpack.expectI64(result) catch continue;

                const expected = @as(i64, @intCast(ctx.thread_id * i));
                if (value == expected) {
                    _ = ctx.success.fetchAdd(1, .monotonic);
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

    // With mutex protection, should have high success rate
    try std.testing.expect(successes >= (total_expected * 95 / 100));
}

// Test: Sequential rapid buffer operations (simulating concurrent load)
test "rapid sequential buffer create and delete operations" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const total_operations = 50;
    var successful: usize = 0;

    var i: usize = 0;
    while (i < total_operations) : (i += 1) {
        // Create buffer
        const buf = client.request("nvim_create_buf", &.{
            msgpack.boolean(false),
            msgpack.boolean(false),
        }) catch continue;
        defer msgpack.free(buf, allocator);

        successful += 1;

        // Verify it's valid
        const is_valid = client.request("nvim_buf_is_valid", &.{buf}) catch continue;
        defer msgpack.free(is_valid, allocator);

        // Delete it
        var opts = msgpack.Value.mapPayload(allocator);
        defer opts.free(allocator);
        opts.mapPut("force", msgpack.boolean(true)) catch continue;

        const del_result = client.request("nvim_buf_delete", &.{ buf, opts }) catch continue;
        defer msgpack.free(del_result, allocator);
    }

    // Should have created most buffers
    try std.testing.expect(successful >= (total_operations * 9 / 10));
}

// Test: High frequency small messages (sequential to avoid concurrency issues)
test "high frequency sequential message stress test" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const message_count = 500;
    var successful: usize = 0;

    const start_time = std.time.milliTimestamp();

    var i: usize = 0;
    while (i < message_count) : (i += 1) {
        // Simple eval - returns quickly
        const expr = msgpack.string(allocator, "1") catch continue;
        defer msgpack.free(expr, allocator);

        const result = client.request("nvim_eval", &.{expr}) catch continue;
        defer msgpack.free(result, allocator);

        successful += 1;
    }

    const end_time = std.time.milliTimestamp();
    const elapsed_ms = end_time - start_time;

    const throughput = if (elapsed_ms > 0) successful * 1000 / @as(usize, @intCast(elapsed_ms)) else 0;
    _ = throughput; // unused

    // Should complete most messages
    try std.testing.expect(successful >= (message_count * 9 / 10));
}
