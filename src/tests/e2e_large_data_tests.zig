const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;

fn createTestClient(allocator: std.mem.Allocator) !znvim.Client {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 30000, // Long timeout for large data operations
    });
    errdefer client.deinit();
    try client.connect();
    return client;
}

// Test: Large string handling
test "large string: 100KB string transfer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const size = 100 * 1024; // 100KB
    const large_text = try allocator.alloc(u8, size);
    defer allocator.free(large_text);

    // Fill with pattern
    for (large_text, 0..) |*char, i| {
        char.* = @intCast((i % 26) + 'a');
    }

    // Set as variable
    const var_name = try msgpack.string(allocator, "large_string_var");
    defer msgpack.free(var_name, allocator);

    const var_value = try msgpack.string(allocator, large_text);
    defer msgpack.free(var_value, allocator);

    const set_result = try client.request("nvim_set_var", &.{ var_name, var_value });
    defer msgpack.free(set_result, allocator);

    // Get it back
    const get_result = try client.request("nvim_get_var", &.{var_name});
    defer msgpack.free(get_result, allocator);

    const retrieved = try msgpack.expectString(get_result);
    try std.testing.expectEqual(size, retrieved.len);
    try std.testing.expectEqualSlices(u8, large_text, retrieved);
}

// Test: Many small lines in buffer (simulating large file)
test "large buffer: 1000 lines of text" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf, allocator);

    const line_count = 1000;

    // Create array of lines
    var lines_array = try msgpack.Value.arrPayload(line_count, allocator);
    defer lines_array.free(allocator);

    var i: usize = 0;
    while (i < line_count) : (i += 1) {
        const line_text = try std.fmt.allocPrint(allocator, "Line number {d} with some content", .{i});
        defer allocator.free(line_text);

        lines_array.arr[i] = try msgpack.string(allocator, line_text);
    }

    // Set all lines at once
    const set_result = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        lines_array,
    });
    defer msgpack.free(set_result, allocator);

    // Verify line count
    const count_result = try client.request("nvim_buf_line_count", &.{buf});
    defer msgpack.free(count_result, allocator);

    const count = try msgpack.expectI64(count_result);
    try std.testing.expectEqual(@as(i64, line_count), count);

    // Read back a sample of lines to verify
    const get_result = try client.request("nvim_buf_get_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(10), // Just first 10 lines
        msgpack.boolean(false),
    });
    defer msgpack.free(get_result, allocator);

    const retrieved_lines = try msgpack.expectArray(get_result);
    try std.testing.expectEqual(@as(usize, 10), retrieved_lines.len);
}

// Test: Large array in variable
test "large array: 1000 element array" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const element_count = 1000;

    // Create large array
    var large_array = try msgpack.Value.arrPayload(element_count, allocator);
    defer large_array.free(allocator);

    var i: usize = 0;
    while (i < element_count) : (i += 1) {
        large_array.arr[i] = msgpack.int(@as(i64, @intCast(i)));
    }

    // Set as variable
    const var_name = try msgpack.string(allocator, "large_array_var");
    defer msgpack.free(var_name, allocator);

    const set_result = try client.request("nvim_set_var", &.{ var_name, large_array });
    defer msgpack.free(set_result, allocator);

    // Get it back
    const get_result = try client.request("nvim_get_var", &.{var_name});
    defer msgpack.free(get_result, allocator);

    const retrieved = try msgpack.expectArray(get_result);
    try std.testing.expectEqual(element_count, retrieved.len);

    // Verify some values
    try std.testing.expectEqual(@as(i64, 0), try msgpack.expectI64(retrieved[0]));
    try std.testing.expectEqual(@as(i64, 500), try msgpack.expectI64(retrieved[500]));
    try std.testing.expectEqual(@as(i64, 999), try msgpack.expectI64(retrieved[999]));
}

// Test: Deep nested structure
test "deep nesting: nested map structure" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create nested structure
    // Note: When a map is put into another map, ownership transfers
    // So only free the root map, not the nested ones
    var inner3 = msgpack.Value.mapPayload(allocator);
    try inner3.mapPut("level", msgpack.int(3));
    try inner3.mapPut("value", try msgpack.string(allocator, "deep"));

    var inner2 = msgpack.Value.mapPayload(allocator);
    try inner2.mapPut("level", msgpack.int(2));
    try inner2.mapPut("nested", inner3); // inner3 ownership transferred

    var inner1 = msgpack.Value.mapPayload(allocator);
    try inner1.mapPut("level", msgpack.int(1));
    try inner1.mapPut("nested", inner2); // inner2 ownership transferred

    var root = msgpack.Value.mapPayload(allocator);
    defer root.free(allocator); // Only free root, which will free all nested maps
    try root.mapPut("level", msgpack.int(0));
    try root.mapPut("nested", inner1); // inner1 ownership transferred

    // Set as variable
    const var_name = try msgpack.string(allocator, "nested_var");
    defer msgpack.free(var_name, allocator);

    const set_result = try client.request("nvim_set_var", &.{ var_name, root });
    defer msgpack.free(set_result, allocator);

    // Get it back
    const get_result = try client.request("nvim_get_var", &.{var_name});
    defer msgpack.free(get_result, allocator);

    // Verify it's a map
    try std.testing.expect(get_result == .map);
}

// Test: Multiple large operations in sequence
test "sequential large operations: multiple large transfers" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const iterations = 10;
    const size_per_iteration = 10 * 1024; // 10KB each

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        const large_text = try allocator.alloc(u8, size_per_iteration);
        defer allocator.free(large_text);

        // Fill with iteration-specific pattern
        for (large_text, 0..) |*char, j| {
            char.* = @intCast(((i + j) % 26) + 'a');
        }

        const var_name_str = try std.fmt.allocPrint(allocator, "large_var_{d}", .{i});
        defer allocator.free(var_name_str);

        const var_name = try msgpack.string(allocator, var_name_str);
        defer msgpack.free(var_name, allocator);

        const var_value = try msgpack.string(allocator, large_text);
        defer msgpack.free(var_value, allocator);

        const set_result = try client.request("nvim_set_var", &.{ var_name, var_value });
        defer msgpack.free(set_result, allocator);
    }
}

// Test: Large command string
test "large command: long vimscript command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create a long command by setting many variables at once
    // Build the command string manually
    var cmd_parts = std.ArrayList([]const u8).initCapacity(allocator, 100) catch unreachable;
    defer cmd_parts.deinit(allocator);

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const part = try std.fmt.allocPrint(allocator, "let g:var{d} = {d}", .{ i, i });
        try cmd_parts.append(allocator, part);
    }

    // Join with " | "
    var total_len: usize = 0;
    for (cmd_parts.items) |part| {
        total_len += part.len;
    }
    // Add space for separators (n-1 separators, each 3 bytes)
    if (cmd_parts.items.len > 0) {
        total_len += (cmd_parts.items.len - 1) * 3;
    }

    const cmd_str = try allocator.alloc(u8, total_len);
    defer allocator.free(cmd_str);

    var pos: usize = 0;
    for (cmd_parts.items, 0..) |part, idx| {
        @memcpy(cmd_str[pos..][0..part.len], part);
        pos += part.len;
        if (idx < cmd_parts.items.len - 1) {
            @memcpy(cmd_str[pos..][0..3], " | ");
            pos += 3;
        }
        allocator.free(part);
    }

    const cmd = try msgpack.string(allocator, cmd_str);
    defer msgpack.free(cmd, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("output", msgpack.boolean(false));

    const exec_result = try client.request("nvim_exec2", &.{ cmd, opts });
    defer msgpack.free(exec_result, allocator);

    // Verify one of the variables was set
    const check_var = try msgpack.string(allocator, "var50");
    defer msgpack.free(check_var, allocator);

    const get_result = try client.request("nvim_get_var", &.{check_var});
    defer msgpack.free(get_result, allocator);

    const value = try msgpack.expectI64(get_result);
    try std.testing.expectEqual(@as(i64, 50), value);
}

// Test: Batch of medium-sized requests
test "batch operations: 100 medium-sized requests" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const batch_size = 100;
    const text_size = 1024; // 1KB per request

    var successful: usize = 0;
    var i: usize = 0;
    while (i < batch_size) : (i += 1) {
        const text = try allocator.alloc(u8, text_size);
        defer allocator.free(text);

        for (text, 0..) |*char, j| {
            char.* = @intCast((j % 26) + 'a');
        }

        const var_name_str = try std.fmt.allocPrint(allocator, "batch_var_{d}", .{i});
        defer allocator.free(var_name_str);

        const var_name = try msgpack.string(allocator, var_name_str);
        defer msgpack.free(var_name, allocator);

        const var_value = try msgpack.string(allocator, text);
        defer msgpack.free(var_value, allocator);

        const result = client.request("nvim_set_var", &.{ var_name, var_value }) catch continue;
        defer msgpack.free(result, allocator);

        successful += 1;
    }

    try std.testing.expect(successful >= (batch_size * 90 / 100));
}

// Test: Large binary data
test "large binary data: transfer binary content" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const size = 50 * 1024; // 50KB of binary data
    const binary_data = try allocator.alloc(u8, size);
    defer allocator.free(binary_data);

    // Fill with binary pattern (all possible bytes)
    for (binary_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    const var_name = try msgpack.string(allocator, "binary_var");
    defer msgpack.free(var_name, allocator);

    const var_value = try msgpack.binary(allocator, binary_data);
    defer msgpack.free(var_value, allocator);

    const set_result = try client.request("nvim_set_var", &.{ var_name, var_value });
    defer msgpack.free(set_result, allocator);

    // Note: Neovim may convert binary to string, so we just verify it was set
    const get_result = try client.request("nvim_get_var", &.{var_name});
    defer msgpack.free(get_result, allocator);
}

// Test: Wide buffer (many columns)
test "wide lines: buffer with very long lines" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf, allocator);

    const line_count = 50;
    const line_length = 2000; // 2000 characters per line

    var lines_array = try msgpack.Value.arrPayload(line_count, allocator);
    defer lines_array.free(allocator);

    var i: usize = 0;
    while (i < line_count) : (i += 1) {
        const line_text = try allocator.alloc(u8, line_length);
        defer allocator.free(line_text);

        for (line_text, 0..) |*char, j| {
            char.* = @intCast((j % 26) + 'a');
        }

        lines_array.arr[i] = try msgpack.string(allocator, line_text);
    }

    const set_result = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        lines_array,
    });
    defer msgpack.free(set_result, allocator);

    // Verify line count
    const count_result = try client.request("nvim_buf_line_count", &.{buf});
    defer msgpack.free(count_result, allocator);

    const count = try msgpack.expectI64(count_result);
    try std.testing.expectEqual(@as(i64, line_count), count);
}

// Test: Streaming-like behavior (many small messages rapidly)
test "streaming simulation: rapid small message sequence" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const message_count = 500;
    const message_size = 100; // 100 bytes each

    var successful: usize = 0;
    var i: usize = 0;
    while (i < message_count) : (i += 1) {
        const text = try allocator.alloc(u8, message_size);
        defer allocator.free(text);

        for (text, 0..) |*char, j| {
            char.* = @intCast((j % 10) + '0');
        }

        const expr_str = try std.fmt.allocPrint(allocator, "'{s}'", .{text});
        defer allocator.free(expr_str);

        const expr = try msgpack.string(allocator, expr_str);
        defer msgpack.free(expr, allocator);

        const result = client.request("nvim_eval", &.{expr}) catch continue;
        defer msgpack.free(result, allocator);

        successful += 1;
    }

    try std.testing.expect(successful >= (message_count * 85 / 100));
}
