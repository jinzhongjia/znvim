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

const ClientType = znvim.DefaultClientType(struct {});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("memory leak!");
    }

    const stream = try std.net.tcpConnectToAddress(try std.net.Address.parseIp4(address, port));
    defer stream.close();

    const client = try ClientType.init(stream, allocator);
    defer client.deinit();
    std.log.info("channel id id {}, function'nums is {}", .{ client.channel_id, client.metadata.functions.len });

    const buffer = try client.call(.nvim_get_current_buf, .{}, allocator);
    defer allocator.free(buffer.data);
    std.log.info("current buffer is {any}", .{buffer.data});

    const chunk = znvim.api.nvim_echo.chunk;

    var chunks = [2]chunk{
        chunk{ wrapStr("hello "), wrapStr("") },
        chunk{ wrapStr("world"), wrapStr("") },
    };
    try client.call(
        .nvim_echo,
        .{ &chunks, true, .{ .verbose = false } },
        allocator,
    );

    // while (true) {
    //     try client.loop(allocator);
    // }
}
