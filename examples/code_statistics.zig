const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;
const helper = @import("connection_helper.zig");

/// Production example: Code statistics analysis tool
///
/// Features:
/// - Supports all platforms and all connection methods
/// - Analyze lines of code, characters
/// - Count functions, comments, blank lines
/// - Generate detailed reports
/// - Support multiple programming languages
///
/// Use cases:
/// - Code quality analysis
/// - Project size estimation
/// - Code review assistance
/// - Technical debt analysis
const FileStats = struct {
    filepath: []const u8,
    total_lines: usize = 0,
    code_lines: usize = 0,
    comment_lines: usize = 0,
    blank_lines: usize = 0,
    total_chars: usize = 0,
    filetype: []const u8 = "",
};

const ProjectStats = struct {
    files: std.array_list.AlignedManaged(FileStats, null),
    total_files: usize = 0,
    total_lines: usize = 0,
    total_code_lines: usize = 0,
    total_comment_lines: usize = 0,
    total_blank_lines: usize = 0,
    total_chars: usize = 0,

    pub fn init(allocator: std.mem.Allocator) ProjectStats {
        return .{
            .files = std.array_list.AlignedManaged(FileStats, null).init(allocator),
        };
    }

    pub fn deinit(self: *ProjectStats) void {
        self.files.deinit();
    }

    pub fn addFile(self: *ProjectStats, stats: FileStats) !void {
        try self.files.append(stats);
        self.total_files += 1;
        self.total_lines += stats.total_lines;
        self.total_code_lines += stats.code_lines;
        self.total_comment_lines += stats.comment_lines;
        self.total_blank_lines += stats.blank_lines;
        self.total_chars += stats.total_chars;
    }
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

    var show_help = false;
    var verbose = false;
    var detailed = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--detailed") or std.mem.eql(u8, arg, "-d")) {
            detailed = true;
        } else {
            try files.append(arg);
        }
    }

    if (show_help) {
        printUsage();
        return;
    }

    std.debug.print("=== Code Statistics Tool ===\n\n", .{});

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

    if (files.items.len == 0) {
        std.debug.print("No files specified, running demo...\n\n", .{});
        try demonstrateStatistics(&client, allocator, verbose, detailed);
    } else {
        try analyzeFiles(&client, allocator, files.items, verbose, detailed);
    }
}

fn demonstrateStatistics(client: *znvim.Client, allocator: std.mem.Allocator, verbose: bool, detailed: bool) !void {
    std.debug.print("=== Statistics Demo ===\n\n", .{});

    // Create sample Zig code
    const sample_code = [_][]const u8{
        "// Example Zig code for statistics analysis",
        "// Copyright (c) 2025",
        "",
        "const std = @import(\"std\");",
        "",
        "/// Main entry point",
        "pub fn main() !void {",
        "    const allocator = std.heap.page_allocator;",
        "    ",
        "    // Print greeting",
        "    std.debug.print(\"Hello, World!\\n\", .{});",
        "    ",
        "    // Calculate result",
        "    const result = add(10, 20);",
        "    std.debug.print(\"Result: {}\\n\", .{result});",
        "}",
        "",
        "/// Add two numbers",
        "fn add(a: i32, b: i32) i32 {",
        "    return a + b; // Simple addition",
        "}",
        "",
        "// End of file",
    };

    std.debug.print("Creating sample file...\n\n", .{});

    // Create buffer
    const buf = try client.request("nvim_create_buf", &[_]msgpack.Value{
        msgpack.boolean(false),
        msgpack.boolean(false),
    });
    defer msgpack.free(buf, allocator);

    // Set file type
    const ft_name = try msgpack.string(allocator, "filetype");
    defer msgpack.free(ft_name, allocator);
    const ft_value = try msgpack.string(allocator, "zig");
    defer msgpack.free(ft_value, allocator);

    const set_opt_result = try client.request("nvim_buf_set_option", &[_]msgpack.Value{
        buf,
        ft_name,
        ft_value,
    });
    defer msgpack.free(set_opt_result, allocator);

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

    // Analyze code
    std.debug.print("Analyzing code...\n\n", .{});
    const stats = try analyzeBuffer(client, allocator, buf, "demo.zig", verbose);

    // Display results
    printFileStats(stats, detailed);

    std.debug.print("\n", .{});

    if (verbose) {
        std.debug.print("Code content:\n", .{});
        std.debug.print("═══════════════════════════════════════════\n", .{});
        for (sample_code, 0..) |line, i| {
            const line_type = classifyLine(line);
            const type_symbol = switch (line_type) {
                .code => "C",
                .comment => "#",
                .blank => " ",
            };
            std.debug.print("{s} {d:2} | {s}\n", .{ type_symbol, i + 1, line });
        }
        std.debug.print("═══════════════════════════════════════════\n\n", .{});
        std.debug.print("Legend: C = code line, # = comment line\n\n", .{});
    }

    std.debug.print("Analysis complete!\n", .{});
}

fn analyzeFiles(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    files: []const []const u8,
    verbose: bool,
    detailed: bool,
) !void {
    std.debug.print("=== Analyzing {d} files ===\n\n", .{files.len});

    var project_stats = ProjectStats.init(allocator);
    defer project_stats.deinit();

    for (files, 0..) |filepath, idx| {
        std.debug.print("[{d}/{d}] {s}\n", .{ idx + 1, files.len, filepath });

        const stats = analyzeFile(client, allocator, filepath, verbose) catch |err| {
            std.debug.print("  Error: {}\n\n", .{err});
            continue;
        };

        try project_stats.addFile(stats);

        if (detailed) {
            printFileStats(stats, true);
        } else {
            std.debug.print("  {d} lines ({d} code, {d} comment, {d} blank)\n\n", .{
                stats.total_lines,
                stats.code_lines,
                stats.comment_lines,
                stats.blank_lines,
            });
        }
    }

    printProjectStats(project_stats);
}

fn analyzeFile(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    filepath: []const u8,
    verbose: bool,
) !FileStats {
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

    return try analyzeBuffer(client, allocator, buf, filepath, verbose);
}

fn analyzeBuffer(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    buf: msgpack.Value,
    filepath: []const u8,
    verbose: bool,
) !FileStats {
    var stats = FileStats{ .filepath = filepath };

    // Get file type
    const ft_name = try msgpack.string(allocator, "filetype");
    defer msgpack.free(ft_name, allocator);

    const ft_result = try client.request("nvim_buf_get_option", &[_]msgpack.Value{ buf, ft_name });
    defer msgpack.free(ft_result, allocator);

    stats.filetype = msgpack.asString(ft_result) orelse "unknown";

    // Get all lines
    const lines_result = try client.request("nvim_buf_get_lines", &[_]msgpack.Value{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(lines_result, allocator);

    const lines = try msgpack.expectArray(lines_result);
    stats.total_lines = lines.len;

    // Analyze each line
    for (lines) |line| {
        const line_str = msgpack.asString(line) orelse "";
        stats.total_chars += line_str.len;

        const line_type = classifyLine(line_str);
        switch (line_type) {
            .code => stats.code_lines += 1,
            .comment => stats.comment_lines += 1,
            .blank => stats.blank_lines += 1,
        }
    }

    if (verbose) {
        std.debug.print("  File type: {s}\n", .{stats.filetype});
    }

    return stats;
}

const LineType = enum {
    code,
    comment,
    blank,
};

fn classifyLine(line: []const u8) LineType {
    // Trim leading/trailing whitespace
    const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

    // Blank line
    if (trimmed.len == 0) {
        return .blank;
    }

    // Check common comment markers
    if (std.mem.startsWith(u8, trimmed, "//") or
        std.mem.startsWith(u8, trimmed, "#") or
        std.mem.startsWith(u8, trimmed, "--") or
        std.mem.startsWith(u8, trimmed, "/*") or
        std.mem.startsWith(u8, trimmed, "*") or
        std.mem.startsWith(u8, trimmed, "///"))
    {
        return .comment;
    }

    // Default to code line
    return .code;
}

fn printFileStats(stats: FileStats, detailed: bool) void {
    std.debug.print("  ───────────────────────────────────────────\n", .{});
    std.debug.print("  File: {s}\n", .{stats.filepath});
    std.debug.print("  File type: {s}\n", .{stats.filetype});
    std.debug.print("  ───────────────────────────────────────────\n", .{});
    std.debug.print("  Total lines:   {d:6}\n", .{stats.total_lines});
    std.debug.print("  Code lines:    {d:6} ({d:5.1}%)\n", .{
        stats.code_lines,
        if (stats.total_lines > 0)
            @as(f64, @floatFromInt(stats.code_lines)) * 100.0 / @as(f64, @floatFromInt(stats.total_lines))
        else
            0.0,
    });
    std.debug.print("  Comment lines: {d:6} ({d:5.1}%)\n", .{
        stats.comment_lines,
        if (stats.total_lines > 0)
            @as(f64, @floatFromInt(stats.comment_lines)) * 100.0 / @as(f64, @floatFromInt(stats.total_lines))
        else
            0.0,
    });
    std.debug.print("  Blank lines:   {d:6} ({d:5.1}%)\n", .{
        stats.blank_lines,
        if (stats.total_lines > 0)
            @as(f64, @floatFromInt(stats.blank_lines)) * 100.0 / @as(f64, @floatFromInt(stats.total_lines))
        else
            0.0,
    });

    if (detailed) {
        std.debug.print("  Total chars:   {d:6}\n", .{stats.total_chars});
        if (stats.total_lines > 0) {
            const avg_line_length = @as(f64, @floatFromInt(stats.total_chars)) / @as(f64, @floatFromInt(stats.total_lines));
            std.debug.print("  Avg line len:  {d:6.1}\n", .{avg_line_length});
        }
    }

    std.debug.print("  ───────────────────────────────────────────\n", .{});
}

fn printProjectStats(stats: ProjectStats) void {
    std.debug.print("\n═══════════════════════════════════════════\n", .{});
    std.debug.print("Project Statistics Summary\n", .{});
    std.debug.print("═══════════════════════════════════════════\n", .{});
    std.debug.print("Total files:    {d:6}\n", .{stats.total_files});
    std.debug.print("Total lines:    {d:6}\n", .{stats.total_lines});
    std.debug.print("Code lines:     {d:6} ({d:5.1}%)\n", .{
        stats.total_code_lines,
        if (stats.total_lines > 0)
            @as(f64, @floatFromInt(stats.total_code_lines)) * 100.0 / @as(f64, @floatFromInt(stats.total_lines))
        else
            0.0,
    });
    std.debug.print("Comment lines:  {d:6} ({d:5.1}%)\n", .{
        stats.total_comment_lines,
        if (stats.total_lines > 0)
            @as(f64, @floatFromInt(stats.total_comment_lines)) * 100.0 / @as(f64, @floatFromInt(stats.total_lines))
        else
            0.0,
    });
    std.debug.print("Blank lines:    {d:6} ({d:5.1}%)\n", .{
        stats.total_blank_lines,
        if (stats.total_lines > 0)
            @as(f64, @floatFromInt(stats.total_blank_lines)) * 100.0 / @as(f64, @floatFromInt(stats.total_lines))
        else
            0.0,
    });
    std.debug.print("Total chars:    {d:6}\n", .{stats.total_chars});
    std.debug.print("═══════════════════════════════════════════\n", .{});

    if (stats.total_files > 0) {
        const avg_lines = @as(f64, @floatFromInt(stats.total_lines)) / @as(f64, @floatFromInt(stats.total_files));
        std.debug.print("Avg per file:   {d:.1} lines\n", .{avg_lines});
    }

    if (stats.total_code_lines > 0 and stats.total_comment_lines > 0) {
        const comment_ratio = @as(f64, @floatFromInt(stats.total_comment_lines)) / @as(f64, @floatFromInt(stats.total_code_lines));
        std.debug.print("Comment ratio:  {d:.2} (comments/code)\n", .{comment_ratio});
    }

    std.debug.print("═══════════════════════════════════════════\n", .{});
}

fn printUsage() void {
    std.debug.print(
        \\Code Statistics Tool
        \\
        \\Usage:
        \\  code_statistics [options] [files...]
        \\
        \\Options:
        \\  -h, --help       Show this help message
        \\  -v, --verbose    Show verbose information
        \\  -d, --detailed   Show detailed statistics for each file
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
        \\  code_statistics
        \\
        \\  # Analyze single file
        \\  code_statistics main.zig
        \\
        \\  # Batch analyze
        \\  code_statistics src/*.zig
        \\
        \\  # Detailed report
        \\  code_statistics --detailed src/*.zig
        \\
        \\  # Connect to running Neovim
        \\  export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock
        \\  code_statistics *.zig
        \\
    , .{});
}
