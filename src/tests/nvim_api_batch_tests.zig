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

// Test nvim_exec
test "nvim_exec executes vimscript" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const src = try msgpack.string(allocator, "let g:test = 1\necho g:test");
    defer msgpack.free(src, allocator);

    const result = try client.request("nvim_exec", &.{
        src,
        msgpack.boolean(true),
    });
    defer msgpack.free(result, allocator);

    const output = try msgpack.expectString(result);
    try std.testing.expect(std.mem.indexOf(u8, output, "1") != null);
}

// Test nvim_command
test "nvim_command executes command" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "let g:cmdtest = 1");
    defer msgpack.free(cmd, allocator);

    const result = try client.request("nvim_command", &.{cmd});
    defer msgpack.free(result, allocator);
}

// Test nvim_eval
test "nvim_eval evaluates expression" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const expr = try msgpack.string(allocator, "5 * 5");
    defer msgpack.free(expr, allocator);

    const result = try client.request("nvim_eval", &.{expr});
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 25), value);
}

// Test nvim_call_function
test "nvim_call_function calls vimscript function" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const func = try msgpack.string(allocator, "abs");
    defer msgpack.free(func, allocator);

    const args = try msgpack.array(allocator, &.{-100});
    defer msgpack.free(args, allocator);

    const result = try client.request("nvim_call_function", &.{ func, args });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 100), value);
}

// Test nvim_call_dict_function
test "nvim_call_dict_function calls dict method" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const expr = try msgpack.string(allocator, "{'max': function('max')}");
    defer msgpack.free(expr, allocator);

    const dict = try client.request("nvim_eval", &.{expr});
    defer msgpack.free(dict, allocator);

    const method = try msgpack.string(allocator, "max");
    defer msgpack.free(method, allocator);

    const arr = try msgpack.array(allocator, &.{msgpack.array(allocator, &.{ 1, 5, 3 }) catch unreachable});
    defer msgpack.free(arr, allocator);

    const result = try client.request("nvim_call_dict_function", &.{ dict, method, arr });
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 5), value);
}

// Test nvim_exec2
test "nvim_exec2 executes command with opts" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "echo 'exec2 test'");
    defer msgpack.free(cmd, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("output", msgpack.boolean(true));

    const result = try client.request("nvim_exec2", &.{ cmd, opts });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_parse_cmd
test "nvim_parse_cmd parses command" {
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

// Test nvim_list_runtime_paths
test "nvim_list_runtime_paths lists runtime paths" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_list_runtime_paths", &.{});
    defer msgpack.free(result, allocator);

    const paths = try msgpack.expectArray(result);
    try std.testing.expect(paths.len > 0);
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

// Test nvim_set_current_dir
test "nvim_set_current_dir sets working directory" {
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

// Test nvim_get_current_line
test "nvim_get_current_line gets current line" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_current_line", &.{});
    defer msgpack.free(result, allocator);

    const line = try msgpack.expectString(result);
    try std.testing.expect(line.len >= 0);
}

// Test nvim_set_current_line
test "nvim_set_current_line sets current line" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const line = try msgpack.string(allocator, "new line");
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

// Test nvim_get_var
test "nvim_get_var gets global variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const var_name = try msgpack.string(allocator, "testvar");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_set_var", &.{ var_name, msgpack.int(42) });

    const result = try client.request("nvim_get_var", &.{var_name});
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 42), value);
}

// Test nvim_set_var
test "nvim_set_var sets global variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const var_name = try msgpack.string(allocator, "setvar_test");
    defer msgpack.free(var_name, allocator);

    const result = try client.request("nvim_set_var", &.{ var_name, msgpack.int(999) });
    defer msgpack.free(result, allocator);
}

// Test nvim_del_var
test "nvim_del_var deletes global variable" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const var_name = try msgpack.string(allocator, "delvar_test");
    defer msgpack.free(var_name, allocator);

    _ = try client.request("nvim_set_var", &.{ var_name, msgpack.int(1) });

    const result = try client.request("nvim_del_var", &.{var_name});
    defer msgpack.free(result, allocator);
}

// Test nvim_get_vvar
test "nvim_get_vvar gets vim variable" {
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

// Test nvim_get_option
test "nvim_get_option gets global option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const opt = try msgpack.string(allocator, "hlsearch");
    defer msgpack.free(opt, allocator);

    const result = try client.request("nvim_get_option", &.{opt});
    defer msgpack.free(result, allocator);

    _ = try msgpack.expectBool(result);
}

// Test nvim_set_option
test "nvim_set_option sets global option" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const opt = try msgpack.string(allocator, "hlsearch");
    defer msgpack.free(opt, allocator);

    const result = try client.request("nvim_set_option", &.{ opt, msgpack.boolean(true) });
    defer msgpack.free(result, allocator);
}
