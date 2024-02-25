//! This file demonstrates how to connect with neovim via tcp
//! Generally used for remote connection between different machines
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

    // get znvim client_type
    const ClientType = znvim.DefaultClientType(struct {}, .socket);

    const client = try ClientType.init(
        stream,
        stream,
        allocator,
        true,
    );
    defer client.deinit();

    std.log.info(
        "channel id id {}, function'nums is {}",
        .{ client.channel_id, client.metadata.functions.len },
    );
}
