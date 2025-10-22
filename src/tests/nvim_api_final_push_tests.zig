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

// Test nvim_open_term
test "nvim_open_term opens terminal" {
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

    const result = try client.request("nvim_open_term", &.{ buf, opts });
    defer msgpack.free(result, allocator);

    const chan_id = try msgpack.expectI64(result);
    try std.testing.expect(chan_id > 0);
}

// Test nvim_chan_send
test "nvim_chan_send sends data to channel" {
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

    const term_result = try client.request("nvim_open_term", &.{ buf, opts });
    defer msgpack.free(term_result, allocator);
    const chan_id = try msgpack.expectI64(term_result);

    const data = try msgpack.string(allocator, "test\n");
    defer msgpack.free(data, allocator);

    const result = try client.request("nvim_chan_send", &.{
        msgpack.int(chan_id),
        data,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_exec_lua
test "nvim_exec_lua executes lua" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const code = try msgpack.string(allocator, "return 2 + 2");
    defer msgpack.free(code, allocator);

    const args = try msgpack.array(allocator, &.{msgpack.Value.nilToPayload()});
    defer msgpack.free(args, allocator);

    const result = try client.request("nvim_exec_lua", &.{ code, args });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 4), value);
}

// Test nvim_buf_create_user_command
test "nvim_buf_create_user_command creates buffer command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const name = try msgpack.string(allocator, "BufCmd");
    defer msgpack.free(name, allocator);
    const command = try msgpack.string(allocator, "echo 'buf'");
    defer msgpack.free(command, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_buf_create_user_command", &.{
        buf,
        name,
        command,
        opts,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_del_user_command
test "nvim_buf_del_user_command deletes buffer command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const name = try msgpack.string(allocator, "BufDelCmd");
    defer msgpack.free(name, allocator);
    const command = try msgpack.string(allocator, "echo 'test'");
    defer msgpack.free(command, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    _ = try client.request("nvim_buf_create_user_command", &.{ buf, name, command, opts });

    const result = try client.request("nvim_buf_del_user_command", &.{ buf, name });
    defer msgpack.free(result, allocator);
}

// Test nvim_create_user_command
test "nvim_create_user_command creates user command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "UserCmd");
    defer msgpack.free(name, allocator);
    const command = try msgpack.string(allocator, "echo 'user'");
    defer msgpack.free(command, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_create_user_command", &.{
        name,
        command,
        opts,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_del_user_command
test "nvim_del_user_command deletes user command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "UserDelCmd");
    defer msgpack.free(name, allocator);
    const command = try msgpack.string(allocator, "echo 'test'");
    defer msgpack.free(command, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    _ = try client.request("nvim_create_user_command", &.{ name, command, opts });

    const result = try client.request("nvim_del_user_command", &.{name});
    defer msgpack.free(result, allocator);
}

// Test nvim_get_commands
test "nvim_get_commands gets commands" {
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
test "nvim_buf_get_commands gets buffer commands" {
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

// Test nvim_buf_get_changedtick
test "nvim_buf_get_changedtick gets changedtick" {
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

// Test nvim_buf_attach
test "nvim_buf_attach attaches to buffer" {
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
test "nvim_buf_detach detaches from buffer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    _ = try client.request("nvim_buf_attach", &.{ buf, msgpack.boolean(false), opts });

    const result = try client.request("nvim_buf_detach", &.{buf});
    defer msgpack.free(result, allocator);

    const detached = try msgpack.expectBool(result);
    try std.testing.expect(detached);
}

// Test nvim_buf_clear_namespace
test "nvim_buf_clear_namespace clears namespace" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const ns_name = try msgpack.string(allocator, "clear_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_result, allocator);
    const ns_id = try msgpack.expectI64(ns_result);

    const result = try client.request("nvim_buf_clear_namespace", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(-1),
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_set_extmark
test "nvim_buf_set_extmark sets extmark" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const ns_name = try msgpack.string(allocator, "extmark_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_result, allocator);
    const ns_id = try msgpack.expectI64(ns_result);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_buf_set_extmark", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(0),
        opts,
    });
    defer msgpack.free(result, allocator);

    const mark_id = try msgpack.expectI64(result);
    try std.testing.expect(mark_id >= 0);
}

// Test nvim_buf_get_extmark_by_id
test "nvim_buf_get_extmark_by_id gets extmark" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const ns_name = try msgpack.string(allocator, "getmark_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_result, allocator);
    const ns_id = try msgpack.expectI64(ns_result);

    var set_opts = msgpack.Value.mapPayload(allocator);
    defer set_opts.free(allocator);

    const mark_result = try client.request("nvim_buf_set_extmark", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(0),
        set_opts,
    });
    defer msgpack.free(mark_result, allocator);
    const mark_id = try msgpack.expectI64(mark_result);

    var get_opts = msgpack.Value.mapPayload(allocator);
    defer get_opts.free(allocator);

    const result = try client.request("nvim_buf_get_extmark_by_id", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(mark_id),
        get_opts,
    });
    defer msgpack.free(result, allocator);

    const pos = try msgpack.expectArray(result);
    try std.testing.expectEqual(@as(usize, 2), pos.len);
}

// Test nvim_buf_get_extmarks
test "nvim_buf_get_extmarks gets extmarks in range" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const ns_name = try msgpack.string(allocator, "getmarks_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_result, allocator);
    const ns_id = try msgpack.expectI64(ns_result);

    var set_opts = msgpack.Value.mapPayload(allocator);
    defer set_opts.free(allocator);

    _ = try client.request("nvim_buf_set_extmark", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(0),
        set_opts,
    });

    var get_opts = msgpack.Value.mapPayload(allocator);
    defer get_opts.free(allocator);

    const result = try client.request("nvim_buf_get_extmarks", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(-1),
        get_opts,
    });
    defer msgpack.free(result, allocator);

    const marks = try msgpack.expectArray(result);
    try std.testing.expect(marks.len >= 1);
}

// Test nvim_buf_del_extmark
test "nvim_buf_del_extmark deletes extmark" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const ns_name = try msgpack.string(allocator, "delmark_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_result, allocator);
    const ns_id = try msgpack.expectI64(ns_result);

    var set_opts = msgpack.Value.mapPayload(allocator);
    defer set_opts.free(allocator);

    const mark_result = try client.request("nvim_buf_set_extmark", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(0),
        set_opts,
    });
    defer msgpack.free(mark_result, allocator);
    const mark_id = try msgpack.expectI64(mark_result);

    const result = try client.request("nvim_buf_del_extmark", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(mark_id),
    });
    defer msgpack.free(result, allocator);

    const deleted = try msgpack.expectBool(result);
    try std.testing.expect(deleted);
}

// Test nvim_buf_add_highlight
test "nvim_buf_add_highlight adds highlight" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const ns_name = try msgpack.string(allocator, "hl_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_result, allocator);
    const ns_id = try msgpack.expectI64(ns_result);

    const hl_group = try msgpack.string(allocator, "Comment");
    defer msgpack.free(hl_group, allocator);

    const result = try client.request("nvim_buf_add_highlight", &.{
        buf,
        msgpack.int(ns_id),
        hl_group,
        msgpack.int(0),
        msgpack.int(0),
        msgpack.int(-1),
    });
    defer msgpack.free(result, allocator);

    const hl_id = try msgpack.expectI64(result);
    try std.testing.expect(hl_id >= 0);
}

// Test nvim_set_hl
test "nvim_set_hl sets highlight group" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "MyHighlight");
    defer msgpack.free(name, allocator);

    var hl_def = msgpack.Value.mapPayload(allocator);
    defer hl_def.free(allocator);
    try hl_def.mapPut("fg", try msgpack.string(allocator, "#FF0000"));

    const result = try client.request("nvim_set_hl", &.{
        msgpack.int(0),
        name,
        hl_def,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_get_hl
test "nvim_get_hl gets highlight" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("name", try msgpack.string(allocator, "Normal"));

    const result = try client.request("nvim_get_hl", &.{ msgpack.int(0), opts });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_get_hl_id_by_name
test "nvim_get_hl_id_by_name gets highlight ID" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "Normal");
    defer msgpack.free(name, allocator);

    const result = try client.request("nvim_get_hl_id_by_name", &.{name});
    defer msgpack.free(result, allocator);

    const hl_id = try msgpack.expectI64(result);
    try std.testing.expect(hl_id > 0);
}

// Test nvim_get_hl_by_name
test "nvim_get_hl_by_name gets highlight by name" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "Normal");
    defer msgpack.free(name, allocator);

    const result = try client.request("nvim_get_hl_by_name", &.{
        name,
        msgpack.boolean(true),
    });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_get_hl_by_id
test "nvim_get_hl_by_id gets highlight by ID" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "Normal");
    defer msgpack.free(name, allocator);

    const id_result = try client.request("nvim_get_hl_id_by_name", &.{name});
    defer msgpack.free(id_result, allocator);
    const hl_id = try msgpack.expectI64(id_result);

    const result = try client.request("nvim_get_hl_by_id", &.{
        msgpack.int(hl_id),
        msgpack.boolean(true),
    });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}


// Test nvim_get_option_info
test "nvim_get_option_info gets option info" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const opt = try msgpack.string(allocator, "number");
    defer msgpack.free(opt, allocator);

    const result = try client.request("nvim_get_option_info", &.{opt});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_clear_autocmds
test "nvim_clear_autocmds clears autocmds" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("event", try msgpack.string(allocator, "User"));

    const result = try client.request("nvim_clear_autocmds", &.{opts});
    defer msgpack.free(result, allocator);
}

// Test nvim_get_autocmds
test "nvim_get_autocmds gets autocmds" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_get_autocmds", &.{opts});
    defer msgpack.free(result, allocator);

    const autocmds = try msgpack.expectArray(result);
    try std.testing.expect(autocmds.len >= 0);
}

// Test nvim_set_client_info
test "nvim_set_client_info sets client info" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const name = try msgpack.string(allocator, "znvim");
    defer msgpack.free(name, allocator);

    var version = msgpack.Value.mapPayload(allocator);
    defer version.free(allocator);
    try version.mapPut("major", msgpack.int(1));
    try version.mapPut("minor", msgpack.int(0));

    const type_str = try msgpack.string(allocator, "remote");
    defer msgpack.free(type_str, allocator);

    var methods = msgpack.Value.mapPayload(allocator);
    defer methods.free(allocator);

    var attrs = msgpack.Value.mapPayload(allocator);
    defer attrs.free(allocator);

    const result = try client.request("nvim_set_client_info", &.{
        name,
        version,
        type_str,
        methods,
        attrs,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_get_option
test "nvim_buf_get_option gets buffer option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const opt = try msgpack.string(allocator, "filetype");
    defer msgpack.free(opt, allocator);

    const result = try client.request("nvim_buf_get_option", &.{ buf, opt });
    defer msgpack.free(result, allocator);

    const ft = try msgpack.expectString(result);
    try std.testing.expect(ft.len >= 0);
}

// Test nvim_buf_set_option
test "nvim_buf_set_option sets buffer option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const opt = try msgpack.string(allocator, "filetype");
    defer msgpack.free(opt, allocator);
    const value = try msgpack.string(allocator, "zig");
    defer msgpack.free(value, allocator);

    const result = try client.request("nvim_buf_set_option", &.{ buf, opt, value });
    defer msgpack.free(result, allocator);
}
