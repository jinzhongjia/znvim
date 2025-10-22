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
            std.debug.print("Example: export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock\n", .{});
            return ExampleError.MissingAddress;
        },
        else => return err,
    };
    defer allocator.free(address);

    var client = try znvim.Client.init(allocator, .{ .socket_path = address });
    defer client.deinit();
    try client.connect();

    std.debug.print("Connected to Neovim!\n", .{});

    // Get the current buffer handle
    var buf_handle_payload = try client.request("nvim_get_current_buf", &.{});
    defer buf_handle_payload.free(allocator);
    const buf_handle = msgpack.expectI64(buf_handle_payload) catch return ExampleError.UnexpectedPayload;

    std.debug.print("Current buffer handle: {d}\n", .{buf_handle});

    // Prepare lines to write
    const replacement_lines = try msgpack.array(allocator, &.{
        "# Hello from znvim!",
        "This is a Zig Neovim RPC client library.",
        "",
        "Features:",
        "- MessagePack-RPC protocol support",
        "- Multiple transport types (Unix socket, TCP, stdio, child process)",
        "- Type-safe API",
        "- Memory leak detection",
        "",
        "Enjoy coding with Zig and Neovim!",
    });
    defer msgpack.free(replacement_lines, allocator);

    // Replace buffer contents: nvim_buf_set_lines(buffer, start, end, strict_indexing, replacement)
    const set_params = [_]msgpack.Value{
        msgpack.int(buf_handle), // buffer handle
        msgpack.int(0), // start line (0-indexed)
        msgpack.int(-1), // end line (-1 means end of buffer)
        msgpack.boolean(false), // strict_indexing
        replacement_lines, // the new lines
    };
    const set_result = try client.request("nvim_buf_set_lines", &set_params);
    defer msgpack.free(set_result, allocator);

    std.debug.print("Buffer lines updated successfully!\n", .{});

    // Read the lines back to confirm
    const get_params = [_]msgpack.Value{
        msgpack.int(buf_handle),
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    };
    const lines_payload = try client.request("nvim_buf_get_lines", &get_params);
    defer msgpack.free(lines_payload, allocator);

    const lines = msgpack.asArray(lines_payload) orelse return ExampleError.UnexpectedPayload;
    std.debug.print("\nBuffer now contains {d} lines:\n", .{lines.len});
    for (lines, 0..) |line_payload, idx| {
        if (msgpack.asString(line_payload)) |line| {
            std.debug.print("{d:3}: {s}\n", .{ idx + 1, line });
        } else {
            std.debug.print("{d:3}: <non-string: {any}>\n", .{ idx + 1, line_payload });
        }
    }
}
