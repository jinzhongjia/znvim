const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;

// The only thing that can realistically go wrong here is forgetting to point
// `NVIM_LISTEN_ADDRESS` at a running Neovim instance.
const ExampleError = error{MissingAddress};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("warning: leaked allocations\n", .{}),
    };
    const allocator = gpa.allocator();

    // Resolve the address of the Neovim instance we should talk to.
    const address = std.process.getEnvVarOwned(allocator, "NVIM_LISTEN_ADDRESS") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            std.debug.print("Set NVIM_LISTEN_ADDRESS before running this example.\n", .{});
            return ExampleError.MissingAddress;
        },
        else => return err,
    };
    defer allocator.free(address);

    // Create and connect our client – identical to the other examples.
    var client = try znvim.Client.init(allocator, .{ .socket_path = address });
    defer client.deinit();
    try client.connect();

    // Notifications do not expect a response, so we can skip the more expensive
    // `request` path. We still need to encode the payload with msgpack though.
    const command_payload = try msgpack.string(allocator, "echom 'Hello from Zig'");
    defer msgpack.free(command_payload, allocator);

    const params = [_]msgpack.Value{command_payload};
    try client.notify("nvim_command", &params);

    std.debug.print("Sent command to Neovim. Check :messages inside the instance.\n", .{});
}
