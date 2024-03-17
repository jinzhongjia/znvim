//! This file is not an example, it is a file that is retained for testing during the development of this package.
const std = @import("std");
const znvim = @import("znvim");

const address = "127.0.0.1";
const port = 9090;

const ClientType = znvim.Client(20480, .socket);

var r: ClientType = undefined;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("memory leak!");
    }

    const stream = try std.net.tcpConnectToAddress(try std.net.Address.parseIp4(address, port));
    defer stream.close();

    r = try ClientType.init(stream, stream, allocator);
    defer r.deinit();

    {
        const params = try ClientType.createParams(0, allocator);
        defer ClientType.freeParams(params, allocator);

        const result = try r.call("nvim_get_current_buf", params);
        defer r.freeResultType(result);
        std.log.info("current buffer id is {}", .{result.result.ext.data[0]});
    }
    {
        const params = try ClientType.createParams(0, allocator);
        defer ClientType.freeParams(params, allocator);

        const result = try r.call("nvim_get_current_buf", params);
        defer r.freeResultType(result);
        std.log.info("current buffer id is {}", .{result.result.ext.data[0]});
    }
    std.log.info("length is {}", .{r.rpc_client.res_fifo.readableLength()});

    std.log.info("channel id is {}", .{r.getChannelID()});

    try r.registerMethod("add", &add);

    while (true) {
        r.loop() catch {
            std.os.exit(0);
        };
    }
}

fn add(_: znvim.Payload, allocator: std.mem.Allocator) znvim.ResultType {
    const params = ClientType.createParams(0, allocator) catch unreachable;
    defer ClientType.freeParams(params, allocator);

    const result = r.call("nvim_get_current_buf", params) catch unreachable;
    defer r.freeResultType(result);

    const res = znvim.Payload.uintToPayload(result.result.ext.data[0] + 1);

    return znvim.ResultType{ .result = res };
}
