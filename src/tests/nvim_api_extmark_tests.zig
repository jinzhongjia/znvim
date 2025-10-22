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

// Test nvim_buf_set_extmark and nvim_buf_get_extmark_by_id
test "nvim_buf extmark set and get" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    // Create namespace
    const ns_name = try msgpack.string(allocator, "test_ns");
    defer msgpack.free(ns_name, allocator);

    const ns_id_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_id_result, allocator);
    const ns_id = try msgpack.expectI64(ns_id_result);

    // Set extmark at row 0, col 0
    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const extmark_id_result = try client.request("nvim_buf_set_extmark", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(0),
        opts,
    });
    defer msgpack.free(extmark_id_result, allocator);

    const extmark_id = try msgpack.expectI64(extmark_id_result);
    try std.testing.expect(extmark_id >= 0);

    // Get extmark by id
    var get_opts = msgpack.Value.mapPayload(allocator);
    defer get_opts.free(allocator);

    const get_result = try client.request("nvim_buf_get_extmark_by_id", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(extmark_id),
        get_opts,
    });
    defer msgpack.free(get_result, allocator);

    const extmark_pos = try msgpack.expectArray(get_result);
    try std.testing.expectEqual(@as(usize, 2), extmark_pos.len);
}

// Test nvim_buf_get_extmarks
test "nvim_buf_get_extmarks returns extmarks in range" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const ns_name = try msgpack.string(allocator, "test_extmarks");
    defer msgpack.free(ns_name, allocator);

    const ns_id_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_id_result, allocator);
    const ns_id = try msgpack.expectI64(ns_id_result);

    // Set an extmark
    var opts1 = msgpack.Value.mapPayload(allocator);
    defer opts1.free(allocator);

    const mark1_result = try client.request("nvim_buf_set_extmark", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(0),
        opts1,
    });
    defer msgpack.free(mark1_result, allocator);

    // Get all extmarks
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

    const extmarks = try msgpack.expectArray(result);
    try std.testing.expect(extmarks.len >= 1);
}

// Test nvim_buf_del_extmark
test "nvim_buf_del_extmark removes extmark" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const ns_name = try msgpack.string(allocator, "test_del");
    defer msgpack.free(ns_name, allocator);

    const ns_id_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_id_result, allocator);
    const ns_id = try msgpack.expectI64(ns_id_result);

    // Set extmark
    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const extmark_id_result = try client.request("nvim_buf_set_extmark", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(0),
        opts,
    });
    defer msgpack.free(extmark_id_result, allocator);
    const extmark_id = try msgpack.expectI64(extmark_id_result);

    // Delete extmark
    const del_result = try client.request("nvim_buf_del_extmark", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(extmark_id),
    });
    defer msgpack.free(del_result, allocator);

    const deleted = try msgpack.expectBool(del_result);
    try std.testing.expect(deleted);
}

// Test nvim_get_namespaces
test "nvim_get_namespaces returns namespace map" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Create a namespace
    const ns_name = try msgpack.string(allocator, "my_namespace");
    defer msgpack.free(ns_name, allocator);

    const ns_id_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_id_result, allocator);

    // Get all namespaces
    const result = try client.request("nvim_get_namespaces", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
    try std.testing.expect(result.map.count() > 0);
}

// Test nvim_buf_clear_namespace
test "nvim_buf_clear_namespace removes extmarks in range" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const ns_name = try msgpack.string(allocator, "clear_test");
    defer msgpack.free(ns_name, allocator);

    const ns_id_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_id_result, allocator);
    const ns_id = try msgpack.expectI64(ns_id_result);

    // Set extmark
    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const mark_result = try client.request("nvim_buf_set_extmark", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(0),
        opts,
    });
    defer msgpack.free(mark_result, allocator);

    // Clear namespace
    const result = try client.request("nvim_buf_clear_namespace", &.{
        buf,
        msgpack.int(ns_id),
        msgpack.int(0),
        msgpack.int(-1),
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_set_hl sets highlight group
test "nvim_set_hl defines highlight group" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const hl_name = try msgpack.string(allocator, "TestHighlight");
    defer msgpack.free(hl_name, allocator);

    var hl_def = msgpack.Value.mapPayload(allocator);
    defer hl_def.free(allocator);
    try hl_def.mapPut("fg", try msgpack.string(allocator, "#FF0000"));
    try hl_def.mapPut("bold", msgpack.boolean(true));

    const result = try client.request("nvim_set_hl", &.{
        msgpack.int(0), // global namespace
        hl_name,
        hl_def,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_get_hl retrieves highlight definition
test "nvim_get_hl retrieves highlight groups" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("name", try msgpack.string(allocator, "Normal"));

    const result = try client.request("nvim_get_hl", &.{
        msgpack.int(0),
        opts,
    });
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim_buf_add_highlight (legacy API)
test "nvim_buf_add_highlight adds highlight" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const ns_name = try msgpack.string(allocator, "hl_test");
    defer msgpack.free(ns_name, allocator);

    const ns_id_result = try client.request("nvim_create_namespace", &.{ns_name});
    defer msgpack.free(ns_id_result, allocator);
    const ns_id = try msgpack.expectI64(ns_id_result);

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
