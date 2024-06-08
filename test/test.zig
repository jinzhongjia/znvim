const std = @import("std");
const znvim = @import("znvim");

test "basic embed connect" {
    // create a client type
    // .socket is just for unix-socket and socket (tcp)
    // others use .pipe
    // u32 is the user data type, recommend to use pointer type
    const ClientType = znvim.defaultClient(.pipe, u32);

    const args = [_][]const u8{ "nvim", "--embed", "--headless", "-u", "NONE" };

    var nvim = try create_nvim_process(std.testing.allocator, &args, true);
    defer _ = nvim.kill() catch unreachable;

    // init the client
    var client = try ClientType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        std.testing.allocator,
    );

    // do not forget deinit client
    defer client.deinit();
    // texit client
    defer client.exit();

    // run client event loop
    try client.loop();
    // get neovim api infos
    // when you call this function
    // this will enable api check on debug mode
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

    // make a params
    // we no need to free params manually
    // znvim will do this automatically
    const params = try client.paramArr(0);

    // call api, and current thread will be blocked utill response comes
    const res = try client.call("nvim_get_current_buf", params);
    // note: we must free result manually
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

    // make a params
    // this is a 4 length array, in lua this is a list or array
    // we no need to free params manually
    // znvim will do this automatically
    var params = try client.paramArr(3);

    // arrary zero element
    const param_0 = try client.paramStr("hello, world!");

    // array first element
    const param_1 = client.paramUint(1);

    // array second element
    const param_2 = try client.paramArr(0);

    // set element
    try params.setArrElement(0, param_0);
    try params.setArrElement(1, param_1);
    try params.setArrElement(2, param_2);

    // notify will not block current thread, it will return immediately
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
        // for unix-socket, we can use `std.net.connectUnixSocket`
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

    const params = try client.paramArr(0);

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
