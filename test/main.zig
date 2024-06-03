const std = @import("std");
const znvim = @import("znvim");
const File = std.fs.File;
const ChildProcess = std.ChildProcess;
const expect = std.testing.expect;

const args = [_][]const u8{ "nvim", "--embed" };

const ClientType = znvim.Client(20480, .pipe, u32);

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }
    var nvim = try create_nvim_process(allocator);

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
    std.log.info("get result is {any}", .{res});
    defer client.rpc_client.freeResultType(res);

    try expect(res.result.ext.data[0] == 1);

    std.log.info("try to exit", .{});
    client.exit();
    std.log.info("run exit successfully", .{});
}

fn create_nvim_process(allocator: std.mem.Allocator) !ChildProcess {
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
