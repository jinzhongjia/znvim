const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;
const Client = znvim.Client;

// Test: Atomic message ID generation is thread-safe
test "atomic message id generation under concurrent load" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    const thread_count = 10;
    const ids_per_thread = 1000;
    const total_ids = thread_count * ids_per_thread;

    // Allocate storage for all generated IDs
    const all_ids = try allocator.alloc(u32, total_ids);
    defer allocator.free(all_ids);

    // Create threads
    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    const ThreadContext = struct {
        client: *Client,
        ids: []u32,
        start_index: usize,
        count: usize,
    };

    // Worker function that generates message IDs
    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.count) : (i += 1) {
                ctx.ids[ctx.start_index + i] = ctx.client.nextMessageId();
            }
        }
    }.run;

    // Spawn threads
    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .ids = all_ids,
            .start_index = i * ids_per_thread,
            .count = ids_per_thread,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    // Wait for all threads to complete
    for (threads) |thread| {
        thread.join();
    }

    // Verify all IDs are unique
    var seen = std.AutoHashMap(u32, void).init(allocator);
    defer seen.deinit();

    for (all_ids) |id| {
        const result = try seen.getOrPut(id);
        try std.testing.expect(!result.found_existing);
    }

    // Should have exactly total_ids unique IDs
    try std.testing.expectEqual(@as(u32, total_ids), seen.count());
}

// Test: Multiple client instances can be used concurrently
test "multiple client instances concurrent operation" {
    const allocator = std.testing.allocator;

    const thread_count = 5;
    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    const ThreadData = struct {
        allocator: std.mem.Allocator,
        success: *std.atomic.Value(bool),
    };

    const worker = struct {
        fn run(data: ThreadData) void {
            var client = Client.init(data.allocator, .{
                .socket_path = "/tmp/test.sock",
            }) catch {
                data.success.store(false, .monotonic);
                return;
            };
            defer client.deinit();

            // Generate some message IDs
            var i: usize = 0;
            while (i < 100) : (i += 1) {
                _ = client.nextMessageId();
            }

            data.success.store(true, .monotonic);
        }
    }.run;

    var success = std.atomic.Value(bool).init(true);

    // Spawn threads with independent clients
    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const data = ThreadData{
            .allocator = allocator,
            .success = &success,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{data});
    }

    // Wait for completion
    for (threads) |thread| {
        thread.join();
    }

    try std.testing.expect(success.load(.monotonic));
}

// Test: Message ID generation under extreme concurrency
test "message id generation stress test with many threads" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    const thread_count = 50;
    const ids_per_thread = 200;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    var id_counter = std.atomic.Value(usize).init(0);

    const ThreadContext = struct {
        client: *Client,
        counter: *std.atomic.Value(usize),
        expected_count: usize,
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.expected_count) : (i += 1) {
                _ = ctx.client.nextMessageId();
                _ = ctx.counter.fetchAdd(1, .monotonic);
            }
        }
    }.run;

    // Spawn threads
    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .counter = &id_counter,
            .expected_count = ids_per_thread,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    // Wait for all threads
    for (threads) |thread| {
        thread.join();
    }

    const total_generated = id_counter.load(.monotonic);
    try std.testing.expectEqual(@as(usize, thread_count * ids_per_thread), total_generated);

    // Verify the client's message ID counter is correct
    const final_id = client.next_msgid.load(.monotonic);
    try std.testing.expectEqual(@as(u32, thread_count * ids_per_thread), final_id);
}

// Test: Concurrent client initialization and destruction
test "concurrent client init and deinit" {
    const allocator = std.testing.allocator;

    const thread_count = 20;
    const cycles = 10;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    const ThreadData = struct {
        allocator: std.mem.Allocator,
        cycles: usize,
    };

    const worker = struct {
        fn run(data: ThreadData) void {
            var i: usize = 0;
            while (i < data.cycles) : (i += 1) {
                var client = Client.init(data.allocator, .{
                    .socket_path = "/tmp/test.sock",
                    .skip_api_info = true,
                }) catch return;
                defer client.deinit();

                // Generate a few IDs
                _ = client.nextMessageId();
                _ = client.nextMessageId();
                _ = client.nextMessageId();
            }
        }
    }.run;

    // Spawn threads
    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const data = ThreadData{
            .allocator = allocator,
            .cycles = cycles,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{data});
    }

    // Wait for completion
    for (threads) |thread| {
        thread.join();
    }
}

// Test: Atomic operations maintain ordering
test "message ids maintain sequential order with concurrency" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    const thread_count = 8;
    const ids_per_thread = 500;

    const all_ids = try allocator.alloc(u32, thread_count * ids_per_thread);
    defer allocator.free(all_ids);

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    const ThreadContext = struct {
        client: *Client,
        ids: []u32,
        start: usize,
        count: usize,
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.count) : (i += 1) {
                ctx.ids[ctx.start + i] = ctx.client.nextMessageId();
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .ids = all_ids,
            .start = i * ids_per_thread,
            .count = ids_per_thread,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    // Sort the IDs and verify they form a complete sequence
    std.mem.sort(u32, all_ids, {}, comptime std.sort.asc(u32));

    for (all_ids, 0..) |id, idx| {
        try std.testing.expectEqual(@as(u32, @intCast(idx)), id);
    }
}

// Test: Concurrent access to independent resources
test "concurrent msgpack operations" {
    const allocator = std.testing.allocator;

    const thread_count = 10;
    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    const worker = struct {
        fn run(alloc: std.mem.Allocator) void {
            var i: usize = 0;
            while (i < 100) : (i += 1) {
                // Create msgpack values
                const val = msgpack.int(@as(i64, @intCast(i)));
                const str = msgpack.string(alloc, "test") catch return;

                // Array takes ownership of val and str, so we only free the array
                const arr = msgpack.array(alloc, &[_]msgpack.Value{ val, str }) catch return;
                defer msgpack.free(arr, alloc);

                // Create and free independent values
                const standalone = msgpack.boolean(true);
                _ = standalone;
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, worker, .{allocator});
    }

    for (threads) |thread| {
        thread.join();
    }
}

// Test: Arena allocator usage is safe per-client
test "concurrent clients with independent arenas" {
    const allocator = std.testing.allocator;

    const thread_count = 5;
    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    const worker = struct {
        fn run(alloc: std.mem.Allocator) void {
            var client = Client.init(alloc, .{
                .socket_path = "/tmp/test.sock",
                .skip_api_info = true,
            }) catch return;
            defer client.deinit();

            // Each client has its own arena
            const arena = client.api_arena.allocator();

            // Allocate some memory in the arena
            var i: usize = 0;
            while (i < 50) : (i += 1) {
                const mem = arena.alloc(u8, 100) catch return;
                @memset(mem, @intCast(i % 256));
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        threads[i] = try std.Thread.spawn(.{}, worker, .{allocator});
    }

    for (threads) |thread| {
        thread.join();
    }
}

// Test: Verify no data races in read-only operations
test "concurrent read-only client operations" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
        .skip_api_info = true,
    });
    defer client.deinit();

    const thread_count = 20;
    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    const ThreadContext = struct {
        client: *const Client,
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            // Only read operations
            var i: usize = 0;
            while (i < 1000) : (i += 1) {
                _ = ctx.client.isConnected();
                _ = ctx.client.options;
                _ = ctx.client.transport_kind;
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

// Test: Measure contention with atomic counters
test "atomic counter contention benchmark" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    const thread_count = 32; // More threads = more contention
    const iterations = 10000;

    var threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    const start_time = std.time.nanoTimestamp();

    const ThreadContext = struct {
        client: *Client,
        iterations: usize,
    };

    const worker = struct {
        fn run(ctx: ThreadContext) void {
            var i: usize = 0;
            while (i < ctx.iterations) : (i += 1) {
                _ = ctx.client.nextMessageId();
            }
        }
    }.run;

    var i: usize = 0;
    while (i < thread_count) : (i += 1) {
        const ctx = ThreadContext{
            .client = &client,
            .iterations = iterations,
        };
        threads[i] = try std.Thread.spawn(.{}, worker, .{ctx});
    }

    for (threads) |thread| {
        thread.join();
    }

    const end_time = std.time.nanoTimestamp();
    const elapsed_ms = @divFloor(end_time - start_time, std.time.ns_per_ms);

    const total_ops = thread_count * iterations;
    const ops_per_ms = @divFloor(total_ops, @max(elapsed_ms, 1));

    std.debug.print("\n[Concurrency Benchmark]\n", .{});
    std.debug.print("  Threads: {}\n", .{thread_count});
    std.debug.print("  Operations: {}\n", .{total_ops});
    std.debug.print("  Time: {}ms\n", .{elapsed_ms});
    std.debug.print("  Throughput: {} ops/ms\n", .{ops_per_ms});

    // Verify final count
    const final_id = client.next_msgid.load(.monotonic);
    try std.testing.expectEqual(@as(u32, @intCast(total_ops)), final_id);
}

// Test: Memory ordering with atomic operations
test "atomic operations have correct memory ordering" {
    const allocator = std.testing.allocator;

    var client = try Client.init(allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    var ready = std.atomic.Value(bool).init(false);
    var value = std.atomic.Value(u32).init(0);

    const ThreadContext = struct {
        client: *Client,
        ready: *std.atomic.Value(bool),
        value: *std.atomic.Value(u32),
    };

    const writer = struct {
        fn run(ctx: ThreadContext) void {
            // Generate an ID
            const id = ctx.client.nextMessageId();
            // Store the value
            ctx.value.store(id, .release);
            // Signal ready
            ctx.ready.store(true, .release);
        }
    }.run;

    const reader = struct {
        fn run(ctx: ThreadContext) !void {
            // Wait for ready signal
            while (!ctx.ready.load(.acquire)) {
                std.atomic.spinLoopHint();
            }
            // Read the value
            const val = ctx.value.load(.acquire);
            try std.testing.expectEqual(@as(u32, 0), val);
        }
    }.run;

    const ctx = ThreadContext{
        .client = &client,
        .ready = &ready,
        .value = &value,
    };

    const writer_thread = try std.Thread.spawn(.{}, writer, .{ctx});
    const reader_thread = try std.Thread.spawn(.{}, reader, .{ctx});

    writer_thread.join();
    reader_thread.join();
}
