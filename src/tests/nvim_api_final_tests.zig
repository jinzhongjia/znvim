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

// Test nvim_set_current_line
test "nvim_set_current_line updates current line content" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const line = try msgpack.string(allocator, "new line content");
    defer msgpack.free(line, allocator);

    const result = try client.request("nvim_set_current_line", &.{line});
    defer msgpack.free(result, allocator);

    const verify = try client.request("nvim_get_current_line", &.{});
    defer msgpack.free(verify, allocator);

    const retrieved = try msgpack.expectString(verify);
    try std.testing.expectEqualStrings("new line content", retrieved);
}

// Test nvim_del_current_line
test "nvim_del_current_line deletes the current line" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const line = try msgpack.string(allocator, "line to delete");
    defer msgpack.free(line, allocator);

    _ = try client.request("nvim_set_current_line", &.{line});

    const result = try client.request("nvim_del_current_line", &.{});
    defer msgpack.free(result, allocator);
}


// Test nvim_subscribe and nvim_unsubscribe
test "nvim subscribe and unsubscribe to events" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const event = try msgpack.string(allocator, "CustomEvent");
    defer msgpack.free(event, allocator);

    const sub_result = try client.request("nvim_subscribe", &.{event});
    defer msgpack.free(sub_result, allocator);

    const unsub_result = try client.request("nvim_unsubscribe", &.{event});
    defer msgpack.free(unsub_result, allocator);
}

// Test nvim_get_hl_ns
test "nvim_get_hl_ns returns current highlight namespace" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_get_hl_ns", &.{opts});
    defer msgpack.free(result, allocator);

    const ns_id = try msgpack.expectI64(result);
    try std.testing.expect(ns_id >= 0);
}

// Test nvim_set_hl with foreground color
test "nvim_set_hl sets highlight with fg color" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const hl_name = try msgpack.string(allocator, "CustomHL");
    defer msgpack.free(hl_name, allocator);

    var hl_def = msgpack.Value.mapPayload(allocator);
    defer hl_def.free(allocator);
    try hl_def.mapPut("fg", try msgpack.string(allocator, "#FF0000"));

    const result = try client.request("nvim_set_hl", &.{
        msgpack.int(0),
        hl_name,
        hl_def,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_set_hl with multiple attributes
test "nvim_set_hl sets highlight with multiple attributes" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const hl_name = try msgpack.string(allocator, "CustomBold");
    defer msgpack.free(hl_name, allocator);

    var hl_def = msgpack.Value.mapPayload(allocator);
    defer hl_def.free(allocator);
    try hl_def.mapPut("bold", msgpack.boolean(true));
    try hl_def.mapPut("italic", msgpack.boolean(true));

    const result = try client.request("nvim_set_hl", &.{
        msgpack.int(0),
        hl_name,
        hl_def,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_get_hl for custom highlight
test "nvim_get_hl retrieves custom highlight" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // First set a highlight
    const hl_name_set = try msgpack.string(allocator, "TestGetHL");
    defer msgpack.free(hl_name_set, allocator);

    var hl_def = msgpack.Value.mapPayload(allocator);
    defer hl_def.free(allocator);
    try hl_def.mapPut("fg", try msgpack.string(allocator, "#00FF00"));

    _ = try client.request("nvim_set_hl", &.{ msgpack.int(0), hl_name_set, hl_def });

    // Get it back
    var get_opts = msgpack.Value.mapPayload(allocator);
    defer get_opts.free(allocator);
    try get_opts.mapPut("name", try msgpack.string(allocator, "TestGetHL"));

    const result = try client.request("nvim_get_hl", &.{ msgpack.int(0), get_opts });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_parse_cmd with options
test "nvim_parse_cmd parses command with options" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "split");
    defer msgpack.free(cmd, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_parse_cmd", &.{ cmd, opts });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_create_augroup
test "nvim_create_augroup creates new group" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const group_name = try msgpack.string(allocator, "TestAuGroup");
    defer msgpack.free(group_name, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("clear", msgpack.boolean(true));

    const result = try client.request("nvim_create_augroup", &.{ group_name, opts });
    defer msgpack.free(result, allocator);

    const group_id = try msgpack.expectI64(result);
    try std.testing.expect(group_id > 0);
}

// Test nvim_del_augroup_by_id
test "nvim_del_augroup_by_id removes augroup" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const group_name = try msgpack.string(allocator, "TestDelGroup");
    defer msgpack.free(group_name, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("clear", msgpack.boolean(true));

    const create_result = try client.request("nvim_create_augroup", &.{ group_name, opts });
    defer msgpack.free(create_result, allocator);
    const group_id = try msgpack.expectI64(create_result);

    const result = try client.request("nvim_del_augroup_by_id", &.{msgpack.int(group_id)});
    defer msgpack.free(result, allocator);
}

// Test nvim_del_augroup_by_name
test "nvim_del_augroup_by_name removes augroup by name" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const group_name = try msgpack.string(allocator, "TestDelByName");
    defer msgpack.free(group_name, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("clear", msgpack.boolean(true));

    _ = try client.request("nvim_create_augroup", &.{ group_name, opts });

    const result = try client.request("nvim_del_augroup_by_name", &.{group_name});
    defer msgpack.free(result, allocator);
}

// Test nvim_win_close
test "nvim_win_close closes window with force" {
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

    var exec_opts = msgpack.Value.mapPayload(allocator);
    defer exec_opts.free(allocator);
    try exec_opts.mapPut("output", msgpack.boolean(false));

    _ = try client.request("nvim_exec2", &.{ cmd, exec_opts });

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

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

// Test nvim_open_win with floating window
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

// Test nvim_win_set_config updates config
test "nvim_win_set_config updates floating window config" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

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

    var update_config = msgpack.Value.mapPayload(allocator);
    defer update_config.free(allocator);
    try update_config.mapPut("relative", try msgpack.string(allocator, "editor"));
    try update_config.mapPut("width", msgpack.int(20));
    try update_config.mapPut("height", msgpack.int(10));
    try update_config.mapPut("row", msgpack.int(0));
    try update_config.mapPut("col", msgpack.int(0));

    const result = try client.request("nvim_win_set_config", &.{ win, update_config });
    defer msgpack.free(result, allocator);
}


// Test nvim_set_current_dir
test "nvim_set_current_dir changes working directory" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const dir = try msgpack.string(allocator, "/tmp");
    defer msgpack.free(dir, allocator);

    const result = try client.request("nvim_set_current_dir", &.{dir});
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_get_changedtick
test "nvim_buf_get_changedtick returns buffer change counter" {
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

// Test nvim_list_chans
test "nvim_list_chans returns channel list" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_list_chans", &.{});
    defer msgpack.free(result, allocator);

    const chans = try msgpack.expectArray(result);
    try std.testing.expect(chans.len > 0);
}

// Test nvim_select_popupmenu_item
test "nvim_select_popupmenu_item with no menu" {
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

// Test nvim_create_user_command
test "nvim_create_user_command creates custom command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd_name = try msgpack.string(allocator, "TestUserCmd");
    defer msgpack.free(cmd_name, allocator);
    const cmd_impl = try msgpack.string(allocator, "echo 'custom command'");
    defer msgpack.free(cmd_impl, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_create_user_command", &.{
        cmd_name,
        cmd_impl,
        opts,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_del_user_command
test "nvim_del_user_command removes custom command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd_name = try msgpack.string(allocator, "TestDelUserCmd");
    defer msgpack.free(cmd_name, allocator);
    const cmd_impl = try msgpack.string(allocator, "echo 'test'");
    defer msgpack.free(cmd_impl, allocator);

    var create_opts = msgpack.Value.mapPayload(allocator);
    defer create_opts.free(allocator);

    _ = try client.request("nvim_create_user_command", &.{
        cmd_name,
        cmd_impl,
        create_opts,
    });

    const result = try client.request("nvim_del_user_command", &.{cmd_name});
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_create_user_command
test "nvim_buf_create_user_command creates buffer-local command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const cmd_name = try msgpack.string(allocator, "BufTestCmd");
    defer msgpack.free(cmd_name, allocator);
    const cmd_impl = try msgpack.string(allocator, "echo 'buffer command'");
    defer msgpack.free(cmd_impl, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_buf_create_user_command", &.{
        buf,
        cmd_name,
        cmd_impl,
        opts,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_del_user_command
test "nvim_buf_del_user_command removes buffer-local command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const cmd_name = try msgpack.string(allocator, "BufDelCmd");
    defer msgpack.free(cmd_name, allocator);
    const cmd_impl = try msgpack.string(allocator, "echo 'test'");
    defer msgpack.free(cmd_impl, allocator);

    var create_opts = msgpack.Value.mapPayload(allocator);
    defer create_opts.free(allocator);

    _ = try client.request("nvim_buf_create_user_command", &.{
        buf,
        cmd_name,
        cmd_impl,
        create_opts,
    });

    const result = try client.request("nvim_buf_del_user_command", &.{ buf, cmd_name });
    defer msgpack.free(result, allocator);
}
