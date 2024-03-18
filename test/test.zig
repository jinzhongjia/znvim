const std = @import("std");
const znvim = @import("znvim");
const File = std.fs.File;
const ChildProcess = std.ChildProcess;
const allocator = std.testing.allocator;
const expect = std.testing.expect;

const args = [_][]const u8{ "nvim", "--embed" };

const ClientFileType = znvim.DefaultClient(.file);

test "basic embed connect" {
    var nvim = try create_nvim_process();

    var client = try ClientFileType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        allocator,
    );
    defer client.deinit();

    _ = try nvim.kill();
}

test "call" {
    var nvim = try create_nvim_process();

    var client = try ClientFileType.init(
        nvim.stdin.?,
        nvim.stdout.?,
        allocator,
    );
    defer client.deinit();

    const params = try ClientFileType.createParams(0, allocator);
    defer ClientFileType.freeParams(params, allocator);

    const res = try client.call("nvim_get_current_buf", params);
    defer client.freeResultType(res);

    _ = try nvim.kill();
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
