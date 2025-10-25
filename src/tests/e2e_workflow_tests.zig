const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;

fn createTestClient(allocator: std.mem.Allocator) !znvim.Client {
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim",
        .timeout_ms = 10000,
    });
    errdefer client.deinit();
    try client.connect();
    return client;
}

// Test: Complete file editing session
test "complete file editing workflow: create -> edit -> save -> verify" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // 1. Create a new buffer
    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(true), // listed
        msgpack.boolean(false), // scratch
    });
    defer msgpack.free(buf, allocator);

    // 2. Set buffer name
    const filename = try msgpack.string(allocator, "test_workflow.txt");
    defer msgpack.free(filename, allocator);

    const set_name_result = try client.request("nvim_buf_set_name", &.{ buf, filename });
    defer msgpack.free(set_name_result, allocator);

    // 3. Write some content
    const line1 = try msgpack.string(allocator, "First line of text");
    const line2 = try msgpack.string(allocator, "Second line of text");
    const line3 = try msgpack.string(allocator, "Third line of text");
    // Note: line ownership transferred to lines_array, don't free separately

    const lines_array = try msgpack.array(allocator, &.{ line1, line2, line3 });
    defer msgpack.free(lines_array, allocator);

    const set_lines_result = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(0), // start
        msgpack.int(-1), // end
        msgpack.boolean(false), // strict_indexing
        lines_array,
    });
    defer msgpack.free(set_lines_result, allocator);

    // 4. Verify line count
    const line_count_result = try client.request("nvim_buf_line_count", &.{buf});
    defer msgpack.free(line_count_result, allocator);
    const line_count = try msgpack.expectI64(line_count_result);
    try std.testing.expectEqual(@as(i64, 3), line_count);

    // 5. Read back the content
    const get_lines_result = try client.request("nvim_buf_get_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(get_lines_result, allocator);

    const retrieved_lines = try msgpack.expectArray(get_lines_result);
    try std.testing.expectEqual(@as(usize, 3), retrieved_lines.len);
    try std.testing.expectEqualStrings("First line of text", try msgpack.expectString(retrieved_lines[0]));
    try std.testing.expectEqualStrings("Second line of text", try msgpack.expectString(retrieved_lines[1]));
    try std.testing.expectEqualStrings("Third line of text", try msgpack.expectString(retrieved_lines[2]));

    // 6. Modify middle line
    const modified_line = try msgpack.string(allocator, "Modified second line");
    // Note: ownership transferred to modify_array

    const modify_array = try msgpack.array(allocator, &.{modified_line});
    defer msgpack.free(modify_array, allocator);

    const modify_result = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(1), // line 1 (0-indexed)
        msgpack.int(2), // up to line 2
        msgpack.boolean(false),
        modify_array,
    });
    defer msgpack.free(modify_result, allocator);

    // 7. Verify modification
    const verify_result = try client.request("nvim_buf_get_lines", &.{
        buf,
        msgpack.int(1),
        msgpack.int(2),
        msgpack.boolean(false),
    });
    defer msgpack.free(verify_result, allocator);

    const verify_lines = try msgpack.expectArray(verify_result);
    try std.testing.expectEqual(@as(usize, 1), verify_lines.len);
    try std.testing.expectEqualStrings("Modified second line", try msgpack.expectString(verify_lines[0]));

    // 8. Clean up - delete buffer
    var del_opts = msgpack.Value.mapPayload(allocator);
    defer del_opts.free(allocator);
    try del_opts.mapPut("force", msgpack.boolean(true));

    const del_result = try client.request("nvim_buf_delete", &.{ buf, del_opts });
    defer msgpack.free(del_result, allocator);
}

// Test: Multi-buffer editing session
test "multi-buffer workflow: work with multiple buffers" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create 3 buffers with different content
    const buffers_count = 3;
    var buffers: [buffers_count]msgpack.Value = undefined;

    var i: usize = 0;
    while (i < buffers_count) : (i += 1) {
        const buf = try client.request("nvim_create_buf", &.{
            msgpack.boolean(false),
            msgpack.boolean(false),
        });
        buffers[i] = buf;

        // Set unique content for each buffer
        const content_str = try std.fmt.allocPrint(allocator, "Buffer {d} content", .{i});
        defer allocator.free(content_str);

        const content = try msgpack.string(allocator, content_str);
        // Note: content ownership transferred to content_array, don't free separately

        const content_array = try msgpack.array(allocator, &.{content});
        defer msgpack.free(content_array, allocator);

        const set_result = try client.request("nvim_buf_set_lines", &.{
            buf,
            msgpack.int(0),
            msgpack.int(-1),
            msgpack.boolean(false),
            content_array,
        });
        defer msgpack.free(set_result, allocator);
    }

    defer {
        for (buffers) |buf| {
            msgpack.free(buf, allocator);
        }
    }

    // Verify each buffer has correct content
    var j: usize = 0;
    while (j < buffers_count) : (j += 1) {
        const get_result = try client.request("nvim_buf_get_lines", &.{
            buffers[j],
            msgpack.int(0),
            msgpack.int(-1),
            msgpack.boolean(false),
        });
        defer msgpack.free(get_result, allocator);

        const lines = try msgpack.expectArray(get_result);
        try std.testing.expectEqual(@as(usize, 1), lines.len);

        const expected = try std.fmt.allocPrint(allocator, "Buffer {d} content", .{j});
        defer allocator.free(expected);

        try std.testing.expectEqualStrings(expected, try msgpack.expectString(lines[0]));
    }

    // Clean up buffers
    for (buffers) |buf| {
        var del_opts = msgpack.Value.mapPayload(allocator);
        defer del_opts.free(allocator);
        try del_opts.mapPut("force", msgpack.boolean(true));

        const del_result = try client.request("nvim_buf_delete", &.{ buf, del_opts });
        defer msgpack.free(del_result, allocator);
    }
}

// Test: Window and buffer interaction workflow
test "window management workflow: split and navigate" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Get initial window
    const initial_win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(initial_win, allocator);

    // List windows (should be 1)
    const windows_before = try client.request("nvim_list_wins", &.{});
    defer msgpack.free(windows_before, allocator);
    const wins_before = try msgpack.expectArray(windows_before);
    try std.testing.expectEqual(@as(usize, 1), wins_before.len);

    // Create a split
    const split_cmd = try msgpack.string(allocator, "split");
    defer msgpack.free(split_cmd, allocator);

    var exec_opts = msgpack.Value.mapPayload(allocator);
    defer exec_opts.free(allocator);
    try exec_opts.mapPut("output", msgpack.boolean(false));

    const exec_result = try client.request("nvim_exec2", &.{ split_cmd, exec_opts });
    defer msgpack.free(exec_result, allocator);

    // Now should have 2 windows
    const windows_after = try client.request("nvim_list_wins", &.{});
    defer msgpack.free(windows_after, allocator);
    const wins_after = try msgpack.expectArray(windows_after);
    try std.testing.expectEqual(@as(usize, 2), wins_after.len);

    // Get current window (should be the new split)
    const current_win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(current_win, allocator);

    // They should be different windows
    try std.testing.expect(!std.mem.eql(u8, std.mem.asBytes(&initial_win), std.mem.asBytes(&current_win)));
}

// Test: Variable and option manipulation workflow
test "configuration workflow: set options and variables" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // 1. Set global variables
    const var_names = [_][]const u8{ "workflow_var1", "workflow_var2", "workflow_var3" };
    const var_values = [_]i64{ 100, 200, 300 };

    for (var_names, var_values) |name, value| {
        const var_name = try msgpack.string(allocator, name);
        defer msgpack.free(var_name, allocator);

        const var_value = msgpack.int(value);

        const set_result = try client.request("nvim_set_var", &.{ var_name, var_value });
        defer msgpack.free(set_result, allocator);
    }

    // 2. Verify all variables
    for (var_names, var_values) |name, expected_value| {
        const var_name = try msgpack.string(allocator, name);
        defer msgpack.free(var_name, allocator);

        const get_result = try client.request("nvim_get_var", &.{var_name});
        defer msgpack.free(get_result, allocator);

        const retrieved = try msgpack.expectI64(get_result);
        try std.testing.expectEqual(expected_value, retrieved);
    }

    // 3. Set an option
    const opt_name = try msgpack.string(allocator, "tabstop");
    defer msgpack.free(opt_name, allocator);

    var set_opts = msgpack.Value.mapPayload(allocator);
    defer set_opts.free(allocator);

    const set_opt_result = try client.request("nvim_set_option_value", &.{
        opt_name,
        msgpack.int(2),
        set_opts,
    });
    defer msgpack.free(set_opt_result, allocator);

    // 4. Verify option
    var get_opts = msgpack.Value.mapPayload(allocator);
    defer get_opts.free(allocator);

    const get_opt_result = try client.request("nvim_get_option_value", &.{ opt_name, get_opts });
    defer msgpack.free(get_opt_result, allocator);

    const tabstop_value = try msgpack.expectI64(get_opt_result);
    try std.testing.expectEqual(@as(i64, 2), tabstop_value);
}

// Test: Search and replace workflow
test "search and replace workflow using commands" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create buffer with content
    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf, allocator);

    // Set as current buffer
    const set_buf_result = try client.request("nvim_set_current_buf", &.{buf});
    defer msgpack.free(set_buf_result, allocator);

    // Add content with repeated word
    const l1 = try msgpack.string(allocator, "foo is here");
    const l2 = try msgpack.string(allocator, "foo is there");
    const l3 = try msgpack.string(allocator, "foo is everywhere");

    const lines_array = try msgpack.array(allocator, &.{ l1, l2, l3 });
    defer msgpack.free(lines_array, allocator);

    const set_lines_result = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        lines_array,
    });
    defer msgpack.free(set_lines_result, allocator);

    // Perform search and replace
    const subst_cmd = try msgpack.string(allocator, "%s/foo/bar/g");
    defer msgpack.free(subst_cmd, allocator);

    var exec_opts = msgpack.Value.mapPayload(allocator);
    defer exec_opts.free(allocator);
    try exec_opts.mapPut("output", msgpack.boolean(false));

    const exec_result = try client.request("nvim_exec2", &.{ subst_cmd, exec_opts });
    defer msgpack.free(exec_result, allocator);

    // Verify replacement
    const get_lines_result = try client.request("nvim_buf_get_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(get_lines_result, allocator);

    const result_lines = try msgpack.expectArray(get_lines_result);
    try std.testing.expectEqualStrings("bar is here", try msgpack.expectString(result_lines[0]));
    try std.testing.expectEqualStrings("bar is there", try msgpack.expectString(result_lines[1]));
    try std.testing.expectEqualStrings("bar is everywhere", try msgpack.expectString(result_lines[2]));
}

// Test: Incremental editing workflow
test "incremental editing: append, insert, delete lines" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    // Start with one line
    const initial = try msgpack.string(allocator, "Line 1");
    const initial_array = try msgpack.array(allocator, &.{initial});
    defer msgpack.free(initial_array, allocator);

    const set1 = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        initial_array,
    });
    defer msgpack.free(set1, allocator);

    // Append line
    const append = try msgpack.string(allocator, "Line 2");
    const append_array = try msgpack.array(allocator, &.{append});
    defer msgpack.free(append_array, allocator);

    const set2 = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(1),
        msgpack.int(1),
        msgpack.boolean(false),
        append_array,
    });
    defer msgpack.free(set2, allocator);

    // Insert line at beginning
    const insert = try msgpack.string(allocator, "Line 0");
    const insert_array = try msgpack.array(allocator, &.{insert});
    defer msgpack.free(insert_array, allocator);

    const set3 = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(0),
        msgpack.boolean(false),
        insert_array,
    });
    defer msgpack.free(set3, allocator);

    // Verify order: Line 0, Line 1, Line 2
    const get_result = try client.request("nvim_buf_get_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(get_result, allocator);

    const lines = try msgpack.expectArray(get_result);
    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqualStrings("Line 0", try msgpack.expectString(lines[0]));
    try std.testing.expectEqualStrings("Line 1", try msgpack.expectString(lines[1]));
    try std.testing.expectEqualStrings("Line 2", try msgpack.expectString(lines[2]));

    // Delete middle line
    const empty_array = try msgpack.array(allocator, &.{});
    defer msgpack.free(empty_array, allocator);

    const set4 = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(1),
        msgpack.int(2),
        msgpack.boolean(false),
        empty_array,
    });
    defer msgpack.free(set4, allocator);

    // Verify deletion
    const get_result2 = try client.request("nvim_buf_get_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(get_result2, allocator);

    const lines2 = try msgpack.expectArray(get_result2);
    try std.testing.expectEqual(@as(usize, 2), lines2.len);
    try std.testing.expectEqualStrings("Line 0", try msgpack.expectString(lines2[0]));
    try std.testing.expectEqualStrings("Line 2", try msgpack.expectString(lines2[1]));
}

// Test: Function call workflow
test "function call workflow: use vimscript functions" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Test abs function
    {
        const func_name = try msgpack.string(allocator, "abs");
        defer msgpack.free(func_name, allocator);

        const args = try msgpack.array(allocator, &.{-42});
        defer msgpack.free(args, allocator);

        const result = try client.request("nvim_call_function", &.{ func_name, args });
        defer msgpack.free(result, allocator);

        try std.testing.expectEqual(@as(i64, 42), try msgpack.expectI64(result));
    }

    // Test len function
    {
        const func_name = try msgpack.string(allocator, "len");
        defer msgpack.free(func_name, allocator);

        const list = try msgpack.array(allocator, &.{ 1, 2, 3, 4, 5 });
        // ownership transferred to args

        const args = try msgpack.array(allocator, &.{list});
        defer msgpack.free(args, allocator);

        const result = try client.request("nvim_call_function", &.{ func_name, args });
        defer msgpack.free(result, allocator);

        try std.testing.expectEqual(@as(i64, 5), try msgpack.expectI64(result));
    }

    // Test max function
    {
        const func_name = try msgpack.string(allocator, "max");
        defer msgpack.free(func_name, allocator);

        const list = try msgpack.array(allocator, &.{ 10, 5, 20, 15 });
        // ownership transferred to args

        const args = try msgpack.array(allocator, &.{list});
        defer msgpack.free(args, allocator);

        const result = try client.request("nvim_call_function", &.{ func_name, args });
        defer msgpack.free(result, allocator);

        try std.testing.expectEqual(@as(i64, 20), try msgpack.expectI64(result));
    }
}

// Test: Realistic plugin development scenario
test "plugin scenario: auto-save on buffer changes" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create and configure a buffer
    const buf = try client.request("nvim_create_buf", &.{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf, allocator);

    // Simulate plugin: set a variable when buffer is modified
    const content1 = try msgpack.string(allocator, "Initial content");
    const array1 = try msgpack.array(allocator, &.{content1});
    defer msgpack.free(array1, allocator);

    const set1 = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        array1,
    });
    defer msgpack.free(set1, allocator);

    // Mark buffer as modified by setting a variable
    const modified_var = try msgpack.string(allocator, "buffer_modified");
    defer msgpack.free(modified_var, allocator);

    const set_var_result = try client.request("nvim_set_var", &.{
        modified_var,
        msgpack.boolean(true),
    });
    defer msgpack.free(set_var_result, allocator);

    // Simulate save operation
    const content2 = try msgpack.string(allocator, "Saved content");
    const array2 = try msgpack.array(allocator, &.{content2});
    defer msgpack.free(array2, allocator);

    const set2 = try client.request("nvim_buf_set_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        array2,
    });
    defer msgpack.free(set2, allocator);

    // Clear modified flag
    const clear_var_result = try client.request("nvim_set_var", &.{
        modified_var,
        msgpack.boolean(false),
    });
    defer msgpack.free(clear_var_result, allocator);

    // Verify final state
    const get_var = try client.request("nvim_get_var", &.{modified_var});
    defer msgpack.free(get_var, allocator);
    try std.testing.expect(!(try msgpack.expectBool(get_var)));

    const get_lines = try client.request("nvim_buf_get_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(get_lines, allocator);

    const lines = try msgpack.expectArray(get_lines);
    try std.testing.expectEqualStrings("Saved content", try msgpack.expectString(lines[0]));
}
