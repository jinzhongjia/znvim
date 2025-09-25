const std = @import("std");
const znvim = @import("znvim");

// Simple error set that captures the three failure modes of this example:
// missing command-line argument, missing environment variable, or the API
// function not existing on the connected Neovim instance.
const ExampleError = error{ MissingAddress, MissingArgument, FunctionNotFound };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("warning: leaked allocations\n", .{}),
    };
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // executable name
    const target_name = args.next() orelse {
        std.debug.print("Usage: api_lookup.zig <function-name>\n", .{});
        return ExampleError.MissingArgument;
    };

    const address = std.process.getEnvVarOwned(allocator, "NVIM_LISTEN_ADDRESS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            std.debug.print("Set NVIM_LISTEN_ADDRESS before running this example.\n", .{});
            return ExampleError.MissingAddress;
        },
        else => return err,
    };
    defer allocator.free(address);

    var client = try znvim.Client.init(allocator, .{ .socket_path = address });
    defer client.deinit();
    try client.connect();

    const info = client.getApiInfo() orelse return error.FunctionNotFound;
    const fn_info = info.findFunction(target_name) orelse {
        std.debug.print("Function '{s}' not found in Neovim API (total {d}).\n", .{ target_name, info.functions.len });
        return ExampleError.FunctionNotFound;
    };

    std.debug.print("Function {s}\n", .{fn_info.name});
    std.debug.print("  since: {d}\n", .{fn_info.since});
    std.debug.print("  return: {s}\n", .{fn_info.return_type});
    std.debug.print("  method: {}\n", .{fn_info.method});

    if (fn_info.parameters.len == 0) {
        std.debug.print("  parameters: (none)\n", .{});
    } else {
        std.debug.print("  parameters:\n", .{});
        for (fn_info.parameters) |param| {
            std.debug.print("    - {s} {s}\n", .{ param.type_name, param.name });
        }
    }
}
