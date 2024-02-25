const std = @import("std");
const znvim = @import("znvim");
const ChildProcess = std.ChildProcess;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("memory leak!");
    }

    const args = [_][]const u8{ "nvim", "--embed" };
    var nvim = ChildProcess.init(&args, allocator);

    // set to use pipe
    nvim.stdin_behavior = .Pipe;
    // set to use pipe
    nvim.stdout_behavior = .Pipe;
    // set ignore
    nvim.stderr_behavior = .Ignore;

    // try spwan
    try nvim.spawn();

    // get stdin and stdout pipe
    const nvim_stdin = if (nvim.stdin) |val| val else @panic("not get nvim stdin!");
    const nvim_stdout = if (nvim.stdout) |val| val else @panic("not get nvim stdout!");

    // get znvim client_type
    const ClientType = znvim.DefaultClientType(struct {}, .file);

    const client = try ClientType.init(
        nvim_stdin,
        nvim_stdout,
        allocator,
        true,
    );
    defer client.deinit();

    std.log.info(
        "channel id id {}, function'nums is {}",
        .{ client.channel_id, client.metadata.functions.len },
    );

    const nvim_term = try nvim.kill();
    switch (nvim_term) {
        inline else => |code, status| {
            std.log.info("nvim status is {s}, code is {}", .{ @tagName(status), code });
        },
    }
}
