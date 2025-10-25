const std = @import("std");
const znvim = @import("znvim");
const msgpack = znvim.msgpack;
const helper = @import("connection_helper.zig");

fn eventHandler(method: []const u8, params: msgpack.Value, userdata: ?*anyopaque) void {
    _ = userdata;
    std.debug.print("Event received: {s}\n", .{method});

    if (params == .arr) {
        std.debug.print("  Params count: {d}\n", .{params.arr.len});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Event Handling Example ===\n\n", .{});

    // Smart connect to Neovim
    var client = try helper.smartConnect(allocator);
    defer client.deinit();

    std.debug.print("Setting event handler...\n", .{});
    client.setEventHandler(eventHandler, null);

    const api_info = client.getApiInfo() orelse return error.NoApiInfo;
    std.debug.print("Channel ID: {d}\n\n", .{api_info.channel_id});

    std.debug.print("Sending notification via lua...\n", .{});
    const lua_code_str = try std.fmt.allocPrint(
        allocator,
        \\vim.rpcnotify({d}, "test_event", "hello", "world")
    ,
        .{api_info.channel_id},
    );
    defer allocator.free(lua_code_str);

    const lua_code = try msgpack.string(allocator, lua_code_str);
    defer msgpack.free(lua_code, allocator);

    const empty_arr = try msgpack.array(allocator, &.{});
    defer msgpack.free(empty_arr, allocator);

    const result = try client.request("nvim_exec_lua", &.{ lua_code, empty_arr });
    defer msgpack.free(result, allocator);

    std.debug.print("Lua executed successfully\n\n", .{});

    // Wait a bit for the notification to arrive
    std.debug.print("Waiting for events...\n", .{});
    std.Thread.sleep(200 * std.time.ns_per_ms);

    // Make another request to trigger event processing
    std.debug.print("Processing events...\n", .{});
    const expr = try msgpack.string(allocator, "1");
    defer msgpack.free(expr, allocator);
    const eval_result = try client.request("nvim_eval", &.{expr});
    defer msgpack.free(eval_result, allocator);

    std.debug.print("Done!\n", .{});
}
