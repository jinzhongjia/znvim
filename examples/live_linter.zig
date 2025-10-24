const std = @import("std");
const znvim = @import("znvim");

/// Production example: Live code linter/checker
///
/// This example demonstrates how to:
/// 1. Subscribe to buffer change events
/// 2. Run lint/check operations when buffer changes
/// 3. Display diagnostics/errors in Neovim
/// 4. Provide real-time feedback to users
///
/// Use case: Building a language server or code quality tool

const DiagnosticSeverity = enum {
    Error,
    Warning,
    Info,
    Hint,
};

const Diagnostic = struct {
    line: usize,
    column: usize,
    message: []const u8,
    severity: DiagnosticSeverity,
};

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
        std.debug.print("🚀 Spawning Neovim instance for live linting...\n", .{});
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

    try demonstrateLiveLinting(&client, allocator);
}

fn demonstrateLiveLinting(client: *znvim.Client, allocator: std.mem.Allocator) !void {
    std.debug.print("=== Live Linter Demo ===\n\n", .{});
    std.debug.print("💡 This example demonstrates real-time code checking\n", .{});
    std.debug.print("   In production, you would:\n", .{});
    std.debug.print("   1. Subscribe to nvim_buf_attach events\n", .{});
    std.debug.print("   2. Run linter when buffer changes\n", .{});
    std.debug.print("   3. Display results using virtual text or signs\n\n", .{});

    // Step 1: Create a buffer with some code
    std.debug.print("📝 Creating buffer with sample Zig code...\n", .{});

    const buf = try client.request("nvim_create_buf", &[_]znvim.msgpack.Value{
        znvim.msgpack.boolean(true), // listed
        znvim.msgpack.boolean(false), // not scratch
    });
    // Don't free buf yet - we'll use it throughout the function
    defer znvim.msgpack.free(buf, allocator);

    std.debug.print("   Buffer created\n\n", .{});

    // Step 2: Add sample code with intentional "issues"
    const sample_code = [_][]const u8{
        "const std = @import(\"std\");",
        "",
        "pub fn main() !void {",
        "    var x = 42; // unused variable",
        "    const y = 10;",
        "    std.debug.print(\"Result: {}\\n\", .{y});",
        "    // TODO: implement error handling",
        "}",
    };

    var lines_array = std.array_list.AlignedManaged(znvim.msgpack.Value, null).init(allocator);
    defer lines_array.deinit(); // Don't free items - array() takes ownership

    for (sample_code) |line| {
        const line_val = try znvim.msgpack.string(allocator, line);
        try lines_array.append(line_val);
    }

    const lines_val = try znvim.msgpack.array(allocator, lines_array.items);
    defer znvim.msgpack.free(lines_val, allocator); // This frees lines_val AND all its elements

    const set_result = try client.request("nvim_buf_set_lines", &[_]znvim.msgpack.Value{
        buf,
        znvim.msgpack.int(0),
        znvim.msgpack.int(-1),
        znvim.msgpack.boolean(false),
        lines_val,
    });
    defer znvim.msgpack.free(set_result, allocator);

    std.debug.print("📄 Sample code loaded:\n", .{});
    for (sample_code, 0..) |line, i| {
        std.debug.print("   {d:2} | {s}\n", .{ i + 1, line });
    }
    std.debug.print("\n", .{});

    // Step 3: Simulate linting - analyze the code
    std.debug.print("🔍 Running linter analysis...\n\n", .{});

    const diagnostics = [_]Diagnostic{
        .{
            .line = 3, // Line 4 (0-indexed line 3)
            .column = 9,
            .message = "unused variable 'x'",
            .severity = .Warning,
        },
        .{
            .line = 6, // Line 7 (0-indexed line 6)
            .column = 4,
            .message = "TODO comment found",
            .severity = .Info,
        },
    };

    std.debug.print("⚠️  Found {d} issue(s):\n\n", .{diagnostics.len});

    for (diagnostics) |diag| {
        const severity_icon = switch (diag.severity) {
            .Error => "❌",
            .Warning => "⚠️ ",
            .Info => "💡",
            .Hint => "💭",
        };

        const severity_name = switch (diag.severity) {
            .Error => "Error",
            .Warning => "Warning",
            .Info => "Info",
            .Hint => "Hint",
        };

        std.debug.print("{s} {s} at line {d}, column {d}:\n", .{
            severity_icon,
            severity_name,
            diag.line + 1,
            diag.column + 1,
        });
        std.debug.print("   {s}\n\n", .{diag.message});
    }

    // Step 4: Create namespace for diagnostics
    std.debug.print("📍 Creating diagnostic namespace...\n", .{});

    const ns_name = try znvim.msgpack.string(allocator, "live_linter_demo");
    defer znvim.msgpack.free(ns_name, allocator);

    const ns_result = try client.request("nvim_create_namespace", &[_]znvim.msgpack.Value{ns_name});
    defer znvim.msgpack.free(ns_result, allocator);

    const ns_id = try znvim.msgpack.expectI64(ns_result);
    std.debug.print("   Namespace ID: {d}\n\n", .{ns_id});

    // Step 5: Add virtual text to show diagnostics
    std.debug.print("💬 Adding virtual text diagnostics...\n", .{});

    for (diagnostics) |diag| {
        const virt_text_msg = try std.fmt.allocPrint(
            allocator,
            "← {s}",
            .{diag.message},
        );
        defer allocator.free(virt_text_msg);

        const highlight = switch (diag.severity) {
            .Error => "ErrorMsg",
            .Warning => "WarningMsg",
            .Info => "Comment",
            .Hint => "Comment",
        };

        // Create virtual text chunk
        const msg_val = try znvim.msgpack.string(allocator, virt_text_msg);
        const hl_val = try znvim.msgpack.string(allocator, highlight);
        const chunk = try znvim.msgpack.array(allocator, &[_]znvim.msgpack.Value{ msg_val, hl_val });
        // Don't free chunk - virt_text takes ownership

        const virt_text = try znvim.msgpack.array(allocator, &[_]znvim.msgpack.Value{chunk});
        // Don't free virt_text - mapPut takes ownership

        // Create options map
        var opts = znvim.msgpack.Value.mapPayload(allocator);
        // Don't free opts here - it will be freed after request completes

        try opts.mapPut("virt_text", virt_text);

        const extmark_result = try client.request("nvim_buf_set_extmark", &[_]znvim.msgpack.Value{
            buf,
            znvim.msgpack.int(ns_id),
            znvim.msgpack.int(@as(i64, @intCast(diag.line))),
            znvim.msgpack.int(@as(i64, @intCast(diag.column))),
            opts,
        });
        defer znvim.msgpack.free(extmark_result, allocator);
        defer znvim.msgpack.free(opts, allocator); // Free opts after request

        std.debug.print("   ✓ Added diagnostic at line {d}\n", .{diag.line + 1});
    }

    std.debug.print("\n", .{});

    // Step 6: Summary and recommendations
    std.debug.print("📊 Linting Summary:\n", .{});
    std.debug.print("   Total issues: {d}\n", .{diagnostics.len});

    var error_count: usize = 0;
    var warning_count: usize = 0;
    var info_count: usize = 0;

    for (diagnostics) |diag| {
        switch (diag.severity) {
            .Error => error_count += 1,
            .Warning => warning_count += 1,
            .Info, .Hint => info_count += 1,
        }
    }

    std.debug.print("   Errors: {d}\n", .{error_count});
    std.debug.print("   Warnings: {d}\n", .{warning_count});
    std.debug.print("   Info: {d}\n\n", .{info_count});

    std.debug.print("💡 In a production linter, you would:\n", .{});
    std.debug.print("   1. Use nvim_buf_attach to get real-time change events\n", .{});
    std.debug.print("   2. Debounce changes to avoid too frequent checks\n", .{});
    std.debug.print("   3. Run actual linter (e.g., zig fmt --check, clippy)\n", .{});
    std.debug.print("   4. Parse linter output and create diagnostics\n", .{});
    std.debug.print("   5. Update extmarks and signs based on diagnostics\n", .{});
    std.debug.print("   6. Provide code actions for auto-fixes\n\n", .{});

    std.debug.print("✨ Live linter demo complete!\n", .{});
    std.debug.print("   The diagnostics have been added to the buffer\n", .{});
    std.debug.print("   In a real editor, you would see virtual text next to the issues\n", .{});
}
