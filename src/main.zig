const std = @import("std");
const znvim = @import("znvim");
const net = std.net;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const address = try std.net.Address.parseIp4("127.0.0.1", 9090);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    const Client = znvim.Client(struct {});

    var client = try Client.init(stream, arena_allocator);

    const buffer = try client.call(.nvim_get_current_buf, .{}, allocator);
    std.log.info("current buffer is {any}", .{buffer.data});
    defer allocator.free(buffer.data);

    while (true) {
        try client.loop(allocator);
    }
}
