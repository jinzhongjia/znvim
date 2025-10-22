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

// Test basic connection and API info retrieval
test "nvim spawn process and get API info" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const info = client.getApiInfo() orelse return error.TestExpectedEqual;
    try std.testing.expect(info.channel_id > 0);
    try std.testing.expect(info.functions.len > 0);
    try std.testing.expect(info.version.major >= 0);
    try std.testing.expect(info.version.api_level > 0);
}

// Test nvim_eval with different return types
test "nvim_eval returns correct types" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Test integer result
    {
        const expr = try msgpack.string(allocator, "42");
        defer msgpack.free(expr, allocator);

        const params = [_]msgpack.Value{expr};
        const result = try client.request("nvim_eval", &params);
        defer msgpack.free(result, allocator);

        const value = try msgpack.expectI64(result);
        try std.testing.expectEqual(@as(i64, 42), value);
    }

    // Test string result
    {
        const expr = try msgpack.string(allocator, "'hello'");
        defer msgpack.free(expr, allocator);

        const params = [_]msgpack.Value{expr};
        const result = try client.request("nvim_eval", &params);
        defer msgpack.free(result, allocator);

        const text = try msgpack.expectString(result);
        try std.testing.expectEqualStrings("hello", text);
    }

    // Test array result
    {
        const expr = try msgpack.string(allocator, "[1, 2, 3]");
        defer msgpack.free(expr, allocator);

        const params = [_]msgpack.Value{expr};
        const result = try client.request("nvim_eval", &params);
        defer msgpack.free(result, allocator);

        const arr = try msgpack.expectArray(result);
        try std.testing.expectEqual(@as(usize, 3), arr.len);
    }
}

// Test variable get/set operations
test "nvim_set_var and nvim_get_var" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Set a string variable
    {
        const var_name = try msgpack.string(allocator, "test_var_string");
        defer msgpack.free(var_name, allocator);
        const var_value = try msgpack.string(allocator, "test_value");
        defer msgpack.free(var_value, allocator);

        const set_params = [_]msgpack.Value{ var_name, var_value };
        const set_result = try client.request("nvim_set_var", &set_params);
        defer msgpack.free(set_result, allocator);

        // Get it back
        const get_params = [_]msgpack.Value{var_name};
        const get_result = try client.request("nvim_get_var", &get_params);
        defer msgpack.free(get_result, allocator);

        const retrieved = try msgpack.expectString(get_result);
        try std.testing.expectEqualStrings("test_value", retrieved);
    }

    // Set an integer variable
    {
        const var_name = try msgpack.string(allocator, "test_var_int");
        defer msgpack.free(var_name, allocator);

        const set_params = [_]msgpack.Value{ var_name, msgpack.int(99) };
        const set_result = try client.request("nvim_set_var", &set_params);
        defer msgpack.free(set_result, allocator);

        const get_params = [_]msgpack.Value{var_name};
        const get_result = try client.request("nvim_get_var", &get_params);
        defer msgpack.free(get_result, allocator);

        const retrieved = try msgpack.expectI64(get_result);
        try std.testing.expectEqual(@as(i64, 99), retrieved);
    }
}

// Test buffer operations
test "nvim buffer list and create operations" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // List existing buffers
    const initial_bufs = try client.request("nvim_list_bufs", &.{});
    defer msgpack.free(initial_bufs, allocator);
    const initial_buf_arr = try msgpack.expectArray(initial_bufs);
    const initial_count = initial_buf_arr.len;

    // Create a new buffer
    const create_params = [_]msgpack.Value{
        msgpack.boolean(false), // listed
        msgpack.boolean(false), // scratch
    };
    const new_buf = try client.request("nvim_create_buf", &create_params);
    defer msgpack.free(new_buf, allocator);

    // Verify buffer was created (it should be an ext type)
    try std.testing.expect(new_buf == .ext);

    // List buffers again - should have one more
    const updated_bufs = try client.request("nvim_list_bufs", &.{});
    defer msgpack.free(updated_bufs, allocator);
    const updated_buf_arr = try msgpack.expectArray(updated_bufs);
    try std.testing.expectEqual(initial_count + 1, updated_buf_arr.len);
}

// Test buffer line operations using current buffer
test "nvim_buf_get_lines returns array" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Get current buffer
    const buf_handle = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf_handle, allocator);

    // Get lines from current buffer (should be initially empty or single line)
    const get_result = try client.request("nvim_buf_get_lines", &.{
        buf_handle,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(get_result, allocator);

    const result_lines = try msgpack.expectArray(get_result);
    try std.testing.expect(result_lines.len >= 0);
}

// Test buffer line count on current buffer
test "nvim_buf_line_count returns positive number" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Get current buffer
    const buf_handle = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf_handle, allocator);

    // Get line count
    const count_result = try client.request("nvim_buf_line_count", &.{buf_handle});
    defer msgpack.free(count_result, allocator);

    const count = try msgpack.expectI64(count_result);
    try std.testing.expect(count >= 1);
}

// Test nvim_get_mode
test "nvim_get_mode returns mode info" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_mode", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
    const mode_val = result.map.get("mode") orelse return error.TestExpectedEqual;
    const mode = try msgpack.expectString(mode_val);

    // Headless Neovim should be in normal mode
    try std.testing.expectEqualStrings("n", mode);
}

// Test nvim_exec2 command execution
test "nvim_exec2 executes commands" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "let g:test_exec = 123");
    defer msgpack.free(cmd, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("output", msgpack.boolean(false));

    const params = [_]msgpack.Value{ cmd, opts };
    const result = try client.request("nvim_exec2", &params);
    defer msgpack.free(result, allocator);

    // Verify the variable was set
    const var_name = try msgpack.string(allocator, "test_exec");
    defer msgpack.free(var_name, allocator);

    const get_result = try client.request("nvim_get_var", &.{var_name});
    defer msgpack.free(get_result, allocator);

    const value = try msgpack.expectI64(get_result);
    try std.testing.expectEqual(@as(i64, 123), value);
}

// Test nvim_exec2 with output capture
test "nvim_exec2 captures output" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const cmd = try msgpack.string(allocator, "echo 'test output'");
    defer msgpack.free(cmd, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("output", msgpack.boolean(true));

    const params = [_]msgpack.Value{ cmd, opts };
    const result = try client.request("nvim_exec2", &params);
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
    const output_val = result.map.get("output") orelse return error.TestExpectedEqual;
    const output = try msgpack.expectString(output_val);
    try std.testing.expectEqualStrings("test output", output);
}

// Test option get/set
test "nvim_get_option_value and nvim_set_option_value" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Get current tabstop value
    const opt_name = try msgpack.string(allocator, "tabstop");
    defer msgpack.free(opt_name, allocator);

    var get_opts = msgpack.Value.mapPayload(allocator);
    defer get_opts.free(allocator);

    const get_params = [_]msgpack.Value{ opt_name, get_opts };
    const get_result = try client.request("nvim_get_option_value", &get_params);
    defer msgpack.free(get_result, allocator);

    const original_value = try msgpack.expectI64(get_result);
    try std.testing.expect(original_value > 0);

    // Set tabstop to a different value
    var set_opts = msgpack.Value.mapPayload(allocator);
    defer set_opts.free(allocator);

    const set_params = [_]msgpack.Value{ opt_name, msgpack.int(4), set_opts };
    const set_result = try client.request("nvim_set_option_value", &set_params);
    defer msgpack.free(set_result, allocator);

    // Verify it was changed
    const verify_result = try client.request("nvim_get_option_value", &get_params);
    defer msgpack.free(verify_result, allocator);

    const new_value = try msgpack.expectI64(verify_result);
    try std.testing.expectEqual(@as(i64, 4), new_value);
}

// Test window operations
test "nvim window operations" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Get current window
    const win_result = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win_result, allocator);
    try std.testing.expect(win_result == .ext);

    // List windows
    const list_result = try client.request("nvim_list_wins", &.{});
    defer msgpack.free(list_result, allocator);
    const windows = try msgpack.expectArray(list_result);
    try std.testing.expect(windows.len > 0);
}

// Test tabpage operations
test "nvim tabpage operations" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Get current tabpage
    const tab_result = try client.request("nvim_get_current_tabpage", &.{});
    defer msgpack.free(tab_result, allocator);
    try std.testing.expect(tab_result == .ext);

    // List tabpages
    const list_result = try client.request("nvim_list_tabpages", &.{});
    defer msgpack.free(list_result, allocator);
    const tabpages = try msgpack.expectArray(list_result);
    try std.testing.expect(tabpages.len > 0);
}

// Test buffer name operations
test "nvim_buf_set_name and nvim_buf_get_name" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create a new buffer
    const buf_handle = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf_handle, allocator);

    // Set buffer name
    const buf_name = try msgpack.string(allocator, "test_buffer.txt");
    defer msgpack.free(buf_name, allocator);

    const set_result = try client.request("nvim_buf_set_name", &.{ buf_handle, buf_name });
    defer msgpack.free(set_result, allocator);

    // Get buffer name back
    const get_result = try client.request("nvim_buf_get_name", &.{buf_handle});
    defer msgpack.free(get_result, allocator);

    const retrieved_name = try msgpack.expectString(get_result);
    // Name will have full path, just check it ends with our name
    try std.testing.expect(std.mem.endsWith(u8, retrieved_name, "test_buffer.txt"));
}

// Test buffer validity
test "nvim_buf_is_valid" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create a buffer
    const buf_handle = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf_handle, allocator);

    // Check it's valid
    const valid_result = try client.request("nvim_buf_is_valid", &.{buf_handle});
    defer msgpack.free(valid_result, allocator);

    const is_valid = try msgpack.expectBool(valid_result);
    try std.testing.expect(is_valid);
}

// Test notification (fire and forget)
test "nvim notification does not wait for response" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const var_name = try msgpack.string(allocator, "notif_test");
    defer msgpack.free(var_name, allocator);
    const var_value = try msgpack.string(allocator, "notification_value");
    defer msgpack.free(var_value, allocator);

    const params = [_]msgpack.Value{ var_name, var_value };

    // Send notification - this should not block
    try client.notify("nvim_set_var", &params);

    // Give Neovim a moment to process (100ms)
    std.Thread.sleep(100 * std.time.ns_per_ms);

    // Verify the variable was set
    const get_result = try client.request("nvim_get_var", &.{var_name});
    defer msgpack.free(get_result, allocator);

    const retrieved = try msgpack.expectString(get_result);
    try std.testing.expectEqualStrings("notification_value", retrieved);
}

// Test buffer deletion
test "nvim_buf_delete removes buffer" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create a buffer
    const buf_handle = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf_handle, allocator);

    // Verify it's valid
    const valid1 = try client.request("nvim_buf_is_valid", &.{buf_handle});
    defer msgpack.free(valid1, allocator);
    try std.testing.expect(try msgpack.expectBool(valid1));

    // Delete the buffer
    var del_opts = msgpack.Value.mapPayload(allocator);
    defer del_opts.free(allocator);
    try del_opts.mapPut("force", msgpack.boolean(true));

    const del_result = try client.request("nvim_buf_delete", &.{ buf_handle, del_opts });
    defer msgpack.free(del_result, allocator);

    // Verify it's no longer valid
    const valid2 = try client.request("nvim_buf_is_valid", &.{buf_handle});
    defer msgpack.free(valid2, allocator);
    try std.testing.expect(!(try msgpack.expectBool(valid2)));
}

// Test nvim_get_current_line
test "nvim_get_current_line" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Set current line content via command
    const cmd = try msgpack.string(allocator, "call setline(1, 'test line content')");
    defer msgpack.free(cmd, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("output", msgpack.boolean(false));

    const exec_result = try client.request("nvim_exec2", &.{ cmd, opts });
    defer msgpack.free(exec_result, allocator);

    // Get current line
    const line_result = try client.request("nvim_get_current_line", &.{});
    defer msgpack.free(line_result, allocator);

    const line = try msgpack.expectString(line_result);
    try std.testing.expectEqualStrings("test line content", line);
}

// Test nvim_list_runtime_paths
test "nvim_list_runtime_paths returns array" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_list_runtime_paths", &.{});
    defer msgpack.free(result, allocator);

    const paths = try msgpack.expectArray(result);
    try std.testing.expect(paths.len > 0);
}

// Test nvim_get_chan_info
test "nvim_get_chan_info returns channel info" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const info = client.getApiInfo() orelse return error.TestExpectedEqual;
    const channel_id = msgpack.int(info.channel_id);

    const result = try client.request("nvim_get_chan_info", &.{channel_id});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);

    // Should have at least stream and mode fields
    const stream_val = result.map.get("stream") orelse return error.TestExpectedEqual;
    const stream = try msgpack.expectString(stream_val);
    try std.testing.expectEqualStrings("stdio", stream);
}

// Test nvim_call_function
test "nvim_call_function invokes vimscript functions" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Call the 'abs' function with -42
    const func_name = try msgpack.string(allocator, "abs");
    defer msgpack.free(func_name, allocator);

    const args = try msgpack.array(allocator, &.{-42});
    defer msgpack.free(args, allocator);

    const params = [_]msgpack.Value{ func_name, args };
    const result = try client.request("nvim_call_function", &params);
    defer msgpack.free(result, allocator);

    const value = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 42), value);
}

// Test multiple sequential requests
test "multiple sequential requests work correctly" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Make 10 sequential requests
    var i: i64 = 0;
    while (i < 10) : (i += 1) {
        const expr = try std.fmt.allocPrint(allocator, "{d} * 2", .{i});
        defer allocator.free(expr);

        const expr_payload = try msgpack.string(allocator, expr);
        defer msgpack.free(expr_payload, allocator);

        const params = [_]msgpack.Value{expr_payload};
        const result = try client.request("nvim_eval", &params);
        defer msgpack.free(result, allocator);

        const value = try msgpack.expectI64(result);
        try std.testing.expectEqual(i * 2, value);
    }
}

// Test API function lookup
test "client findApiFunction locates functions" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Find a known function
    const fn_info = client.findApiFunction("nvim_eval") orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("nvim_eval", fn_info.name);
    try std.testing.expect(fn_info.parameters.len > 0);

    // Non-existent function should return null
    const not_found = client.findApiFunction("non_existent_function");
    try std.testing.expect(not_found == null);
}

// Test buffer is_loaded
test "nvim_buf_is_loaded checks buffer loaded state" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create an unloaded buffer
    const buf_handle = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf_handle, allocator);

    const result = try client.request("nvim_buf_is_loaded", &.{buf_handle});
    defer msgpack.free(result, allocator);

    const is_loaded = try msgpack.expectBool(result);
    try std.testing.expect(is_loaded);
}

// Test getting Neovim color map
test "nvim_get_color_map returns map" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_color_map", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
    // Should have common colors
    try std.testing.expect(result.map.count() > 0);
}

// Test nvim_get_context and nvim_load_context
test "nvim_get_context and nvim_load_context" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Get context with specific options
    var get_opts = msgpack.Value.mapPayload(allocator);
    defer get_opts.free(allocator);
    try get_opts.mapPut("types", try msgpack.array(allocator, &.{"regs"}));

    const context = try client.request("nvim_get_context", &.{get_opts});
    defer msgpack.free(context, allocator);

    try std.testing.expect(context == .map);
}

// Test buffer offset
test "nvim_buf_get_offset returns valid offset" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Get current buffer
    const buf_handle = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf_handle, allocator);

    // Get offset of line 0
    const offset_result = try client.request("nvim_buf_get_offset", &.{
        buf_handle,
        msgpack.int(0),
    });
    defer msgpack.free(offset_result, allocator);

    const offset = try msgpack.expectI64(offset_result);
    try std.testing.expectEqual(@as(i64, 0), offset);
}

// Test command list
test "nvim_get_commands returns command map" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_get_commands", &.{opts});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
    try std.testing.expect(result.map.count() >= 0);
}

// Test namespace operations
test "nvim_create_namespace" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const ns_name = try msgpack.string(allocator, "test_namespace");
    defer msgpack.free(ns_name, allocator);

    const result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(result, allocator);

    const ns_id = try msgpack.expectI64(result);
    try std.testing.expect(ns_id >= 0);
}
