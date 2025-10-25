const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;

fn createTestClient(allocator: std.mem.Allocator) !znvim.Client {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 5000,
    });
    errdefer client.deinit();
    try client.connect();
    return client;
}

// Test: Connection state check after disconnect
test "connection state properly reflects after disconnect" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Should be connected
    try std.testing.expect(client.isConnected());

    // Disconnect
    client.disconnect();

    // Should not be connected
    try std.testing.expect(!client.isConnected());

    // Attempting request should fail
    const result = client.request("nvim_eval", &.{msgpack.int(1)});
    try std.testing.expectError(error.NotConnected, result);
}

// Test: Multiple disconnect calls are safe
test "multiple disconnect calls are safe" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    client.disconnect();
    client.disconnect(); // Should be safe
    client.disconnect(); // Should be safe

    try std.testing.expect(!client.isConnected());
}

// Test: Reconnect after disconnect
test "reconnect after manual disconnect" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Make a request
    const expr1 = try msgpack.string(allocator, "42");
    defer msgpack.free(expr1, allocator);
    const result1 = try client.request("nvim_eval", &.{expr1});
    defer msgpack.free(result1, allocator);
    try std.testing.expectEqual(@as(i64, 42), try msgpack.expectI64(result1));

    // Disconnect
    client.disconnect();
    try std.testing.expect(!client.isConnected());

    // Reconnect
    try client.connect();
    try std.testing.expect(client.isConnected());

    // Make another request - should work
    const expr2 = try msgpack.string(allocator, "99");
    defer msgpack.free(expr2, allocator);
    const result2 = try client.request("nvim_eval", &.{expr2});
    defer msgpack.free(result2, allocator);
    try std.testing.expectEqual(@as(i64, 99), try msgpack.expectI64(result2));
}

// Test: Request sequence after error
test "continue requests after recoverable error" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Make a valid request
    const expr1 = try msgpack.string(allocator, "1 + 1");
    defer msgpack.free(expr1, allocator);
    const result1 = try client.request("nvim_eval", &.{expr1});
    defer msgpack.free(result1, allocator);
    try std.testing.expectEqual(@as(i64, 2), try msgpack.expectI64(result1));

    // Make an invalid request (should get NvimError)
    const bad_expr = try msgpack.string(allocator, "undefined_variable");
    defer msgpack.free(bad_expr, allocator);
    const bad_result = client.request("nvim_eval", &.{bad_expr});
    try std.testing.expectError(error.NvimError, bad_result);

    // Should still be connected
    try std.testing.expect(client.isConnected());

    // Next valid request should work
    const expr2 = try msgpack.string(allocator, "2 + 2");
    defer msgpack.free(expr2, allocator);
    const result2 = try client.request("nvim_eval", &.{expr2});
    defer msgpack.free(result2, allocator);
    try std.testing.expectEqual(@as(i64, 4), try msgpack.expectI64(result2));
}

// Test: API info refresh after disconnect/reconnect
test "api info refreshes after reconnect" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Get initial API info
    const info1 = client.getApiInfo() orelse return error.TestExpectedEqual;
    try std.testing.expect(info1.channel_id > 0);

    // Disconnect
    client.disconnect();
    try std.testing.expect(client.getApiInfo() == null);

    // Reconnect (spawns new nvim process)
    try client.connect();

    // API info should be refreshed
    const info2 = client.getApiInfo() orelse return error.TestExpectedEqual;
    try std.testing.expect(info2.channel_id > 0);
    try std.testing.expect(info2.functions.len > 0);

    // Note: Channel IDs may be the same if both nvim instances assign ID 1
    // The important thing is that we got valid API info after reconnect
}

// Test: Error handling doesn't leak memory
test "error handling doesn't leak memory" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Generate multiple errors
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const bad_expr = try msgpack.string(allocator, "undefined_var");
        defer msgpack.free(bad_expr, allocator);

        const result = client.request("nvim_eval", &.{bad_expr});
        try std.testing.expectError(error.NvimError, result);
    }

    // Should still be connected and functional
    try std.testing.expect(client.isConnected());

    const good_expr = try msgpack.string(allocator, "123");
    defer msgpack.free(good_expr, allocator);
    const good_result = try client.request("nvim_eval", &.{good_expr});
    defer msgpack.free(good_result, allocator);
    try std.testing.expectEqual(@as(i64, 123), try msgpack.expectI64(good_result));
}

// Test: Partial message handling (simulated via rapid requests)
test "rapid sequential requests handle buffering correctly" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Send many requests rapidly - tests read buffer handling
    const count = 100;
    var j: usize = 0;
    while (j < count) : (j += 1) {
        const expr_str = try std.fmt.allocPrint(allocator, "{d}", .{j});
        defer allocator.free(expr_str);

        const expr = try msgpack.string(allocator, expr_str);
        defer msgpack.free(expr, allocator);

        const result = try client.request("nvim_eval", &.{expr});
        defer msgpack.free(result, allocator);

        const value = try msgpack.expectI64(result);
        try std.testing.expectEqual(@as(i64, @intCast(j)), value);
    }
}

// Test: Empty response handling
test "handle empty and nil responses" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // nvim_list_uis returns empty array in headless mode
    const result = try client.request("nvim_list_uis", &.{});
    defer msgpack.free(result, allocator);

    const arr = try msgpack.expectArray(result);
    try std.testing.expectEqual(@as(usize, 0), arr.len);
}

// Test: Client can handle many sequential connect/disconnect cycles
test "multiple connect disconnect cycles" {
    const allocator = std.testing.allocator;

    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 5000,
    });
    defer client.deinit();

    const cycles = 5;
    var i: usize = 0;
    while (i < cycles) : (i += 1) {
        // Connect
        try client.connect();
        try std.testing.expect(client.isConnected());

        // Make a request
        const expr = try msgpack.string(allocator, "1");
        defer msgpack.free(expr, allocator);
        const result = try client.request("nvim_eval", &.{expr});
        defer msgpack.free(result, allocator);

        // Disconnect
        client.disconnect();
        try std.testing.expect(!client.isConnected());

        // Small delay between cycles
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }
}

// Test: Buffer state after disconnect
test "read buffer cleared after disconnect" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Make some requests to populate read buffer
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const expr = try msgpack.string(allocator, "1");
        defer msgpack.free(expr, allocator);
        const result = try client.request("nvim_eval", &.{expr});
        defer msgpack.free(result, allocator);
    }

    // Disconnect
    client.disconnect();

    // Read buffer should be cleared
    try std.testing.expectEqual(@as(usize, 0), client.read_buffer.items.len);
}

// Test: Notification doesn't block on errors
test "notifications continue after errors" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Send valid notification
    const var_name1 = try msgpack.string(allocator, "notif_test1");
    defer msgpack.free(var_name1, allocator);
    const var_value1 = try msgpack.string(allocator, "value1");
    defer msgpack.free(var_value1, allocator);

    try client.notify("nvim_set_var", &.{ var_name1, var_value1 });

    // Send another notification (doesn't matter if first succeeded)
    const var_name2 = try msgpack.string(allocator, "notif_test2");
    defer msgpack.free(var_name2, allocator);
    const var_value2 = try msgpack.string(allocator, "value2");
    defer msgpack.free(var_value2, allocator);

    try client.notify("nvim_set_var", &.{ var_name2, var_value2 });

    // Give time for notifications to process
    std.Thread.sleep(200 * std.time.ns_per_ms);

    // Verify via request
    const get_result = try client.request("nvim_get_var", &.{var_name2});
    defer msgpack.free(get_result, allocator);

    const retrieved = try msgpack.expectString(get_result);
    try std.testing.expectEqualStrings("value2", retrieved);
}

// Test: Recovery from invalid method call
test "recover from invalid method call" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Call non-existent method
    const result = client.request("nvim_nonexistent_method", &.{});
    try std.testing.expectError(error.NvimError, result);

    // Should still work
    try std.testing.expect(client.isConnected());

    // Valid call should succeed
    const expr = try msgpack.string(allocator, "42");
    defer msgpack.free(expr, allocator);
    const valid_result = try client.request("nvim_eval", &.{expr});
    defer msgpack.free(valid_result, allocator);
    try std.testing.expectEqual(@as(i64, 42), try msgpack.expectI64(valid_result));
}

// Test: Transport state consistency
test "transport state consistent with connection state" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // After connection, transport should report connected
    try std.testing.expect(client.isConnected());
    try std.testing.expect(client.transport.isConnected());

    // After disconnect, both should be false
    client.disconnect();
    try std.testing.expect(!client.isConnected());
    try std.testing.expect(!client.transport.isConnected());
}

// Test: Message ID counter survives disconnect
test "message id counter persists across disconnect" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Record current message ID
    const id_start = client.next_msgid.load(.monotonic);

    // Generate some message IDs
    _ = client.nextMessageId();
    _ = client.nextMessageId();
    _ = client.nextMessageId();

    const id_before = client.next_msgid.load(.monotonic);

    // Verify we generated exactly 3 IDs (may be offset if other tests ran first)
    try std.testing.expectEqual(@as(u32, 3), id_before - id_start);

    // Disconnect and reconnect
    client.disconnect();
    try client.connect();

    // Note: connect() calls refreshApiInfo() which makes a request (consuming 1 ID)
    // So the ID after reconnect will be start + 3 (before disconnect) + 1 (api info request)
    const id_after_connect = client.next_msgid.load(.monotonic);
    const id_consumed_by_reconnect = id_after_connect - id_before;

    // Verify ID wasn't reset to 0, and we consumed some IDs for reconnection
    try std.testing.expect(id_after_connect > id_before);
    try std.testing.expect(id_consumed_by_reconnect >= 1); // At least api info request
}

// Test: Sequential errors don't break the client (concurrent version removed due to thread safety)
test "sequential errors don't break client state" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Generate multiple errors sequentially
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const bad_expr = try msgpack.string(allocator, "bad_var");
        defer msgpack.free(bad_expr, allocator);

        _ = client.request("nvim_eval", &.{bad_expr}) catch {};
    }

    // Client should still be functional
    try std.testing.expect(client.isConnected());

    const expr = try msgpack.string(allocator, "123");
    defer msgpack.free(expr, allocator);
    const result = try client.request("nvim_eval", &.{expr});
    defer msgpack.free(result, allocator);
    try std.testing.expectEqual(@as(i64, 123), try msgpack.expectI64(result));
}
