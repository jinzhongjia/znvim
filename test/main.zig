const std = @import("std");
const znvim = @import("znvim");
const File = std.fs.File;
const ChildProcess = std.ChildProcess;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

var user_data: u32 = 1;

pub fn main() !void {
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }

    // try pipee(allocator);
    try socket(allocator);
    // try unix_socket(allocator);
}

const ClientType = znvim.Client(20480, .socket, *u32);

var client: ClientType = undefined;
fn socket(allocator: std.mem.Allocator) !void {
    const address = "127.0.0.1";
    const port = 9090;

    const stream = try std.net.tcpConnectToAddress(try std.net.Address.parseIp4(address, port));
    defer stream.close();
    defer std.log.info("latest current userdata is {}", .{user_data});

    client = try ClientType.init(stream, stream, allocator);

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

    std.log.info("register method add", .{});
    const reqFuncType = ClientType.ReqMethodType;
    const notifyFuncType = ClientType.NotifyMethodType;

    try client.registerRequestMethod("add", reqFuncType{
        .func = add,
        .userdata = &user_data,
    });

    try client.registerNotifyMethod("exit", notifyFuncType{
        .func = exit,
        .userdata = &user_data,
    });

    std.log.info("current userdata is {}", .{user_data});

    // client.rpc_client.exit();
}

fn add(_: znvim.Payload, allocator: std.mem.Allocator, userdata: *u32) znvim.ResultType {
    const params = znvim.Payload.arrPayload(0, allocator) catch unreachable;
    client.freePayload(params);

    const result = client.call("nvim_get_current_buf", params) catch unreachable;
    defer client.freeResultType(result);

    const res = znvim.Payload.uintToPayload(result.result.ext.data[0] + 1);

    userdata.* += 1;

    return znvim.ResultType{ .result = res };
}

fn exit(_: znvim.Payload, _: std.mem.Allocator, _: *u32) void {
    std.log.info("exit", .{});
    client.exit();
}

// fn unix_socket(allocator: std.mem.Allocator) !void {
//     const unix_path = "/run/user/1000//nvim.5440.0";
//
//     const ClientType = znvim.Client(20480, .socket, u32);
//
//     const stream = try std.net.connectUnixSocket(unix_path);
//
//     defer stream.close();
//
//     var client = try ClientType.init(stream, stream, allocator);
//
//     defer client.deinit();
//     try client.loop();
//
//     std.log.info("get api infos", .{});
//     try client.getApiInfo();
//     const channel_id = try client.getChannelID();
//     std.log.info("channel id is {}", .{channel_id});
//
//     const params = try znvim.Payload.arrPayload(0, allocator);
//     defer params.free(allocator);
//
//     {
//         std.log.info("try to call nvim_get_current_buf", .{});
//         const res = try client.rpc_client.call("nvim_get_current_buf", params);
//         defer client.rpc_client.freeResultType(res);
//         std.log.info("result is {any}", .{res.result});
//     }
//
//     {
//         std.log.info("try to call nvim_get_current_buf", .{});
//         const res = try client.rpc_client.call("nvim_get_current_buf", params);
//         defer client.rpc_client.freeResultType(res);
//         std.log.info("result is {any}", .{res.result});
//     }
//
//     client.rpc_client.exit();
// }
//
// fn pipee(allocator: std.mem.Allocator) !void {
//     const pipe_path = "\\\\.\\pipe\\nvim.29832.0";
//     const ClientType = znvim.Client(20480, .named_pipe, u32);
//
//     const pipe = try znvim.connectNamedPipe(
//         pipe_path,
//         allocator,
//     );
//     defer pipe.close();
//
//     var client = try ClientType.init(pipe, pipe, allocator);
//     defer client.deinit();
//
//     try client.loop();
//
//     std.log.info("get api infos", .{});
//     try client.getApiInfo();
//     const channel_id = try client.getChannelID();
//     std.log.info("channel id is {}", .{channel_id});
//
//     const params = try znvim.Payload.arrPayload(0, allocator);
//     defer params.free(allocator);
//
//     std.log.info("try to call nvim_get_current_buf", .{});
//     const res = try client.rpc_client.call("nvim_get_current_buf", params);
//     defer client.rpc_client.freeResultType(res);
//     std.log.info("result is {any}", .{res.result});
//
//     client.rpc_client.exit();
// }
