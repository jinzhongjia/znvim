const std = @import("std");
const znvim = @import("znvim");
const File = std.fs.File;
const ChildProcess = std.ChildProcess;
const allocator = std.testing.allocator;
const expect = std.testing.expect;

const args = [_][]const u8{ "nvim", "--embed" };

const ClientType = znvim.defaultClient(.pipe, u32);

test "basic embed connect" {
    var nvim = try create_nvim_process();

    var client = try ClientType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        allocator,
    );

    defer _ = nvim.kill() catch unreachable;
    defer client.deinit();

    try client.loop();

    const params = try znvim.Payload.arrPayload(0, allocator);
    defer params.free(allocator);

    const res = try client.rpc_client.call("nvim_get_current_buf", params);
    defer client.rpc_client.freeResultType(res);

    try expect(res.result.ext.data[0] == 1);

    client.exit();
}

fn create_nvim_process() !ChildProcess {
    var nvim = ChildProcess.init(&args, allocator);

    // set to use pipe
    nvim.stdin_behavior = .Pipe;
    // set to use pipe
    nvim.stdout_behavior = .Pipe;
    // set ignore
    nvim.stderr_behavior = .Ignore;

    // try spwan
    try nvim.spawn();

    return nvim;
}
