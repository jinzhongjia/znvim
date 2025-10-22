const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;

const ExampleError = error{MissingAddress};

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

    std.debug.print("Connected to Neovim!\n\n", .{});

    // Example 1: Evaluate a simple expression that returns a string
    {
        const expr1 = try msgpack.string(allocator, "join(['zig', 'nvim'], '-')");
        defer msgpack.free(expr1, allocator);

        const params1 = [_]msgpack.Value{expr1};
        const result1 = try client.request("nvim_eval", &params1);
        defer msgpack.free(result1, allocator);

        std.debug.print("Expression: join(['zig', 'nvim'], '-')\n", .{});
        switch (result1) {
            .str => |s| std.debug.print("Result (string): {s}\n\n", .{s.value()}),
            else => std.debug.print("Result: {any}\n\n", .{result1}),
        }
    }

    // Example 2: Evaluate an expression that returns a number
    {
        const expr2 = try msgpack.string(allocator, "2 + 3 * 4");
        defer msgpack.free(expr2, allocator);

        const params2 = [_]msgpack.Value{expr2};
        const result2 = try client.request("nvim_eval", &params2);
        defer msgpack.free(result2, allocator);

        std.debug.print("Expression: 2 + 3 * 4\n", .{});
        switch (result2) {
            .int => |v| std.debug.print("Result (integer): {d}\n\n", .{v}),
            .uint => |v| std.debug.print("Result (unsigned): {d}\n\n", .{v}),
            else => std.debug.print("Result: {any}\n\n", .{result2}),
        }
    }

    // Example 3: Evaluate an expression that returns a list
    {
        const expr3 = try msgpack.string(allocator, "range(1, 6)");
        defer msgpack.free(expr3, allocator);

        const params3 = [_]msgpack.Value{expr3};
        const result3 = try client.request("nvim_eval", &params3);
        defer msgpack.free(result3, allocator);

        std.debug.print("Expression: range(1, 6)\n", .{});
        switch (result3) {
            .arr => |arr| {
                std.debug.print("Result (array of {d} elements): [", .{arr.len});
                for (arr, 0..) |item, i| {
                    if (i > 0) std.debug.print(", ", .{});
                    switch (item) {
                        .int => |v| std.debug.print("{d}", .{v}),
                        .uint => |v| std.debug.print("{d}", .{v}),
                        else => std.debug.print("{any}", .{item}),
                    }
                }
                std.debug.print("]\n\n", .{});
            },
            else => std.debug.print("Result: {any}\n\n", .{result3}),
        }
    }

    // Example 4: Get Neovim version using expression
    {
        const expr4 = try msgpack.string(allocator, "v:version");
        defer msgpack.free(expr4, allocator);

        const params4 = [_]msgpack.Value{expr4};
        const result4 = try client.request("nvim_eval", &params4);
        defer msgpack.free(result4, allocator);

        std.debug.print("Expression: v:version\n", .{});
        switch (result4) {
            .int => |v| std.debug.print("Neovim version: {d}\n\n", .{v}),
            else => std.debug.print("Result: {any}\n\n", .{result4}),
        }
    }

    std.debug.print("All expressions evaluated successfully!\n", .{});
}
