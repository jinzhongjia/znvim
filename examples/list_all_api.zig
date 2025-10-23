const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("warning: leaked allocations\n", .{}),
    };
    const allocator = gpa.allocator();

    std.debug.print("=== znvim - List All Neovim API Functions ===\n\n", .{});

    // Spawn Neovim in clean headless mode
    std.debug.print("🚀 Spawning Neovim in clean headless mode...\n", .{});
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim", // Uses nvim from PATH
        .timeout_ms = 5000,
    });
    defer client.deinit();

    try client.connect();
    std.debug.print("✓ Connected successfully!\n\n", .{});

    // Get API info
    const info = client.getApiInfo() orelse return error.ApiInfoUnavailable;

    // ========================================
    // Print Neovim Version Information
    // ========================================
    std.debug.print("╭─────────────────────────────────────────────────────\n", .{});
    std.debug.print("│ 📋 Neovim Version Information\n", .{});
    std.debug.print("├─────────────────────────────────────────────────────\n", .{});
    std.debug.print("│  Version:        {d}.{d}.{d}\n", .{
        info.version.major,
        info.version.minor,
        info.version.patch,
    });
    std.debug.print("│  API Level:      {d}\n", .{info.version.api_level});
    std.debug.print("│  API Compatible: {d}\n", .{info.version.api_compatible});
    std.debug.print("│  Channel ID:     {d}\n", .{info.channel_id});
    std.debug.print("│  Prerelease:     {}\n", .{info.version.prerelease});
    std.debug.print("│  API Prerelease: {}\n", .{info.version.api_prerelease});

    if (info.version.build) |build| {
        std.debug.print("│  Build:          {s}\n", .{build});
    }

    std.debug.print("╰─────────────────────────────────────────────────────\n\n", .{});

    // ========================================
    // Categorize API Functions
    // ========================================
    var buf_functions = std.ArrayListUnmanaged(*const znvim.ApiFunction){};
    defer buf_functions.deinit(allocator);

    var win_functions = std.ArrayListUnmanaged(*const znvim.ApiFunction){};
    defer win_functions.deinit(allocator);

    var tabpage_functions = std.ArrayListUnmanaged(*const znvim.ApiFunction){};
    defer tabpage_functions.deinit(allocator);

    var ui_functions = std.ArrayListUnmanaged(*const znvim.ApiFunction){};
    defer ui_functions.deinit(allocator);

    var extmark_functions = std.ArrayListUnmanaged(*const znvim.ApiFunction){};
    defer extmark_functions.deinit(allocator);

    var core_functions = std.ArrayListUnmanaged(*const znvim.ApiFunction){};
    defer core_functions.deinit(allocator);

    for (info.functions) |*fn_info| {
        if (std.mem.startsWith(u8, fn_info.name, "nvim_buf_")) {
            try buf_functions.append(allocator, fn_info);
        } else if (std.mem.startsWith(u8, fn_info.name, "nvim_win_")) {
            try win_functions.append(allocator, fn_info);
        } else if (std.mem.startsWith(u8, fn_info.name, "nvim_tabpage_")) {
            try tabpage_functions.append(allocator, fn_info);
        } else if (std.mem.startsWith(u8, fn_info.name, "nvim_ui_")) {
            try ui_functions.append(allocator, fn_info);
        } else if (std.mem.indexOf(u8, fn_info.name, "extmark") != null) {
            try extmark_functions.append(allocator, fn_info);
        } else {
            try core_functions.append(allocator, fn_info);
        }
    }

    // ========================================
    // Print Statistics
    // ========================================
    std.debug.print("╭─────────────────────────────────────────────────────\n", .{});
    std.debug.print("│ 📊 API Function Statistics\n", .{});
    std.debug.print("├─────────────────────────────────────────────────────\n", .{});
    std.debug.print("│  Core Functions:       {d:4}\n", .{core_functions.items.len});
    std.debug.print("│  Buffer Functions:     {d:4}\n", .{buf_functions.items.len});
    std.debug.print("│  Window Functions:     {d:4}\n", .{win_functions.items.len});
    std.debug.print("│  Tabpage Functions:    {d:4}\n", .{tabpage_functions.items.len});
    std.debug.print("│  UI Functions:         {d:4}\n", .{ui_functions.items.len});
    std.debug.print("│  Extmark Functions:    {d:4}\n", .{extmark_functions.items.len});
    std.debug.print("│  ─────────────────────────────\n", .{});
    std.debug.print("│  Total:                {d:4}\n", .{info.functions.len});
    std.debug.print("╰─────────────────────────────────────────────────────\n\n", .{});

    // ========================================
    // Print All Functions by Category
    // ========================================
    std.debug.print("Legend: ● = method call, ○ = regular function\n\n", .{});

    // Print Core Functions
    std.debug.print("╭─ Core Functions ({d})\n", .{core_functions.items.len});
    for (core_functions.items) |fn_info| {
        const method_indicator = if (fn_info.method) "●" else "○";
        std.debug.print("│  {s} {s:<45} -> {s}\n", .{
            method_indicator,
            fn_info.name,
            fn_info.return_type,
        });
    }
    std.debug.print("╰\n\n", .{});

    // Print Buffer Functions
    if (buf_functions.items.len > 0) {
        std.debug.print("╭─ Buffer Functions ({d})\n", .{buf_functions.items.len});
        for (buf_functions.items) |fn_info| {
            const method_indicator = if (fn_info.method) "●" else "○";
            std.debug.print("│  {s} {s:<45} -> {s}\n", .{
                method_indicator,
                fn_info.name,
                fn_info.return_type,
            });
        }
        std.debug.print("╰\n\n", .{});
    }

    // Print Window Functions
    if (win_functions.items.len > 0) {
        std.debug.print("╭─ Window Functions ({d})\n", .{win_functions.items.len});
        for (win_functions.items) |fn_info| {
            const method_indicator = if (fn_info.method) "●" else "○";
            std.debug.print("│  {s} {s:<45} -> {s}\n", .{
                method_indicator,
                fn_info.name,
                fn_info.return_type,
            });
        }
        std.debug.print("╰\n\n", .{});
    }

    // Print Tabpage Functions
    if (tabpage_functions.items.len > 0) {
        std.debug.print("╭─ Tabpage Functions ({d})\n", .{tabpage_functions.items.len});
        for (tabpage_functions.items) |fn_info| {
            const method_indicator = if (fn_info.method) "●" else "○";
            std.debug.print("│  {s} {s:<45} -> {s}\n", .{
                method_indicator,
                fn_info.name,
                fn_info.return_type,
            });
        }
        std.debug.print("╰\n\n", .{});
    }

    // Print UI Functions
    if (ui_functions.items.len > 0) {
        std.debug.print("╭─ UI Functions ({d})\n", .{ui_functions.items.len});
        for (ui_functions.items) |fn_info| {
            const method_indicator = if (fn_info.method) "●" else "○";
            std.debug.print("│  {s} {s:<45} -> {s}\n", .{
                method_indicator,
                fn_info.name,
                fn_info.return_type,
            });
        }
        std.debug.print("╰\n\n", .{});
    }

    // Print Extmark Functions
    if (extmark_functions.items.len > 0) {
        std.debug.print("╭─ Extmark Functions ({d})\n", .{extmark_functions.items.len});
        for (extmark_functions.items) |fn_info| {
            const method_indicator = if (fn_info.method) "●" else "○";
            std.debug.print("│  {s} {s:<45} -> {s}\n", .{
                method_indicator,
                fn_info.name,
                fn_info.return_type,
            });
        }
        std.debug.print("╰\n\n", .{});
    }

    // ========================================
    // Print Function Details (Optional)
    // ========================================
    std.debug.print("╭─────────────────────────────────────────────────────\n", .{});
    std.debug.print("│ 🔍 Detailed Function Information\n", .{});
    std.debug.print("├─────────────────────────────────────────────────────\n", .{});
    std.debug.print("│  Showing details for first 3 functions...\n", .{});
    std.debug.print("╰─────────────────────────────────────────────────────\n\n", .{});

    const detail_count = @min(3, info.functions.len);
    for (info.functions[0..detail_count]) |*fn_info| {
        std.debug.print("Function: {s}\n", .{fn_info.name});
        std.debug.print("  Return Type: {s}\n", .{fn_info.return_type});
        std.debug.print("  Method Call: {}\n", .{fn_info.method});
        std.debug.print("  Since API:   {d}\n", .{fn_info.since});
        std.debug.print("  Parameters:  {d}\n", .{fn_info.parameters.len});

        if (fn_info.parameters.len > 0) {
            std.debug.print("    Parameters:\n", .{});
            for (fn_info.parameters) |param| {
                std.debug.print("      - {s:<20} : {s}\n", .{ param.name, param.type_name });
            }
        }
        std.debug.print("\n", .{});
    }

    // ========================================
    // Summary
    // ========================================
    std.debug.print("╭─────────────────────────────────────────────────────\n", .{});
    std.debug.print("│ ✓ Complete API List Generated\n", .{});
    std.debug.print("├─────────────────────────────────────────────────────\n", .{});
    std.debug.print("│  Total Functions: {d}\n", .{info.functions.len});
    std.debug.print("│  Neovim Version:  {d}.{d}.{d}\n", .{
        info.version.major,
        info.version.minor,
        info.version.patch,
    });
    std.debug.print("│  API Level:       {d}\n", .{info.version.api_level});
    std.debug.print("╰─────────────────────────────────────────────────────\n", .{});

    std.debug.print("\n✓ Neovim process will be terminated automatically.\n", .{});
}
