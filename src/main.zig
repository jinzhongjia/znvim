const std = @import("std");
const znvim = @import("znvim");
const net = std.net;

const wrapStr = znvim.wrapStr;

const remote = struct {
    pub fn add(a: u16, b: u16) u16 {
        return a + b;
    }
};

const address = "127.0.0.1";
const port = 9090;

const uid: u16 = 1000;
const nvim_pid: u16 = 4076;
const unique_number: u16 = 0;

const unix_socket = std.fmt.comptimePrint(
    "/run/user/{}//nvim.{}.{}",
    .{ uid, nvim_pid, unique_number },
);

const named_pipe = std.fmt.comptimePrint("\\\\.\\pipe\\nvim.{}.{}", .{ nvim_pid, unique_number });

/// get znvim client_type
const ClientType = znvim.DefaultClientType(struct {}, .file);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("memory leak!");
    }

    // const stream = try std.net.connectUnixSocket("/run/user/1000//nvim.2163.0");
    // defer stream.close();

    // const stream = try std.net.tcpConnectToAddress(try std.net.Address.parseIp4(address, port));
    // defer stream.close();

    const file = try znvim.connectNamedPipe(named_pipe, allocator);
    const client = try ClientType.init(file, file, allocator);
    defer client.deinit();
    std.log.info("channel id id {}, function'nums is {}", .{ client.channel_id, client.metadata.functions.len });

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

    const read = try client.call_with_reader(
        .nvim_get_chan_info,
        .{client.channel_id},
        allocator,
    );
    const map_Len = try read.read_map_len();

    for (map_Len) |_| {
        const key = try read.read_str(allocator);
        defer allocator.free(key);
        if (std.mem.eql(u8, key, "mode")) {
            const mode = try read.read_str(allocator);
            defer allocator.free(mode);
            std.log.info("mode is {s}", .{mode});
        } else {
            try read.skip();
        }
    }

    while (true) {
        try client.loop(allocator);
    }
}
