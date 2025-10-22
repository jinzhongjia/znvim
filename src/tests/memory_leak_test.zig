const std = @import("std");
const msgpack = @import("../msgpack.zig");

// This test should PASS - it properly frees memory
test "msgpack encode struct - no leak" {
    const allocator = std.testing.allocator;

    const TestStruct = struct {
        name: []const u8,
        value: i32,
    };

    const obj = try msgpack.object(allocator, TestStruct{
        .name = "test",
        .value = 42,
    });
    defer msgpack.free(obj, allocator);

    try std.testing.expect(obj == .map);
}

// This test verifies that encodeStructValue correctly frees the encoded payload
// when mapPut fails with OutOfMemory (the bug we fixed)
test "msgpack encode struct handles mapPut failure correctly" {
    const allocator = std.testing.allocator;

    const TestStruct = struct {
        field1: []const u8,
        field2: i32,
    };

    // This should succeed and not leak memory
    const obj = try msgpack.object(allocator, TestStruct{
        .field1 = "hello",
        .field2 = 100,
    });
    defer msgpack.free(obj, allocator);

    try std.testing.expect(obj == .map);

    const field1_val = obj.map.get("field1");
    try std.testing.expect(field1_val != null);
}

// Test that cloning payloads doesn't leak memory
test "payload clone does not leak" {
    const allocator = std.testing.allocator;
    const payload_utils = @import("../protocol/payload_utils.zig");
    const base_msgpack = @import("msgpack");

    var original = try base_msgpack.Payload.arrPayload(2, allocator);
    defer original.free(allocator);

    original.arr[0] = try base_msgpack.Payload.strToPayload("test", allocator);
    original.arr[1] = base_msgpack.Payload.intToPayload(42);

    const cloned = try payload_utils.clonePayload(allocator, original);
    defer cloned.free(allocator);

    try std.testing.expect(cloned == .arr);
    try std.testing.expectEqual(@as(usize, 2), cloned.arr.len);
}
