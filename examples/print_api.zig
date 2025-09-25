const std = @import("std");
const znvim = @import("znvim");

// Define a light-weight error set that expresses everything that can go wrong
// in this example. Returning explicit errors keeps the control flow readable.
const ExampleError = error{ MissingAddress, ApiInfoUnavailable };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("warning: leaked allocations\n", .{}),
    };
    const allocator = gpa.allocator();

    // Ask the user for the Neovim socket location. Any transport supported by
    // Neovim (Unix socket, TCP, etc.) works – as long as the address is stored
    // in the `NVIM_LISTEN_ADDRESS` environment variable.
    const address = std.process.getEnvVarOwned(allocator, "NVIM_LISTEN_ADDRESS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            std.debug.print("Set NVIM_LISTEN_ADDRESS before running this example.\n", .{});
            return ExampleError.MissingAddress;
        },
        else => return err,
    };
    defer allocator.free(address);

    // Initialising the client only records options. `connect` performs the
    // actual socket dial and queries the Neovim API metadata automatically.
    var client = try znvim.Client.init(allocator, .{ .socket_path = address });
    defer client.deinit();
    try client.connect();

    // Metadata is cached inside the client, so querying it is inexpensive.
    const info = client.getApiInfo() orelse return ExampleError.ApiInfoUnavailable;

    std.debug.print(
        "Connected to Neovim API {d}.{d}.{d} (channel id {d}). Total functions: {d}\n",
        .{ info.version.major, info.version.minor, info.version.patch, info.channel_id, info.functions.len },
    );

    const show = @min(info.functions.len, 10);
    if (show == 0) {
        std.debug.print("No functions reported.\n", .{});
        return;
    }

    std.debug.print("First {d} functions:\n", .{show});
    for (info.functions[0..show]) |fn_info| {
        std.debug.print("  {s} (since {d}, method={})\n", .{ fn_info.name, fn_info.since, fn_info.method });
    }
}
