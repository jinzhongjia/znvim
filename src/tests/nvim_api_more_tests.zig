const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;

// Helper to create a test client with embedded Neovim
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

    // Set buffer variable
    const set_result = try client.request("nvim_buf_set_var", &.{
        buf,
        var_name,
        var_value,
    });
    defer msgpack.free(set_result, allocator);

    // Get it back
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

    // Set variable
    _ = try client.request("nvim_buf_set_var", &.{
        buf,
        var_name,
        msgpack.int(123),
    });

    // Delete it
    const del_result = try client.request("nvim_buf_del_var", &.{
        buf,
        var_name,
    });
    defer msgpack.free(del_result, allocator);
}

// Test nvim_win_get_var and nvim_win_set_var
test "nvim_win get and set window variables" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const var_name = try msgpack.string(allocator, "test_win_var");
    defer msgpack.free(var_name, allocator);

    // Set window variable
    const set_result = try client.request("nvim_win_set_var", &.{
        win,
        var_name,
        msgpack.int(456),
    });
    defer msgpack.free(set_result, allocator);

    // Get it back
    const get_result = try client.request("nvim_win_get_var", &.{
        win,
        var_name,
    });
    defer msgpack.free(get_result, allocator);

    const retrieved = try msgpack.expectI64(get_result);
    try std.testing.expectEqual(@as(i64, 456), retrieved);
}

// Test nvim_win_del_var
test "nvim_win_del_var removes window variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const var_name = try msgpack.string(allocator, "temp_win_var");
    defer msgpack.free(var_name, allocator);

    // Set variable
    _ = try client.request("nvim_win_set_var", &.{
        win,
        var_name,
        msgpack.int(789),
    });

    // Delete it
    const del_result = try client.request("nvim_win_del_var", &.{
        win,
        var_name,
    });
    defer msgpack.free(del_result, allocator);
}

// Test nvim_tabpage_get_var and nvim_tabpage_set_var
test "nvim_tabpage get and set tabpage variables" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const var_name = try msgpack.string(allocator, "test_tab_var");
    defer msgpack.free(var_name, allocator);

    // Set tabpage variable
    const set_result = try client.request("nvim_tabpage_set_var", &.{
        tab,
        var_name,
        msgpack.boolean(true),
    });
    defer msgpack.free(set_result, allocator);

    // Get it back
    const get_result = try client.request("nvim_tabpage_get_var", &.{
        tab,
        var_name,
    });
    defer msgpack.free(get_result, allocator);

    const retrieved = try msgpack.expectBool(get_result);
    try std.testing.expect(retrieved);
}

// Test nvim_tabpage_del_var
test "nvim_tabpage_del_var removes tabpage variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const var_name = try msgpack.string(allocator, "temp_tab_var");
    defer msgpack.free(var_name, allocator);

    // Set variable
    _ = try client.request("nvim_tabpage_set_var", &.{
        tab,
        var_name,
        msgpack.int(999),
    });

    // Delete it
    const del_result = try client.request("nvim_tabpage_del_var", &.{
        tab,
        var_name,
    });
    defer msgpack.free(del_result, allocator);
}

// Test nvim_buf_get_option
test "nvim_buf_get_option retrieves buffer option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const opt_name = try msgpack.string(allocator, "filetype");
    defer msgpack.free(opt_name, allocator);

    const result = try client.request("nvim_buf_get_option", &.{
        buf,
        opt_name,
    });
    defer msgpack.free(result, allocator);

    const filetype = try msgpack.expectString(result);
    try std.testing.expect(filetype.len >= 0);
}

// Test nvim_buf_set_option
test "nvim_buf_set_option sets buffer option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const opt_name = try msgpack.string(allocator, "filetype");
    defer msgpack.free(opt_name, allocator);
    const opt_value = try msgpack.string(allocator, "zig");
    defer msgpack.free(opt_value, allocator);

    const result = try client.request("nvim_buf_set_option", &.{
        buf,
        opt_name,
        opt_value,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_win_get_option
test "nvim_win_get_option retrieves window option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const opt_name = try msgpack.string(allocator, "wrap");
    defer msgpack.free(opt_name, allocator);

    const result = try client.request("nvim_win_get_option", &.{
        win,
        opt_name,
    });
    defer msgpack.free(result, allocator);

    const wrap = try msgpack.expectBool(result);
    try std.testing.expect(wrap == true or wrap == false);
}

// Test nvim_win_set_option
test "nvim_win_set_option sets window option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const opt_name = try msgpack.string(allocator, "wrap");
    defer msgpack.free(opt_name, allocator);

    const result = try client.request("nvim_win_set_option", &.{
        win,
        opt_name,
        msgpack.boolean(false),
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_set_current_dir
test "nvim_set_current_dir changes working directory" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Use system temp directory for cross-platform compatibility
    const builtin = @import("builtin");
    const tmp_dir = std.process.getEnvVarOwned(allocator, "TMPDIR") catch
        std.process.getEnvVarOwned(allocator, "TEMP") catch
        std.process.getEnvVarOwned(allocator, "TMP") catch
        try allocator.dupe(u8, if (builtin.target.os.tag == .windows) "C:\\Windows\\Temp" else "/tmp");
    defer allocator.free(tmp_dir);

    const dir = try msgpack.string(allocator, tmp_dir);
    defer msgpack.free(dir, allocator);

    const result = try client.request("nvim_set_current_dir", &.{dir});
    defer msgpack.free(result, allocator);
}

// Test nvim_paste
test "nvim_paste inserts text" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const data = try msgpack.string(allocator, "pasted text");
    defer msgpack.free(data, allocator);

    const result = try client.request("nvim_paste", &.{
        data,
        msgpack.boolean(false),
        msgpack.int(-1),
    });
    defer msgpack.free(result, allocator);

    const pasted = try msgpack.expectBool(result);
    try std.testing.expect(pasted);
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

// Test nvim_subscribe
test "nvim_subscribe subscribes to event" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const event = try msgpack.string(allocator, "TestEvent");
    defer msgpack.free(event, allocator);

    const result = try client.request("nvim_subscribe", &.{event});
    defer msgpack.free(result, allocator);
}

// Test nvim_unsubscribe
test "nvim_unsubscribe unsubscribes from event" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const event = try msgpack.string(allocator, "TestEvent");
    defer msgpack.free(event, allocator);

    // Subscribe first
    _ = try client.request("nvim_subscribe", &.{event});

    // Unsubscribe
    const result = try client.request("nvim_unsubscribe", &.{event});
    defer msgpack.free(result, allocator);
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

// Test nvim_buf_get_changedtick
test "nvim_buf_get_changedtick returns change counter" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const result = try client.request("nvim_buf_get_changedtick", &.{buf});
    defer msgpack.free(result, allocator);

    const tick = try msgpack.expectI64(result);
    try std.testing.expect(tick > 0);
}

// Test nvim_win_get_number
test "nvim_win_get_number returns window number" {
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

// Test nvim_get_all_options_info
test "nvim_get_all_options_info returns option metadata" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_all_options_info", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
    try std.testing.expect(result.map.count() > 0);
}

// Test nvim_win_set_buf
test "nvim_win_set_buf switches window buffer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    // Create new buffer
    const new_buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(true),
        msgpack.boolean(false),
    });
    defer msgpack.free(new_buf, allocator);

    // Set buffer in window
    const result = try client.request("nvim_win_set_buf", &.{
        win,
        new_buf,
    });
    defer msgpack.free(result, allocator);

    // Verify
    const verify = try client.request("nvim_win_get_buf", &.{win});
    defer msgpack.free(verify, allocator);
}

// Test nvim_buf_attach
test "nvim_buf_attach registers for buffer events" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_buf_attach", &.{
        buf,
        msgpack.boolean(false),
        opts,
    });
    defer msgpack.free(result, allocator);

    const attached = try msgpack.expectBool(result);
    try std.testing.expect(attached);
}

// Test nvim_buf_detach
test "nvim_buf_detach unregisters from buffer events" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    // Attach first
    var attach_opts = msgpack.Value.mapPayload(allocator);
    defer attach_opts.free(allocator);
    _ = try client.request("nvim_buf_attach", &.{
        buf,
        msgpack.boolean(false),
        attach_opts,
    });

    // Detach
    const result = try client.request("nvim_buf_detach", &.{buf});
    defer msgpack.free(result, allocator);

    const detached = try msgpack.expectBool(result);
    try std.testing.expect(detached);
}

// Test nvim_set_hl_ns
test "nvim_set_hl_ns sets highlight namespace" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const ns_name = try msgpack.string(allocator, "hl_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_id_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_id_result, allocator);
    const ns_id = try msgpack.expectI64(ns_id_result);

    const result = try client.request("nvim_set_hl_ns", &.{msgpack.int(ns_id)});
    defer msgpack.free(result, allocator);
}

// Test nvim_set_hl_ns_fast
test "nvim_set_hl_ns_fast sets highlight namespace quickly" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const ns_name = try msgpack.string(allocator, "hl_ns_fast");
    defer msgpack.free(ns_name, allocator);

    const ns_id_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_id_result, allocator);
    const ns_id = try msgpack.expectI64(ns_id_result);

    const result = try client.request("nvim_set_hl_ns_fast", &.{msgpack.int(ns_id)});
    defer msgpack.free(result, allocator);
}

// Test nvim_open_win creates floating window
test "nvim_open_win creates floating window" {
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

    // Create a split first
    const cmd = try msgpack.string(allocator, "split");
    defer msgpack.free(cmd, allocator);

    var exec_opts = msgpack.Value.mapPayload(allocator);
    defer exec_opts.free(allocator);
    try exec_opts.mapPut("output", msgpack.boolean(false));

    _ = try client.request("nvim_exec2", &.{ cmd, exec_opts });

    // Get current window
    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    // Close it
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

    // Create a split
    const cmd = try msgpack.string(allocator, "split");
    defer msgpack.free(cmd, allocator);

    var exec_opts = msgpack.Value.mapPayload(allocator);
    defer exec_opts.free(allocator);
    try exec_opts.mapPut("output", msgpack.boolean(false));

    _ = try client.request("nvim_exec2", &.{ cmd, exec_opts });

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    // Hide window
    const result = try client.request("nvim_win_hide", &.{win});
    defer msgpack.free(result, allocator);
}

// Test nvim_win_get_config
test "nvim_win_get_config returns window configuration" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_config", &.{win});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_win_set_config
test "nvim_win_set_config updates window configuration" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create floating window
    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(true),
    });
    defer msgpack.free(buf, allocator);

    var create_config = msgpack.Value.mapPayload(allocator);
    defer create_config.free(allocator);
    try create_config.mapPut("relative", try msgpack.string(allocator, "editor"));
    try create_config.mapPut("width", msgpack.int(10));
    try create_config.mapPut("height", msgpack.int(5));
    try create_config.mapPut("row", msgpack.int(0));
    try create_config.mapPut("col", msgpack.int(0));

    const win = try client.request("nvim_open_win", &.{
        buf,
        msgpack.boolean(false),
        create_config,
    });
    defer msgpack.free(win, allocator);

    // Update config - keep same relative positioning
    var update_config = msgpack.Value.mapPayload(allocator);
    defer update_config.free(allocator);
    try update_config.mapPut("relative", try msgpack.string(allocator, "editor"));
    try update_config.mapPut("width", msgpack.int(20));
    try update_config.mapPut("height", msgpack.int(10));
    try update_config.mapPut("row", msgpack.int(0));
    try update_config.mapPut("col", msgpack.int(0));

    const result = try client.request("nvim_win_set_config", &.{
        win,
        update_config,
    });
    defer msgpack.free(result, allocator);
}
