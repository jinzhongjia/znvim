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

// Test nvim_list_tabpages
test "nvim_list_tabpages lists all tabpages" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_list_tabpages", &.{});
    defer msgpack.free(result, allocator);

    const tabs = try msgpack.expectArray(result);
    try std.testing.expect(tabs.len > 0);
}

// Test nvim_get_current_tabpage
test "nvim_get_current_tabpage gets current tabpage" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
}

// Test nvim_set_current_tabpage
test "nvim_set_current_tabpage sets current tabpage" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const result = try client.request("nvim_set_current_tabpage", &.{tab});
    defer msgpack.free(result, allocator);
}

// Test nvim_tabpage_list_wins
test "nvim_tabpage_list_wins lists tabpage windows" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const result = try client.request("nvim_tabpage_list_wins", &.{tab});
    defer msgpack.free(result, allocator);

    const wins = try msgpack.expectArray(result);
    try std.testing.expect(wins.len > 0);
}

// Test nvim_tabpage_get_win
test "nvim_tabpage_get_win gets tabpage window" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const result = try client.request("nvim_tabpage_get_win", &.{tab});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
}

// Test nvim_tabpage_get_number
test "nvim_tabpage_get_number gets tabpage number" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const result = try client.request("nvim_tabpage_get_number", &.{tab});
    defer msgpack.free(result, allocator);

    const num = try msgpack.expectI64(result);
    try std.testing.expect(num > 0);
}

// Test nvim_tabpage_is_valid
test "nvim_tabpage_is_valid checks tabpage validity" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const result = try client.request("nvim_tabpage_is_valid", &.{tab});
    defer msgpack.free(result, allocator);

    const is_valid = try msgpack.expectBool(result);
    try std.testing.expect(is_valid);
}

// Test nvim_tabpage_get_var
test "nvim_tabpage_get_var gets tabpage variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const var_name = try msgpack.string(allocator, "tpvar");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_tabpage_set_var", &.{ tab, var_name, msgpack.int(123) });

    const result = try client.request("nvim_tabpage_get_var", &.{ tab, var_name });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 123), value);
}

// Test nvim_tabpage_set_var
test "nvim_tabpage_set_var sets tabpage variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const var_name = try msgpack.string(allocator, "tpsetvar");
    defer msgpack.free(var_name, allocator);

    const result = try client.request("nvim_tabpage_set_var", &.{ tab, var_name, msgpack.int(456) });
    defer msgpack.free(result, allocator);
}

// Test nvim_tabpage_del_var
test "nvim_tabpage_del_var deletes tabpage variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const var_name = try msgpack.string(allocator, "tpdelvar");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_tabpage_set_var", &.{ tab, var_name, msgpack.int(1) });

    const result = try client.request("nvim_tabpage_del_var", &.{ tab, var_name });
    defer msgpack.free(result, allocator);
}
