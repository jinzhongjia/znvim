//! This file is not an example, it is a file that is retained for testing during the development of this package.
const std = @import("std");
const znvim = @import("znvim");

const address = "127.0.0.1";
const port = 9090;

const ClientType = znvim.Client(20480, .socket);

var client: ClientType = undefined;
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("memory leak!");
    }

    const stream = try std.net.tcpConnectToAddress(try std.net.Address.parseIp4(address, port));
    defer stream.close();

    client = try ClientType.init(stream, stream, allocator);
    defer client.deinit();

    {
        const params = try ClientType.createParams(0, allocator);
        defer ClientType.freeParams(params, allocator);

        const result = try client.call("nvim_get_current_buf", params);
        defer client.freeResultType(result);
        std.log.info("current buffer id is {}", .{result.result.ext.data[0]});
    }
    {
        const params = try ClientType.createParams(0, allocator);
        defer ClientType.freeParams(params, allocator);

        const result = try client.call("nvim_get_current_buf", params);
        defer client.freeResultType(result);
        std.log.info("current buffer id is {}", .{result.result.ext.data[0]});
    }
    std.log.info("length is {}", .{client.rpc_client.res_fifo.readableLength()});

    std.log.info("channel id is {}", .{client.getChannelID()});

    try client.registerMethod("add", &add);

    {
        var params = try ClientType.createParams(2, allocator);
        defer ClientType.freeParams(params, allocator);

        params.arr[0] = try znvim.Payload.strToPayload(
            \\ return (function()
            \\ print(zignvim)
            \\ end)()
        , allocator);
        params.arr[1] = try znvim.Payload.arrPayload(0, allocator);

        try client.notify(
            "nvim_exec_lua",
            params,
        );
    }

    {
        const params = try ClientType.createParams(3, allocator);
        defer ClientType.freeParams(params, allocator);
        params.arr[0] = try znvim.Payload.strToPayload("hello", allocator);
        params.arr[1] = znvim.Payload.uintToPayload(2);
        params.arr[2] = znvim.Payload.mapPayload(allocator);

        const res = try client.call("nvim_notify", params);
        defer client.freeResultType(res);
    }

    while (true) {
        client.loop() catch {
            break;
        };
    }
}

fn add(_: znvim.Payload, allocator: std.mem.Allocator) znvim.ResultType {
    const params = ClientType.createParams(0, allocator) catch unreachable;
    defer ClientType.freeParams(params, allocator);

    const result = client.call("nvim_get_current_buf", params) catch unreachable;
    defer client.freeResultType(result);

    const res = znvim.Payload.uintToPayload(result.result.ext.data[0] + 1);

    return znvim.ResultType{ .result = res };
}
