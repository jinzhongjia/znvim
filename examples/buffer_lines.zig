const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;

const ExampleError = error{ MissingAddress, UnexpectedPayload };

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
    const buf_handle = msgpack.expectI64(buf_handle_payload) catch return ExampleError.UnexpectedPayload;

    const replacement_lines = try msgpack.array(allocator, &.{ "Hello from znvim", "Have fun with Zig!" });
    defer msgpack.free(replacement_lines, allocator);

    // Replace the buffer contents with the new lines. Neovim expects a handful
    // of integer flags in addition to the text array.
    const set_params = [_]msgpack.Value{
        msgpack.int(buf_handle),
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        replacement_lines,
    };
    const set_result = try client.request("nvim_buf_set_lines", &set_params);
    defer msgpack.free(set_result, allocator);

    // Read the lines back to confirm the change.
    const get_params = [_]msgpack.Value{
        msgpack.int(buf_handle),
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    };
    const lines_payload = try client.request("nvim_buf_get_lines", &get_params);
    defer msgpack.free(lines_payload, allocator);

    const lines = msgpack.asArray(lines_payload) orelse return ExampleError.UnexpectedPayload;
    std.debug.print("Buffer now contains:\n", .{});
    for (lines, 0..) |line_payload, idx| {
        if (msgpack.asString(line_payload)) |line| {
            std.debug.print("{d}: {s}\n", .{ idx + 1, line });
        } else {
            std.debug.print("{d}: {any}\n", .{ idx + 1, line_payload });
        }
    }
}
