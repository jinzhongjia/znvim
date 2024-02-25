const std = @import("std");
const znvim = @import("znvim");

const ChildProcess = std.ChildProcess;
const wrapStr = znvim.wrapStr;

/// get znvim client_type
const ClientType = znvim.DefaultClientType(struct {}, .file);

const args = [_][]const u8{ "nvim", "--embed" };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("memory leak!");
    }

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

    const writer = try client.call_with_writer(.nvim_get_current_buf);
    try writer.write_array_header(0);
    const reader = try client.get_reader_with_writer(writer, allocator);
    const res = try reader.read_ext(allocator);
    defer allocator.free(res.data);
    std.log.info("current buffer is {any}", .{res.data});

    // const reader = try client.call_with_reader(.nvim_get_current_buf, .{}, allocator);
    // const res = try reader.read_ext(allocator);
    // defer allocator.free(res.data);
    // std.log.info("current buffer is {any}", .{res.data});

    // const buffer = try client.call(.nvim_get_current_buf, .{}, allocator);
    // defer allocator.free(buffer.data);
    // std.log.info("current buffer is {any}", .{buffer.data});

    const chunk = znvim.api_defs.nvim_echo.chunk;

    var chunks = [2]chunk{
        chunk{ wrapStr("hello "), wrapStr("") },
        chunk{ wrapStr("world"), wrapStr("") },
    };
    try client.call(
        .nvim_echo,
        .{ &chunks, true, .{ .verbose = false } },
        allocator,
    );

    // const read = try client.call_with_reader(
    //     .nvim_get_chan_info,
    //     .{client.channel_id},
    //     allocator,
    // );
    // const map_Len = try read.read_map_len();

    // for (map_Len) |_| {
    //     const key = try read.read_str(allocator);
    //     defer allocator.free(key);
    //     if (std.mem.eql(u8, key, "mode")) {
    //         const mode = try read.read_str(allocator);
    //         defer allocator.free(mode);
    //         std.log.info("mode is {s}", .{mode});
    //     } else {
    //         try read.skip();
    //     }
    // }

    // while (true) {
    //     try client.loop(allocator);
    // }

    const nvim_term = try nvim.kill();
    switch (nvim_term) {
        inline else => |code, status| {
            std.log.info("nvim status is {s}, code is {}", .{ @tagName(status), code });
        },
    }
}
