const std = @import("std");
const znvim = @import("znvim");

/// Production example: Batch file processing
///
/// This example demonstrates how to:
/// 1. Connect to Neovim
/// 2. Process multiple files/buffers in batch
/// 3. Apply transformations (e.g., add headers, format, refactor)
/// 4. Save changes
///
/// Use case: Adding license headers to all source files in a project

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("warning: leaked allocations\n", .{}),
    };
    const allocator = gpa.allocator();

    // Get connection info or spawn clean instance
    const maybe_address = std.process.getEnvVarOwned(allocator, "NVIM_LISTEN_ADDRESS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (maybe_address) |addr| allocator.free(addr);

    var client = if (maybe_address == null) blk: {
        std.debug.print("📦 Spawning clean Neovim instance for batch processing...\n", .{});
        break :blk try znvim.Client.init(allocator, .{
            .spawn_process = true,
            .nvim_path = "nvim",
        });
    } else blk: {
        std.debug.print("📡 Connecting to Neovim at {s}...\n", .{maybe_address.?});
        break :blk try znvim.Client.init(allocator, .{
            .socket_path = maybe_address.?,
        });
    };
    defer client.deinit();
    try client.connect();

    std.debug.print("✅ Connected to Neovim\n\n", .{});

    // Example: Process files provided as command-line arguments
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next(); // Skip executable name

    var files_to_process = std.array_list.AlignedManaged([]const u8, null).init(allocator);
    defer files_to_process.deinit();

    // If no files provided, create example files
    var has_args = false;
    while (args.next()) |_| {
        has_args = true;
        break;
    }

    if (!has_args) {
        std.debug.print("💡 Usage: batch_file_processing <file1> <file2> ...\n", .{});
        std.debug.print("   For demo, creating and processing example files...\n\n", .{});
        try demonstrateBatchProcessing(&client, allocator);
    } else {
        // Reset args to process files
        args.deinit();
        args = try std.process.argsWithAllocator(allocator);
        _ = args.next(); // Skip executable name
        try processUserFiles(&client, allocator, &args);
    }
}

fn demonstrateBatchProcessing(client: *znvim.Client, allocator: std.mem.Allocator) !void {
    std.debug.print("=== Batch Processing Demo ===\n\n", .{});

    // Step 1: Create multiple buffers (simulating files)
    std.debug.print("📝 Creating 3 example buffers...\n", .{});

    var buffers = std.array_list.AlignedManaged(znvim.msgpack.Value, null).init(allocator);
    defer {
        for (buffers.items) |buf| {
            znvim.msgpack.free(buf, allocator);
        }
        buffers.deinit();
    }

    for (0..3) |i| {
        // Create new buffer
        const buf = try client.request("nvim_create_buf", &[_]znvim.msgpack.Value{
            znvim.msgpack.boolean(false), // not listed
            znvim.msgpack.boolean(false), // not scratch
        });
        // Don't free buf - we're storing it in the list
        try buffers.append(buf);
        std.debug.print("   Buffer #{d} created\n", .{i + 1});
    }

    std.debug.print("\n", .{});

    // Step 2: Add license header to each buffer
    const license_header = [_][]const u8{
        "// Copyright (c) 2025 Your Company",
        "// Licensed under MIT License",
        "//",
        "",
        "const std = @import(\"std\");",
        "",
        "pub fn main() !void {",
        "    std.debug.print(\"Hello from file!\\n\", .{});",
        "}",
    };

    std.debug.print("📄 Adding license headers to all buffers...\n", .{});
    for (buffers.items, 0..) |buf, i| {
        // Convert lines to msgpack array
        var lines_array = std.array_list.AlignedManaged(znvim.msgpack.Value, null).init(allocator);
        defer lines_array.deinit(); // Don't free items - array() takes ownership

        for (license_header) |line| {
            const line_val = try znvim.msgpack.string(allocator, line);
            try lines_array.append(line_val);
        }

        const lines_val = try znvim.msgpack.array(allocator, lines_array.items);
        defer znvim.msgpack.free(lines_val, allocator); // This frees lines_val AND all its elements

        const result = try client.request("nvim_buf_set_lines", &[_]znvim.msgpack.Value{
            buf, // Use buf directly as msgpack.Value
            znvim.msgpack.int(0),
            znvim.msgpack.int(-1),
            znvim.msgpack.boolean(false),
            lines_val,
        });
        defer znvim.msgpack.free(result, allocator);

        std.debug.print("   ✓ Buffer #{d} processed\n", .{i + 1});
    }

    std.debug.print("\n", .{});

    // Step 3: Verify content
    std.debug.print("🔍 Verifying buffer contents...\n", .{});
    for (buffers.items, 0..) |buf, i| {
        const result = try client.request("nvim_buf_get_lines", &[_]znvim.msgpack.Value{
            buf, // Use buf directly
            znvim.msgpack.int(0),
            znvim.msgpack.int(3), // Get first 3 lines
            znvim.msgpack.boolean(false),
        });
        defer znvim.msgpack.free(result, allocator);

        const lines = try znvim.msgpack.expectArray(result);
        std.debug.print("   Buffer #{d} preview:\n", .{i + 1});
        for (lines[0..@min(3, lines.len)]) |line| {
            const line_str = try znvim.msgpack.expectString(line);
            std.debug.print("     {s}\n", .{line_str});
        }
    }

    std.debug.print("\n", .{});

    // Step 4: Get statistics
    std.debug.print("📊 Statistics:\n", .{});
    std.debug.print("   Total buffers processed: {d}\n", .{buffers.items.len});
    std.debug.print("   Lines added per buffer: {d}\n", .{license_header.len});
    std.debug.print("   Total lines processed: {d}\n", .{buffers.items.len * license_header.len});

    std.debug.print("\n✨ Batch processing complete!\n", .{});
}

fn processUserFiles(client: *znvim.Client, allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    std.debug.print("=== Processing User Files ===\n\n", .{});

    var file_count: usize = 0;
    while (args.next()) |filepath| {
        file_count += 1;
        std.debug.print("📂 Processing file: {s}\n", .{filepath});

        // Open file in new buffer
        const filepath_val = try znvim.msgpack.string(allocator, filepath);
        defer znvim.msgpack.free(filepath_val, allocator);

        const result = try client.request("nvim_command", &[_]znvim.msgpack.Value{
            try znvim.msgpack.string(allocator, std.fmt.allocPrint(
                allocator,
                "edit {s}",
                .{filepath},
            ) catch return error.OutOfMemory),
        });
        defer znvim.msgpack.free(result, allocator);

        // Get current buffer
        const buf = try client.request("nvim_get_current_buf", &[_]znvim.msgpack.Value{});
        defer znvim.msgpack.free(buf, allocator);

        // Get line count
        const line_count_result = try client.request("nvim_buf_line_count", &[_]znvim.msgpack.Value{
            buf, // Use buf directly
        });
        defer znvim.msgpack.free(line_count_result, allocator);

        const line_count = try znvim.msgpack.expectI64(line_count_result);

        std.debug.print("   Lines: {d}\n", .{line_count});
        std.debug.print("   ✓ Loaded successfully\n\n", .{});
    }

    std.debug.print("📊 Summary:\n", .{});
    std.debug.print("   Total files processed: {d}\n", .{file_count});
    std.debug.print("\n✨ Processing complete!\n", .{});
}
