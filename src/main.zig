const std = @import("std");
const znvim = @import("znvim");
const msgpack = @import("msgpack");
const net = std.net;

const remote = struct {
    pub fn add(a: u16, b: u16) u16 {
        return a + b;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    // const arena_allocator = arena.allocator();

    const address = try std.net.Address.parseIp4("127.0.0.1", 9090);
    const stream = try std.net.tcpConnectToAddress(address);

    defer stream.close();

    const Client = znvim.Client(struct {});

    var client = try Client.init(stream);

    const buffer = try client.call(.nvim_get_current_buf, .{}, allocator);
    std.log.info("current buffer is {any}", .{buffer.data});
    defer allocator.free(buffer.data);
    std.log.info("get current is ok", .{});
    const arr = [_]u8{ 148, 0, 5, 177, 110, 118, 105, 109, 95, 103, 101, 116, 95, 97, 112, 105, 95, 105, 110, 102, 111, 144 };
    // _ = try client.c.send_request("get_api_info", .{});
    try client.c.pack.write_arr(u8, &arr);
    // try client.get_api_info(arena_allocator);

    // while (true) {
    //     try client.loop(allocator);
    // }
}
