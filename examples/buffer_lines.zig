const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;
const helper = @import("connection_helper.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("Warning: Memory leak detected\n", .{}),
    };
    const allocator = gpa.allocator();

    std.debug.print("=== Buffer Lines Example ===\n\n", .{});

    // Smart connect to Neovim
    var client = try helper.smartConnect(allocator);
    defer client.deinit();

    std.debug.print("Connected to Neovim!\n\n", .{});

    // Create a new buffer for demonstration
    std.debug.print("Creating a new buffer...\n", .{});
    const buf = try client.request("nvim_create_buf", &[_]msgpack.Value{
        msgpack.boolean(true), // listed
        msgpack.boolean(false), // not scratch
    });
    defer msgpack.free(buf, allocator);

    std.debug.print("Buffer created successfully!\n\n", .{});

    // Prepare lines to write
    const lines_text = [_][]const u8{
        "# Hello from znvim!",
        "This is a Zig Neovim RPC client library.",
        "",
        "Features:",
        "- MessagePack-RPC protocol support",
        "- Multiple transport types (Unix socket, TCP, stdio, child process)",
        "- Type-safe API",
        "- Cross-platform support (Windows, Linux, macOS)",
        "",
        "Enjoy coding with Zig and Neovim!",
    };

    var lines_list = std.array_list.AlignedManaged(msgpack.Value, null).init(allocator);
    defer lines_list.deinit();

    for (lines_text) |line| {
        const line_val = try msgpack.string(allocator, line);
        try lines_list.append(line_val);
    }

    const replacement_lines = try msgpack.array(allocator, lines_list.items);
    defer msgpack.free(replacement_lines, allocator);

    // Replace buffer contents: nvim_buf_set_lines(buffer, start, end, strict_indexing, replacement)
    std.debug.print("Writing lines to buffer...\n", .{});
    const set_result = try client.request("nvim_buf_set_lines", &.{
        buf, // buffer handle (use directly as msgpack.Value)
        msgpack.int(0), // start line (0-indexed)
        msgpack.int(-1), // end line (-1 means end of buffer)
        msgpack.boolean(false), // strict_indexing
        replacement_lines, // the new lines
    });
    defer msgpack.free(set_result, allocator);

    std.debug.print("Buffer lines updated successfully!\n\n", .{});

    // Read the lines back to confirm
    std.debug.print("Reading lines back from buffer...\n", .{});
    const lines_payload = try client.request("nvim_buf_get_lines", &.{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(lines_payload, allocator);

    const lines = try msgpack.expectArray(lines_payload);
    std.debug.print("\nBuffer now contains {d} lines:\n", .{lines.len});
    std.debug.print("-------------------------------------------\n", .{});
    for (lines, 0..) |line_payload, idx| {
        if (msgpack.asString(line_payload)) |line| {
            std.debug.print("{d:3}: {s}\n", .{ idx + 1, line });
        } else {
            std.debug.print("{d:3}: <non-string>\n", .{idx + 1});
        }
    }
    std.debug.print("-------------------------------------------\n\n", .{});

    std.debug.print("Example completed successfully!\n", .{});
}
