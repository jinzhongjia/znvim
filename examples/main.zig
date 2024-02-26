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
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // get znvim client_type
    const ClientType = znvim.DefaultClientType(remote, .file);

    const client = try ClientType.init(
        stdout,
        stdin,
        allocator,
        false,
    );
    defer client.deinit();

    while (true) {
        try client.loop(allocator);
    }
}

const remote = struct {
    pub fn add(a: u16, b: u16) u16 {
        return a + b;
    }

    pub fn print() !void {
        std.log.info("hello, world!", .{});
        return error.kkkl;
    }
};
