const std = @import("std");
const znvim = @import("../root.zig");
const msgpack = znvim.msgpack;

test "msgpack encode primitives" {
    const allocator = std.testing.allocator;

    const bool_value = try msgpack.encode(allocator, true);
    defer msgpack.free(bool_value, allocator);
    try std.testing.expect(bool_value == .bool);
    try std.testing.expectEqual(true, try msgpack.expectBool(bool_value));
    try std.testing.expectEqual(true, msgpack.asBool(bool_value).?);

    const int_value = try msgpack.encode(allocator, @as(i32, -42));
    defer msgpack.free(int_value, allocator);
    try std.testing.expect(int_value == .int);
    try std.testing.expectEqual(@as(i64, -42), try msgpack.expectI64(int_value));
    try std.testing.expectEqual(@as(i64, -42), msgpack.asI64(int_value).?);

    const optional_null = try msgpack.encode(allocator, @as(?u8, null));
    defer msgpack.free(optional_null, allocator);
    try std.testing.expect(optional_null == .nil);

    const optional_value = try msgpack.encode(allocator, @as(?u8, 7));
    defer msgpack.free(optional_value, allocator);
    try std.testing.expectEqual(@as(u64, 7), try msgpack.expectU64(optional_value));
    try std.testing.expectEqual(@as(u64, 7), msgpack.asU64(optional_value).?);
}

test "msgpack string helper" {
    const allocator = std.testing.allocator;

    const str_value = try msgpack.string(allocator, "hello");
    defer msgpack.free(str_value, allocator);

    const text = try msgpack.expectString(str_value);
    try std.testing.expectEqualStrings("hello", text);
    try std.testing.expectEqualStrings("hello", msgpack.asString(str_value).?);
}

test "msgpack array helper encodes tuple" {
    const allocator = std.testing.allocator;

    const str_slice: []const u8 = "hi";
    const array_value = try msgpack.array(allocator, .{ true, @as(i8, -1), str_slice });
    defer msgpack.free(array_value, allocator);

    try std.testing.expect(array_value == .arr);

    const arr = try msgpack.expectArray(array_value);
    try std.testing.expectEqual(@as(usize, 3), arr.len);
    try std.testing.expectEqual(true, try msgpack.expectBool(arr[0]));
    try std.testing.expectEqual(@as(i64, -1), try msgpack.expectI64(arr[1]));
    const text = try msgpack.expectString(arr[2]);
    try std.testing.expectEqualStrings("hi", text);
}

test "msgpack object helper encodes struct" {
    const allocator = std.testing.allocator;

    const PayloadStruct = struct {
        foo: u32,
        bar: []const u8,
    };

    const obj_value = try msgpack.object(allocator, PayloadStruct{
        .foo = 9,
        .bar = "bar",
    });
    defer msgpack.free(obj_value, allocator);

    try std.testing.expect(obj_value == .map);

    const foo_payload_opt = obj_value.map.get("foo");
    try std.testing.expect(foo_payload_opt != null);
    const foo_payload = foo_payload_opt.?;
    try std.testing.expectEqual(@as(u64, 9), try msgpack.expectU64(foo_payload));

    const bar_payload_opt = obj_value.map.get("bar");
    try std.testing.expect(bar_payload_opt != null);
    const bar_payload = bar_payload_opt.?;
    const text = try msgpack.expectString(bar_payload);
    try std.testing.expectEqualStrings("bar", text);
}

test "msgpack expect error paths" {
    const bool_value = msgpack.boolean(true);
    try std.testing.expectError(msgpack.DecodeError.ExpectedArray, msgpack.expectArray(bool_value));

    const big_uint = msgpack.uint(std.math.maxInt(u64));
    try std.testing.expectError(msgpack.DecodeError.Overflow, msgpack.expectI64(big_uint));

    const negative_int = msgpack.int(-1);
    try std.testing.expectError(msgpack.DecodeError.Overflow, msgpack.expectU64(negative_int));
}

// ============================================================================
// Test: nil() function
// ============================================================================

test "msgpack nil() creates nil value" {
    const nil_value = msgpack.nil();
    try std.testing.expect(nil_value == .nil);
}

// ============================================================================
// Test: boolean() function
// ============================================================================

test "msgpack boolean() creates bool values" {
    const true_value = msgpack.boolean(true);
    try std.testing.expect(true_value == .bool);
    try std.testing.expectEqual(true, true_value.bool);

    const false_value = msgpack.boolean(false);
    try std.testing.expect(false_value == .bool);
    try std.testing.expectEqual(false, false_value.bool);
}

// ============================================================================
// Test: int() function
// ============================================================================

test "msgpack int() creates signed integer values" {
    const zero = msgpack.int(0);
    try std.testing.expect(zero == .int);
    try std.testing.expectEqual(@as(i64, 0), zero.int);

    const positive = msgpack.int(42);
    try std.testing.expect(positive == .int);
    try std.testing.expectEqual(@as(i64, 42), positive.int);

    const negative = msgpack.int(-123);
    try std.testing.expect(negative == .int);
    try std.testing.expectEqual(@as(i64, -123), negative.int);

    const max_int = msgpack.int(std.math.maxInt(i64));
    try std.testing.expect(max_int == .int);
    try std.testing.expectEqual(std.math.maxInt(i64), max_int.int);

    const min_int = msgpack.int(std.math.minInt(i64));
    try std.testing.expect(min_int == .int);
    try std.testing.expectEqual(std.math.minInt(i64), min_int.int);
}

// ============================================================================
// Test: uint() function
// ============================================================================

test "msgpack uint() creates unsigned integer values" {
    const zero = msgpack.uint(0);
    try std.testing.expect(zero == .uint);
    try std.testing.expectEqual(@as(u64, 0), zero.uint);

    const small = msgpack.uint(255);
    try std.testing.expect(small == .uint);
    try std.testing.expectEqual(@as(u64, 255), small.uint);

    const large = msgpack.uint(1_000_000);
    try std.testing.expect(large == .uint);
    try std.testing.expectEqual(@as(u64, 1_000_000), large.uint);

    const max_uint = msgpack.uint(std.math.maxInt(u64));
    try std.testing.expect(max_uint == .uint);
    try std.testing.expectEqual(std.math.maxInt(u64), max_uint.uint);
}

// ============================================================================
// Test: float() function
// ============================================================================

test "msgpack float() creates float values" {
    const allocator = std.testing.allocator;

    const zero = msgpack.float(0.0);
    defer msgpack.free(zero, allocator);
    try std.testing.expect(zero == .float);
    try std.testing.expectEqual(@as(f64, 0.0), zero.float);

    const positive = msgpack.float(3.14159);
    defer msgpack.free(positive, allocator);
    try std.testing.expect(positive == .float);
    try std.testing.expectApproxEqRel(@as(f64, 3.14159), positive.float, 0.00001);

    const negative = msgpack.float(-2.71828);
    defer msgpack.free(negative, allocator);
    try std.testing.expect(negative == .float);
    try std.testing.expectApproxEqRel(@as(f64, -2.71828), negative.float, 0.00001);

    const large = msgpack.float(1.23e100);
    defer msgpack.free(large, allocator);
    try std.testing.expect(large == .float);
    try std.testing.expectApproxEqRel(@as(f64, 1.23e100), large.float, 1e95);

    const small = msgpack.float(1.23e-100);
    defer msgpack.free(small, allocator);
    try std.testing.expect(small == .float);
    try std.testing.expectApproxEqRel(@as(f64, 1.23e-100), small.float, 1e-105);
}

test "msgpack float() handles special values" {
    const allocator = std.testing.allocator;

    const inf = msgpack.float(std.math.inf(f64));
    defer msgpack.free(inf, allocator);
    try std.testing.expect(inf == .float);
    try std.testing.expect(std.math.isInf(inf.float));
    try std.testing.expect(inf.float > 0);

    const neg_inf = msgpack.float(-std.math.inf(f64));
    defer msgpack.free(neg_inf, allocator);
    try std.testing.expect(neg_inf == .float);
    try std.testing.expect(std.math.isInf(neg_inf.float));
    try std.testing.expect(neg_inf.float < 0);

    const nan = msgpack.float(std.math.nan(f64));
    defer msgpack.free(nan, allocator);
    try std.testing.expect(nan == .float);
    try std.testing.expect(std.math.isNan(nan.float));
}

// ============================================================================
// Test: binary() function
// ============================================================================

test "msgpack binary() creates binary data" {
    const allocator = std.testing.allocator;

    // Empty binary
    const empty = try msgpack.binary(allocator, "");
    defer msgpack.free(empty, allocator);
    try std.testing.expect(empty == .bin);
    try std.testing.expectEqual(@as(usize, 0), empty.bin.value().len);

    // Small binary
    const small = try msgpack.binary(allocator, "hello");
    defer msgpack.free(small, allocator);
    try std.testing.expect(small == .bin);
    try std.testing.expectEqualStrings("hello", small.bin.value());

    // Binary with null bytes
    const with_nulls = try msgpack.binary(allocator, &[_]u8{ 0x00, 0x01, 0x02, 0x00, 0xFF });
    defer msgpack.free(with_nulls, allocator);
    try std.testing.expect(with_nulls == .bin);
    const expected = [_]u8{ 0x00, 0x01, 0x02, 0x00, 0xFF };
    try std.testing.expectEqualSlices(u8, &expected, with_nulls.bin.value());
}

test "msgpack binary() handles large data" {
    const allocator = std.testing.allocator;

    // Create 1KB of binary data
    var large_data: [1024]u8 = undefined;
    for (&large_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    const large_bin = try msgpack.binary(allocator, &large_data);
    defer msgpack.free(large_bin, allocator);
    try std.testing.expect(large_bin == .bin);
    try std.testing.expectEqual(@as(usize, 1024), large_bin.bin.value().len);
    try std.testing.expectEqualSlices(u8, &large_data, large_bin.bin.value());
}

// ============================================================================
// Test: as*() functions returning null
// ============================================================================

test "msgpack asArray() returns null for non-array" {
    const bool_val = msgpack.boolean(true);
    try std.testing.expect(msgpack.asArray(bool_val) == null);

    const int_val = msgpack.int(42);
    try std.testing.expect(msgpack.asArray(int_val) == null);

    const nil_val = msgpack.nil();
    try std.testing.expect(msgpack.asArray(nil_val) == null);
}

test "msgpack asString() returns null for non-string" {
    const bool_val = msgpack.boolean(true);
    try std.testing.expect(msgpack.asString(bool_val) == null);

    const int_val = msgpack.int(42);
    try std.testing.expect(msgpack.asString(int_val) == null);

    const nil_val = msgpack.nil();
    try std.testing.expect(msgpack.asString(nil_val) == null);

    const allocator = std.testing.allocator;
    const arr = try msgpack.array(allocator, .{@as(i64, 1)});
    defer msgpack.free(arr, allocator);
    try std.testing.expect(msgpack.asString(arr) == null);
}

test "msgpack asBool() returns null for non-bool" {
    const int_val = msgpack.int(42);
    try std.testing.expect(msgpack.asBool(int_val) == null);

    const nil_val = msgpack.nil();
    try std.testing.expect(msgpack.asBool(nil_val) == null);

    const allocator = std.testing.allocator;
    const str = try msgpack.string(allocator, "not a bool");
    defer msgpack.free(str, allocator);
    try std.testing.expect(msgpack.asBool(str) == null);
}

test "msgpack asI64() returns null for non-int" {
    const bool_val = msgpack.boolean(true);
    try std.testing.expect(msgpack.asI64(bool_val) == null);

    const nil_val = msgpack.nil();
    try std.testing.expect(msgpack.asI64(nil_val) == null);

    const allocator = std.testing.allocator;
    const str = try msgpack.string(allocator, "not an int");
    defer msgpack.free(str, allocator);
    try std.testing.expect(msgpack.asI64(str) == null);

    // uint that's too large for i64
    const big_uint = msgpack.uint(std.math.maxInt(u64));
    try std.testing.expect(msgpack.asI64(big_uint) == null);
}

test "msgpack asU64() returns null for non-uint" {
    const bool_val = msgpack.boolean(true);
    try std.testing.expect(msgpack.asU64(bool_val) == null);

    const nil_val = msgpack.nil();
    try std.testing.expect(msgpack.asU64(nil_val) == null);

    const allocator = std.testing.allocator;
    const str = try msgpack.string(allocator, "not a uint");
    defer msgpack.free(str, allocator);
    try std.testing.expect(msgpack.asU64(str) == null);

    // negative int
    const neg_int = msgpack.int(-1);
    try std.testing.expect(msgpack.asU64(neg_int) == null);
}

// ============================================================================
// Test: as*() functions returning values
// ============================================================================

test "msgpack asArray() returns array for valid array" {
    const allocator = std.testing.allocator;
    const arr = try msgpack.array(allocator, .{ @as(i64, 1), @as(i64, 2), @as(i64, 3) });
    defer msgpack.free(arr, allocator);

    const result = msgpack.asArray(arr);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(usize, 3), result.?.len);
}

test "msgpack asString() returns string for valid string" {
    const allocator = std.testing.allocator;
    const str = try msgpack.string(allocator, "test string");
    defer msgpack.free(str, allocator);

    const result = msgpack.asString(str);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("test string", result.?);
}

test "msgpack asBool() returns bool for valid bool" {
    const true_val = msgpack.boolean(true);
    const result_true = msgpack.asBool(true_val);
    try std.testing.expect(result_true != null);
    try std.testing.expectEqual(true, result_true.?);

    const false_val = msgpack.boolean(false);
    const result_false = msgpack.asBool(false_val);
    try std.testing.expect(result_false != null);
    try std.testing.expectEqual(false, result_false.?);
}

test "msgpack asI64() returns int for valid int" {
    const int_val = msgpack.int(42);
    const result = msgpack.asI64(int_val);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 42), result.?);

    // asI64 DOES convert small uint to i64 (using std.math.cast)
    const small_uint = msgpack.uint(100);
    const result2 = msgpack.asI64(small_uint);
    try std.testing.expect(result2 != null);
    try std.testing.expectEqual(@as(i64, 100), result2.?);

    // But large uint that doesn't fit in i64 returns null
    const big_uint = msgpack.uint(std.math.maxInt(u64));
    const result3 = msgpack.asI64(big_uint);
    try std.testing.expect(result3 == null);
}

test "msgpack asU64() returns uint for valid uint" {
    const uint_val = msgpack.uint(42);
    const result = msgpack.asU64(uint_val);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(u64, 42), result.?);

    // asU64 does NOT convert int to uint (that's what expectU64 does)
    const pos_int = msgpack.int(100);
    const result2 = msgpack.asU64(pos_int);
    try std.testing.expect(result2 == null); // No conversion, returns null
}
