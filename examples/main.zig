const std = @import("std");
const znvim = @import("znvim");

const client_type = znvim.DefaultClientType(remote, .socket);

const address = "127.0.0.1";
const port = 9090;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("memory leak!");
    }

    const stream = try std.net.tcpConnectToAddress(try std.net.Address.parseIp4(address, port));
    defer stream.close();

    const client = try client_type.init(stream, stream, allocator, true);
    defer client.deinit();

    std.log.info("channel id is {}", .{client.channel_id});

    while (true) {
        try client.loop(allocator);
    }
}

const remote = struct {
    pub fn add(a: u16, b: u16) u16 {
        return a + b;
    }
};
