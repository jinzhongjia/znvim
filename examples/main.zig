//! This file is not an example, it is a file that is retained for testing during the development of this package.
const std = @import("std");
const znvim = @import("znvim");

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

    const ClientType = znvim.Client(20480, .socket);
    var r = try ClientType.init(stream, stream, allocator);
    defer r.deinit();

    const params = try ClientType.createParams(0, allocator);
    defer ClientType.freeParams(params, allocator);

    const result = try r.call("nvim_get_current_buf", params);
    defer r.freeResultType(result);

    std.log.info("channel id is {}", .{result.result});
}
