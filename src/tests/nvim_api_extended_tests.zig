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

// Test nvim_set_current_line
test "nvim_set_current_line" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const line_text = try msgpack.string(allocator, "test line content");
    defer msgpack.free(line_text, allocator);

    const result = try client.request("nvim_set_current_line", &.{line_text});
    defer msgpack.free(result, allocator);

    // Verify by getting current line
    const get_result = try client.request("nvim_get_current_line", &.{});
    defer msgpack.free(get_result, allocator);

    const retrieved = try msgpack.expectString(get_result);
    try std.testing.expectEqualStrings("test line content", retrieved);
}

// Test nvim_del_var
test "nvim_del_var removes variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Set a variable
    const var_name = try msgpack.string(allocator, "temp_var");
    defer msgpack.free(var_name, allocator);
    const var_value = try msgpack.string(allocator, "temp");
    defer msgpack.free(var_value, allocator);

    const set_result = try client.request("nvim_set_var", &.{ var_name, var_value });
    defer msgpack.free(set_result, allocator);

    // Delete it
    const del_result = try client.request("nvim_del_var", &.{var_name});
    defer msgpack.free(del_result, allocator);

    // Getting it should now fail
    const get_result = client.request("nvim_get_var", &.{var_name});
    try std.testing.expectError(error.NvimError, get_result);
}

// Test nvim_list_uis
test "nvim_list_uis returns array" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_list_uis", &.{});
    defer msgpack.free(result, allocator);

    const uis = try msgpack.expectArray(result);
    // Headless mode should have no UIs
    try std.testing.expectEqual(@as(usize, 0), uis.len);
}

// Test nvim_get_api_info directly
test "nvim_get_api_info returns valid structure" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_api_info", &.{});
    defer msgpack.free(result, allocator);

    const root = try msgpack.expectArray(result);
    try std.testing.expectEqual(@as(usize, 2), root.len);

    // First element is channel_id
    const channel_id = try msgpack.expectI64(root[0]);
    try std.testing.expect(channel_id > 0);

    // Second element is metadata map
    try std.testing.expect(root[1] == .map);
}

// Test nvim_command_output
test "nvim_command_output returns string" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "echo 'test'");
    defer msgpack.free(cmd, allocator);

    const result = try client.request("nvim_command_output", &.{cmd});
    defer msgpack.free(result, allocator);

    const output = try msgpack.expectString(result);
    try std.testing.expectEqualStrings("test", output);
}

// Test nvim_get_vvar
test "nvim_get_vvar retrieves vim variables" {
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

// Test nvim_feedkeys
test "nvim_feedkeys accepts input" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const keys = try msgpack.string(allocator, "iHello");
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
test "nvim_input accepts keyboard input" {
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
test "nvim_replace_termcodes processes special keys" {
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
test "nvim_strwidth calculates display width" {
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

// Test nvim_get_current_buf and nvim_set_current_buf
test "nvim get and set current buffer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Get current buffer
    const current = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(current, allocator);

    // Create new buffer
    const new_buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(true),
        msgpack.boolean(false),
    });
    defer msgpack.free(new_buf, allocator);

    // Set as current
    const set_result = try client.request("nvim_set_current_buf", &.{new_buf});
    defer msgpack.free(set_result, allocator);

    // Verify it's current
    const verify = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(verify, allocator);
    try std.testing.expect(verify == .ext);
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

// Test nvim_notify sends message
test "nvim_notify sends notification" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const msg = try msgpack.string(allocator, "Test notification");
    defer msgpack.free(msg, allocator);

    const result = try client.request("nvim_notify", &.{
        msg,
        msgpack.int(1), // log level INFO
        msgpack.Value.mapPayload(allocator),
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_parse_expression
test "nvim_parse_expression parses vimscript" {
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
test "nvim_out_write sends output" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const text = try msgpack.string(allocator, "test output\n");
    defer msgpack.free(text, allocator);

    const result = try client.request("nvim_out_write", &.{text});
    defer msgpack.free(result, allocator);
}

// Test nvim_err_write
test "nvim_err_write sends error output" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const text = try msgpack.string(allocator, "error message\n");
    defer msgpack.free(text, allocator);

    const result = try client.request("nvim_err_write", &.{text});
    defer msgpack.free(result, allocator);
}

// Test nvim_del_current_line
test "nvim_del_current_line removes line" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // First set a line
    const line_text = try msgpack.string(allocator, "line to delete");
    defer msgpack.free(line_text, allocator);

    _ = try client.request("nvim_set_current_line", &.{line_text});

    // Get line count before
    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const count_before = try client.request("nvim_buf_line_count", &.{buf});
    defer msgpack.free(count_before, allocator);
    const lines_before = try msgpack.expectI64(count_before);

    // Delete current line
    const del_result = try client.request("nvim_del_current_line", &.{});
    defer msgpack.free(del_result, allocator);

    // Verify line count decreased
    const count_after = try client.request("nvim_buf_line_count", &.{buf});
    defer msgpack.free(count_after, allocator);
    const lines_after = try msgpack.expectI64(count_after);

    try std.testing.expect(lines_after < lines_before or lines_after == 1);
}

// Test nvim_buf_get_mark
test "nvim_buf_get_mark returns position" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const mark_name = try msgpack.string(allocator, "\"");
    defer msgpack.free(mark_name, allocator);

    const result = try client.request("nvim_buf_get_mark", &.{ buf, mark_name });
    defer msgpack.free(result, allocator);

    const pos = try msgpack.expectArray(result);
    try std.testing.expectEqual(@as(usize, 2), pos.len);
}

// Test nvim_win_get_buf
test "nvim_win_get_buf returns buffer handle" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_buf", &.{win});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
}

// Test nvim_win_get_cursor and nvim_win_set_cursor
test "nvim_win get and set cursor" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    // Get current cursor position
    const get_result = try client.request("nvim_win_get_cursor", &.{win});
    defer msgpack.free(get_result, allocator);

    const pos = try msgpack.expectArray(get_result);
    try std.testing.expectEqual(@as(usize, 2), pos.len);

    // Set cursor to row 1, col 0
    const new_pos = try msgpack.array(allocator, &.{ 1, 0 });
    defer msgpack.free(new_pos, allocator);

    const set_result = try client.request("nvim_win_set_cursor", &.{ win, new_pos });
    defer msgpack.free(set_result, allocator);
}

// Test nvim_win_get_height and nvim_win_set_height
test "nvim_win get and set height" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    // Get current height
    const get_result = try client.request("nvim_win_get_height", &.{win});
    defer msgpack.free(get_result, allocator);

    const height = try msgpack.expectI64(get_result);
    try std.testing.expect(height > 0);

    // Set new height
    const set_result = try client.request("nvim_win_set_height", &.{ win, msgpack.int(10) });
    defer msgpack.free(set_result, allocator);

    // Verify
    const verify = try client.request("nvim_win_get_height", &.{win});
    defer msgpack.free(verify, allocator);
    const new_height = try msgpack.expectI64(verify);
    try std.testing.expectEqual(@as(i64, 10), new_height);
}

// Test nvim_win_get_width and nvim_win_set_width
test "nvim_win get and set width" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    // Get current width
    const get_result = try client.request("nvim_win_get_width", &.{win});
    defer msgpack.free(get_result, allocator);

    const width = try msgpack.expectI64(get_result);
    try std.testing.expect(width > 0);

    // Set new width
    const set_result = try client.request("nvim_win_set_width", &.{ win, msgpack.int(80) });
    defer msgpack.free(set_result, allocator);

    // Verify
    const verify = try client.request("nvim_win_get_width", &.{win});
    defer msgpack.free(verify, allocator);
    const new_width = try msgpack.expectI64(verify);
    try std.testing.expectEqual(@as(i64, 80), new_width);
}

// Test nvim_win_get_position
test "nvim_win_get_position returns coordinates" {
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
test "nvim_win_get_tabpage returns tabpage handle" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const result = try client.request("nvim_win_get_tabpage", &.{win});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
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
    try std.testing.expect(num > 0);
}

// Test nvim_tabpage_is_valid
test "nvim_tabpage_is_valid checks validity" {
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

// Test nvim_tabpage_list_wins
test "nvim_tabpage_list_wins returns windows in tab" {
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
test "nvim_tabpage_get_win returns current window in tab" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const tab = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab, allocator);

    const result = try client.request("nvim_tabpage_get_win", &.{tab});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .ext);
}

// Test nvim_create_user_command
test "nvim_create_user_command creates command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd_name = try msgpack.string(allocator, "TestCmd");
    defer msgpack.free(cmd_name, allocator);
    const cmd_impl = try msgpack.string(allocator, "echo 'test'");
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
test "nvim_del_user_command removes command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create a command first
    const cmd_name = try msgpack.string(allocator, "TestDelCmd");
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

    // Delete it
    const result = try client.request("nvim_del_user_command", &.{cmd_name});
    defer msgpack.free(result, allocator);
}
