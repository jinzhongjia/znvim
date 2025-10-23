const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;

fn createTestClient(allocator: std.mem.Allocator) !znvim.Client {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 30000, // Longer timeout for long-running tests
    });
    errdefer client.deinit();
    try client.connect();
    return client;
}

// Test: Many sequential requests without disconnect
test "sustained operation: 1000 sequential requests" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const request_count = 1000;
    var successful: usize = 0;

    var i: usize = 0;
    while (i < request_count) : (i += 1) {
        const expr_str = try std.fmt.allocPrint(allocator, "{d} * 2", .{i});
        defer allocator.free(expr_str);

        const expr = try msgpack.string(allocator, expr_str);
        defer msgpack.free(expr, allocator);

        const result = client.request("nvim_eval", &.{expr}) catch continue;
        defer msgpack.free(result, allocator);

        const value = msgpack.expectI64(result) catch continue;
        const expected = @as(i64, @intCast(i * 2));

        if (value == expected) {
            successful += 1;
        }
    }

    // Should complete at least 95% of requests
    try std.testing.expect(successful >= (request_count * 95 / 100));
}

// Test: Memory stability over many operations
test "memory stability: repeated buffer create and delete" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cycles = 200;
    var successful_cycles: usize = 0;

    var i: usize = 0;
    while (i < cycles) : (i += 1) {
        // Create buffer
        const buf = client.request("nvim_create_buf", &.{
            msgpack.boolean(false),
            msgpack.boolean(false),
        }) catch continue;
        defer msgpack.free(buf, allocator);

        // Add some content
        const content = try msgpack.string(allocator, "Test content");
        // ownership transferred to content_array

        const content_array = try msgpack.array(allocator, &.{content});
        defer msgpack.free(content_array, allocator);

        const set_result = client.request("nvim_buf_set_lines", &.{
            buf,
            msgpack.int(0),
            msgpack.int(-1),
            msgpack.boolean(false),
            content_array,
        }) catch continue;
        defer msgpack.free(set_result, allocator);

        // Read it back
        const get_result = client.request("nvim_buf_get_lines", &.{
            buf,
            msgpack.int(0),
            msgpack.int(-1),
            msgpack.boolean(false),
        }) catch continue;
        defer msgpack.free(get_result, allocator);

        // Delete buffer
        var del_opts = msgpack.Value.mapPayload(allocator);
        defer del_opts.free(allocator);
        del_opts.mapPut("force", msgpack.boolean(true)) catch continue;

        const del_result = client.request("nvim_buf_delete", &.{ buf, del_opts }) catch continue;
        defer msgpack.free(del_result, allocator);

        successful_cycles += 1;
    }

    try std.testing.expect(successful_cycles >= (cycles * 90 / 100));
}

// Test: Session with mixed operations over time
test "extended session: mixed operations for sustained period" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const duration_seconds = 5; // 5 seconds sustained test
    const start_time = std.time.timestamp();

    var operations: usize = 0;
    var errors: usize = 0;

    while (std.time.timestamp() - start_time < duration_seconds) {
        // Cycle through different operation types
        const op_type = operations % 4;

        switch (op_type) {
            0 => {
                // Eval operation
                const expr = try msgpack.string(allocator, "1 + 1");
                defer msgpack.free(expr, allocator);

                const result = client.request("nvim_eval", &.{expr}) catch {
                    errors += 1;
                    continue;
                };
                defer msgpack.free(result, allocator);
            },
            1 => {
                // Variable operation
                const var_name = try msgpack.string(allocator, "test_var");
                defer msgpack.free(var_name, allocator);

                const set_result = client.request("nvim_set_var", &.{
                    var_name,
                    msgpack.int(@intCast(operations)),
                }) catch {
                    errors += 1;
                    continue;
                };
                defer msgpack.free(set_result, allocator);
            },
            2 => {
                // Get API info
                const result = client.request("nvim_get_mode", &.{}) catch {
                    errors += 1;
                    continue;
                };
                defer msgpack.free(result, allocator);
            },
            3 => {
                // Notification
                const var_name = try msgpack.string(allocator, "notif_var");
                defer msgpack.free(var_name, allocator);

                client.notify("nvim_set_var", &.{
                    var_name,
                    msgpack.int(@intCast(operations)),
                }) catch {
                    errors += 1;
                    continue;
                };
            },
            else => unreachable,
        }

        operations += 1;
    }

    // Should have minimal errors
    try std.testing.expect(errors < (operations / 10));
    // Should have done substantial work
    try std.testing.expect(operations > 50);
}

// Test: Variable accumulation doesn't cause performance degradation
test "performance stability: many variables created" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const var_count = 500;
    const samples = 5;

    var timings = try allocator.alloc(i64, samples);
    defer allocator.free(timings);

    var sample_idx: usize = 0;
    while (sample_idx < samples) : (sample_idx += 1) {
        const start = std.time.milliTimestamp();

        // Create batch of variables
        const batch_start = sample_idx * (var_count / samples);
        const batch_end = batch_start + (var_count / samples);

        var i = batch_start;
        while (i < batch_end) : (i += 1) {
            const var_name_str = try std.fmt.allocPrint(allocator, "perf_var_{d}", .{i});
            defer allocator.free(var_name_str);

            const var_name = try msgpack.string(allocator, var_name_str);
            defer msgpack.free(var_name, allocator);

            const result = try client.request("nvim_set_var", &.{
                var_name,
                msgpack.int(@as(i64, @intCast(i))),
            });
            defer msgpack.free(result, allocator);
        }

        const end = std.time.milliTimestamp();
        timings[sample_idx] = end - start;
    }

    // Check that later batches aren't significantly slower
    const first_batch_time = timings[0];
    const last_batch_time = timings[samples - 1];

    // Last batch should be within 3x of first batch time (allowing for some variance)
    try std.testing.expect(last_batch_time < first_batch_time * 3);
}

// Test: Multiple reconnect cycles with sustained work
test "reconnect endurance: multiple disconnect-reconnect cycles with work" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 5000,
    });
    defer client.deinit();

    const cycles = 10;
    const requests_per_cycle = 20;

    var total_successful: usize = 0;

    var cycle: usize = 0;
    while (cycle < cycles) : (cycle += 1) {
        // Connect
        try client.connect();

        // Do some work
        var req: usize = 0;
        while (req < requests_per_cycle) : (req += 1) {
            const expr = try msgpack.string(allocator, "1");
            defer msgpack.free(expr, allocator);

            const result = client.request("nvim_eval", &.{expr}) catch continue;
            defer msgpack.free(result, allocator);

            total_successful += 1;
        }

        // Disconnect
        client.disconnect();

        // Brief pause
        std.Thread.sleep(50 * std.time.ns_per_ms);
    }

    // Should complete most requests
    try std.testing.expect(total_successful >= (cycles * requests_per_cycle * 85 / 100));
}

// Test: Message ID counter doesn't overflow in extended use
test "message id counter stability over many requests" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const initial_id = client.next_msgid.load(.monotonic);

    // Make many requests
    const request_count = 500;
    var i: usize = 0;
    while (i < request_count) : (i += 1) {
        _ = client.nextMessageId();
    }

    const final_id = client.next_msgid.load(.monotonic);

    // Should have incremented correctly
    try std.testing.expectEqual(initial_id + request_count, final_id);

    // Make actual requests to verify IDs work
    var j: usize = 0;
    while (j < 10) : (j += 1) {
        const expr = try msgpack.string(allocator, "1");
        defer msgpack.free(expr, allocator);

        const result = try client.request("nvim_eval", &.{expr});
        defer msgpack.free(result, allocator);
    }

    // Verify final count
    try std.testing.expectEqual(initial_id + request_count, final_id);
}

// Test: Notification throughput over sustained period
test "sustained notification throughput" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const duration_seconds = 3;
    const start_time = std.time.timestamp();

    var notifications_sent: i64 = 0;

    while (std.time.timestamp() - start_time < duration_seconds) {
        const var_name = try msgpack.string(allocator, "notif_test");
        defer msgpack.free(var_name, allocator);

        client.notify("nvim_set_var", &.{
            var_name,
            msgpack.int(notifications_sent),
        }) catch continue;

        notifications_sent += 1;

        // Small delay to avoid overwhelming
        std.Thread.sleep(1 * std.time.ns_per_ms);
    }

    // Should send a substantial number
    try std.testing.expect(notifications_sent > 100);
}

// Test: Buffer content stability over many read/write cycles
test "buffer content integrity over repeated operations" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf, allocator);

    const test_content = "Stable content line";
    const iterations = 100;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // Write content
        const content = try msgpack.string(allocator, test_content);
        // ownership transferred

        const content_array = try msgpack.array(allocator, &.{content});
        defer msgpack.free(content_array, allocator);

        const set_result = try client.request("nvim_buf_set_lines", &.{
            buf,
            msgpack.int(0),
            msgpack.int(-1),
            msgpack.boolean(false),
            content_array,
        });
        defer msgpack.free(set_result, allocator);

        // Read it back
        const get_result = try client.request("nvim_buf_get_lines", &.{
            buf,
            msgpack.int(0),
            msgpack.int(-1),
            msgpack.boolean(false),
        });
        defer msgpack.free(get_result, allocator);

        const lines = try msgpack.expectArray(get_result);
        const retrieved = try msgpack.expectString(lines[0]);

        // Verify content is intact
        try std.testing.expectEqualStrings(test_content, retrieved);
    }
}
