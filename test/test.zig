const std = @import("std");
const znvim = @import("znvim");

test "basic embed connect" {
    const ClientType = znvim.defaultClient(.pipe, u32);

    const args = [_][]const u8{ "nvim", "--embed", "--headless", "-u", "NONE" };

    var nvim = try create_nvim_process(std.testing.allocator, &args, true);
    defer _ = nvim.kill() catch unreachable;

    var client = try ClientType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        std.testing.allocator,
    );

    defer client.deinit();
    defer client.exit();

    try client.loop();
    try client.getApiInfo();
}

test "call function" {
    const ClientType = znvim.defaultClient(.pipe, u32);

    const args = [_][]const u8{ "nvim", "--embed", "--headless", "-u", "NONE" };

    var nvim = try create_nvim_process(std.testing.allocator, &args, true);
    defer _ = nvim.kill() catch unreachable;

    var client = try ClientType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        std.testing.allocator,
    );

    defer client.deinit();
    defer client.exit();

    try client.loop();
    try client.getApiInfo();

    const params = try znvim.Payload.arrPayload(0, std.testing.allocator);

    const res = try client.call("nvim_get_current_buf", params);
    defer client.freeResultType(res);

    try std.testing.expect(res.result.ext.data[0] == 1);
}

test "notify function" {
    const ClientType = znvim.defaultClient(.pipe, u32);

    const args = [_][]const u8{ "nvim", "--embed", "--headless", "-u", "NONE" };

    var nvim = try create_nvim_process(std.testing.allocator, &args, true);
    defer _ = nvim.kill() catch unreachable;

    var client = try ClientType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        std.testing.allocator,
    );

    defer client.deinit();
    defer client.exit();

    try client.loop();
    try client.getApiInfo();

    var params = try znvim.Payload.arrPayload(3, std.testing.allocator);

    const param_0 = try znvim.Payload.strToPayload("hello, world!", std.testing.allocator);

    const param_1 = znvim.Payload.uintToPayload(1);

    const param_2 = try znvim.Payload.arrPayload(0, std.testing.allocator);

    try params.setArrElement(0, param_0);
    try params.setArrElement(1, param_1);
    try params.setArrElement(2, param_2);

    // try params
    _ = try client.notify("nvim_notify", params);
}

test "socket connect test" {
    const address = "127.0.0.1";
    const port = 9090;

    const str = try std.fmt.allocPrint(std.testing.allocator, "{s}:{d}", .{ address, port });
    defer std.testing.allocator.free(str);

    const ClientType = znvim.defaultClient(.socket, u32);

    const args = [_][]const u8{ "nvim", "--headless", "--listen", str, "-u", "NONE" };

    var nvim = try create_nvim_process(std.testing.allocator, &args, false);
    defer _ = nvim.kill() catch unreachable;

    const stream: std.net.Stream = while (true) {
        const res = std.net.tcpConnectToHost(std.testing.allocator, address, port) catch {
            continue;
        };
        break res;
    };
    defer stream.close();

    var client = try ClientType.init(
        stream,
        stream,
        std.testing.allocator,
    );

    defer client.deinit();
    defer client.exit();

    try client.loop();
    try client.getApiInfo();

    const params = try znvim.Payload.arrPayload(0, std.testing.allocator);

    const res = try client.call("nvim_get_current_buf", params);
    defer client.freeResultType(res);

    try std.testing.expect(res.result.ext.data[0] == 1);
}

fn create_nvim_process(allocator: std.mem.Allocator, args: []const []const u8, is_pipe: bool) !std.process.Child {
    var nvim = std.process.Child.init(args, allocator);

    // set to use pipe
    nvim.stdin_behavior = if (is_pipe) .Pipe else .Ignore;
    // set to use pipe
    nvim.stdout_behavior = if (is_pipe) .Pipe else .Ignore;
    // set ignore
    nvim.stderr_behavior = if (is_pipe) .Pipe else .Ignore;

    // try spwan
    try nvim.spawn();

    return nvim;
}
