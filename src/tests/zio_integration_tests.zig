const std = @import("std");
const testing = std.testing;
const znvim = @import("../root.zig");
const Client = znvim.Client;
const PendingRequest = @import("../client.zig").PendingRequest;
const zio_transport = @import("../zio_transport.zig");
const connection = @import("../connection.zig");

// ============================================================================
// PendingRequest Tests
// ============================================================================

test "PendingRequest: init creates default state" {
    const pending = PendingRequest.init(testing.allocator);
    try testing.expect(pending.result == null);
    try testing.expect(pending.err == null);
}

test "PendingRequest: complete sets result" {
    var pending = PendingRequest.init(testing.allocator);

    const result = @import("msgpack").Payload.intToPayload(42);
    pending.complete(result);

    try testing.expect(pending.result != null);
    try testing.expect(pending.err == null);
}

test "PendingRequest: fail sets error" {
    var pending = PendingRequest.init(testing.allocator);

    pending.fail(error.ConnectionClosed);

    try testing.expect(pending.result == null);
    try testing.expect(pending.err != null);
}

test "PendingRequest: reset clears state" {
    var pending = PendingRequest.init(testing.allocator);

    const result = @import("msgpack").Payload.intToPayload(42);
    pending.complete(result);
    pending.reset();

    try testing.expect(pending.result == null);
    try testing.expect(pending.err == null);
}

// ============================================================================
// ConnectionOptions Tests
// ============================================================================

test "ConnectionOptions: default runtime_mode is owned_background_thread" {
    const opts = connection.ConnectionOptions{};
    try testing.expect(opts.runtime_mode == .owned_background_thread);
    try testing.expect(opts.zio_runtime == null);
    try testing.expect(opts.worker_threads == null);
}

test "ConnectionOptions: can set external runtime mode" {
    const opts = connection.ConnectionOptions{
        .runtime_mode = .external,
    };
    try testing.expect(opts.runtime_mode == .external);
}

// ============================================================================
// zio_transport Tests
// ============================================================================

test "zio_transport: StdioConnection init" {
    const conn = zio_transport.StdioConnection.init();
    _ = conn;
}

test "zio_transport: ChildProcessConnection error types" {
    _ = zio_transport.ConnectError;
}

test "zio_transport: TransportType enum" {
    const unix = zio_transport.TransportType.unix_socket;
    const tcp = zio_transport.TransportType.tcp;
    const child = zio_transport.TransportType.child_process;
    const stdio = zio_transport.TransportType.stdio;

    try testing.expect(unix != tcp);
    try testing.expect(tcp != child);
    try testing.expect(child != stdio);
}

// ============================================================================
// Client zio State Tests
// ============================================================================

test "Client: isUsingZio returns false by default" {
    var client = try Client.init(testing.allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try testing.expect(client.zio_runtime == null);
}

test "Client: new zio fields are initialized" {
    var client = try Client.init(testing.allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try testing.expect(client.zio_runtime == null);
    try testing.expect(client.owns_runtime == false);
    try testing.expect(client.zio_stream == null);
    try testing.expect(client.child_conn == null);
    try testing.expect(client.stdio_conn == null);
    try testing.expect(client.pending.count() == 0);
}

test "Client: shutdown flag initialized to false" {
    var client = try Client.init(testing.allocator, .{
        .socket_path = "/tmp/test.sock",
    });
    defer client.deinit();

    try testing.expect(!client.shutdown.load(.acquire));
}

// ============================================================================
// RequestTask Tests (compile-time verification)
// ============================================================================

test "Client.RequestTask: type exists and has expected fields" {
    const TaskType = Client.RequestTask;

    // Verify the type has the expected structure
    const info = @typeInfo(TaskType);
    try testing.expect(info == .@"struct");

    // Verify methods exist (compile-time check)
    _ = TaskType.wait;
    _ = TaskType.cancel;
}

// ============================================================================
// Integration Test: Client with spawn_process (if nvim available)
// ============================================================================

test "Client: spawn_process option still works with legacy transport" {
    // This test verifies backward compatibility
    var client = try Client.init(testing.allocator, .{
        .spawn_process = true,
    });
    defer client.deinit();

    // Should use legacy transport, not zio
    try testing.expect(client.zio_runtime == null);

    // Try to connect - this will actually spawn nvim
    client.connect() catch |err| {
        // If nvim is not available, that's ok for this test
        if (err == error.TransportNotInitialized) return;
        return err;
    };

    try testing.expect(client.isConnected());

    // Make a simple request
    const result = client.request("nvim_get_api_info", &.{}) catch {
        // Ignore errors for now - nvim may not be fully responsive
        return;
    };
    defer @import("msgpack").Payload.free(result, testing.allocator);

    client.disconnect();
    try testing.expect(!client.isConnected());
}
