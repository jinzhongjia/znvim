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

    // Example 1: Execute a simple echo command using nvim_exec2
    // nvim_exec2 is the modern replacement for the deprecated nvim_command
    {
        std.debug.print("Example 1: Execute echo command\n", .{});

        const cmd1 = try msgpack.string(allocator, "echo 'Hello from Zig!'");
        defer msgpack.free(cmd1, allocator);

        var opts1 = msgpack.Value.mapPayload(allocator);
        defer opts1.free(allocator);
        try opts1.mapPut("output", msgpack.boolean(true));

        const params1 = [_]msgpack.Value{ cmd1, opts1 };
        const result1 = try client.request("nvim_exec2", &params1);
        defer msgpack.free(result1, allocator);

        if (result1 == .map) {
            if (result1.map.get("output")) |output| {
                if (msgpack.asString(output)) |text| {
                    std.debug.print("Output: {s}\n\n", .{text});
                }
            }
        }
    }

    // Example 2: Set an option using a command
    {
        std.debug.print("Example 2: Set line numbers\n", .{});

        const cmd2 = try msgpack.string(allocator, "set number relativenumber");
        defer msgpack.free(cmd2, allocator);

        var opts2 = msgpack.Value.mapPayload(allocator);
        defer opts2.free(allocator);
        try opts2.mapPut("output", msgpack.boolean(false));

        const params2 = [_]msgpack.Value{ cmd2, opts2 };
        const result2 = try client.request("nvim_exec2", &params2);
        defer msgpack.free(result2, allocator);

        std.debug.print("Line numbers enabled!\n\n", .{});
    }

    // Example 3: Use nvim_cmd with a structured command (modern API)
    {
        std.debug.print("Example 3: Open a new split using nvim_cmd\n", .{});

        var cmd_dict = msgpack.Value.mapPayload(allocator);
        defer cmd_dict.free(allocator);
        try cmd_dict.mapPut("cmd", try msgpack.string(allocator, "split"));

        var opts3 = msgpack.Value.mapPayload(allocator);
        defer opts3.free(allocator);

        const params3 = [_]msgpack.Value{ cmd_dict, opts3 };
        const result3 = try client.request("nvim_cmd", &params3);
        defer msgpack.free(result3, allocator);

        std.debug.print("Split window created!\n\n", .{});
    }

    // Example 4: Create a user command using nvim_exec2
    {
        std.debug.print("Example 4: Create a user command\n", .{});

        const cmd4 = try msgpack.string(
            allocator,
            \\command! HelloZig echo 'This is a custom command from Zig!'
        );
        defer msgpack.free(cmd4, allocator);

        var opts4 = msgpack.Value.mapPayload(allocator);
        defer opts4.free(allocator);
        try opts4.mapPut("output", msgpack.boolean(false));

        const params4 = [_]msgpack.Value{ cmd4, opts4 };
        const result4 = try client.request("nvim_exec2", &params4);
        defer msgpack.free(result4, allocator);

        std.debug.print("User command :HelloZig created!\n", .{});
        std.debug.print("Try running ':HelloZig' in Neovim.\n\n", .{});
    }

    // Example 5: Send a notification (fire-and-forget)
    // Use notify() for commands that don't need a response
    {
        std.debug.print("Example 5: Send notification (no response needed)\n", .{});

        const cmd5 = try msgpack.string(allocator, "echom 'Message from Zig via notification'");
        defer msgpack.free(cmd5, allocator);

        var opts5 = msgpack.Value.mapPayload(allocator);
        defer opts5.free(allocator);
        try opts5.mapPut("output", msgpack.boolean(false));

        const params5 = [_]msgpack.Value{ cmd5, opts5 };
        try client.notify("nvim_exec2", &params5);

        std.debug.print("Notification sent! Check :messages in Neovim.\n\n", .{});
    }

    std.debug.print("All commands executed successfully!\n", .{});
}
