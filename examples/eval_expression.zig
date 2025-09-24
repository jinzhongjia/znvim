const std = @import("std");
const znvim = @import("../src/root.zig");
const msgpack = @import("msgpack");

const ExampleError = error{MissingAddress};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("warning: leaked allocations\n", .{}),
    };
    const allocator = gpa.allocator();

    const address = std.os.getenv("NVIM_LISTEN_ADDRESS") orelse {
        std.debug.print("Set NVIM_LISTEN_ADDRESS before running this example.\n", .{});
        return ExampleError.MissingAddress;
    };

    // The client performs runtime API discovery during connect, so the
    // resulting `request` call can rely on the negotiated interface.
    var client = try znvim.Client.init(allocator, .{ .socket_path = address });
    defer client.deinit();
    try client.connect();

    // Build the MsgPack parameter list the same way Neovim expects when
    // calling `nvim_eval`. Here we ask Neovim to join two strings with a dash.
    var expr_payload = try msgpack.Payload.strToPayload("join(['zig', 'nvim'], '-')", allocator);
    defer expr_payload.free(allocator);

    const params = [_]msgpack.Payload{expr_payload};
    var result = try client.request("vim_eval", &params);
    defer result.free(allocator);

    // The result type depends on the evaluated expression. Demonstrate a few
    // common conversions and print the raw MsgPack payload otherwise.
    switch (result) {
        .str => |s| std.debug.print("vim_eval returned string: {s}\n", .{s.value()}),
        .int => |v| std.debug.print("vim_eval returned integer: {d}\n", .{v}),
        else => std.debug.print("vim_eval returned: {any}\n", .{result}),
    }
}
