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

// Test nvim_open_win
test "nvim_open_win opens floating window" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(true),
    });
    defer msgpack.free(buf, allocator);

    var config = msgpack.Value.mapPayload(allocator);
    defer config.free(allocator);
    try config.mapPut("relative", try msgpack.string(allocator, "editor"));
    try config.mapPut("width", msgpack.int(20));
    try config.mapPut("height", msgpack.int(5));
    try config.mapPut("row", msgpack.int(0));
    try config.mapPut("col", msgpack.int(0));

    const result = try client.request("nvim_open_win", &.{
        buf,
        msgpack.boolean(false),
        config,
    });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
}

// Test nvim_win_close
test "nvim_win_close closes window" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "split");
    defer msgpack.free(cmd, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("output", msgpack.boolean(false));

    _ = try client.request("nvim_exec2", &.{ cmd, opts });

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_close", &.{
        win,
        msgpack.boolean(true),
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_win_hide
test "nvim_win_hide hides window" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "split");
    defer msgpack.free(cmd, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("output", msgpack.boolean(false));

    _ = try client.request("nvim_exec2", &.{ cmd, opts });

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_hide", &.{win});
    defer msgpack.free(result, allocator);
}

// Test nvim_win_del_var
test "nvim_win_del_var deletes window variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const var_name = try msgpack.string(allocator, "winvar_del");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_win_set_var", &.{ win, var_name, msgpack.int(1) });

    const result = try client.request("nvim_win_del_var", &.{ win, var_name });
    defer msgpack.free(result, allocator);
}

// Test nvim_win_get_var
test "nvim_win_get_var gets window variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const var_name = try msgpack.string(allocator, "winvar_get");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_win_set_var", &.{ win, var_name, msgpack.int(777) });

    const result = try client.request("nvim_win_get_var", &.{ win, var_name });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 777), value);
}

// Test nvim_win_set_var
test "nvim_win_set_var sets window variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const var_name = try msgpack.string(allocator, "winvar_set");
    defer msgpack.free(var_name, allocator);

    const result = try client.request("nvim_win_set_var", &.{ win, var_name, msgpack.int(888) });
    defer msgpack.free(result, allocator);
}

// Test nvim_create_namespace
test "nvim_create_namespace creates namespace" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "my_ns");
    defer msgpack.free(name, allocator);

    const result = try client.request("nvim_create_namespace", &.{name});
    defer msgpack.free(result, allocator);

    const ns_id = try msgpack.expectI64(result);
    try std.testing.expect(ns_id >= 0);
}

// Test nvim_get_namespaces
test "nvim_get_namespaces gets all namespaces" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "test_get_ns");
    defer msgpack.free(name, allocator);

    _ = try client.request("nvim_create_namespace", &.{name});

    const result = try client.request("nvim_get_namespaces", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_get_mode
test "nvim_get_mode gets current mode" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_mode", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
    const mode_val = result.map.get("mode") orelse return error.TestExpectedEqual;
    const mode = try msgpack.expectString(mode_val);
    try std.testing.expectEqualStrings("n", mode);
}

// Test nvim_get_api_info
test "nvim_get_api_info gets API information" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_api_info", &.{});
    defer msgpack.free(result, allocator);

    const arr = try msgpack.expectArray(result);
    try std.testing.expectEqual(@as(usize, 2), arr.len);
}

// Test nvim_strwidth
test "nvim_strwidth calculates width" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const text = try msgpack.string(allocator, "abc");
    defer msgpack.free(text, allocator);

    const result = try client.request("nvim_strwidth", &.{text});
    defer msgpack.free(result, allocator);

    const width = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 3), width);
}

// Test nvim_list_uis
test "nvim_list_uis lists UIs" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_list_uis", &.{});
    defer msgpack.free(result, allocator);

    const uis = try msgpack.expectArray(result);
    try std.testing.expect(uis.len >= 0);
}

// Test nvim_feedkeys
test "nvim_feedkeys feeds keys" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const keys = try msgpack.string(allocator, "i");
    defer msgpack.free(keys, allocator);
    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);

    const result = try client.request("nvim_feedkeys", &.{
        keys,
        mode,
        msgpack.boolean(false),
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_input
test "nvim_input sends input" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const keys = try msgpack.string(allocator, "a");
    defer msgpack.free(keys, allocator);

    const result = try client.request("nvim_input", &.{keys});
    defer msgpack.free(result, allocator);

    const written = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 1), written);
}

// Test nvim_replace_termcodes
test "nvim_replace_termcodes replaces codes" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const str = try msgpack.string(allocator, "<CR>");
    defer msgpack.free(str, allocator);

    const result = try client.request("nvim_replace_termcodes", &.{
        str,
        msgpack.boolean(true),
        msgpack.boolean(true),
        msgpack.boolean(true),
    });
    defer msgpack.free(result, allocator);

    const replaced = try msgpack.expectString(result);
    try std.testing.expect(replaced.len > 0);
}

// Test nvim_out_write
test "nvim_out_write writes to output" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const text = try msgpack.string(allocator, "test\n");
    defer msgpack.free(text, allocator);

    const result = try client.request("nvim_out_write", &.{text});
    defer msgpack.free(result, allocator);
}

// Test nvim_err_write
test "nvim_err_write writes to error" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const text = try msgpack.string(allocator, "error\n");
    defer msgpack.free(text, allocator);

    const result = try client.request("nvim_err_write", &.{text});
    defer msgpack.free(result, allocator);
}

// Test nvim_command_output
test "nvim_command_output returns output" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "echo 'output'");
    defer msgpack.free(cmd, allocator);

    const result = try client.request("nvim_command_output", &.{cmd});
    defer msgpack.free(result, allocator);

    const output = try msgpack.expectString(result);
    try std.testing.expectEqualStrings("output", output);
}

// Test nvim_subscribe
test "nvim_subscribe subscribes to event" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const event = try msgpack.string(allocator, "MyEvent");
    defer msgpack.free(event, allocator);

    const result = try client.request("nvim_subscribe", &.{event});
    defer msgpack.free(result, allocator);
}

// Test nvim_unsubscribe
test "nvim_unsubscribe unsubscribes from event" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const event = try msgpack.string(allocator, "MyEvent2");
    defer msgpack.free(event, allocator);

    _ = try client.request("nvim_subscribe", &.{event});

    const result = try client.request("nvim_unsubscribe", &.{event});
    defer msgpack.free(result, allocator);
}

// Test nvim_get_color_by_name
test "nvim_get_color_by_name gets color value" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "Red");
    defer msgpack.free(name, allocator);

    const result = try client.request("nvim_get_color_by_name", &.{name});
    defer msgpack.free(result, allocator);

    const color = try msgpack.expectI64(result);
    try std.testing.expect(color != -1);
}

// Test nvim_get_color_map
test "nvim_get_color_map gets color map" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_color_map", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_get_context
test "nvim_get_context gets context" {
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

// Test nvim_parse_expression
test "nvim_parse_expression parses expression" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const expr = try msgpack.string(allocator, "1+1");
    defer msgpack.free(expr, allocator);
    const flags = try msgpack.string(allocator, "");
    defer msgpack.free(flags, allocator);

    const result = try client.request("nvim_parse_expression", &.{
        expr,
        flags,
        msgpack.boolean(false),
    });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
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

    _ = try client.request("nvim_ui_attach", &.{ msgpack.int(80), msgpack.int(24), opts });

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

    _ = try client.request("nvim_ui_attach", &.{ msgpack.int(80), msgpack.int(24), opts });

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

    _ = try client.request("nvim_ui_attach", &.{ msgpack.int(80), msgpack.int(24), opts });

    const result = try client.request("nvim_ui_try_resize_grid", &.{
        msgpack.int(1),
        msgpack.int(100),
        msgpack.int(30),
    });
    defer msgpack.free(result, allocator);
}


// Test nvim_select_popupmenu_item
test "nvim_select_popupmenu_item selects item" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_select_popupmenu_item", &.{
        msgpack.int(-1),
        msgpack.boolean(false),
        msgpack.boolean(false),
        opts,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_notify
test "nvim_notify sends notification" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const msg = try msgpack.string(allocator, "Test");
    defer msgpack.free(msg, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_notify", &.{
        msg,
        msgpack.int(1),
        opts,
    });
    defer msgpack.free(result, allocator);
}
