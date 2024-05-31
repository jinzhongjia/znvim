const std = @import("std");
const znvim = @import("znvim");
const File = std.fs.File;
const ChildProcess = std.ChildProcess;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    // try pipee(allocator);
    try socket_win(allocator);
}

fn socket_win(allocator: std.mem.Allocator) !void {
    const address = "127.0.0.1";
    const port = 9090;

    const ClientType = znvim.Client(20480, .socket, u32);

    const stream = try std.net.tcpConnectToAddress(try std.net.Address.parseIp4(address, port));
    defer stream.close();

    var client = try ClientType.init(stream, stream, allocator);

    defer client.deinit();
    try client.loop();

    std.log.info("get api infos", .{});
    try client.getApiInfo();
    const channel_id = try client.getChannelID();
    std.log.info("channel id is {}", .{channel_id});

    const params = try znvim.Payload.arrPayload(0, allocator);
    defer params.free(allocator);

    std.log.info("try to call nvim_get_current_buf", .{});
    const res = try client.rpc_client.call("nvim_get_current_buf", params);
    defer client.rpc_client.freeResultType(res);
    std.log.info("result is {any}", .{res.result});

    client.rpc_client.exit();
}

fn pipee(allocator: std.mem.Allocator) !void {
    const pipe_path = "\\\\.\\pipe\\nvim.29832.0";
    const ClientType = znvim.Client(20480, .named_pipe, u32);

    const pipe = try znvim.connectNamedPipe(
        pipe_path,
        allocator,
    );
    defer pipe.close();

    var client = try ClientType.init(pipe, pipe, allocator);
    defer client.deinit();

    try client.loop();

    std.log.info("get api infos", .{});
    try client.getApiInfo();
    const channel_id = try client.getChannelID();
    std.log.info("channel id is {}", .{channel_id});

    const params = try znvim.Payload.arrPayload(0, allocator);
    defer params.free(allocator);

    std.log.info("try to call nvim_get_current_buf", .{});
    const res = try client.rpc_client.call("nvim_get_current_buf", params);
    defer client.rpc_client.freeResultType(res);
    std.log.info("result is {any}", .{res.result});

    client.rpc_client.exit();
}
