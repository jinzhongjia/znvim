const std = @import("std");
const znvim = @import("znvim");
const File = std.fs.File;
const ChildProcess = std.ChildProcess;
const allocator = std.testing.allocator;
const expect = std.testing.expect;

const args = [_][]const u8{ "nvim", "--embed" };

const ClientType = znvim.DefaultClientType(struct {}, .file);

test "basic connect" {
    const nvim = try create_nvim_process();

    const client = try ClientType.init(
        try get_stdin(nvim),
        try get_stdout(nvim),
        allocator,
    );
    defer client.deinit();
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

fn get_stdin(nvim: ChildProcess) !File {
    if (nvim.stdin) |val| {
        return val;
    }
    return error.NotFoundStdin;
}

fn get_stdout(nvim: ChildProcess) !File {
    if (nvim.stdout) |val| {
        return val;
    }
    return error.NotFoundStdout;
}
