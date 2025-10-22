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

// Test nvim_list_wins
test "nvim_list_wins lists all windows" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_list_wins", &.{});
    defer msgpack.free(result, allocator);

    const wins = try msgpack.expectArray(result);
    try std.testing.expect(wins.len > 0);
}

// Test nvim_get_current_win
test "nvim_get_current_win gets current window" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
}

// Test nvim_set_current_win
test "nvim_set_current_win sets current window" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_set_current_win", &.{win});
    defer msgpack.free(result, allocator);
}

// Test nvim_win_get_buf
test "nvim_win_get_buf gets window buffer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_buf", &.{win});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
}

// Test nvim_win_set_buf
test "nvim_win_set_buf sets window buffer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(true),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf, allocator);

    const result = try client.request("nvim_win_set_buf", &.{ win, buf });
    defer msgpack.free(result, allocator);
}

// Test nvim_win_get_cursor
test "nvim_win_get_cursor gets cursor position" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_cursor", &.{win});
    defer msgpack.free(result, allocator);

    const pos = try msgpack.expectArray(result);
    try std.testing.expectEqual(@as(usize, 2), pos.len);
}

// Test nvim_win_set_cursor
test "nvim_win_set_cursor sets cursor position" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const pos = try msgpack.array(allocator, &.{ 1, 0 });
    defer msgpack.free(pos, allocator);

    const result = try client.request("nvim_win_set_cursor", &.{ win, pos });
    defer msgpack.free(result, allocator);
}

// Test nvim_win_get_height
test "nvim_win_get_height gets window height" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_height", &.{win});
    defer msgpack.free(result, allocator);

    const height = try msgpack.expectI64(result);
    try std.testing.expect(height > 0);
}

// Test nvim_win_set_height
test "nvim_win_set_height sets window height" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_set_height", &.{ win, msgpack.int(10) });
    defer msgpack.free(result, allocator);
}

// Test nvim_win_get_width
test "nvim_win_get_width gets window width" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_width", &.{win});
    defer msgpack.free(result, allocator);

    const width = try msgpack.expectI64(result);
    try std.testing.expect(width > 0);
}

// Test nvim_win_set_width
test "nvim_win_set_width sets window width" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_set_width", &.{ win, msgpack.int(80) });
    defer msgpack.free(result, allocator);
}

// Test nvim_win_get_position
test "nvim_win_get_position gets window position" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_position", &.{win});
    defer msgpack.free(result, allocator);

    const pos = try msgpack.expectArray(result);
    try std.testing.expectEqual(@as(usize, 2), pos.len);
}

// Test nvim_win_get_tabpage
test "nvim_win_get_tabpage gets window tabpage" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_tabpage", &.{win});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
}

// Test nvim_win_get_number
test "nvim_win_get_number gets window number" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_number", &.{win});
    defer msgpack.free(result, allocator);

    const num = try msgpack.expectI64(result);
    try std.testing.expect(num > 0);
}

// Test nvim_win_is_valid
test "nvim_win_is_valid checks window validity" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_is_valid", &.{win});
    defer msgpack.free(result, allocator);

    const is_valid = try msgpack.expectBool(result);
    try std.testing.expect(is_valid);
}

// Test nvim_win_get_config
test "nvim_win_get_config gets window config" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_config", &.{win});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_win_get_option
test "nvim_win_get_option gets window option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const opt = try msgpack.string(allocator, "wrap");
    defer msgpack.free(opt, allocator);

    const result = try client.request("nvim_win_get_option", &.{ win, opt });
    defer msgpack.free(result, allocator);

    _ = try msgpack.expectBool(result);
}

// Test nvim_win_set_option
test "nvim_win_set_option sets window option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const opt = try msgpack.string(allocator, "wrap");
    defer msgpack.free(opt, allocator);

    const result = try client.request("nvim_win_set_option", &.{ win, opt, msgpack.boolean(false) });
    defer msgpack.free(result, allocator);
}
