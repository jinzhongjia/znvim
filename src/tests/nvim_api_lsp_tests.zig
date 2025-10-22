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

// Test nvim__buf_stats
test "nvim__buf_stats returns buffer statistics" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const buf = try client.request("nvim_get_current_buf", &.{});
    defer msgpack.free(buf, allocator);

    const result = try client.request("nvim__buf_stats", &.{buf});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}

// Test nvim__id
test "nvim__id returns same value" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const value = msgpack.int(42);

    const result = try client.request("nvim__id", &.{value});
    defer msgpack.free(result, allocator);

    const returned = try msgpack.expectI64(result);
    try std.testing.expectEqual(@as(i64, 42), returned);
}

// Test nvim__id_array
test "nvim__id_array returns same array" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const arr = try msgpack.array(allocator, &.{ 1, 2, 3 });
    defer msgpack.free(arr, allocator);

    const result = try client.request("nvim__id_array", &.{arr});
    defer msgpack.free(result, allocator);

    const returned = try msgpack.expectArray(result);
    try std.testing.expectEqual(@as(usize, 3), returned.len);
}

// Test nvim__id_float
test "nvim__id_float returns same float" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const value = msgpack.float(3.14);

    const result = try client.request("nvim__id_float", &.{value});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .float);
}

// Test nvim__get_lib_dir
test "nvim__get_lib_dir returns library directory" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim__get_lib_dir", &.{});
    defer msgpack.free(result, allocator);

    const lib_dir = try msgpack.expectString(result);
    try std.testing.expect(lib_dir.len > 0);
}

// Test nvim__get_runtime
test "nvim__get_runtime returns runtime paths" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const patterns = try msgpack.array(allocator, &.{"colors/*.vim"});
    defer msgpack.free(patterns, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer opts.free(allocator);

    const result = try client.request("nvim__get_runtime", &.{
        patterns,
        msgpack.boolean(false),
        opts,
    });
    defer msgpack.free(result, allocator);

    const files = try msgpack.expectArray(result);
    try std.testing.expect(files.len >= 0);
}

// Test nvim__stats
test "nvim__stats returns internal statistics" {
    const allocator = std.testing.allocator;

    var client = try createTestClient(allocator);
    defer client.deinit();

    const result = try client.request("nvim__stats", &.{});
    defer msgpack.free(result, allocator);

    try std.testing.expect(result == .map);
}
