const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;
const helper = @import("connection_helper.zig");

/// Production example: Batch search and replace tool
///
/// Features:
/// - Supports all platforms and all connection methods
/// - Supports regular expressions
/// - Multi-file batch replace
/// - Replace preview
/// - Supports confirm mode and auto mode
/// - Generates replace reports
///
/// Use cases:
/// - Code refactoring (rename variables, functions, types)
/// - Batch update copyright notices
/// - Unify code style
/// - API migration
const ReplaceMode = enum {
    preview, // Preview only, don't modify
    auto, // Automatically replace all
    interactive, // Interactive confirm (requires UI)
};

const ReplaceStats = struct {
    files_scanned: usize = 0,
    files_modified: usize = 0,
    total_replacements: usize = 0,
    errors: usize = 0,
};

const ReplaceConfig = struct {
    pattern: []const u8,
    replacement: []const u8,
    mode: ReplaceMode = .preview,
    use_regex: bool = true,
    case_sensitive: bool = true,
    whole_word: bool = false,
    verbose: bool = false,
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

    var files = std.array_list.AlignedManaged([]const u8, null).init(allocator);
    defer files.deinit();

    var pattern: ?[]const u8 = null;
    var replacement: ?[]const u8 = null;
    var mode = ReplaceMode.preview;
    var show_help = false;
    var verbose = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--pattern") or std.mem.eql(u8, arg, "-p")) {
            pattern = args.next();
        } else if (std.mem.eql(u8, arg, "--replace") or std.mem.eql(u8, arg, "-r")) {
            replacement = args.next();
        } else if (std.mem.eql(u8, arg, "--auto") or std.mem.eql(u8, arg, "-a")) {
            mode = .auto;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else {
            try files.append(arg);
        }
    }

    if (show_help) {
        printUsage();
        return;
    }

    std.debug.print("=== Batch Search & Replace ===\n\n", .{});

    // Smart connect to Neovim
    var client = try helper.smartConnect(allocator);
    defer client.deinit();

    // Get API info
    const api_info = client.getApiInfo() orelse return error.ApiInfoUnavailable;
    if (verbose) {
        std.debug.print("Neovim version: {d}.{d}.{d}\n\n", .{
            api_info.version.major,
            api_info.version.minor,
            api_info.version.patch,
        });
    }

    if (pattern == null or replacement == null or files.items.len == 0) {
        std.debug.print("Running demo...\n\n", .{});
        try demonstrateSearchReplace(&client, allocator, verbose);
    } else {
        const config = ReplaceConfig{
            .pattern = pattern.?,
            .replacement = replacement.?,
            .mode = mode,
            .verbose = verbose,
        };
        try batchReplace(&client, allocator, config, files.items);
    }
}

fn demonstrateSearchReplace(client: *znvim.Client, allocator: std.mem.Allocator, verbose: bool) !void {
    std.debug.print("=== Search & Replace Demo ===\n\n", .{});

    // Create sample code
    const sample_code = [_][]const u8{
        "const oldName = 42;",
        "const another_oldName = 10;",
        "pub fn processOldName(oldName: i32) void {",
        "    std.debug.print(\"oldName = {}\\n\", .{oldName});",
        "    const result = oldName * 2;",
        "    return result;",
        "}",
        "",
        "// TODO: refactor oldName to newName",
        "const OLD_NAME_CONSTANT = 100;",
    };

    std.debug.print("Creating sample code...\n\n", .{});

    // Create buffer
    const buf = try client.request("nvim_create_buf", &[_]msgpack.Value{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf, allocator);

    // Write code
    var lines_list = std.array_list.AlignedManaged(msgpack.Value, null).init(allocator);
    defer lines_list.deinit();

    for (sample_code) |line| {
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

    std.debug.print("Original code:\n", .{});
    std.debug.print("============================================\n", .{});
    for (sample_code, 0..) |line, i| {
        std.debug.print("{d:2} | {s}\n", .{ i + 1, line });
    }
    std.debug.print("============================================\n\n", .{});

    // Demo 1: Simple replace
    std.debug.print("Example 1: Replace 'oldName' with 'newName'\n\n", .{});

    const pattern1 = "oldName";
    const replace1 = "newName";

    const match_count = try performReplace(client, allocator, buf, pattern1, replace1, verbose);

    std.debug.print("Replace result: {d} changes\n\n", .{match_count});

    // Read replaced content
    const get_lines_result = try client.request("nvim_buf_get_lines", &[_]msgpack.Value{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(get_lines_result, allocator);

    const modified_lines = try msgpack.expectArray(get_lines_result);

    std.debug.print("Modified code:\n", .{});
    std.debug.print("============================================\n", .{});
    for (modified_lines, 0..) |line, i| {
        const line_str = msgpack.asString(line) orelse "";
        // Highlight modified lines
        if (std.mem.indexOf(u8, line_str, "newName") != null) {
            std.debug.print("{d:2} | {s} <- MODIFIED\n", .{ i + 1, line_str });
        } else {
            std.debug.print("{d:2} | {s}\n", .{ i + 1, line_str });
        }
    }
    std.debug.print("============================================\n\n", .{});

    std.debug.print("Demo complete!\n\n", .{});

    if (verbose) {
        std.debug.print("In production, you can:\n", .{});
        std.debug.print("  * Use regular expressions for complex patterns\n", .{});
        std.debug.print("  * Batch process multiple files\n", .{});
        std.debug.print("  * Preview changes before applying\n", .{});
        std.debug.print("  * Generate detailed replace reports\n", .{});
    }
}

fn performReplace(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    buf: msgpack.Value,
    pattern: []const u8,
    replacement: []const u8,
    verbose: bool,
) !usize {
    // Set as current buffer
    const set_buf_result = try client.request("nvim_set_current_buf", &[_]msgpack.Value{buf});
    defer msgpack.free(set_buf_result, allocator);

    // Build replace command
    const cmd_str = try std.fmt.allocPrint(
        allocator,
        "%s/{s}/{s}/g",
        .{ pattern, replacement },
    );
    defer allocator.free(cmd_str);

    if (verbose) {
        std.debug.print("  Executing command: :{s}\n", .{cmd_str});
    }

    const cmd = try msgpack.string(allocator, cmd_str);
    defer msgpack.free(cmd, allocator);

    var opts = msgpack.Value.mapPayload(allocator);
    defer msgpack.free(opts, allocator);
    try opts.mapPut("output", msgpack.boolean(true));

    const exec_result = try client.request("nvim_exec2", &[_]msgpack.Value{ cmd, opts });
    defer msgpack.free(exec_result, allocator);

    // Parse output to get substitution count
    if (exec_result == .map) {
        if (exec_result.map.get("output")) |output| {
            if (msgpack.asString(output)) |output_str| {
                if (verbose) {
                    std.debug.print("  Output: {s}\n", .{output_str});
                }
                // Try to extract substitution count from output
                // Format is like "5 substitutions on 3 lines"
                return parseSubstitutionCount(output_str);
            }
        }
    }

    return 0;
}

fn parseSubstitutionCount(output: []const u8) usize {
    // Simple parse for "X substitutions" format
    var it = std.mem.splitSequence(u8, output, " ");
    while (it.next()) |word| {
        if (std.mem.eql(u8, word, "substitution") or std.mem.eql(u8, word, "substitutions")) {
            // Previous word should be the number
            it.reset();
            var prev: ?[]const u8 = null;
            while (it.next()) |w| {
                if (std.mem.eql(u8, w, word)) {
                    if (prev) |p| {
                        return std.fmt.parseInt(usize, p, 10) catch 0;
                    }
                }
                prev = w;
            }
            break;
        }
    }
    return 1; // At least one substitution (if command succeeded)
}

fn batchReplace(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    config: ReplaceConfig,
    files: []const []const u8,
) !void {
    std.debug.print("=== Batch replace: '{s}' -> '{s}' ===\n\n", .{ config.pattern, config.replacement });
    std.debug.print("Mode: {s}\n", .{@tagName(config.mode)});
    std.debug.print("Files: {d}\n\n", .{files.len});

    var stats = ReplaceStats{};

    for (files, 0..) |filepath, idx| {
        stats.files_scanned += 1;
        std.debug.print("[{d}/{d}] {s}\n", .{ idx + 1, files.len, filepath });

        const replacements = replaceInFile(
            client,
            allocator,
            config,
            filepath,
        ) catch |err| {
            std.debug.print("  Error: {}\n\n", .{err});
            stats.errors += 1;
            continue;
        };

        if (replacements > 0) {
            stats.files_modified += 1;
            stats.total_replacements += replacements;
            std.debug.print("  {d} replacements\n\n", .{replacements});
        } else {
            std.debug.print("  No matches\n\n", .{});
        }
    }

    printStats(stats);
}

fn replaceInFile(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    config: ReplaceConfig,
    filepath: []const u8,
) !usize {
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

    // Get current buffer
    const buf = try client.request("nvim_get_current_buf", &[_]msgpack.Value{});
    defer msgpack.free(buf, allocator);

    // Perform replace
    const count = try performReplace(client, allocator, buf, config.pattern, config.replacement, config.verbose);

    // Save file if in auto mode and has changes
    if (config.mode == .auto and count > 0) {
        const write_cmd = try msgpack.string(allocator, "write");
        defer msgpack.free(write_cmd, allocator);

        var write_opts = msgpack.Value.mapPayload(allocator);
        defer msgpack.free(write_opts, allocator);
        try write_opts.mapPut("output", msgpack.boolean(false));

        const write_result = try client.request("nvim_exec2", &[_]msgpack.Value{ write_cmd, write_opts });
        defer msgpack.free(write_result, allocator);
    }

    return count;
}

fn printStats(stats: ReplaceStats) void {
    std.debug.print("===========================================\n", .{});
    std.debug.print("Replace Statistics\n", .{});
    std.debug.print("===========================================\n", .{});
    std.debug.print("Files scanned:   {d}\n", .{stats.files_scanned});
    std.debug.print("Files modified:  {d}\n", .{stats.files_modified});
    std.debug.print("Total replaces:  {d}\n", .{stats.total_replacements});
    std.debug.print("Errors:          {d}\n", .{stats.errors});
    std.debug.print("===========================================\n", .{});

    if (stats.files_modified > 0) {
        const avg = @as(f64, @floatFromInt(stats.total_replacements)) / @as(f64, @floatFromInt(stats.files_modified));
        std.debug.print("Average per file: {d:.1} replacements\n", .{avg});
    }
}

fn printUsage() void {
    std.debug.print(
        \\Batch Search & Replace Tool
        \\
        \\Usage:
        \\  batch_search_replace [options] [files...]
        \\
        \\Options:
        \\  -h, --help              Show this help message
        \\  -p, --pattern TEXT      Search pattern
        \\  -r, --replace TEXT      Replacement text
        \\  -a, --auto              Auto mode (replace without preview)
        \\  -v, --verbose           Show verbose information
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
        \\  batch_search_replace
        \\
        \\  # Preview replace (don't modify files)
        \\  batch_search_replace -p "oldName" -r "newName" src/*.zig
        \\
        \\  # Auto replace
        \\  batch_search_replace -p "oldName" -r "newName" -a src/*.zig
        \\
        \\  # Connect to running Neovim
        \\  export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock
        \\  batch_search_replace -p "foo" -r "bar" main.zig
        \\
    , .{});
}
