//! This file demonstrates how to communicate with neovim through stdio and is generally used for plug-in development started using jobstart.
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
    const ClientType = znvim.DefaultClientType(struct {}, .file);

    const client = try ClientType.init(
        stdout,
        stdin,
        allocator,
        false,
    );
    defer client.deinit();
}
