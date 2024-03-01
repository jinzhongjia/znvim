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
    const ClientType = znvim.DefaultClientType(struct {}, .file);

    const client = try ClientType.init(
        stdout,
        stdin,
        allocator,
        false,
    );
    defer client.deinit();

    // get a writer of method `nvim_set_client_info`
    const writer = try client.call_with_writer(.nvim_set_client_info);
    // the parameters number is 5
    try writer.write_array_header(5);

    // write the first param `name`
    try writer.write_str("zig-client");

    // write the second parameters lentgth, 5
    // map length is 5 pairs
    try writer.write_map_header(5);
    {
        // first pair
        try writer.write_str("major");
        try writer.write_uint(1);
        // second pair
        try writer.write_str("minor");
        try writer.write_uint(10);
        // third pair
        try writer.write_str("patch");
        try writer.write_uint(2024);
        // forth pair
        try writer.write_str("prerelease");
        try writer.write_str("dev");
        // fifth pair
        try writer.write_str("commit");
        try writer.write_str("5a12d5");
    }

    // write the third parameter
    try writer.write_str("remote");

    // write the forth parameter
    try writer.write_array_header(0);

    // wirte the fifth parameter
    try writer.write_array_header(0);

    // then read the result, nvim_set_client_info will result nil, use void to read it
    try client.get_result_with_writer(void, writer, allocator);

    while (true) {
        try client.loop(allocator);
    }
}
