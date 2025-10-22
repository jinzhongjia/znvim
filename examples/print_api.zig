const std = @import("std");
const znvim = @import("znvim");

const ExampleError = error{ MissingAddress, ApiInfoUnavailable };

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

    const info = client.getApiInfo() orelse return ExampleError.ApiInfoUnavailable;

    // Print API version information
    std.debug.print("╭─ Neovim API Information\n", .{});
    std.debug.print("│\n", .{});
    std.debug.print("│  Version: {d}.{d}.{d}\n", .{ info.version.major, info.version.minor, info.version.patch });
    std.debug.print("│  API Level: {d}\n", .{info.version.api_level});
    std.debug.print("│  API Compatible: {d}\n", .{info.version.api_compatible});
    std.debug.print("│  Channel ID: {d}\n", .{info.channel_id});
    std.debug.print("│  Prerelease: {}\n", .{info.version.prerelease});
    std.debug.print("│  API Prerelease: {}\n", .{info.version.api_prerelease});

    if (info.version.build) |build| {
        std.debug.print("│  Build: {s}\n", .{build});
    }

    std.debug.print("│\n", .{});
    std.debug.print("│  Total Functions: {d}\n", .{info.functions.len});
    std.debug.print("╰\n\n", .{});

    // Count functions by category
    var buf_count: usize = 0;
    var win_count: usize = 0;
    var tabpage_count: usize = 0;
    var ui_count: usize = 0;
    var core_count: usize = 0;
    var other_count: usize = 0;

    for (info.functions) |fn_info| {
        if (std.mem.startsWith(u8, fn_info.name, "nvim_buf_")) {
            buf_count += 1;
        } else if (std.mem.startsWith(u8, fn_info.name, "nvim_win_")) {
            win_count += 1;
        } else if (std.mem.startsWith(u8, fn_info.name, "nvim_tabpage_")) {
            tabpage_count += 1;
        } else if (std.mem.startsWith(u8, fn_info.name, "nvim_ui_")) {
            ui_count += 1;
        } else if (std.mem.startsWith(u8, fn_info.name, "nvim_")) {
            core_count += 1;
        } else {
            other_count += 1;
        }
    }

    // Print category summary
    std.debug.print("Function Categories:\n", .{});
    if (core_count > 0) std.debug.print("  Core Functions:     {d:4}\n", .{core_count});
    if (buf_count > 0) std.debug.print("  Buffer Functions:   {d:4}\n", .{buf_count});
    if (win_count > 0) std.debug.print("  Window Functions:   {d:4}\n", .{win_count});
    if (tabpage_count > 0) std.debug.print("  Tabpage Functions:  {d:4}\n", .{tabpage_count});
    if (ui_count > 0) std.debug.print("  UI Functions:       {d:4}\n", .{ui_count});
    if (other_count > 0) std.debug.print("  Other Functions:    {d:4}\n", .{other_count});
    std.debug.print("\n", .{});

    // Show a sample of functions from each category
    const show_per_category = 5;

    std.debug.print("Sample Functions:\n\n", .{});

    // Core functions
    std.debug.print("╭─ Core Functions (showing {d} of {d})\n", .{ @min(core_count, show_per_category), core_count });
    var shown: usize = 0;
    for (info.functions) |fn_info| {
        if (std.mem.startsWith(u8, fn_info.name, "nvim_") and
            !std.mem.startsWith(u8, fn_info.name, "nvim_buf_") and
            !std.mem.startsWith(u8, fn_info.name, "nvim_win_") and
            !std.mem.startsWith(u8, fn_info.name, "nvim_tabpage_") and
            !std.mem.startsWith(u8, fn_info.name, "nvim_ui_"))
        {
            if (shown >= show_per_category) break;
            const method_indicator = if (fn_info.method) "●" else "○";
            std.debug.print("│  {s} {s:<40} -> {s}\n", .{ method_indicator, fn_info.name, fn_info.return_type });
            shown += 1;
        }
    }
    if (core_count > show_per_category) {
        std.debug.print("│  ... and {d} more\n", .{core_count - show_per_category});
    }
    std.debug.print("╰\n\n", .{});

    // Buffer functions
    if (buf_count > 0) {
        std.debug.print("╭─ Buffer Functions (showing {d} of {d})\n", .{ @min(buf_count, show_per_category), buf_count });
        shown = 0;
        for (info.functions) |fn_info| {
            if (std.mem.startsWith(u8, fn_info.name, "nvim_buf_")) {
                if (shown >= show_per_category) break;
                const method_indicator = if (fn_info.method) "●" else "○";
                std.debug.print("│  {s} {s:<40} -> {s}\n", .{ method_indicator, fn_info.name, fn_info.return_type });
                shown += 1;
            }
        }
        if (buf_count > show_per_category) {
            std.debug.print("│  ... and {d} more\n", .{buf_count - show_per_category});
        }
        std.debug.print("╰\n\n", .{});
    }

    std.debug.print("Legend: ● = method call, ○ = regular function\n", .{});
    std.debug.print("\nTip: Use 'api_lookup <function-name>' to see details for a specific function.\n", .{});
}
