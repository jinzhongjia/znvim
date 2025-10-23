const std = @import("std");
const protocol = @import("../protocol/mod.zig");
const msgpack = @import("msgpack");

// Manual fuzzing test cases - curated malformed inputs to test decoder robustness

test "fuzz: all zeros" {
    const allocator = std.testing.allocator;
    const input = [_]u8{0x00} ** 100;

    // Should fail gracefully
    if (protocol.decoder.decode(allocator, &input)) |_| {
        unreachable; // Shouldn't decode successfully
    } else |_| {
        // Expected to fail
    }
}

test "fuzz: all ones" {
    const allocator = std.testing.allocator;
    const input = [_]u8{0xFF} ** 100;

    if (protocol.decoder.decode(allocator, &input)) |r| {
        var msg = r.message;
        defer protocol.message.deinitMessage(&msg, allocator);
        // If it decodes, verify we can re-encode
        switch (msg) {
            .Request => |req| {
                if (protocol.encoder.encodeRequest(allocator, req)) |reencoded| {
                    defer allocator.free(reencoded);
                } else |_| {}
            },
            .Response => |resp| {
                if (protocol.encoder.encodeResponse(allocator, resp)) |reencoded| {
                    defer allocator.free(reencoded);
                } else |_| {}
            },
            .Notification => |notif| {
                if (protocol.encoder.encodeNotification(allocator, notif)) |reencoded| {
                    defer allocator.free(reencoded);
                } else |_| {}
            },
        }
    } else |_| {
        // Expected to fail
    }
}

// NOTE: This test was previously disabled due to crashes in zig-msgpack 0.0.13.
// zig-msgpack 0.0.14 has fixed the recursion depth issue, so we're re-enabling it.
// Success! This demonstrates the value of fuzzing AND the value of upstream fixes.

test "fuzz: random bytes" {
    const allocator = std.testing.allocator;

    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();

    var buffer: [200]u8 = undefined;

    // Test with 100 random inputs - now safe with zig-msgpack 0.0.14+
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        random.bytes(&buffer);

        // Should not crash with zig-msgpack 0.0.14+
        if (protocol.decoder.decode(allocator, &buffer)) |r| {
            var msg = r.message;
            defer protocol.message.deinitMessage(&msg, allocator);
            // Successfully decoded random data - rare, but possible
        } else |_| {
            // Expected - most random bytes won't be valid MessagePack
        }
    }
}

test "fuzz: controlled random patterns" {
    const allocator = std.testing.allocator;

    // Additional targeted patterns to test specific edge cases
    const patterns = [_][]const u8{
        &[_]u8{ 0x91, 0x91, 0x91, 0x00 }, // Nested arrays
        &[_]u8{ 0x94, 0x00, 0x01, 0xa0 }, // Incomplete request
        &[_]u8{ 0xde, 0x00, 0x00 }, // Map16 with 0 length
        &[_]u8{ 0xdc, 0x00, 0x00 }, // Array16 with 0 length
        &[_]u8{ 0xc0, 0xc0, 0xc0, 0xc0 }, // Multiple nils
    };

    for (patterns) |pattern| {
        if (protocol.decoder.decode(allocator, pattern)) |r| {
            var msg = r.message;
            defer protocol.message.deinitMessage(&msg, allocator);
        } else |_| {
            // Expected to fail on malformed patterns
        }
    }
}

test "fuzz: truncated valid message" {
    const allocator = std.testing.allocator;

    // Create a valid request
    var request = protocol.message.Request{
        .msgid = 42,
        .method = "nvim_get_mode",
        .params = try msgpack.Payload.arrPayload(0, allocator),
    };
    defer request.deinit(allocator);

    const valid_bytes = try protocol.encoder.encodeRequest(allocator, request);
    defer allocator.free(valid_bytes);

    // Try truncating at every position
    var truncate_at: usize = 1;
    while (truncate_at < valid_bytes.len) : (truncate_at += 1) {
        const truncated = valid_bytes[0..truncate_at];

        if (protocol.decoder.decode(allocator, truncated)) |r| {
            var msg = r.message;
            defer protocol.message.deinitMessage(&msg, allocator);
            // Somehow decoded truncated data - should not happen for most positions
        } else |err| {
            // Expected to fail on truncated messages
            switch (err) {
                error.LengthReading,
                error.InvalidMessageFormat,
                error.InvalidFieldType,
                error.InvalidMessageType => {},
                else => {
                    std.debug.print("Unexpected error on truncate_at={}: {}\n", .{ truncate_at, err });
                    return err;
                },
            }
        }
    }
}

test "fuzz: oversized array declaration" {
    const allocator = std.testing.allocator;

    // Manually craft MessagePack with array claiming huge size
    var input = std.ArrayListUnmanaged(u8){};
    defer input.deinit(allocator);

    // MessagePack array with fixarray (4 elements) but only provide 2
    try input.append(allocator, 0x94); // fixarray with 4 elements
    try input.append(allocator, 0x00); // element 0: int 0 (message type)
    try input.append(allocator, 0x01); // element 1: int 1 (msgid)
    // Missing elements 2 and 3

    const result = protocol.decoder.decode(allocator, input.items);
    try std.testing.expectError(error.LengthReading, result);
}

test "fuzz: deeply nested arrays" {
    const allocator = std.testing.allocator;

    // Create deeply nested structure: [[[[...]]]]
    var input = std.ArrayListUnmanaged(u8){};
    defer input.deinit(allocator);

    const depth = 100;
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        try input.append(allocator, 0x91); // fixarray with 1 element
    }
    try input.append(allocator, 0x00); // innermost element: int 0

    // This should decode but might stress the stack
    if (protocol.decoder.decode(allocator, input.items)) |r| {
        var msg = r.message;
        defer protocol.message.deinitMessage(&msg, allocator);
        // Decoded successfully - verify structure
    } else |_| {
        // Might fail due to depth limits or format issues
    }
}

test "fuzz: invalid message type 255" {
    const allocator = std.testing.allocator;

    var input = std.ArrayListUnmanaged(u8){};
    defer input.deinit(allocator);

    // Array with 4 elements
    try input.append(allocator, 0x94);
    try input.append(allocator, 0xcc); // uint8
    try input.append(allocator, 0xFF); // value 255 (invalid message type)
    try input.append(allocator, 0x00); // msgid
    try input.append(allocator, 0xa0); // empty string (method)
    try input.append(allocator, 0x90); // empty array (params)

    const result = protocol.decoder.decode(allocator, input.items);
    try std.testing.expectError(error.InvalidMessageType, result);
}

test "fuzz: negative message id" {
    const allocator = std.testing.allocator;

    var input = std.ArrayListUnmanaged(u8){};
    defer input.deinit(allocator);

    // Request with negative msgid
    try input.append(allocator, 0x94); // fixarray 4
    try input.append(allocator, 0x00); // type: Request
    try input.append(allocator, 0xff); // int -1
    try input.append(allocator, 0xa0); // empty string
    try input.append(allocator, 0x90); // empty array

    const result = protocol.decoder.decode(allocator, input.items);
    try std.testing.expectError(error.InvalidFieldType, result);
}

test "fuzz: extremely long method name" {
    const allocator = std.testing.allocator;

    var input = std.ArrayListUnmanaged(u8){};
    defer input.deinit(allocator);

    // Request with 65KB method name
    try input.append(allocator, 0x94); // fixarray 4
    try input.append(allocator, 0x00); // type: Request
    try input.append(allocator, 0x01); // msgid: 1

    // str32 format: 0xdb + 4 byte length + data
    try input.append(allocator, 0xdb);
    const len: u32 = 65535;

    var len_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_bytes, len, .big);
    try input.appendSlice(allocator, &len_bytes);

    // Append 65KB of 'A'
    const method_data = try allocator.alloc(u8, len);
    defer allocator.free(method_data);
    @memset(method_data, 'A');
    try input.appendSlice(allocator, method_data);

    // Empty params array
    try input.append(allocator, 0x90);

    if (protocol.decoder.decode(allocator, input.items)) |r| {
        var msg = r.message;
        defer protocol.message.deinitMessage(&msg, allocator);

        switch (msg) {
            .Request => |req| {
                // Should decode successfully
                try std.testing.expectEqual(@as(usize, 65535), req.method.len);
                try std.testing.expectEqual(@as(u8, 'A'), req.method[0]);
            },
            else => return error.UnexpectedMessageType,
        }
    } else |err| {
        // Might fail due to memory limits
        switch (err) {
            error.OutOfMemory => {},
            else => return err,
        }
    }
}

test "fuzz: response with both error and result" {
    const allocator = std.testing.allocator;

    // Create response with both error and result (unusual but valid?)
    var response = protocol.message.Response{
        .msgid = 1,
        .@"error" = try msgpack.Payload.strToPayload("error", allocator),
        .result = msgpack.Payload.intToPayload(42),
    };
    const bytes = try protocol.encoder.encodeResponse(allocator, response);
    defer allocator.free(bytes);
    if (response.@"error") |*e| e.*.free(allocator);

    const decoded = try protocol.decoder.decode(allocator, bytes);
    var msg = decoded.message;
    defer protocol.message.deinitMessage(&msg, allocator);

    switch (msg) {
        .Response => |resp| {
            // Both fields should be preserved
            try std.testing.expect(resp.@"error" != null);
            try std.testing.expect(resp.result != null);
        },
        else => return error.UnexpectedMessageType,
    }
}

test "fuzz: notification with non-string method" {
    const allocator = std.testing.allocator;

    var input = std.ArrayListUnmanaged(u8){};
    defer input.deinit(allocator);

    // Notification with integer instead of string method
    try input.append(allocator, 0x93); // fixarray 3
    try input.append(allocator, 0x02); // type: Notification
    try input.append(allocator, 0x2a); // int 42 (should be string!)
    try input.append(allocator, 0x90); // empty array params

    const result = protocol.decoder.decode(allocator, input.items);
    try std.testing.expectError(error.InvalidFieldType, result);
}

test "fuzz: request with map instead of array params" {
    const allocator = std.testing.allocator;

    var input = std.ArrayListUnmanaged(u8){};
    defer input.deinit(allocator);

    // Request with map params (should be array)
    try input.append(allocator, 0x94); // fixarray 4
    try input.append(allocator, 0x00); // type: Request
    try input.append(allocator, 0x01); // msgid: 1
    try input.append(allocator, 0xa4); // str "test"
    try input.appendSlice(allocator, "test");
    try input.append(allocator, 0x80); // empty map (should be array!)

    // Should decode - params can be any Payload
    if (protocol.decoder.decode(allocator, input.items)) |r| {
        var msg = r.message;
        defer protocol.message.deinitMessage(&msg, allocator);

        switch (msg) {
            .Request => |req| {
                // Params can be a map - it's valid MessagePack
                try std.testing.expect(req.params == .map);
            },
            else => return error.UnexpectedMessageType,
        }
    } else |err| {
        return err;
    }
}

test "fuzz: empty input" {
    const allocator = std.testing.allocator;
    const empty = [_]u8{};

    const result = protocol.decoder.decode(allocator, &empty);
    try std.testing.expectError(error.LengthReading, result);
}

test "fuzz: single byte inputs" {
    const allocator = std.testing.allocator;

    // Try all possible single-byte inputs
    var byte: u8 = 0;
    while (true) : (byte +%= 1) {
        const input = [_]u8{byte};

        _ = protocol.decoder.decode(allocator, &input) catch {};

        if (byte == 255) break;
    }
}

test "fuzz: two byte combinations" {
    const allocator = std.testing.allocator;

    // Sample of two-byte combinations (exhaustive would be 65K tests)
    const test_cases = [_][2]u8{
        .{ 0x00, 0x00 },
        .{ 0xFF, 0xFF },
        .{ 0x90, 0x91 }, // Array combinations
        .{ 0xdc, 0x00 }, // Array16 with 0 length
        .{ 0xde, 0x00 }, // Map16 with 0 length
        .{ 0xc0, 0xc2 }, // nil, false
        .{ 0x94, 0x00 }, // fixarray(4), int 0
    };

    for (test_cases) |case| {
        _ = protocol.decoder.decode(allocator, &case) catch {};
    }
}
