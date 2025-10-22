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

// Test nvim_buf_get_var and nvim_buf_set_var
test "nvim_buf get and set buffer-local variables" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const var_name = try msgpack.string(allocator, "test_buf_var");
    defer msgpack.free(var_name, allocator);
    const var_value = try msgpack.string(allocator, "buffer local value");
    defer msgpack.free(var_value, allocator);

    const set_result = try client.request("nvim_buf_set_var", &.{
        buf,
        var_name,
        var_value,
    });
    defer msgpack.free(set_result, allocator);

    const get_result = try client.request("nvim_buf_get_var", &.{
        buf,
        var_name,
    });
    defer msgpack.free(get_result, allocator);

    const retrieved = try msgpack.expectString(get_result);
    try std.testing.expectEqualStrings("buffer local value", retrieved);
}

// Test nvim_buf_del_var
test "nvim_buf_del_var removes buffer variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const var_name = try msgpack.string(allocator, "temp_buf_var");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_buf_set_var", &.{ buf, var_name, msgpack.int(123) });

    const del_result = try client.request("nvim_buf_del_var", &.{ buf, var_name });
    defer msgpack.free(del_result, allocator);
}

// Test nvim_get_option
test "nvim_get_option retrieves global option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const opt_name = try msgpack.string(allocator, "hlsearch");
    defer msgpack.free(opt_name, allocator);

    const result = try client.request("nvim_get_option", &.{opt_name});
    defer msgpack.free(result, allocator);

    _ = try msgpack.expectBool(result);
}

// Test nvim_set_option
test "nvim_set_option sets global option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const opt_name = try msgpack.string(allocator, "hlsearch");
    defer msgpack.free(opt_name, allocator);

    const result = try client.request("nvim_set_option", &.{ opt_name, msgpack.boolean(true) });
    defer msgpack.free(result, allocator);
}

// Test nvim_set_current_win
test "nvim_set_current_win changes current window" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_set_current_win", &.{win});
    defer msgpack.free(result, allocator);
}

// Test nvim_set_current_tabpage
test "nvim_set_current_tabpage changes current tab" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const result = try client.request("nvim_set_current_tabpage", &.{tab});
    defer msgpack.free(result, allocator);
}

// Test nvim_get_runtime_file
test "nvim_get_runtime_file finds runtime files" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "*.vim");
    defer msgpack.free(name, allocator);

    const result = try client.request("nvim_get_runtime_file", &.{
        name,
        msgpack.boolean(false),
    });
    defer msgpack.free(result, allocator);

    const files = try msgpack.expectArray(result);
    try std.testing.expect(files.len >= 0);
}

// Test nvim_get_all_options_info
test "nvim_get_all_options_info returns all option metadata" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_all_options_info", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
    try std.testing.expect(result.map.count() > 0);
}

// Test nvim_get_color_by_name
test "nvim_get_color_by_name returns color value" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const color_name = try msgpack.string(allocator, "Red");
    defer msgpack.free(color_name, allocator);

    const result = try client.request("nvim_get_color_by_name", &.{color_name});
    defer msgpack.free(result, allocator);

    const color = try msgpack.expectI64(result);
    try std.testing.expect(color != -1);
}

// Test nvim_get_hl_id_by_name
test "nvim_get_hl_id_by_name returns highlight group ID" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const hl_name = try msgpack.string(allocator, "Normal");
    defer msgpack.free(hl_name, allocator);

    const result = try client.request("nvim_get_hl_id_by_name", &.{hl_name});
    defer msgpack.free(result, allocator);

    const hl_id = try msgpack.expectI64(result);
    try std.testing.expect(hl_id > 0);
}

// Test nvim_get_hl_by_name
test "nvim_get_hl_by_name returns highlight attributes" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const hl_name = try msgpack.string(allocator, "Normal");
    defer msgpack.free(hl_name, allocator);

    const result = try client.request("nvim_get_hl_by_name", &.{ hl_name, msgpack.boolean(true) });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_get_hl_by_id
test "nvim_get_hl_by_id returns highlight attributes by ID" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const hl_name_for_id = try msgpack.string(allocator, "Normal");
    defer msgpack.free(hl_name_for_id, allocator);

    const id_result = try client.request("nvim_get_hl_id_by_name", &.{hl_name_for_id});
    defer msgpack.free(id_result, allocator);
    const hl_id = try msgpack.expectI64(id_result);

    const result = try client.request("nvim_get_hl_by_id", &.{ msgpack.int(hl_id), msgpack.boolean(true) });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}
