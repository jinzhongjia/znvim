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

// Test nvim_ui_attach
test "nvim_ui_attach attaches UI" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("rgb", msgpack.boolean(true));

    const result = try client.request("nvim_ui_attach", &.{
        msgpack.int(80),
        msgpack.int(24),
        opts,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_ui_detach
test "nvim_ui_detach detaches UI" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("rgb", msgpack.boolean(true));

    _ = try client.request("nvim_ui_attach", &.{
        msgpack.int(80),
        msgpack.int(24),
        opts,
    });

    const result = try client.request("nvim_ui_detach", &.{});
    defer msgpack.free(result, allocator);
}

// Test nvim_ui_try_resize
test "nvim_ui_try_resize resizes UI" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("rgb", msgpack.boolean(true));

    _ = try client.request("nvim_ui_attach", &.{
        msgpack.int(80),
        msgpack.int(24),
        opts,
    });

    const result = try client.request("nvim_ui_try_resize", &.{
        msgpack.int(100),
        msgpack.int(30),
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_ui_try_resize_grid
test "nvim_ui_try_resize_grid resizes grid" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("rgb", msgpack.boolean(true));
    try opts.mapPut("ext_multigrid", msgpack.boolean(true));

    _ = try client.request("nvim_ui_attach", &.{
        msgpack.int(80),
        msgpack.int(24),
        opts,
    });

    const result = try client.request("nvim_ui_try_resize_grid", &.{
        msgpack.int(1),
        msgpack.int(100),
        msgpack.int(30),
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_tabpage_get_number
test "nvim_tabpage_get_number returns tab number" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const result = try client.request("nvim_tabpage_get_number", &.{tab});
    defer msgpack.free(result, allocator);

    const num = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 1), num);
}

// Test nvim_exec with output capture
test "nvim_exec captures vimscript output" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const src = try msgpack.string(allocator, "echo 'test123'");
    defer msgpack.free(src, allocator);

    const result = try client.request("nvim_exec", &.{
        src,
        msgpack.boolean(true),
    });
    defer msgpack.free(result, allocator);

    const output = try msgpack.expectString(result);
    try std.testing.expectEqualStrings("test123", output);
}

// Test nvim_command
test "nvim_command executes ex command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "let g:test_var = 999");
    defer msgpack.free(cmd, allocator);

    const result = try client.request("nvim_command", &.{cmd});
    defer msgpack.free(result, allocator);
}

// Test nvim_call_dict_function
test "nvim_call_dict_function calls dictionary method" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const expr = try msgpack.string(allocator, "{'abs': function('abs')}");
    defer msgpack.free(expr, allocator);

    const dict_result = try client.request("nvim_eval", &.{expr});
    defer msgpack.free(dict_result, allocator);

    const method_name = try msgpack.string(allocator, "abs");
    defer msgpack.free(method_name, allocator);

    const args = try msgpack.array(allocator, &.{-50});
    defer msgpack.free(args, allocator);

    const result = try client.request("nvim_call_dict_function", &.{
        dict_result,
        method_name,
        args,
    });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 50), value);
}

// Test nvim_win_get_var
test "nvim_win_get_var retrieves window variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const var_name = try msgpack.string(allocator, "test_var");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_win_set_var", &.{ win, var_name, msgpack.int(100) });

    const result = try client.request("nvim_win_get_var", &.{ win, var_name });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 100), value);
}

// Test nvim_tabpage_get_var
test "nvim_tabpage_get_var retrieves tabpage variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const var_name = try msgpack.string(allocator, "tab_var");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_tabpage_set_var", &.{ tab, var_name, msgpack.int(200) });

    const result = try client.request("nvim_tabpage_get_var", &.{ tab, var_name });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 200), value);
}

// Test nvim_buf_get_var
test "nvim_buf_get_var retrieves buffer variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const var_name = try msgpack.string(allocator, "buf_test_var");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_buf_set_var", &.{ buf, var_name, msgpack.int(300) });

    const result = try client.request("nvim_buf_get_var", &.{ buf, var_name });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 300), value);
}

// Test nvim_get_context
test "nvim_get_context retrieves editor context" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_get_context", &.{opts});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_load_context
test "nvim_load_context loads context" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var ctx = msgpack.Value.mapPayload(allocator);
    defer ctx.free(allocator);

    const result = try client.request("nvim_load_context", &.{ctx});
    defer msgpack.free(result, allocator);
}

// Test nvim_get_commands
test "nvim_get_commands returns command dictionary" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_get_commands", &.{opts});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_buf_get_commands
test "nvim_buf_get_commands returns buffer commands" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_buf_get_commands", &.{ buf, opts });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}
