//! This file demonstrates how to use unixsocket to connect neovim under the unix platform
//! Neovim will listen to a unixsocket for communication by default when it is started on the unix platform.
const std = @import("std");
const znvim = @import("znvim");

const uid: u16 = 1000;
const nvim_pid: u16 = 4076;
const unique_number: u16 = 0;

const unix_socket = std.fmt.comptimePrint(
    "/run/user/{}//nvim.{}.{}",
    .{ uid, nvim_pid, unique_number },
);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("memory leak!");
    }

    const stream = try std.net.connectUnixSocket(unix_socket);
    defer stream.close();

    // get znvim client_type
    const ClientType = znvim.DefaultClient(.socket);

    var client = try ClientType.init(
        stream,
        stream,
        allocator,
    );
    defer client.deinit();

    std.log.info(
        "channel id id {}",
        .{ client.getChannelID() },
    );
}
