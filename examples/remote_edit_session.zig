const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;
const helper = @import("connection_helper.zig");

/// Production example: Remote editing session
///
/// Features:
/// - Supports all platforms and all connection methods
/// - Connect to remote/local Neovim instance
/// - Real-time view and modify buffers
/// - Monitor editing events
/// - Sync editing state
///
/// Use cases:
/// - Remote collaborative editing
/// - Automated testing and validation
/// - Editor integration
/// - Real-time code review
const SessionConfig = struct {
    monitor_changes: bool = true,
    auto_save: bool = false,
    show_cursor_position: bool = true,
    refresh_interval_ms: u64 = 1000,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("Warning: Memory leak detected\n", .{}),
    };
    const allocator = gpa.allocator();

    // Parse command-line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // Skip program name

    var show_help = false;
    var monitor = false;
    var filepath: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--monitor") or std.mem.eql(u8, arg, "-m")) {
            monitor = true;
        } else if (filepath == null) {
            filepath = arg;
        }
    }

    if (show_help) {
        printUsage();
        return;
    }

    std.debug.print("=== Remote Editing Session ===\n\n", .{});

    // Smart connect to Neovim
    var client = try helper.smartConnect(allocator);
    defer client.deinit();

    // Get API info
    const api_info = client.getApiInfo() orelse return error.ApiInfoUnavailable;
    std.debug.print("Neovim version: {d}.{d}.{d}\n", .{
        api_info.version.major,
        api_info.version.minor,
        api_info.version.patch,
    });
    std.debug.print("Channel ID: {d}\n\n", .{api_info.channel_id});

    const config = SessionConfig{
        .monitor_changes = monitor,
    };

    if (filepath) |path| {
        try editFile(&client, allocator, config, path);
    } else {
        try demonstrateSession(&client, allocator, config);
    }
}

fn demonstrateSession(client: *znvim.Client, allocator: std.mem.Allocator, config: SessionConfig) !void {
    std.debug.print("=== Editing Session Demo ===\n\n", .{});

    // 1. Get current editor state
    try printEditorState(client, allocator);

    // 2. Create new buffer and edit
    std.debug.print("Creating new buffer...\n", .{});
    const buf = try client.request("nvim_create_buf", &[_]msgpack.Value{
        msgpack.boolean(true), // listed
        msgpack.boolean(false), // not scratch
    });
    defer msgpack.free(buf, allocator);

    std.debug.print("   Buffer created successfully\n\n", .{});

    // 3. Set buffer content
    std.debug.print("Writing sample content...\n", .{});
    const sample_lines = [_][]const u8{
        "# Remote Editing Session Example",
        "",
        "This is a file created and edited via znvim.",
        "",
        "Supported features:",
        "- Cross-platform connection",
        "- Real-time editing",
        "- Status monitoring",
        "- Auto-save",
        "",
        "Current time: " ++ "2025-10-25",
    };

    var lines_list = std.array_list.AlignedManaged(msgpack.Value, null).init(allocator);
    defer lines_list.deinit();

    for (sample_lines) |line| {
        const line_val = try msgpack.string(allocator, line);
        try lines_list.append(line_val);
    }

    const lines_array = try msgpack.array(allocator, lines_list.items);
    defer msgpack.free(lines_array, allocator);

    const set_lines_result = try client.request("nvim_buf_set_lines", &[_]msgpack.Value{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
        lines_array,
    });
    defer msgpack.free(set_lines_result, allocator);

    std.debug.print("   Written {d} lines\n\n", .{sample_lines.len});

    // 4. Switch to new buffer
    std.debug.print("Switching to new buffer...\n", .{});
    const set_buf_result = try client.request("nvim_set_current_buf", &[_]msgpack.Value{buf});
    defer msgpack.free(set_buf_result, allocator);

    // 5. Get cursor position
    if (config.show_cursor_position) {
        try showCursorInfo(client, allocator);
    }

    // 6. Demonstrate editing operations
    std.debug.print("\nDemonstrating editing operations...\n\n", .{});

    // 6.1 Insert new content at line 3
    std.debug.print("   1. Insert text at line 3\n", .{});
    const new_line = try msgpack.string(allocator, "   > This is a new inserted line!");
    const insert_lines = try msgpack.array(allocator, &[_]msgpack.Value{new_line});
    defer msgpack.free(insert_lines, allocator);

    const insert_result = try client.request("nvim_buf_set_lines", &[_]msgpack.Value{
        buf,
        msgpack.int(2),
        msgpack.int(2),
        msgpack.boolean(false),
        insert_lines,
    });
    defer msgpack.free(insert_result, allocator);

    // 6.2 Modify specific line
    std.debug.print("   2. Modify line 1 title\n", .{});
    const modified_line = try msgpack.string(allocator, "# Remote Editing Session Example (Modified)");
    const modify_lines = try msgpack.array(allocator, &[_]msgpack.Value{modified_line});
    defer msgpack.free(modify_lines, allocator);

    const modify_result = try client.request("nvim_buf_set_lines", &[_]msgpack.Value{
        buf,
        msgpack.int(0),
        msgpack.int(1),
        msgpack.boolean(false),
        modify_lines,
    });
    defer msgpack.free(modify_result, allocator);

    // 6.3 Move cursor
    std.debug.print("   3. Move cursor to line 5 column 1\n", .{});
    const set_cursor_result = try client.request("nvim_win_set_cursor", &[_]msgpack.Value{
        msgpack.int(0), // current window
        try msgpack.array(allocator, &[_]msgpack.Value{
            msgpack.int(5),
            msgpack.int(0),
        }),
    });
    defer msgpack.free(set_cursor_result, allocator);

    std.debug.print("\n", .{});

    // 7. Display final content
    std.debug.print("Final buffer content:\n", .{});
    std.debug.print("═══════════════════════════════════════════\n", .{});

    const final_lines_result = try client.request("nvim_buf_get_lines", &[_]msgpack.Value{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(final_lines_result, allocator);

    const final_lines = try msgpack.expectArray(final_lines_result);
    for (final_lines, 0..) |line, i| {
        const line_str = msgpack.asString(line) orelse "";
        std.debug.print("{d:2} | {s}\n", .{ i + 1, line_str });
    }
    std.debug.print("═══════════════════════════════════════════\n\n", .{});

    // 8. Buffer information
    try printBufferInfo(client, allocator, buf);

    std.debug.print("Session demo complete!\n\n", .{});

    std.debug.print("Tips:\n", .{});
    std.debug.print("  * Use --monitor parameter to enable change monitoring\n", .{});
    std.debug.print("  * Specify filename to open existing file\n", .{});
    std.debug.print("  * Supports multiple connection methods (Socket/Pipe/TCP/Spawn)\n", .{});
}

fn editFile(client: *znvim.Client, allocator: std.mem.Allocator, config: SessionConfig, filepath: []const u8) !void {
    std.debug.print("=== Editing file: {s} ===\n\n", .{filepath});

    // Open file
    const edit_cmd_str = try std.fmt.allocPrint(allocator, "edit {s}", .{filepath});
    defer allocator.free(edit_cmd_str);

    const edit_cmd = try msgpack.string(allocator, edit_cmd_str);
    defer msgpack.free(edit_cmd, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer msgpack.free(opts, allocator);
    try opts.mapPut("output", msgpack.boolean(false));

    const edit_result = try client.request("nvim_exec2", &[_]msgpack.Value{ edit_cmd, opts });
    defer msgpack.free(edit_result, allocator);

    std.debug.print("File opened\n\n", .{});

    // Get current buffer
    const buf = try client.request("nvim_get_current_buf", &[_]msgpack.Value{});
    defer msgpack.free(buf, allocator);

    // Display file information
    try printBufferInfo(client, allocator, buf);

    // Display file content
    std.debug.print("\nFile content:\n", .{});
    std.debug.print("═══════════════════════════════════════════\n", .{});

    const lines_result = try client.request("nvim_buf_get_lines", &[_]msgpack.Value{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(lines_result, allocator);

    const lines = try msgpack.expectArray(lines_result);
    const preview_lines = @min(lines.len, 20); // Only show first 20 lines

    for (lines[0..preview_lines], 0..) |line, i| {
        const line_str = msgpack.asString(line) orelse "";
        std.debug.print("{d:4} | {s}\n", .{ i + 1, line_str });
    }

    if (lines.len > preview_lines) {
        std.debug.print("... ({d} lines not shown)\n", .{lines.len - preview_lines});
    }

    std.debug.print("═══════════════════════════════════════════\n\n", .{});

    if (config.show_cursor_position) {
        try showCursorInfo(client, allocator);
    }

    if (config.monitor_changes) {
        std.debug.print("\nMonitor mode enabled (demo version does not include actual monitoring)\n", .{});
        std.debug.print("   In production, you can:\n", .{});
        std.debug.print("   * Use nvim_buf_attach to subscribe to change events\n", .{});
        std.debug.print("   * Real-time sync editing state\n", .{});
        std.debug.print("   * Auto-save changes\n", .{});
    }
}

fn printEditorState(client: *znvim.Client, allocator: std.mem.Allocator) !void {
    std.debug.print("Editor state:\n", .{});
    std.debug.print("───────────────────────────────────────────\n", .{});

    // Get all buffers
    const bufs_result = try client.request("nvim_list_bufs", &[_]msgpack.Value{});
    defer msgpack.free(bufs_result, allocator);

    const bufs = try msgpack.expectArray(bufs_result);
    std.debug.print("  Buffers: {d}\n", .{bufs.len});

    // Get all windows
    const wins_result = try client.request("nvim_list_wins", &[_]msgpack.Value{});
    defer msgpack.free(wins_result, allocator);

    const wins = try msgpack.expectArray(wins_result);
    std.debug.print("  Windows: {d}\n", .{wins.len});

    // Get all tabpages
    const tabs_result = try client.request("nvim_list_tabpages", &[_]msgpack.Value{});
    defer msgpack.free(tabs_result, allocator);

    const tabs = try msgpack.expectArray(tabs_result);
    std.debug.print("  Tabpages: {d}\n", .{tabs.len});

    // Get current mode
    const mode_result = try client.request("nvim_get_mode", &[_]msgpack.Value{});
    defer msgpack.free(mode_result, allocator);

    if (mode_result == .map) {
        if (mode_result.map.get("mode")) |mode_val| {
            if (msgpack.asString(mode_val)) |mode| {
                std.debug.print("  Current mode: {s}\n", .{mode});
            }
        }
    }

    std.debug.print("───────────────────────────────────────────\n\n", .{});
}

fn printBufferInfo(client: *znvim.Client, allocator: std.mem.Allocator, buf: msgpack.Value) !void {
    std.debug.print("Buffer information:\n", .{});
    std.debug.print("───────────────────────────────────────────\n", .{});

    // Get buffer name
    const name_result = try client.request("nvim_buf_get_name", &[_]msgpack.Value{buf});
    defer msgpack.free(name_result, allocator);

    const name = msgpack.asString(name_result) orelse "(unnamed)";
    std.debug.print("  Name: {s}\n", .{name});

    // Get line count
    const line_count_result = try client.request("nvim_buf_line_count", &[_]msgpack.Value{buf});
    defer msgpack.free(line_count_result, allocator);

    const line_count = try msgpack.expectI64(line_count_result);
    std.debug.print("  Lines: {d}\n", .{line_count});

    // Get file type
    const ft_name = try msgpack.string(allocator, "filetype");
    defer msgpack.free(ft_name, allocator);

    const ft_result = try client.request("nvim_buf_get_option", &[_]msgpack.Value{ buf, ft_name });
    defer msgpack.free(ft_result, allocator);

    const filetype = msgpack.asString(ft_result) orelse "(not set)";
    std.debug.print("  File type: {s}\n", .{filetype});

    // Check if modified
    const mod_name = try msgpack.string(allocator, "modified");
    defer msgpack.free(mod_name, allocator);

    const mod_result = try client.request("nvim_buf_get_option", &[_]msgpack.Value{ buf, mod_name });
    defer msgpack.free(mod_result, allocator);

    const modified = msgpack.asBool(mod_result) orelse false;
    std.debug.print("  Modified: {}\n", .{modified});

    std.debug.print("───────────────────────────────────────────\n", .{});
}

fn showCursorInfo(client: *znvim.Client, allocator: std.mem.Allocator) !void {
    const win_result = try client.request("nvim_get_current_win", &[_]msgpack.Value{});
    defer msgpack.free(win_result, allocator);

    const cursor_result = try client.request("nvim_win_get_cursor", &[_]msgpack.Value{win_result});
    defer msgpack.free(cursor_result, allocator);

    const cursor = try msgpack.expectArray(cursor_result);
    if (cursor.len >= 2) {
        const row = try msgpack.expectI64(cursor[0]);
        const col = try msgpack.expectI64(cursor[1]);
        std.debug.print("\nCursor position: line {d}, column {d}\n", .{ row, col + 1 });
    }
}

fn printUsage() void {
    std.debug.print(
        \\Remote Editing Session
        \\
        \\Usage:
        \\  remote_edit_session [options] [file]
        \\
        \\Options:
        \\  -h, --help       Show this help message
        \\  -m, --monitor    Enable change monitoring mode
        \\
        \\Connection:
        \\  * Set NVIM_LISTEN_ADDRESS environment variable to connect to running Neovim
        \\  * Leave unset to auto-spawn new Neovim instance
        \\
        \\Supported platforms:
        \\  * Windows: Named Pipe, TCP, Stdio, Spawn
        \\  * Unix/Linux/macOS: Unix Socket, TCP, Stdio, Spawn
        \\
        \\Examples:
        \\  # Demo mode
        \\  remote_edit_session
        \\
        \\  # Open existing file
        \\  remote_edit_session main.zig
        \\
        \\  # Monitor mode
        \\  remote_edit_session --monitor config.json
        \\
        \\  # Connect to remote Neovim (TCP)
        \\  export NVIM_LISTEN_ADDRESS=192.168.1.100:6666
        \\  remote_edit_session
        \\
        \\  # Connect to local Neovim (Unix Socket)
        \\  export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock
        \\  remote_edit_session
        \\
    , .{});
}
