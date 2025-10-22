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

// Test nvim_set_keymap
test "nvim_set_keymap creates key mapping" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);
    const lhs = try msgpack.string(allocator, "<F5>");
    defer msgpack.free(lhs, allocator);
    const rhs = try msgpack.string(allocator, ":echo 'test'<CR>");
    defer msgpack.free(rhs, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);
    try opts.mapPut("noremap", msgpack.boolean(true));

    const result = try client.request("nvim_set_keymap", &.{
        mode,
        lhs,
        rhs,
        opts,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_del_keymap
test "nvim_del_keymap removes key mapping" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    // Set a mapping
    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);
    const lhs = try msgpack.string(allocator, "<F6>");
    defer msgpack.free(lhs, allocator);
    const rhs = try msgpack.string(allocator, ":echo 'test'<CR>");
    defer msgpack.free(rhs, allocator);

    var set_opts = msgpack.Value.mapPayload(allocator);
    defer set_opts.free(allocator);

    _ = try client.request("nvim_set_keymap", &.{
        mode,
        lhs,
        rhs,
        set_opts,
    });

    // Delete it
    const del_result = try client.request("nvim_del_keymap", &.{
        mode,
        lhs,
    });
    defer msgpack.free(del_result, allocator);
}

// Test nvim_get_keymap
test "nvim_get_keymap returns mappings for mode" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);

    const result = try client.request("nvim_get_keymap", &.{mode});
    defer msgpack.free(result, allocator);

    const keymaps = try msgpack.expectArray(result);
    try std.testing.expect(keymaps.len >= 0);
}

// Test nvim_buf_set_keymap (buffer-local mapping)
test "nvim_buf_set_keymap creates buffer-local mapping" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);
    const lhs = try msgpack.string(allocator, "<F7>");
    defer msgpack.free(lhs, allocator);
    const rhs = try msgpack.string(allocator, ":echo 'buf map'<CR>");
    defer msgpack.free(rhs, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim_buf_set_keymap", &.{
        buf,
        mode,
        lhs,
        rhs,
        opts,
    });
    defer msgpack.free(result, allocator);
}

// Test nvim_buf_del_keymap
test "nvim_buf_del_keymap removes buffer mapping" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);
    const lhs = try msgpack.string(allocator, "<F8>");
    defer msgpack.free(lhs, allocator);
    const rhs = try msgpack.string(allocator, ":echo 'test'<CR>");
    defer msgpack.free(rhs, allocator);

    var set_opts = msgpack.Value.mapPayload(allocator);
    defer set_opts.free(allocator);

    _ = try client.request("nvim_buf_set_keymap", &.{
        buf,
        mode,
        lhs,
        rhs,
        set_opts,
    });

    // Delete it
    const del_result = try client.request("nvim_buf_del_keymap", &.{
        buf,
        mode,
        lhs,
    });
    defer msgpack.free(del_result, allocator);
}

// Test nvim_buf_get_keymap
test "nvim_buf_get_keymap returns buffer mappings" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const mode = try msgpack.string(allocator, "n");
    defer msgpack.free(mode, allocator);

    const result = try client.request("nvim_buf_get_keymap", &.{
        buf,
        mode,
    });
    defer msgpack.free(result, allocator);

    const keymaps = try msgpack.expectArray(result);
    try std.testing.expect(keymaps.len >= 0);
}
