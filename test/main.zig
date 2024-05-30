const std = @import("std");
const znvim = @import("znvim");
const File = std.fs.File;
const ChildProcess = std.ChildProcess;

const ClientType = znvim.Client(20480, .file, u32);

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    const pipe = try znvim.connectNamedPipe(
        "\\\\.\\pipe\\nvim.29832.0",
        allocator,
    );
    defer pipe.close();

    var client = try ClientType.init(pipe, pipe, allocator);
    defer client.deinit();

    try client.rpc_client.loop();

    std.log.info("get api infos", .{});
    try client.getApiInfo();
    const channel_id = client.getChannelID();
    std.log.info("channel id is {}", .{channel_id});

    const params = try znvim.Payload.arrPayload(0, allocator);
    defer params.free(allocator);

    std.log.info("try to call nvim_get_current_buf", .{});
    const res = try client.rpc_client.call("nvim_get_current_buf", params);
    defer client.rpc_client.freeResultType(res);
    std.log.info("result is {any}", .{res.result});

    client.rpc_client.exit();
}
