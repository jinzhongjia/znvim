const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer switch (gpa.deinit()) {
        .ok => {},
        .leak => std.debug.print("warning: leaked allocations\n", .{}),
    };
    const allocator = gpa.allocator();

    std.debug.print("=== znvim Simple Example (Auto-spawn Neovim) ===\n\n", .{});

    // This will automatically spawn Neovim in headless mode
    // No need to set NVIM_LISTEN_ADDRESS environment variable
    var client = try znvim.Client.init(allocator, .{
        .spawn_process = true,
        .nvim_path = "nvim", // Uses nvim from PATH
        .timeout_ms = 5000,
    });
    defer client.deinit();

    std.debug.print("Starting Neovim process...\n", .{});
    try client.connect();
    std.debug.print("✓ Connected to embedded Neovim!\n\n", .{});

    // Get API info
    const info = client.getApiInfo() orelse return error.ApiInfoUnavailable;
    std.debug.print("Neovim Version: {d}.{d}.{d}\n", .{
        info.version.major,
        info.version.minor,
        info.version.patch,
    });
    std.debug.print("API Level: {d}\n", .{info.version.api_level});
    std.debug.print("Total API Functions: {d}\n\n", .{info.functions.len});

    // Example 1: Evaluate mathematical expressions
    std.debug.print("Example 1: Evaluating '10 + 20'\n", .{});
    {
        const expr = try msgpack.string(allocator, "10 + 20");
        defer msgpack.free(expr, allocator);

        const params = [_]msgpack.Value{expr};
        const result = try client.request("nvim_eval", &params);
        defer msgpack.free(result, allocator);

        switch (result) {
            .int => |v| std.debug.print("  Result: {d}\n\n", .{v}),
            .uint => |v| std.debug.print("  Result: {d}\n\n", .{v}),
            else => std.debug.print("  Unexpected result type\n\n", .{}),
        }
    }

    // Example 2: Evaluate string expressions
    std.debug.print("Example 2: Evaluating join(['Zig', 'Neovim'], ' + ')\n", .{});
    {
        const expr = try msgpack.string(allocator, "join(['Zig', 'Neovim'], ' + ')");
        defer msgpack.free(expr, allocator);

        const params = [_]msgpack.Value{expr};
        const result = try client.request("nvim_eval", &params);
        defer msgpack.free(result, allocator);

        if (msgpack.asString(result)) |text| {
            std.debug.print("  Result: {s}\n\n", .{text});
        }
    }

    // Example 3: Get Neovim mode
    std.debug.print("Example 3: Getting current mode\n", .{});
    {
        const result = try client.request("nvim_get_mode", &.{});
        defer msgpack.free(result, allocator);

        if (result == .map) {
            if (result.map.get("mode")) |mode_val| {
                if (msgpack.asString(mode_val)) |mode| {
                    std.debug.print("  Current mode: {s}\n", .{mode});
                }
            }
            if (result.map.get("blocking")) |blocking_val| {
                if (msgpack.asBool(blocking_val)) |blocking| {
                    std.debug.print("  Blocking: {}\n\n", .{blocking});
                }
            }
        }
    }

    // Example 4: List all loaded buffers
    std.debug.print("Example 4: Listing buffers\n", .{});
    {
        const result = try client.request("nvim_list_bufs", &.{});
        defer msgpack.free(result, allocator);

        if (msgpack.asArray(result)) |buffers| {
            std.debug.print("  Total buffers: {d}\n\n", .{buffers.len});
        }
    }

    // Example 5: Get a variable
    std.debug.print("Example 5: Setting and getting a variable\n", .{});
    {
        // Set a global variable
        const var_name = try msgpack.string(allocator, "my_test_var");
        defer msgpack.free(var_name, allocator);
        const var_value = try msgpack.string(allocator, "Hello from Zig!");
        defer msgpack.free(var_value, allocator);

        const set_params = [_]msgpack.Value{ var_name, var_value };
        const set_result = try client.request("nvim_set_var", &set_params);
        defer msgpack.free(set_result, allocator);

        // Get the variable back
        const get_params = [_]msgpack.Value{var_name};
        const get_result = try client.request("nvim_get_var", &get_params);
        defer msgpack.free(get_result, allocator);

        if (msgpack.asString(get_result)) |text| {
            std.debug.print("  Variable value: {s}\n\n", .{text});
        }
    }

    std.debug.print("✓ All examples completed successfully!\n", .{});
    std.debug.print("✓ Neovim process will be terminated automatically\n", .{});
}
