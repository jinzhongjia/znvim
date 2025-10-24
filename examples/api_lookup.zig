const std = @import("std");
const znvim = @import("znvim");

const ExampleError = error{ MissingArgument, FunctionNotFound };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("warning: leaked allocations\n", .{}),
    };
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // Skip executable name
    const target_name = args.next() orelse {
        std.debug.print("Usage: api_lookup <function-name>\n\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  api_lookup nvim_buf_set_lines\n", .{});
        std.debug.print("  api_lookup nvim_get_current_buf\n", .{});
        std.debug.print("  api_lookup nvim_eval\n", .{});
        return ExampleError.MissingArgument;
    };

    // Try to get NVIM_LISTEN_ADDRESS from environment
    const maybe_address = std.process.getEnvVarOwned(allocator, "NVIM_LISTEN_ADDRESS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    defer if (maybe_address) |addr| allocator.free(addr);

    // If environment variable is not set, spawn a clean Neovim instance
    const use_spawn = maybe_address == null;
    var client = if (use_spawn) blk: {
        std.debug.print("NVIM_LISTEN_ADDRESS not set, spawning clean Neovim instance...\n", .{});
        break :blk try znvim.Client.init(allocator, .{
            .spawn_process = true,
            .nvim_path = "nvim",
        });
    } else blk: {
        std.debug.print("Connecting to Neovim at {s}...\n", .{maybe_address.?});
        break :blk try znvim.Client.init(allocator, .{
            .socket_path = maybe_address.?,
        });
    };
    defer client.deinit();
    try client.connect();

    const info = client.getApiInfo() orelse return error.FunctionNotFound;
    const fn_info = info.findFunction(target_name) orelse {
        std.debug.print("Function '{s}' not found in Neovim API.\n", .{target_name});
        std.debug.print("Total available functions: {d}\n\n", .{info.functions.len});
        std.debug.print("Tip: Run 'print_api' to see all available functions.\n", .{});
        return ExampleError.FunctionNotFound;
    };

    // Print detailed function information
    std.debug.print("╭─ Function: {s}\n", .{fn_info.name});
    std.debug.print("│\n", .{});
    std.debug.print("│  API Level: {d}\n", .{fn_info.since});
    std.debug.print("│  Method: {}\n", .{fn_info.method});
    std.debug.print("│  Return Type: {s}\n", .{fn_info.return_type});
    std.debug.print("│\n", .{});

    if (fn_info.parameters.len == 0) {
        std.debug.print("│  Parameters: (none)\n", .{});
    } else {
        std.debug.print("│  Parameters ({d}):\n", .{fn_info.parameters.len});
        for (fn_info.parameters, 0..) |param, i| {
            const prefix = if (i == fn_info.parameters.len - 1) "└─" else "├─";
            std.debug.print("│    {s} {s}: {s}\n", .{ prefix, param.name, param.type_name });
        }
    }
    std.debug.print("╰\n", .{});
}
