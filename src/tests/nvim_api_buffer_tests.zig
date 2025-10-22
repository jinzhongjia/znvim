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

// Test nvim_buf_line_count
test "nvim_buf_line_count returns line count" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const result = try client.request("nvim_buf_line_count", &.{buf});
    defer msgpack.free(result, allocator);

    const count = try msgpack.expectI64(result);
    try std.testing.expect(count >= 1);
}

// Test nvim_buf_get_offset
test "nvim_buf_get_offset returns byte offset" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const result = try client.request("nvim_buf_get_offset", &.{
        buf,
        msgpack.int(0),
    });
    defer msgpack.free(result, allocator);

    const offset = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 0), offset);
}

// Test nvim_buf_is_valid
test "nvim_buf_is_valid checks buffer validity" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const result = try client.request("nvim_buf_is_valid", &.{buf});
    defer msgpack.free(result, allocator);

    const is_valid = try msgpack.expectBool(result);
    try std.testing.expect(is_valid);
}

// Test nvim_buf_get_mark
test "nvim_buf_get_mark gets buffer mark position" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const mark_name = try msgpack.string(allocator, "\"");
    defer msgpack.free(mark_name, allocator);

    const result = try client.request("nvim_buf_get_mark", &.{ buf, mark_name });
    defer msgpack.free(result, allocator);

    const pos = try msgpack.expectArray(result);
    try std.testing.expectEqual(@as(usize, 2), pos.len);
}

// Test nvim_buf_get_name
test "nvim_buf_get_name returns buffer name" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const result = try client.request("nvim_buf_get_name", &.{buf});
    defer msgpack.free(result, allocator);

    const name = try msgpack.expectString(result);
    try std.testing.expect(name.len >= 0);
}

// Test nvim_buf_set_name
test "nvim_buf_set_name sets buffer name" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(true),
    });
    defer msgpack.free(buf, allocator);

    const name = try msgpack.string(allocator, "test_buf.txt");
    defer msgpack.free(name, allocator);

    const result = try client.request("nvim_buf_set_name", &.{ buf, name });
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_is_loaded
test "nvim_buf_is_loaded checks if buffer loaded" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const result = try client.request("nvim_buf_is_loaded", &.{buf});
    defer msgpack.free(result, allocator);

    const is_loaded = try msgpack.expectBool(result);
    try std.testing.expect(is_loaded);
}

// Test nvim_buf_delete
test "nvim_buf_delete deletes buffer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(true),
    });
    defer msgpack.free(buf, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("force", msgpack.boolean(true));

    const result = try client.request("nvim_buf_delete", &.{ buf, opts });
    defer msgpack.free(result, allocator);
}

// Test nvim_create_buf
test "nvim_create_buf creates new buffer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(true),
    });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
}

// Test nvim_list_bufs
test "nvim_list_bufs lists all buffers" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_list_bufs", &.{});
    defer msgpack.free(result, allocator);

    const bufs = try msgpack.expectArray(result);
    try std.testing.expect(bufs.len > 0);
}

// Test nvim_get_current_buf
test "nvim_get_current_buf returns current buffer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
}

// Test nvim_set_current_buf
test "nvim_set_current_buf changes current buffer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const new_buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(true),
        msgpack.boolean(false),
    });
    defer msgpack.free(new_buf, allocator);

    const result = try client.request("nvim_set_current_buf", &.{new_buf});
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_get_lines
test "nvim_buf_get_lines gets buffer lines" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const result = try client.request("nvim_buf_get_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(result, allocator);

    const lines = try msgpack.expectArray(result);
    try std.testing.expect(lines.len >= 0);
}

// Test nvim_buf_get_text
test "nvim_buf_get_text gets text in range" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_buf_get_text", &.{
        buf,
        msgpack.int(0),
        msgpack.int(0),
        msgpack.int(0),
        msgpack.int(-1),
        opts,
    });
    defer msgpack.free(result, allocator);

    const text = try msgpack.expectArray(result);
    try std.testing.expect(text.len >= 0);
}
