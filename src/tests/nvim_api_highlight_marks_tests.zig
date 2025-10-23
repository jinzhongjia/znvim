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

// Test nvim_set_hl_ns
test "nvim_set_hl_ns sets highlight namespace" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const ns_name = try msgpack.string(allocator, "test_hl_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_result, allocator);
    const ns_id = try msgpack.expectI64(ns_result);

    const result = try client.request("nvim_set_hl_ns", &.{msgpack.int(ns_id)});
    defer msgpack.free(result, allocator);
}

// Test nvim_set_hl_ns_fast
test "nvim_set_hl_ns_fast sets namespace quickly" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const ns_name = try msgpack.string(allocator, "fast_hl_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_result, allocator);
    const ns_id = try msgpack.expectI64(ns_result);

    const result = try client.request("nvim_set_hl_ns_fast", &.{msgpack.int(ns_id)});
    defer msgpack.free(result, allocator);
}

// Test nvim_get_hl_ns
test "nvim_get_hl_ns gets current highlight namespace" {
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

// Test nvim_buf_set_mark
test "nvim_buf_set_mark sets buffer mark" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const mark_name = try msgpack.string(allocator, "a");
    defer msgpack.free(mark_name, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_buf_set_mark", &.{
        buf,
        mark_name,
        msgpack.int(1),
        msgpack.int(0),
        opts,
    });
    defer msgpack.free(result, allocator);

    const success = try msgpack.expectBool(result);
    try std.testing.expect(success);
}

// Test nvim_buf_del_mark
test "nvim_buf_del_mark deletes buffer mark" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const mark_name = try msgpack.string(allocator, "b");
    defer msgpack.free(mark_name, allocator);

    const result = try client.request("nvim_buf_del_mark", &.{
        buf,
        mark_name,
    });
    defer msgpack.free(result, allocator);

    _ = try msgpack.expectBool(result);
}

// Test nvim_win_set_hl_ns
test "nvim_win_set_hl_ns sets window highlight namespace" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const win = try client.request("nvim_get_current_win", &.{});
    defer msgpack.free(win, allocator);

    const ns_name = try msgpack.string(allocator, "win_hl_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_result, allocator);
    const ns_id = try msgpack.expectI64(ns_result);

    const result = try client.request("nvim_win_set_hl_ns", &.{
        win,
        msgpack.int(ns_id),
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_get_option_info
test "nvim_get_option_info returns option metadata" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const opt_name = try msgpack.string(allocator, "number");
    defer msgpack.free(opt_name, allocator);

    const result = try client.request("nvim_get_option_info", &.{opt_name});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_ui_set_focus
test "nvim_ui_set_focus sets UI focus" {
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

    const result = try client.request("nvim_ui_set_focus", &.{msgpack.boolean(true)});
    defer msgpack.free(result, allocator);
}

// Test nvim_ui_term_event
test "nvim_ui_term_event sends terminal event" {
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

    const event = try msgpack.string(allocator, "focus");
    defer msgpack.free(event, allocator);

    const result = try client.request("nvim_ui_term_event", &.{
        event,
        msgpack.int(0),
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_get_chan_info
test "nvim_get_chan_info returns channel info" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const info = client.getApiInfo() orelse return error.TestExpectedEqual;

    const result = try client.request("nvim_get_chan_info", &.{msgpack.int(info.channel_id)});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_list_chans
test "nvim_list_chans lists all channels" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_list_chans", &.{});
    defer msgpack.free(result, allocator);

    const chans = try msgpack.expectArray(result);
    try std.testing.expect(chans.len > 0);
}

// Test nvim_get_color_map
test "nvim_get_color_map returns colors" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim_get_color_map", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
    try std.testing.expect(result.map.count() > 0);
}

// Test nvim_get_context
test "nvim_get_context gets editor context" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_get_context", &.{opts});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}
