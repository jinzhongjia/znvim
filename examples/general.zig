//! This file is a general template. The way to communicate with neovim is through stdio.
//! that is, neovim uses jobstart to wrap the plug-in program.
//! we connect neovim and set the client info use `nvim_set_client_info`
const std = @import("std");
const znvim = @import("znvim");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("memory leak!");
    }

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // get znvim client_type
    const ClientType = znvim.DefaultClient(.file);

    var client = try ClientType.init(
        stdout,
        stdin,
        allocator,
    );

    defer client.deinit();

    while (true) {
        try client.loop();
    }
}
