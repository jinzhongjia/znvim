const std = @import("std");
const base = @import("msgpack");

const AllocatorError = std.mem.Allocator.Error;

pub const Value = base.Payload;
pub const Map = base.Map;

pub const EncodeError = AllocatorError || error{
    Overflow,
    NonStringKey,
};

pub const DecodeError = error{
    ExpectedArray,
    ExpectedMap,
    ExpectedString,
    ExpectedBool,
    ExpectedInt,
    Overflow,
};

pub fn nil() Value {
    return base.Payload.nilToPayload();
}

pub fn boolean(value: bool) Value {
    return base.Payload.boolToPayload(value);
}

pub fn int(value: i64) Value {
    return base.Payload.intToPayload(value);
}

pub fn uint(value: u64) Value {
    return base.Payload.uintToPayload(value);
}

pub fn float(value: f64) Value {
    return base.Payload.floatToPayload(value);
}

pub fn string(allocator: std.mem.Allocator, text: []const u8) !Value {
    return base.Payload.strToPayload(text, allocator);
}

pub fn binary(allocator: std.mem.Allocator, bytes: []const u8) !Value {
    return base.Payload.binToPayload(bytes, allocator);
}

/// Encode any Zig value into a MessagePack Value.
pub fn encode(allocator: std.mem.Allocator, value: anytype) EncodeError!Value {
    return try encodeInternal(allocator, value);
}

/// Convenience helper for building MessagePack arrays from Zig tuples, arrays or slices.
pub fn array(allocator: std.mem.Allocator, values: anytype) EncodeError!Value {
    return try encodeSequence(allocator, values);
}

/// Convenience helper for turning Zig structs into MessagePack maps. Field names are used as keys.
pub fn object(allocator: std.mem.Allocator, value: anytype) EncodeError!Value {
    return try encodeStruct(allocator, value);
}

pub fn expectArray(value: Value) DecodeError![]Value {
    return if (value == .arr) value.arr else DecodeError.ExpectedArray;
}

pub fn expectString(value: Value) DecodeError![]const u8 {
    return switch (value) {
        .str => |s| s.value(),
        else => DecodeError.ExpectedString,
    };
}

pub fn expectBool(value: Value) DecodeError!bool {
    return if (value == .bool) value.bool else DecodeError.ExpectedBool;
}

pub fn expectI64(value: Value) DecodeError!i64 {
    return switch (value) {
        .int => value.int,
        .uint => |v| std.math.cast(i64, v) orelse DecodeError.Overflow,
        else => DecodeError.ExpectedInt,
    };
}

pub fn expectU64(value: Value) DecodeError!u64 {
    return switch (value) {
        .uint => value.uint,
        .int => |v| std.math.cast(u64, v) orelse DecodeError.Overflow,
        else => DecodeError.ExpectedInt,
    };
}

pub fn asArray(value: Value) ?[]Value {
    return if (value == .arr) value.arr else null;
}

pub fn asString(value: Value) ?[]const u8 {
    return switch (value) {
        .str => |s| s.value(),
        else => null,
    };
}

pub fn asBool(value: Value) ?bool {
    return if (value == .bool) value.bool else null;
}

pub fn asI64(value: Value) ?i64 {
    return switch (value) {
        .int => value.int,
        .uint => |v| std.math.cast(i64, v),
        else => null,
    };
}

pub fn asU64(value: Value) ?u64 {
    return if (value == .uint) value.uint else null;
}

pub fn free(value: Value, allocator: std.mem.Allocator) void {
    value.free(allocator);
}

fn encodeInternal(allocator: std.mem.Allocator, value: anytype) EncodeError!Value {
    const T = @TypeOf(value);

    if (T == Value) return value;

    switch (@typeInfo(T)) {
        .bool => return boolean(value),
        .int => |info| switch (info.signedness) {
            .signed => {
                const converted = std.math.cast(i64, value) orelse return EncodeError.Overflow;
                return int(converted);
            },
            .unsigned => {
                const converted = std.math.cast(u64, value) orelse return EncodeError.Overflow;
                return uint(converted);
            },
        },
        .comptime_int => return if (value < 0)
            int(@as(i64, value))
        else
            uint(@as(u64, value)),
        .float => return float(value),
        .comptime_float => return float(value),
        .@"enum" => {
            return try encodeInternal(allocator, @intFromEnum(value));
        },
        .error_set => return try string(allocator, @errorName(value)),
        .optional => {
            return if (value) |some|
                try encodeInternal(allocator, some)
            else
                nil();
        },
        .pointer => |ptr_info| {
            return switch (ptr_info.size) {
                .slice => encodeSlicePtr(allocator, value, ptr_info),
                .one => encodePointer(allocator, value, ptr_info),
                else => @compileError("Unsupported pointer type for msgpack encoding"),
            };
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                if (arr_info.sentinel) |sentinel| {
                    _ = sentinel;
                }
                return try string(allocator, value[0..]);
            }
            return try encodeArrayLiteral(allocator, value);
        },
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                return try encodeTuple(allocator, value, struct_info);
            }
            return try encodeStructValue(allocator, value, struct_info);
        },
        .@"union" => @compileError("Unsupported union type for msgpack encoding"),
        else => @compileError("Unsupported type for msgpack encoding"),
    }
}

fn encodeSlicePtr(allocator: std.mem.Allocator, slice: anytype, info: std.builtin.Type.Pointer) EncodeError!Value {
    if (info.child == u8) {
        if (info.is_const) {
            return try string(allocator, slice);
        }
        return try binary(allocator, slice);
    }
    return try encodeSlice(allocator, slice);
}

fn encodePointer(allocator: std.mem.Allocator, ptr: anytype, info: std.builtin.Type.Pointer) EncodeError!Value {
    if (info.child == Value) {
        return ptr.*;
    }
    switch (@typeInfo(info.child)) {
        .array => return try encodeSequence(allocator, ptr.*),
        .@"struct" => return try encodeStruct(allocator, ptr.*),
        .int, .comptime_int, .float, .comptime_float, .bool, .@"enum", .optional, .error_set => {
            return try encodeInternal(allocator, ptr.*);
        },
        else => @compileError("Unsupported pointer child type for msgpack encoding"),
    }
}

fn encodeSlice(allocator: std.mem.Allocator, slice: anytype) EncodeError!Value {
    var arr = try base.Payload.arrPayload(slice.len, allocator);
    errdefer arr.free(allocator);

    for (slice, 0..) |item, idx| {
        arr.arr[idx] = try encodeInternal(allocator, item);
    }

    return arr;
}

fn encodeArrayLiteral(allocator: std.mem.Allocator, literal: anytype) EncodeError!Value {
    var arr = try base.Payload.arrPayload(literal.len, allocator);
    errdefer arr.free(allocator);

    for (literal, 0..) |item, idx| {
        arr.arr[idx] = try encodeInternal(allocator, item);
    }

    return arr;
}

fn encodeTuple(
    allocator: std.mem.Allocator,
    tuple: anytype,
    info: std.builtin.Type.Struct,
) EncodeError!Value {
    var arr = try base.Payload.arrPayload(info.fields.len, allocator);
    errdefer arr.free(allocator);

    inline for (info.fields, 0..) |field, idx| {
        arr.arr[idx] = try encodeInternal(allocator, @field(tuple, field.name));
    }

    return arr;
}

fn encodeSequence(allocator: std.mem.Allocator, seq: anytype) EncodeError!Value {
    const T = @TypeOf(seq);
    return switch (@typeInfo(T)) {
        .pointer => |ptr_info| switch (ptr_info.size) {
            .slice => encodeSlice(allocator, seq),
            .one => encodeSequence(allocator, seq.*),
            else => @compileError("msgpack.array expects a slice, array, or tuple"),
        },
        .array => encodeArrayLiteral(allocator, seq),
        .@"struct" => |struct_info| {
            if (!struct_info.is_tuple) {
                @compileError("msgpack.array expects a tuple-like value");
            }
            return encodeTuple(allocator, seq, struct_info);
        },
        else => @compileError("msgpack.array expects a slice, array, or tuple"),
    };
}

fn encodeStruct(allocator: std.mem.Allocator, value: anytype) EncodeError!Value {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    return switch (info) {
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                return encodeTuple(allocator, value, struct_info);
            }
            return encodeStructValue(allocator, value, struct_info);
        },
        else => @compileError("msgpack.object expects a struct"),
    };
}

fn encodeStructValue(
    allocator: std.mem.Allocator,
    value: anytype,
    info: std.builtin.Type.Struct,
) EncodeError!Value {
    var map = base.Payload.mapPayload(allocator);
    errdefer map.free(allocator);

    inline for (info.fields) |field| {
        const field_value = @field(value, field.name);
        const encoded = try encodeInternal(allocator, field_value);
        try map.mapPut(field.name, encoded);
    }

    return map;
}
