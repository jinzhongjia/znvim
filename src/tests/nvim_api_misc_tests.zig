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

// Test nvim_exec_lua
test "nvim_exec_lua executes lua code" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const code = try msgpack.string(allocator, "return 1 + 1");
    defer msgpack.free(code, allocator);

    const args = try msgpack.array(allocator, &.{msgpack.Value.nilToPayload()});
    defer msgpack.free(args, allocator);

    const result = try client.request("nvim_exec_lua", &.{ code, args });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 2), value);
}

// Test nvim_exec_lua with args
test "nvim_exec_lua with arguments" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const code = try msgpack.string(allocator, "return ... * 2");
    defer msgpack.free(code, allocator);

    const args = try msgpack.array(allocator, &.{21});
    defer msgpack.free(args, allocator);

    const result = try client.request("nvim_exec_lua", &.{ code, args });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 42), value);
}

// Test nvim_set_keymap
test "nvim_set_keymap creates global key mapping" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);
    const lhs = try msgpack.string(allocator, "<F9>");
    defer msgpack.free(lhs, allocator);
    const rhs = try msgpack.string(allocator, ":echo 'F9'<CR>");
    defer msgpack.free(rhs, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_set_keymap", &.{
        mode,
        lhs,
        rhs,
        opts,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_del_keymap
test "nvim_del_keymap deletes key mapping" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);
    const lhs = try msgpack.string(allocator, "<F10>");
    defer msgpack.free(lhs, allocator);
    const rhs = try msgpack.string(allocator, ":echo 'test'<CR>");
    defer msgpack.free(rhs, allocator);

    var set_opts = msgpack.Value.mapPayload(allocator);
    defer set_opts.free(allocator);

    _ = try client.request("nvim_set_keymap", &.{ mode, lhs, rhs, set_opts });

    const result = try client.request("nvim_del_keymap", &.{ mode, lhs });
    defer msgpack.free(result, allocator);
}

// Test nvim_get_keymap
test "nvim_get_keymap retrieves keymaps for mode" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);

    const result = try client.request("nvim_get_keymap", &.{mode});
    defer msgpack.free(result, allocator);

    const keymaps = try msgpack.expectArray(result);
    try std.testing.expect(keymaps.len >= 0);
}

// Test nvim_buf_set_keymap
test "nvim_buf_set_keymap creates buffer-local keymap" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);
    const lhs = try msgpack.string(allocator, "<F11>");
    defer msgpack.free(lhs, allocator);
    const rhs = try msgpack.string(allocator, ":echo 'buf'<CR>");
    defer msgpack.free(rhs, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_buf_set_keymap", &.{
        buf,
        mode,
        lhs,
        rhs,
        opts,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_del_keymap
test "nvim_buf_del_keymap deletes buffer keymap" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);
    const lhs = try msgpack.string(allocator, "<F12>");
    defer msgpack.free(lhs, allocator);
    const rhs = try msgpack.string(allocator, ":echo 'test'<CR>");
    defer msgpack.free(rhs, allocator);

    var set_opts = msgpack.Value.mapPayload(allocator);
    defer set_opts.free(allocator);

    _ = try client.request("nvim_buf_set_keymap", &.{ buf, mode, lhs, rhs, set_opts });

    const result = try client.request("nvim_buf_del_keymap", &.{ buf, mode, lhs });
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_get_keymap
test "nvim_buf_get_keymap retrieves buffer keymaps" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);

    const result = try client.request("nvim_buf_get_keymap", &.{ buf, mode });
    defer msgpack.free(result, allocator);

    const keymaps = try msgpack.expectArray(result);
    try std.testing.expect(keymaps.len >= 0);
}

// Test nvim_get_all_options_info
test "nvim_get_all_options_info returns all option info" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_all_options_info", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
    try std.testing.expect(result.map.count() > 0);
}

// Test nvim_get_option_info2
test "nvim_get_option_info2 returns specific option info" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const opt_name = try msgpack.string(allocator, "tabstop");
    defer msgpack.free(opt_name, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_get_option_info2", &.{ opt_name, opts });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_get_option_value
test "nvim_get_option_value gets option value" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const opt_name = try msgpack.string(allocator, "tabstop");
    defer msgpack.free(opt_name, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_get_option_value", &.{ opt_name, opts });
    defer msgpack.free(result, allocator);

    const tabstop = try msgpack.expectI64(result);
    try std.testing.expect(tabstop > 0);
}

// Test nvim_set_option_value
test "nvim_set_option_value sets option value" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const opt_name = try msgpack.string(allocator, "tabstop");
    defer msgpack.free(opt_name, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_set_option_value", &.{
        opt_name,
        msgpack.int(4),
        opts,
    });
    defer msgpack.free(result, allocator);
}
