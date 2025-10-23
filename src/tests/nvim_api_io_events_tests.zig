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

// Test nvim_feedkeys with keys
test "nvim_feedkeys feeds keys to neovim" {
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

    const keys = try msgpack.string(allocator, "i");
    defer msgpack.free(keys, allocator);

    const result = try client.request("nvim_input", &.{keys});
    defer msgpack.free(result, allocator);

    const written = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 1), written);
}

// Test nvim_replace_termcodes
test "nvim_replace_termcodes replaces special codes" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const str = try msgpack.string(allocator, "<C-W>");
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

// Test nvim_strwidth
test "nvim_strwidth calculates string display width" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const text = try msgpack.string(allocator, "hello");
    defer msgpack.free(text, allocator);

    const result = try client.request("nvim_strwidth", &.{text});
    defer msgpack.free(result, allocator);

    const width = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 5), width);
}

// Test nvim_list_uis
test "nvim_list_uis returns attached UIs" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_list_uis", &.{});
    defer msgpack.free(result, allocator);

    const uis = try msgpack.expectArray(result);
    try std.testing.expect(uis.len >= 0);
}

// Test nvim_notify
test "nvim_notify sends notification message" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const msg = try msgpack.string(allocator, "Test notification");
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

// Test nvim_parse_expression
test "nvim_parse_expression parses vimscript expression" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const expr = try msgpack.string(allocator, "1 + 1");
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

// Test nvim_out_write
test "nvim_out_write outputs to stdout" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const text = try msgpack.string(allocator, "output text\n");
    defer msgpack.free(text, allocator);

    const result = try client.request("nvim_out_write", &.{text});
    defer msgpack.free(result, allocator);
}

// Test nvim_err_write
test "nvim_err_write outputs to stderr" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const text = try msgpack.string(allocator, "error text\n");
    defer msgpack.free(text, allocator);

    const result = try client.request("nvim_err_write", &.{text});
    defer msgpack.free(result, allocator);
}

// Test nvim_command_output
test "nvim_command_output returns command output" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "echo 'test output'");
    defer msgpack.free(cmd, allocator);

    const result = try client.request("nvim_command_output", &.{cmd});
    defer msgpack.free(result, allocator);

    const output = try msgpack.expectString(result);
    try std.testing.expectEqualStrings("test output", output);
}

// Test nvim_get_vvar
test "nvim_get_vvar gets vim variables" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const var_name = try msgpack.string(allocator, "progname");
    defer msgpack.free(var_name, allocator);

    const result = try client.request("nvim_get_vvar", &.{var_name});
    defer msgpack.free(result, allocator);

    const progname = try msgpack.expectString(result);
    // On Windows it's "nvim.exe", on Unix it's "nvim"
    try std.testing.expect(std.mem.startsWith(u8, progname, "nvim"));
}

// Test nvim_set_current_line updates line
test "nvim_set_current_line sets line content" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const line = try msgpack.string(allocator, "new content");
    defer msgpack.free(line, allocator);

    const result = try client.request("nvim_set_current_line", &.{line});
    defer msgpack.free(result, allocator);
}

// Test nvim_del_current_line
test "nvim_del_current_line deletes current line" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_del_current_line", &.{});
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

    _ = try client.request("nvim_subscribe", &.{event});

    const result = try client.request("nvim_unsubscribe", &.{event});
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

// Test nvim_del_var
test "nvim_del_var deletes global variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const var_name = try msgpack.string(allocator, "temp_global_var");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_set_var", &.{ var_name, msgpack.int(123) });

    const result = try client.request("nvim_del_var", &.{var_name});
    defer msgpack.free(result, allocator);
}
