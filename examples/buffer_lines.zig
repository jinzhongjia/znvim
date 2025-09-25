const std = @import("std");
const znvim = @import("znvim");
const msgpack = @import("msgpack");

const ExampleError = error{ MissingAddress, UnexpectedPayload };

// Helper that converts the payload returned by `vim_get_current_buffer` into a
// numeric handle. The actual type is an integer but MsgPack may encode it as
// signed or unsigned.
fn payloadToBufferHandle(payload: msgpack.Payload) !i64 {
    return switch (payload) {
        .int => payload.int,
        .uint => |value| std.math.cast(i64, value) orelse return error.UnexpectedPayload,
        else => error.UnexpectedPayload,
    };
}

// Build a MsgPack array of strings from a Zig slice. Many Neovim APIs expect
// string arrays; constructing them manually helps illustrate how znvim maps to
// MsgPack primitives.
fn makeStringArray(allocator: std.mem.Allocator, values: []const []const u8) !msgpack.Payload {
    var arr = try msgpack.Payload.arrPayload(values.len, allocator);
    errdefer arr.free(allocator);
    for (values, 0..) |line, idx| {
        arr.arr[idx] = try msgpack.Payload.strToPayload(line, allocator);
    }
    return arr;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("warning: leaked allocations\n", .{}),
    };
    const allocator = gpa.allocator();

    const address = std.process.getEnvVarOwned(allocator, "NVIM_LISTEN_ADDRESS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            std.debug.print("Set NVIM_LISTEN_ADDRESS before running this example.\n", .{});
            return ExampleError.MissingAddress;
        },
        else => return err,
    };
    defer allocator.free(address);

    var client = try znvim.Client.init(allocator, .{ .socket_path = address });
    defer client.deinit();
    try client.connect();

    // First obtain a handle to the current buffer so we can operate on it.
    var buf_handle_payload = try client.request("vim_get_current_buffer", &.{});
    defer buf_handle_payload.free(allocator);
    const buf_handle = try payloadToBufferHandle(buf_handle_payload);

    var replacement_lines = try makeStringArray(allocator, &.{ "Hello from znvim", "Have fun with Zig!" });
    defer replacement_lines.free(allocator);

    // Replace the buffer contents with the new lines. Neovim expects a handful
    // of integer flags in addition to the text array.
    const set_params = [_]msgpack.Payload{
        msgpack.Payload.intToPayload(buf_handle),
        msgpack.Payload.intToPayload(0),
        msgpack.Payload.intToPayload(-1),
        msgpack.Payload.boolToPayload(false),
        replacement_lines,
    };
    var set_result = try client.request("nvim_buf_set_lines", &set_params);
    defer set_result.free(allocator);

    // Read the lines back to confirm the change.
    const get_params = [_]msgpack.Payload{
        msgpack.Payload.intToPayload(buf_handle),
        msgpack.Payload.intToPayload(0),
        msgpack.Payload.intToPayload(-1),
        msgpack.Payload.boolToPayload(false),
    };
    var lines_payload = try client.request("nvim_buf_get_lines", &get_params);
    defer lines_payload.free(allocator);

    switch (lines_payload) {
        .arr => |lines| {
            std.debug.print("Buffer now contains:\n", .{});
            for (lines, 0..) |line_payload, idx| {
                switch (line_payload) {
                    .str => |s| std.debug.print("{d}: {s}\n", .{ idx + 1, s.value() }),
                    else => std.debug.print("{d}: {any}\n", .{ idx + 1, line_payload }),
                }
            }
        },
        else => return ExampleError.UnexpectedPayload,
    }
}
