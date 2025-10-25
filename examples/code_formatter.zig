const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;
const helper = @import("connection_helper.zig");

/// Production example: Code formatter tool
///
/// Features:
/// - Supports all platforms and all connection methods
/// - Auto-detect file types
/// - Batch format multiple files
/// - Support custom format commands
/// - Provide before/after comparison
///
/// Use cases:
/// - Code format checking in CI/CD pipelines
/// - Batch format project files
/// - Integration into editor plugins
const FormatError = error{
    NoFilesProvided,
    FormatCommandNotFound,
    BufferNotFound,
};

/// File formatter configuration
const FormatterConfig = struct {
    /// File type to format command mapping
    formatters: std.StringHashMap([]const u8),
    /// Show verbose information
    verbose: bool = false,
    /// Actually modify files (false means check only)
    write_changes: bool = true,
    /// Continue on error
    continue_on_error: bool = true,

    pub fn init(allocator: std.mem.Allocator) FormatterConfig {
        const formatters = std.StringHashMap([]const u8).init(allocator);
        return .{
            .formatters = formatters,
            .verbose = false,
            .write_changes = true,
            .continue_on_error = true,
        };
    }

    pub fn deinit(self: *FormatterConfig) void {
        self.formatters.deinit();
    }

    /// Add default formatters
    pub fn addDefaultFormatters(self: *FormatterConfig) !void {
        try self.formatters.put("zig", "!zig fmt %");
        try self.formatters.put("python", "!black %");
        try self.formatters.put("rust", "!rustfmt %");
        try self.formatters.put("go", "!gofmt -w %");
        try self.formatters.put("javascript", "!prettier --write %");
        try self.formatters.put("typescript", "!prettier --write %");
        try self.formatters.put("json", "!prettier --write %");
        try self.formatters.put("markdown", "!prettier --write %");
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
    var check_only = false;
    var verbose = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "--check") or std.mem.eql(u8, arg, "-c")) {
            check_only = true;
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

    std.debug.print("=== Code Formatter ===\n\n", .{});

    // Smart connect to Neovim
    var client = try helper.smartConnect(allocator);
    defer client.deinit();

    // Get API info
    const api_info = client.getApiInfo() orelse return error.ApiInfoUnavailable;
    if (verbose) {
        std.debug.print("Neovim version: {d}.{d}.{d}\n", .{
            api_info.version.major,
            api_info.version.minor,
            api_info.version.patch,
        });
    }

    // Configure formatter
    var config = FormatterConfig.init(allocator);
    defer config.deinit();
    try config.addDefaultFormatters();
    config.verbose = verbose;
    config.write_changes = !check_only;

    if (files.items.len == 0) {
        std.debug.print("No files specified, running demo...\n\n", .{});
        try demonstrateFormatter(&client, allocator, config);
    } else {
        try formatFiles(&client, allocator, config, files.items);
    }
}

fn demonstrateFormatter(client: *znvim.Client, allocator: std.mem.Allocator, config: FormatterConfig) !void {
    std.debug.print("=== Formatter Demo ===\n\n", .{});
    std.debug.print("Note: This demo shows text transformation capabilities.\n", .{});
    std.debug.print("      In production, integrate external formatters for your languages.\n\n", .{});

    // Create sample text with mixed case (easier to see the change)
    const sample_code = [_][]const u8{
        "hello world from znvim",
        "this is a test file",
        "demonstrating text processing",
        "with neovim rpc client",
    };

    std.debug.print("Creating test buffer...\n", .{});
    const buf = try client.request("nvim_create_buf", &[_]msgpack.Value{
        msgpack.boolean(false), // not listed
        msgpack.boolean(false), // not scratch
    });
    defer msgpack.free(buf, allocator);

    // Write sample code
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

    std.debug.print("\nBefore transformation:\n", .{});
    std.debug.print("---------------------------------------------\n", .{});
    for (sample_code) |line| {
        std.debug.print("  {s}\n", .{line});
    }
    std.debug.print("---------------------------------------------\n\n", .{});

    // Set current buffer
    const set_buf_result = try client.request("nvim_set_current_buf", &[_]msgpack.Value{buf});
    defer msgpack.free(set_buf_result, allocator);

    // Demonstrate text transformation: Convert to UPPERCASE
    std.debug.print("Applying transformation: Convert to UPPERCASE...\n\n", .{});
    const upper_cmd = try msgpack.string(allocator, "silent! %s/.*/\\U&/g");
    defer msgpack.free(upper_cmd, allocator);

    var upper_opts = msgpack.Value.mapPayload(allocator);
    defer msgpack.free(upper_opts, allocator);
    try upper_opts.mapPut("output", msgpack.boolean(false));

    const upper_result = try client.request("nvim_exec2", &[_]msgpack.Value{ upper_cmd, upper_opts });
    defer msgpack.free(upper_result, allocator);

    // Read transformed content
    const get_lines_result = try client.request("nvim_buf_get_lines", &[_]msgpack.Value{
        buf,
        msgpack.int(0),
        msgpack.int(-1),
        msgpack.boolean(false),
    });
    defer msgpack.free(get_lines_result, allocator);

    const transformed_lines = try msgpack.expectArray(get_lines_result);

    std.debug.print("After transformation:\n", .{});
    std.debug.print("---------------------------------------------\n", .{});
    for (transformed_lines) |line| {
        const line_str = msgpack.asString(line) orelse "";
        std.debug.print("  {s}\n", .{line_str});
    }
    std.debug.print("---------------------------------------------\n\n", .{});

    std.debug.print("Transformation complete!\n\n", .{});

    if (config.verbose) {
        std.debug.print("Tips:\n", .{});
        std.debug.print("  - This demo shows Neovim's built-in text transformations\n", .{});
        std.debug.print("  - In production, use external formatters:\n", .{});
        std.debug.print("    * Zig: zig fmt (requires zig installation)\n", .{});
        std.debug.print("    * Python: black, autopep8\n", .{});
        std.debug.print("    * JavaScript/TypeScript: prettier, eslint\n", .{});
        std.debug.print("    * Rust: rustfmt\n", .{});
        std.debug.print("  - Use --check mode to verify without modifying files\n", .{});
    }
}

fn formatFiles(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    config: FormatterConfig,
    files: []const []const u8,
) !void {
    std.debug.print("=== Batch formatting {d} files ===\n\n", .{files.len});

    var success_count: usize = 0;
    var error_count: usize = 0;

    for (files, 0..) |filepath, idx| {
        std.debug.print("[{d}/{d}] {s}\n", .{ idx + 1, files.len, filepath });

        formatFile(client, allocator, config, filepath) catch |err| {
            std.debug.print("  Error: {}\n\n", .{err});
            error_count += 1;
            if (!config.continue_on_error) {
                return err;
            }
            continue;
        };

        success_count += 1;
        std.debug.print("  Success\n\n", .{});
    }

    std.debug.print("=== Formatting Summary ===\n", .{});
    std.debug.print("Total: {d}\n", .{files.len});
    std.debug.print("Success: {d}\n", .{success_count});
    std.debug.print("Failed: {d}\n", .{error_count});
}

fn formatFile(
    client: *znvim.Client,
    allocator: std.mem.Allocator,
    config: FormatterConfig,
    filepath: []const u8,
) !void {
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

    // Get file type
    const ft_name = try msgpack.string(allocator, "filetype");
    defer msgpack.free(ft_name, allocator);

    const ft_result = try client.request("nvim_buf_get_option", &[_]msgpack.Value{ buf, ft_name });
    defer msgpack.free(ft_result, allocator);

    const ft_str = msgpack.asString(ft_result) orelse "unknown";
    const filetype = if (ft_str.len == 0) "(not set)" else ft_str;

    if (config.verbose) {
        std.debug.print("  File type: {s}\n", .{filetype});
    }

    // Find corresponding format command
    const fmt_cmd_template = config.formatters.get(filetype) orelse {
        if (config.verbose) {
            std.debug.print("  Skipped (no formatter)\n", .{});
        }
        return;
    };

    // Replace % with filename
    const fmt_cmd_str = try std.mem.replaceOwned(u8, allocator, fmt_cmd_template, "%", filepath);
    defer allocator.free(fmt_cmd_str);

    if (config.verbose) {
        std.debug.print("  Command: {s}\n", .{fmt_cmd_str});
    }

    // Execute format
    const fmt_cmd = try msgpack.string(allocator, fmt_cmd_str);
    defer msgpack.free(fmt_cmd, allocator);

    var fmt_opts = msgpack.Value.mapPayload(allocator);
    defer msgpack.free(fmt_opts, allocator);
    try fmt_opts.mapPut("output", msgpack.boolean(true));

    const fmt_result = try client.request("nvim_exec2", &[_]msgpack.Value{ fmt_cmd, fmt_opts });
    defer msgpack.free(fmt_result, allocator);

    // Write changes if needed
    if (config.write_changes) {
        const write_cmd = try msgpack.string(allocator, "write");
        defer msgpack.free(write_cmd, allocator);

        var write_opts = msgpack.Value.mapPayload(allocator);
        defer msgpack.free(write_opts, allocator);
        try write_opts.mapPut("output", msgpack.boolean(false));

        const write_result = try client.request("nvim_exec2", &[_]msgpack.Value{ write_cmd, write_opts });
        defer msgpack.free(write_result, allocator);
    }
}

fn printUsage() void {
    std.debug.print(
        \\Code Formatter
        \\
        \\Usage:
        \\  code_formatter [options] [files...]
        \\
        \\Options:
        \\  -h, --help       Show this help message
        \\  -c, --check      Check only, don't modify files
        \\  -v, --verbose    Show verbose information
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
        \\  code_formatter
        \\
        \\  # Format a single file
        \\  code_formatter main.zig
        \\
        \\  # Batch format
        \\  code_formatter src/*.zig
        \\
        \\  # Check format only
        \\  code_formatter --check src/*.zig
        \\
        \\  # Connect to running Neovim
        \\  export NVIM_LISTEN_ADDRESS=/tmp/nvim.sock
        \\  code_formatter main.zig
        \\
    , .{});
}
